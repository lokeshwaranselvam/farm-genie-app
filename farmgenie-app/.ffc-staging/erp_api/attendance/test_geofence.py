"""Local mocked execution tests. This test file is NOT a Frappe Server Script."""
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


def run_request(office, lat, lon, *, action="check_in", operation=0,
                has_field=True, saved_office=None, spoof=False):
    inserted = []
    employee = Record(name="EMP-1", employee_name="Employee", company="Company")
    logs = []
    if action == "check_out":
        logs = [Record(name="IN-1", log_type="IN", time="2026-10-22 09:00:00",
                       custom_office_type=saved_office or office)]

    def get_value(doctype, filters, fields, **kwargs):
        return operation if fields == "custom_is_operation" else employee

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
        get_all=lambda *args, **kwargs: logs,
        get_doc=get_doc, throw=throw, response={},
        utils=SimpleNamespace(
            cint=lambda value: int(value or 0),
            getdate=lambda value: "2026-10-22", now_datetime=lambda: "2026-10-22 10:00:00",
            add_days=lambda value, days: "2026-10-23", get_datetime=lambda value: value,
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
                run_request("Operation", 12, 79, action=action, spoof=True)
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


if __name__ == "__main__":
    unittest.main()
