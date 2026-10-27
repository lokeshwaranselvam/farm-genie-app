"""Run with: python -m unittest discover -s test -p mobile_face_auth_test.py.

The mock intentionally exposes only the Frappe namespaces used in safe_exec,
not request.files/method, session.sid, cache, SQL, or custom app imports.
"""
import base64
from datetime import datetime
import hashlib
import json
from pathlib import Path
from types import SimpleNamespace
import unittest


class Row(dict):
    __getattr__ = dict.get
    __setattr__ = dict.__setitem__


class Document(Row):
    def get_content(self):
        if self.decode:
            self.decode_calls = (self.decode_calls or 0) + 1
            content = base64.b64decode(self.content, validate=True)
            self.decode = False
            return content
        return self.content

    def check_permission(self, action):
        if not self.get("read_allowed", True):
            raise ValueError("Event read denied")

    def save(self, ignore_permissions=False):
        self.store[self.name] = self
        return self

    def has_value_changed(self, field):
        return self.get("previous", {}).get(field) != self.get(field)

    def insert(self, ignore_permissions=False, set_name=None):
        store = self.store
        name = set_name or "DOC-" + str(len(store) + 1)
        if name in store:
            raise ValueError("Duplicate primary key")
        self.name = name
        self.owner = self.current_user
        self.creation = "2026-10-12 10:00:00"
        if self.doctype == "File":
            content = self.get_content()
            self.content_hash = hashlib.sha256(content).hexdigest()
            self.file_url = "/private/files/" + name + ".jpg"
        store[name] = self
        return self


class MobileFaceAuthTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.script = (Path(__file__).resolve().parents[1] /
                      "erp_api/face/mobile_face_auth.py").read_text()

    def setUp(self):
        self.user = "employee@example.test"
        self.store = {}
        self.created = []
        self.events = {}
        self.error_logs = []
        self.roles = ["Employee"]
        self.jpg = b"\xff\xd8\xff" + b"live-selfie" + b"\xff\xd9"
        self.encoded = base64.b64encode(self.jpg).decode()
        self.frappe = SimpleNamespace(
            session=Row(user=self.user, csrf_token="csrf-test"), response={},
            form_dict=Row(), get_doc=self.get_doc,
            get_meta=lambda doctype: SimpleNamespace(has_field=lambda field: False),
            db=SimpleNamespace(get_value=self.get_value, exists=self.exists, set_value=self.set_value),
            log_error=self.log_error, get_roles=lambda user=None: list(self.roles),
            utils=SimpleNamespace(
                cint=lambda value: int(value or 0),
                sha256_hash=lambda value: hashlib.sha256(value.encode()).hexdigest(),
                flt=lambda value: float(value or 0),
                now=lambda: "2026-10-12 10:00:00",
                now_datetime=datetime.now,
                time_diff_in_seconds=lambda first, second: (
                    datetime.fromisoformat(str(first)) - datetime.fromisoformat(str(second))
                ).total_seconds(),
            ),
            throw=lambda message: (_ for _ in ()).throw(ValueError(message)),
        )

    def log_error(self, **kwargs):
        self.error_logs.append(kwargs)

    def get_doc(self, value, name=None, **kwargs):
        if isinstance(value, dict):
            doc = Document(value, store=self.store, current_user=self.frappe.session.user)
            self.created.append(doc)
            return doc
        if value == "Event":
            return self.events[name]
        return self.store[name]

    def get_value(self, doctype, name, fields, as_dict=False):
        if doctype == "Employee":
            if fields == "custom_is_operation":
                return getattr(self, "operation", 0)
            return self.user if name == "EMP-1" else "other@example.test"
        self.assertEqual(doctype, "File")
        row = self.store.get(name)
        return Row({field: row.get(field) for field in fields}) if row else None

    def exists(self, doctype, name):
        if doctype == "ToDo" and isinstance(name, dict):
            return any(
                row.get("doctype") == "ToDo"
                and all(row.get(key) == value for key, value in name.items() if key != "status")
                and row.get("status") not in ["Cancelled", "Closed"]
                for row in self.store.values()
            )
        return (doctype == "Event" and name in self.events) or (doctype == "Comment" and name in self.store)

    def set_value(self, doctype, name, field, value, update_modified=True):
        self.assertIn(doctype, ("Comment", "File"))
        self.store[name][field] = value

    def run_api(self, action="status", **params):
        self.frappe.form_dict = Row(action=action, **params)
        self.frappe.response = {}
        exec(compile(self.script, "mobile_face_auth.py", "exec"),
             {"frappe": self.frappe, "json": json})
        return self.frappe.response["message"]

    def enroll(self, **params):
        values = dict(
            image_base64=self.encoded, csrf_token="csrf-test",
            model_version="opencv-sface-2021dec-v1", blink_completed=True)
        values.update(params)
        return self.run_api("enroll", **values)

    def verify(self, **params):
        reference = self.run_api()["reference_file"]
        values = dict(
            csrf_token="csrf-test",
            reference_file=reference["name"], reference_version=reference["version"],
            verification_action="attendance_in", model_version="opencv-sface-2021dec-v1",
            similarity=0.7, blink_completed=True, latitude=13.01, longitude=80.1,
            accuracy=8.0, is_mocked=False,
            captured_on="2026-10-12T10:00:00", event="",
        )
        values.update(params)
        return self.run_api("record_verification", **values)

    def test_guest_cannot_read_status_or_enroll(self):
        self.frappe.session.user = "Guest"
        for action in ["status", "enroll", "record_verification"]:
            with self.subTest(action=action), self.assertRaisesRegex(ValueError, "Sign in"):
                self.run_api(action)
        self.assertFalse(self.created)

    def test_status_without_initialized_csrf_does_not_access_missing_session_data(self):
        # safe_exec exposes user/csrf_token, not a full Session object.
        self.frappe.session = Row(user=self.user, csrf_token=None)
        result = self.run_api()
        self.assertIsNone(result["csrf_token"])
        self.assertFalse(result["enrolled"])

    def test_model_version_negotiation_preserves_existing_clients(self):
        self.assertEqual(self.run_api()["model_version"], "opencv-sface-2021dec-v1")
        version = "opencv-sface-2021dec-int8bq-v1"
        self.assertEqual(self.run_api(model_version=version)["model_version"], version)
        self.enroll(model_version=version)
        result = self.verify(model_version=version)
        metadata = json.loads(self.store[result["record_id"]].content)
        self.assertEqual(metadata["model_version"], version)
        with self.assertRaisesRegex(ValueError, "model has changed"):
            self.run_api(model_version="unknown")

    def test_status_is_read_only_and_returns_no_other_user_reference(self):
        result = self.run_api()
        self.assertFalse(result["enrolled"])
        self.assertIsNone(result["reference_file"])
        self.assertEqual(result["csrf_token"], "csrf-test")
        self.assertFalse(self.created)
        self.enroll()
        self.frappe.session.user = "another@example.test"
        self.assertFalse(self.run_api()["enrolled"])

    def test_first_photo_is_private_and_attached_only_to_authenticated_user(self):
        result = self.enroll(user="other@example.test", attached_to_name="other@example.test")
        doc = self.store[result["reference_file"]["name"]]
        self.assertEqual((doc.attached_to_doctype, doc.attached_to_name, doc.owner),
                         ("User", self.user, "Administrator"))
        self.assertEqual(doc.is_private, 1)
        self.assertEqual(doc.content, self.jpg)
        self.assertEqual(doc.decode_calls, 1)
        self.assertEqual(self.run_api()["reference_file"], result["reference_file"])

    def test_enrollment_never_overwrites_existing_reference(self):
        reference = self.enroll()["reference_file"]
        with self.assertRaisesRegex(ValueError, "already registered"):
            self.enroll()
        self.assertEqual(len(self.store), 1)
        self.assertEqual(self.run_api()["reference_file"], reference)

    def test_verification_never_creates_a_file_even_for_legacy_image_payload(self):
        self.enroll()
        for params in [{}, {"image_base64": self.encoded}]:
            result = self.verify(**params)
            self.assertEqual(result["receipt_version"], 2)
            self.assertNotIn("evidence_file", result)
            self.assertNotIn("photo_url", result)
        self.assertEqual(sum(row.doctype == "File" for row in self.created), 1)

    def test_invalid_base64_characters_at_any_position_are_rejected(self):
        for char in ["!", " ", "\n", "\t", "é"]:
            for position in [0, len(self.encoded) // 2, len(self.encoded) - 1]:
                value = self.encoded[:position] + char + self.encoded[position + 1:]
                with self.subTest(char=char, position=position):
                    with self.assertRaisesRegex(ValueError, "encoding is invalid"):
                        self.enroll(image_base64=value)
        self.assertFalse(self.store)

    def test_server_timings_are_optional_and_contain_only_durations(self):
        self.enroll()
        self.verify()
        self.assertNotIn("attendance_timings_ms", self.frappe.response)
        result = self.verify(include_timings=True)
        timings = self.frappe.response["attendance_timings_ms"]
        self.assertEqual(set(timings), {
            "request_validation",
            "receipt_insert", "receipt_secure", "verification_total",
        })
        self.assertTrue(all(isinstance(value, (int, float)) and value >= 0
                            for value in timings.values()))
        self.assertEqual(self.store[result["record_id"]].owner, "Administrator")

    def test_csrf_body_required_for_all_mutations(self):
        for token in [None, "wrong"]:
            with self.subTest(token=token), self.assertRaisesRegex(ValueError, "session token"):
                self.run_api("enroll", image_base64=self.encoded, csrf_token=token)
        self.enroll()
        with self.assertRaisesRegex(ValueError, "session token"):
            self.verify(csrf_token="wrong")
        self.assertEqual(len(self.store), 1)

    def test_session_data_csrf_fallback_for_older_frappe(self):
        self.frappe.session = Row(user=self.user, data=Row(csrf_token="csrf-test"))
        self.assertEqual(self.run_api()["csrf_token"], "csrf-test")
        self.enroll()

    def test_invalid_jpeg_base64_and_oversize_are_rejected_without_insert(self):
        invalid = ["", "not-base64!", "====", base64.b64encode(b"not a JPEG").decode(),
                   base64.b64encode(b"\xff\xd8\xff" + b"x" * (2 * 1024 * 1024) + b"\xff\xd9").decode()]
        for data in invalid:
            with self.subTest(size=len(data)), self.assertRaises(ValueError):
                self.run_api("enroll", image_base64=data, csrf_token="csrf-test",
                             model_version="opencv-sface-2021dec-v1", blink_completed=True)
        self.assertFalse(self.store)

    def test_enrollment_requires_the_configured_model_and_live_blink_assertion(self):
        for params in [{"model_version": "old", "blink_completed": True},
                       {"model_version": "opencv-sface-2021dec-v1", "blink_completed": False}]:
            with self.subTest(params=params), self.assertRaises(ValueError):
                self.run_api("enroll", image_base64=self.encoded, csrf_token="csrf-test", **params)
        self.assertFalse(self.store)

    def test_tampered_public_or_other_owner_reference_fails_closed(self):
        name = self.enroll()["reference_file"]["name"]
        for field, value in [("is_private", 0), ("owner", "other@example.test"),
                             ("attached_to_name", "other@example.test")]:
            doc = self.store[name]
            original = doc[field]
            doc[field] = value
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "reference is invalid"):
                self.run_api()
            doc[field] = original

    def test_legacy_user_owned_reference_is_handed_to_administrator(self):
        name = self.enroll()["reference_file"]["name"]
        self.store[name].owner = self.user
        self.assertTrue(self.run_api()["enrolled"])
        self.assertEqual(self.store[name].owner, self.user)  # GET does not write.
        self.verify()
        self.assertEqual(self.store[name].owner, "Administrator")

    def test_mocked_or_inaccurate_gps_creates_no_receipt(self):
        self.enroll()
        before = len(self.created)
        cases = [({"is_mocked": True}, "mock location"), ({"is_mocked": "1"}, "mock location"),
                 ({"is_mocked": None}, "mock location"), ({"accuracy": 120}, "too weak"),
                 ({"accuracy": None}, "Update the app"), ({"accuracy": "nan"}, "too weak")]
        for params, message in cases:
            with self.subTest(params=params), self.assertRaisesRegex(ValueError, message):
                self.verify(**params)
        self.assertEqual(before, len(self.created))
        metadata = json.loads(self.store[self.verify()["record_id"]].content)
        self.assertEqual((metadata["accuracy"], metadata["is_mocked"]), (8.0, False))

    def test_operation_staff_may_send_low_accuracy_gps(self):
        self.enroll()
        self.frappe.get_meta = lambda doctype: SimpleNamespace(has_field=lambda field: True)
        self.operation = 1
        self.verify(accuracy=120)
        self.operation = 0
        with self.assertRaisesRegex(ValueError, "too weak"):
            self.verify(accuracy=120)

    def test_daily_receipt_has_no_photo_and_is_system_owned(self):
        self.enroll()
        result = self.verify()
        receipt = self.store[result["record_id"]]
        metadata = json.loads(receipt.content)
        self.assertEqual(metadata["version"], 2)
        self.assertNotIn("evidence_file", metadata)
        self.assertNotIn("photo_url", metadata)
        self.assertEqual((receipt.reference_doctype, receipt.reference_name), ("User", self.user))
        self.assertEqual((receipt.owner, receipt.comment_type), ("Administrator", "Info"))
        self.assertEqual(metadata["current_user"], self.user)
        self.assertEqual(metadata["received_on"], "2026-10-12 10:00:00")
        self.assertFalse(metadata["used"])
        self.assertEqual(metadata["verification_source"], "device_reported")

    def test_unexpected_verification_type_error_is_written_to_error_log(self):
        self.enroll()

        original = self.frappe.get_doc
        def raise_type_error(value, *args, **kwargs):
            if isinstance(value, dict) and value.get("doctype") == "Comment":
                raise TypeError("simulated receipt failure")
            return original(value, *args, **kwargs)

        self.frappe.get_doc = raise_type_error
        with self.assertRaisesRegex(TypeError, "simulated receipt failure"):
            self.verify()

        self.assertEqual(len(self.error_logs), 1)
        self.assertEqual(
            self.error_logs[0]["title"], "Genie Face Verification TypeError"
        )
        self.assertTrue(self.error_logs[0]["defer_insert"])
        self.assertIn(
            "Stage: saving verification receipt",
            self.error_logs[0]["message"],
        )
        self.assertIn("simulated receipt failure", self.error_logs[0]["message"])

    def test_wrong_face_no_blink_stale_template_and_invalid_coordinates_create_no_evidence(self):
        self.enroll()
        invalid = [{"similarity": 0.49}, {"similarity": float("nan")},
                   {"similarity": float("inf")}, {"blink_completed": False},
                   {"reference_file": "another-file"}, {"reference_version": "old"},
                   {"model_version": "unknown"}, {"latitude": float("nan")},
                   {"latitude": 91}, {"longitude": 181}, {"latitude": None},
                   {"verification_action": "approve"}, {"event": "EVENT-1"},
                   {"verification_action": "event_in"},
                   {"verification_action": "event_out"}]
        for values in invalid:
            with self.subTest(values=values), self.assertRaises(ValueError):
                self.verify(**values)
        self.assertEqual(len(self.store), 1)

    def test_event_actions_are_rejected_without_creating_evidence(self):
        self.enroll()
        for action in ["event_in", "event_out"]:
            with self.subTest(action=action), self.assertRaisesRegex(
                ValueError, "only available for attendance"
            ):
                self.verify(verification_action=action)
        self.assertEqual(len(self.store), 1)

    def test_receipt_json_survives_html_sensitive_usernames_and_capture_strings(self):
        self.user = "sales&support@example.test"
        self.frappe.session.user = self.user
        self.enroll()
        result = self.verify(captured_on="<client&time>")
        content = self.store[result["record_id"]].content
        self.assertNotIn("&", content)
        self.assertNotIn("<", content)
        metadata = json.loads(content)
        self.assertEqual(metadata["current_user"], self.user)
        self.assertEqual(metadata["captured_on"], "<client&time>")


