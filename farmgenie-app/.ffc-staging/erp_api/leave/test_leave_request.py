"""Local mocked execution tests. This test file is NOT a Frappe Server Script."""
from datetime import date
from pathlib import Path
from types import SimpleNamespace
import unittest


class Record(dict):
    __getattr__ = dict.get


class ValidationError(Exception):
    pass


SCRIPT = Path(__file__).with_name("leave_request_api.py").read_text(encoding="utf-8")


def run_request(employees=None, **params):
    inserted = []
    if employees is None:
        employees = [Record(name="EMP-1", employee_name="Employee", company="Company",
                            leave_approver="approver@example.com")]
    form = dict(from_date="2026-10-22", to_date="2026-10-22", leave_type="Casual Leave",
                description="Family function")
    form.update(params)

    def get_doc(values):
        doc = Record(values, status="Open", name="LEAVE-1")
        doc.insert = lambda: inserted.append(doc)
        return doc

    def throw(message):
        raise ValidationError(message)

    fake = SimpleNamespace(
        form_dict=Record(form), session=SimpleNamespace(user="employee@example.com"),
        get_all=lambda doctype, filters, **kwargs: employees,
        get_doc=get_doc, throw=throw, response={},
        utils=SimpleNamespace(cint=lambda value: int(value or 0), getdate=date.fromisoformat),
    )
    exec(compile(SCRIPT, "leave_request_api.py", "exec"), {"frappe": fake})
    return fake.response["message"], inserted


class LeaveRequestTests(unittest.TestCase):
    def test_half_day_date_defaults_to_the_only_day(self):
        _, inserted = run_request(half_day="1")
        self.assertEqual(inserted[0]["half_day_date"], "2026-10-22")

    def test_multi_day_half_day_requires_a_date_inside_the_range(self):
        multi = dict(to_date="2026-10-24", half_day="1")
        with self.assertRaisesRegex(ValidationError, "Choose which day"):
            run_request(**multi)
        for outside in ("2026-10-21", "2026-10-25"):
            with self.subTest(outside=outside), self.assertRaisesRegex(ValidationError, "between"):
                run_request(half_day_date=outside, **multi)
        _, inserted = run_request(half_day_date="2026-10-23", **multi)
        self.assertEqual(inserted[0]["half_day_date"], "2026-10-23")

    def test_full_day_ignores_half_day_date(self):
        _, inserted = run_request(half_day="0", half_day_date="2026-10-22")
        self.assertIsNone(inserted[0]["half_day_date"])

    def test_non_text_fields_are_rejected(self):
        with self.assertRaisesRegex(ValidationError, "Invalid value for description"):
            run_request(description=["x"])

    def test_employee_must_be_linked_by_user_id_exactly_once(self):
        for employees in ([], [Record(name="EMP-1"), Record(name="EMP-2")]):
            with self.subTest(count=len(employees)), self.assertRaisesRegex(ValidationError, "No active"):
                run_request(employees=employees)

    def test_to_date_before_from_date_is_rejected(self):
        with self.assertRaisesRegex(ValidationError, "before from date"):
            run_request(to_date="2026-10-21")


if __name__ == "__main__":
    unittest.main()
