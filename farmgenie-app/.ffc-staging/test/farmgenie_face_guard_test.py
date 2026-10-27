"""Mocked execution of the Farmgenie Before/After Insert receipt hooks."""
from datetime import datetime, timedelta
import json
from pathlib import Path
import unittest

from mobile_face_auth_test import MobileFaceAuthTest, Row


class FarmgenieFaceGuardTest(unittest.TestCase):
    def setUp(self):
        self.api = MobileFaceAuthTest()
        MobileFaceAuthTest.setUpClass()
        self.api.setUp()
        self.api.enroll()
        self.frappe = self.api.frappe
        original = self.frappe.db.get_value

        def lookup(doctype, name, fields, **kwargs):
            if doctype == "Employee":
                return Row(name=name, user_id=self.api.user if name == "EMP-1" else "other@example.test",
                           company_email=None, personal_email=None, status="Active")
            return original(doctype, name, fields, **kwargs)

        self.frappe.db.get_value = lookup
        self.receipt = self.api.verify()["record_id"]
        self.doc = Row(name="CHECKIN-1", employee="EMP-1", log_type="IN",
                       custom_latitude=13.01, custom_longitude=80.1)

    def run_hook(self, name="guard", **params):
        self.frappe.form_dict = Row(cmd="farmgenie_employee_attendance", action="check_in",
                                   face_verification=self.receipt)
        self.frappe.form_dict.update(params)
        source = Path(__file__).resolve().parents[1] / "erp_api/face" / (
            "mobile_face_employee_checkin_" + name + ".py")
        exec(compile(source.read_text(), str(source), "exec"),
             {"frappe": self.frappe, "json": json, "doc": self.doc})

    def metadata(self):
        return json.loads(self.api.store[self.receipt].content)

    def update_metadata(self, **values):
        data = self.metadata()
        data.update(values)
        self.api.store[self.receipt].content = json.dumps(data)

    def test_receipt_consumed_and_linked_without_attendance_photo(self):
        files_before = [d for d in self.api.created if d.doctype == "File"]
        self.run_hook()
        self.assertTrue(self.metadata()["used"])
        self.run_hook("attach")
        self.assertEqual(self.metadata()["used_for_name"], "CHECKIN-1")
        self.assertEqual(files_before, [d for d in self.api.created if d.doctype == "File"])
        with self.assertRaisesRegex(ValueError, "already linked"):
            self.run_hook("attach")
        with self.assertRaisesRegex(ValueError, "used or expired"):
            self.run_hook()

    def test_checkout_requires_checkout_receipt(self):
        self.doc.log_type = "OUT"
        with self.assertRaisesRegex(ValueError, "does not match"):
            self.run_hook(action="check_out")
        self.receipt = self.api.verify(verification_action="attendance_out")["record_id"]
        self.run_hook(action="check_out")
        self.run_hook("attach", action="check_out")
        self.assertEqual(self.metadata()["used_for_name"], self.doc.name)

    def test_missing_wrong_user_and_wrong_employee_fail_closed(self):
        with self.assertRaisesRegex(ValueError, "Complete face verification"):
            self.run_hook(face_verification="")
        self.doc.employee = "EMP-2"
        with self.assertRaisesRegex(ValueError, "employee or action"):
            self.run_hook()
        self.doc.employee = "EMP-1"
        self.update_metadata(current_user="other@example.test")
        with self.assertRaisesRegex(ValueError, "does not match"):
            self.run_hook()

    def test_expired_future_and_tampered_receipts_fail_closed(self):
        record = self.api.store[self.receipt]
        for stamp in ["2026-10-12 09:57:59", "2026-10-12 10:00:01"]:
            record.creation = stamp
            with self.assertRaisesRegex(ValueError, "used or expired"):
                self.run_hook()
        record.creation = "2026-10-12 10:00:00"
        record.owner = self.api.user
        with self.assertRaisesRegex(ValueError, "does not belong"):
            self.run_hook()

    def test_mismatched_or_nonfinite_gps_rejected_before_consumption(self):
        for lat in [13.02, float("nan"), float("inf"), "bad"]:
            self.doc.custom_latitude = lat
            with self.subTest(lat=lat), self.assertRaises(ValueError):
                self.run_hook()
            self.assertFalse(self.metadata()["used"])

    def test_reference_change_requires_new_scan(self):
        self.update_metadata(reference_version="old")
        with self.assertRaisesRegex(ValueError, "reference has changed"):
            self.run_hook()

    def test_legacy_image_receipt_is_rejected(self):
        self.update_metadata(evidence_file="PHOTO-1")
        with self.assertRaisesRegex(ValueError, "format has changed"):
            self.run_hook()

    def test_direct_inserts_outside_the_app_need_an_hr_role(self):
        commands = ["frappe.desk.form.save.savedocs", "frappe.client.insert", "other.checkin", ""]
        for command in commands:
            with self.subTest(command=command), self.assertRaisesRegex(ValueError, "Genie app"):
                self.run_hook(cmd=command, face_verification="")
            self.run_hook("attach", cmd=command, face_verification="")
        for role in ["HR User", "HR Manager", "System Manager"]:
            self.api.roles = ["Employee", role]
            for command in commands:
                self.run_hook(cmd=command, face_verification="")
        self.assertFalse(self.metadata()["used"])

    def test_status_and_calendar_do_not_consume_receipts(self):
        for action in ["status", "calendar"]:
            with self.assertRaisesRegex(ValueError, "Genie app"):
                self.run_hook(action=action)
            self.run_hook("attach", action=action)
            self.assertFalse(self.metadata()["used"])

    def test_web_checkin_role_uses_mobile_checkin_without_a_receipt(self):
        params = dict(cmd="mobile_checkin", action="checkin", log_type="IN", face_verification="")
        with self.assertRaisesRegex(ValueError, "Complete face verification"):
            self.run_hook(**params)
        self.api.roles = ["Employee", "iOS User"]
        self.run_hook(**params)
        self.run_hook("attach", **params)
        self.assertFalse(self.metadata()["used"])
        self.doc.employee = "EMP-2"
        with self.assertRaisesRegex(ValueError, "employee or action"):
            self.run_hook(**params)
        self.doc.employee = "EMP-1"
        with self.assertRaisesRegex(ValueError, "Genie app"):
            self.run_hook(cmd="frappe.client.insert", face_verification="")
        # A receipt sent by the Android app is still verified for this role.
        self.run_hook(cmd="mobile_checkin", action="checkin", log_type="IN")
        self.assertTrue(self.metadata()["used"])

    def test_backdated_or_future_checkin_time_is_rejected(self):
        for minutes in [-10, 10]:
            self.doc.time = datetime.now() + timedelta(minutes=minutes)
            with self.subTest(minutes=minutes), self.assertRaisesRegex(ValueError, "current time"):
                self.run_hook()
        self.doc.time = datetime.now()
        self.run_hook()
        self.assertTrue(self.metadata()["used"])

    def test_after_insert_requires_before_insert_consumption(self):
        with self.assertRaisesRegex(ValueError, "does not belong"):
            self.run_hook("attach")

    def test_html_sensitive_receipt_content_still_round_trips(self):
        self.update_metadata(captured_on="<time&client>")
        self.run_hook()
        self.run_hook("attach")
        self.assertEqual(self.metadata()["captured_on"], "<time&client>")
        self.assertNotIn("<", self.api.store[self.receipt].content)
        self.assertNotIn("&", self.api.store[self.receipt].content)

    def test_optional_timings_keep_linking_intact(self):
        self.run_hook(include_timings="1")
        self.run_hook("attach", include_timings="1")
        self.assertTrue({"receipt_lock", "guard_total", "attach_total"}.issubset(
            self.frappe.response["attendance_timings_ms"]))

    def test_mobile_checkin_receipt_is_consumed_and_linked_for_both_directions(self):
        for log_type, action in [("IN", "attendance_in"), ("OUT", "attendance_out")]:
            self.receipt = self.api.verify(verification_action=action)["record_id"]
            self.doc.log_type = log_type
            self.run_hook(cmd="mobile_checkin", action="checkin", log_type=log_type)
            self.run_hook("attach", cmd="mobile_checkin", action="checkin", log_type=log_type)
            self.assertEqual(self.metadata()["used_for_name"], self.doc.name)
            with self.assertRaisesRegex(ValueError, "used or expired"):
                self.run_hook(cmd="mobile_checkin", action="checkin", log_type=log_type)

    def test_mobile_checkin_requires_a_receipt_and_matching_action(self):
        with self.assertRaisesRegex(ValueError, "Complete face verification"):
            self.run_hook(cmd="mobile_checkin", action="checkin", log_type="IN", face_verification="")
        self.doc.log_type = "OUT"
        with self.assertRaisesRegex(ValueError, "does not match"):
            self.run_hook(cmd="mobile_checkin", action="checkin", log_type="OUT")

    def test_mobile_status_leaves_receipt_unchanged(self):
        with self.assertRaisesRegex(ValueError, "Genie app"):
            self.run_hook(cmd="mobile_checkin", action="status")
        self.run_hook("attach", cmd="mobile_checkin", action="status")
        self.assertFalse(self.metadata()["used"])


if __name__ == "__main__":
    unittest.main()
