"""Local mocked execution tests. This test file is NOT a Frappe Server Script."""
from datetime import datetime, timedelta
import math
from pathlib import Path
import sqlite3
from types import SimpleNamespace
import unittest


class Record(dict):
    __getattr__ = dict.get


class ValidationError(Exception):
    pass


SCRIPT = Path(__file__).with_name("attendance_api.py").read_text(encoding="utf-8")
CENTERS = {
    "Head Office - Alapakkam": (13.0431622, 80.1609604),
    "Head Office - RWD GrandCorridor": (13.0570, 80.1371),
    "Head Office - Vanagaram": (13.0549854, 80.1545772),
    "Head Office - Prestige": (13.0604, 80.15483),
}


NOW = datetime(2026, 10, 22, 10, 0, 0)


def run_request(office, lat, lon, *, action="check_in", operation=0,
                has_field=True, saved_office=None, spoof=False, logs=None,
                employees=None, locks=None):
    inserted = []
    employee = Record(name="EMP-1", employee_name="Employee", company="Company")
    if employees is None:
        employees = [employee]
    if logs is None:
        logs = []
        if action == "check_out":
            logs = [Record(name="IN-1", log_type="IN", time=NOW - timedelta(hours=1),
                           custom_office_type=saved_office or office)]
    logs = sorted(logs, key=lambda log: log.time, reverse=True)

    def get_value(doctype, filters, fields, **kwargs):
        if kwargs.get("for_update") and locks is not None:
            locks.append((doctype, filters))
        return operation if fields == "custom_is_operation" else employee

    def get_all(doctype, filters=None, **kwargs):
        if doctype == "Employee":
            assert set(filters) == {"user_id", "status"}
            return employees
        if "time" in filters:
            start, end = filters["time"][1]
            return [log for log in logs if start <= log.time < end][:kwargs["limit_page_length"]]
        return logs[:kwargs["limit_page_length"]]

    def sql(query, params):
        # Execute the SQL formula locally, including syntax and bindings.
        assert "%s" in query and len(params) == 6
        with sqlite3.connect(":memory:") as connection:
            connection.create_function("LEAST", 2, min)
            connection.create_function("GREATEST", 2, max)
            return connection.execute(query.replace("%s", "?"), params).fetchall()

    def get_doc(values):
        doc = Record(values)
        doc.insert = lambda: inserted.append(doc)
        return doc

    def throw(message):
        raise ValidationError(message)

    fake = SimpleNamespace(
        form_dict=Record(action=action, office_type=office, latitude=lat,
                         longitude=lon, is_operation=spoof),
        session=SimpleNamespace(user="employee@example.com"),
        db=SimpleNamespace(get_value=get_value, sql=sql),
        get_meta=lambda dt: SimpleNamespace(has_field=lambda field: has_field),
        get_all=get_all,
        get_doc=get_doc, throw=throw, response={},
        utils=SimpleNamespace(
            cint=lambda value: int(value or 0),
            getdate=lambda value: value.date() if isinstance(value, datetime) else value,
            now_datetime=lambda: NOW,
            add_days=lambda value, days: value + timedelta(days=days),
            get_datetime=lambda value: datetime.fromisoformat(value),
            time_diff_in_hours=lambda first, second: (first - second).total_seconds() / 3600,
        ),
    )
    exec(compile(SCRIPT, "attendance_api.py", "exec"), {"frappe": fake})
    return fake.response["message"], inserted


class GeofenceTests(unittest.TestCase):
    def test_all_offices_in_and_out_boundaries(self):
        for office, (lat, lon) in CENTERS.items():
            for action in ("check_in", "check_out"):
                for meters in (99, 101):
                    with self.subTest(office=office, action=action, meters=meters):
                        moved_lat = lat + math.degrees(meters / 6371000)
                        if meters == 99:
                            result, inserted = run_request(office, moved_lat, lon, action=action)
                            self.assertTrue(result["ok"])
                            self.assertEqual(len(inserted), 1)
                        else:
                            with self.assertRaisesRegex(ValidationError, "100 meters"):
                                run_request(office, moved_lat, lon, action=action)

    def test_checkout_uses_saved_office(self):
        with self.assertRaisesRegex(ValidationError, "100 meters"):
            run_request("Head Office - Prestige", *CENTERS["Head Office - Prestige"],
                        action="check_out", saved_office="Head Office - Vanagaram")

    def test_operation_exemption_is_server_controlled(self):
        for action in ("check_in", "check_out"):
            result, _ = run_request("Operation", 12, 79, action=action, operation=1)
            self.assertTrue(result["data"]["is_operation"])
            with self.assertRaises(ValidationError):
                run_request("Operation", 12, 79, action=action, spoof=True,
                            saved_office="Head Office - Prestige")
        with self.assertRaises(ValidationError):
            run_request("Operation", 12, 79, has_field=False, operation=1)

    def test_invalid_gps_rejected_even_for_operation(self):
        for lat, lon in [("abc", 80), ("nan", 80), (13, "inf"), (91, 80), (13, -181), (None, 80)]:
            with self.subTest(lat=lat, lon=lon), self.assertRaises(ValidationError):
                run_request("Operation", lat, lon, operation=1)

    def test_alias_and_status(self):
        result, _ = run_request("Head Office - Aalapakkam", *CENTERS["Head Office - Alapakkam"])
        self.assertEqual(result["data"]["office_type"], "Head Office - Alapakkam")
        result, inserted = run_request("", None, None, action="status", operation=1)
        self.assertTrue(result["data"]["is_operation"])
        self.assertEqual(inserted, [])

    def test_checkin_and_checkout_lock_the_employee_row(self):
        for action in ("check_in", "check_out"):
            locks = []
            run_request("Head Office - Prestige", *CENTERS["Head Office - Prestige"],
                        action=action, locks=locks)
            self.assertEqual(locks, [("Employee", "EMP-1")])
        locks = []
        run_request("", None, None, action="status", locks=locks)
        self.assertEqual(locks, [])

    def test_night_shift_checks_out_after_midnight(self):
        office = "Head Office - Prestige"
        night_in = Record(name="IN-1", log_type="IN", time=NOW - timedelta(hours=10, minutes=10),
                          custom_office_type=office)
        result, _ = run_request("", None, None, action="status", logs=[night_in])
        self.assertTrue(result["data"]["checked_in"])
        self.assertEqual(result["data"]["office_type"], office)
        with self.assertRaisesRegex(ValidationError, "already checked in"):
            run_request(office, *CENTERS[office], logs=[night_in])
        _, inserted = run_request(office, *CENTERS[office], action="check_out", logs=[night_in])
        self.assertEqual(inserted[0]["log_type"], "OUT")

    def test_forgotten_checkout_does_not_block_a_new_day(self):
        office = "Head Office - Prestige"
        stale = Record(name="IN-1", log_type="IN", time=NOW - timedelta(days=2), custom_office_type=office)
        result, _ = run_request("", None, None, action="status", logs=[stale])
        self.assertFalse(result["data"]["checked_in"])
        _, inserted = run_request(office, *CENTERS[office], logs=[stale])
        self.assertEqual(inserted[0]["log_type"], "IN")

    def test_checkout_after_operation_flag_removed_mid_shift(self):
        result, inserted = run_request("", 12, 79, action="check_out", operation=0, saved_office="Operation")
        self.assertEqual(inserted[0]["custom_office_type"], "Operation")

    def test_employee_must_be_linked_by_user_id_exactly_once(self):
        for employees in ([], [Record(name="EMP-1"), Record(name="EMP-2")]):
            with self.subTest(count=len(employees)), self.assertRaisesRegex(ValidationError, "Employee"):
                run_request("", None, None, action="status", employees=employees)

    def test_address_is_trimmed_and_limited(self):
        office = "Head Office - Prestige"
        _, inserted = run_request(office, *CENTERS[office])
        self.assertEqual(inserted[0]["device_id"], "Farmgenie Mobile")


if __name__ == "__main__":
    unittest.main()
