
# Frappe Server Script settings:
#   Script Type: DocType Event
#   Reference DocType: Employee Checkin
#   DocType Event: Before Insert
#   Allow Guest: Disabled
#
# Install with mobile_face_auth after every mobile client is updated. This
# protects farmgenie_employee_attendance check_in/check_out when they use normal
# Employee Checkin.insert(). Any other insert path (REST /api/resource, Desk,
# frappe.client.insert) is allowed only for Administrator and the HR roles below.
# Users with the web check-in role may use mobile_checkin without a face receipt.
# Methods using direct DB writes must call equivalent validation themselves.
# The receipt verifies submission/audit linkage, not a client AI assertion.
# Also protects mobile_checkin action=checkin, log_type=IN/OUT.

command = str(frappe.form_dict.get("cmd") or "")
expected_action = None
expected_log_type = None
current_user = frappe.session.user
# Desk, data import and biometric-device integrations need one of these roles.
checkin_admin_roles = ("System Manager", "HR Manager", "HR User")
# The web check-in page has no camera/face scan; it calls mobile_checkin.
web_checkin_role = "iOS User"
if command == "farmgenie_employee_attendance":
    requested_action = str(frappe.form_dict.get("action") or "").strip().lower()
    if requested_action == "check_in":
        expected_action = "attendance_in"
        expected_log_type = "IN"
    elif requested_action == "check_out":
        expected_action = "attendance_out"
        expected_log_type = "OUT"
elif command == "mobile_checkin" and str(frappe.form_dict.get("action") or "status").strip().lower() == "checkin":
    expected_log_type = str(frappe.form_dict.get("log_type") or "").strip().upper()
    if expected_log_type not in ("IN", "OUT"):
        frappe.throw("The attendance action is invalid.")
    expected_action = "attendance_in" if expected_log_type == "IN" else "attendance_out"

roles = frappe.get_roles(current_user) if current_user else []
if not expected_action:
    # Without this, any employee could POST /api/resource/Employee Checkin with
    # any time, GPS or employee and skip the face and geofence checks.
    if current_user != "Administrator" and not any(role in roles for role in checkin_admin_roles):
        frappe.throw("Mark attendance from the Genie app or the web check-in page.")
else:
    if not current_user or current_user == "Guest":
        frappe.throw("Sign in before checking in or out.")
    # Only Employee.user_id links a login to an Employee; email fallbacks could
    # resolve to a different person.
    employee = frappe.db.get_value("Employee", doc.employee, ["name", "user_id", "status"], as_dict=True)
    if (not employee or employee.status != "Active" or employee.user_id != current_user
        or doc.log_type != expected_log_type):
        frappe.throw("The attendance employee or action does not match your account.")
    # Attendance is recorded for the current moment only; no backdating.
    if doc.time and abs(frappe.utils.time_diff_in_seconds(frappe.utils.now_datetime(), doc.time)) > 300:
        frappe.throw("The attendance time must be the current time.")
web_checkin = bool(
    expected_action and command == "mobile_checkin" and web_checkin_role in roles
    and not frappe.form_dict.get("face_verification")
)

if expected_action and not web_checkin:
    include_timings = frappe.form_dict.get("include_timings") in [True, 1, "1", "true"]
    guard_started = frappe.utils.now_datetime() if include_timings else None
    record_id = frappe.form_dict.get("face_verification")
    if not isinstance(record_id, str):
        frappe.throw("Complete face verification before checking in or out.")
    record_id = record_id.strip()
    if not record_id or not frappe.db.exists("Comment", record_id):
        frappe.throw("Complete face verification before checking in or out.")
    # DB row lock is held until the existing attendance transaction completes;
    # a second request cannot consume this receipt concurrently.
    lock_started = frappe.utils.now_datetime() if include_timings else None
    record = frappe.get_doc("Comment", record_id, for_update=True)
    if include_timings:
        lock_ms = max(0, frappe.utils.time_diff_in_seconds(
            frappe.utils.now_datetime(), lock_started
        ) * 1000)
    if (
        record.owner != "Administrator" or record.comment_type != "Info"
        or record.subject != "Genie Face Verification v1"
        or record.reference_doctype != "User" or record.reference_name != current_user
    ):
        frappe.throw("The face verification does not belong to your account.")
    try:
        metadata = json.loads(record.content or "{}")
    except Exception:
        frappe.throw("The face verification is invalid. Scan again.")
    age = frappe.utils.time_diff_in_seconds(frappe.utils.now(), record.creation)
    if not isinstance(metadata, dict) or metadata.get("used") or not 0 <= age <= 120:
        frappe.throw("The face verification was used or expired. Scan again.")
    try:
        receipt_similarity = float(metadata.get("similarity"))
    except (TypeError, ValueError):
        frappe.throw("The face verification score is invalid. Scan again.")
    if (
        metadata.get("current_user") != current_user or metadata.get("action") != expected_action
        or metadata.get("event")
        or metadata.get("model_version") not in ["opencv-sface-2021dec-v1", "opencv-sface-2021dec-int8bq-v1"]
        or metadata.get("blink_completed") is not True
        or not 0.5 <= receipt_similarity <= 1
    ):
        frappe.throw("The face verification does not match this attendance action.")
    # Receipt GPS is bound to the exact fix submitted with this Checkin.
    try:
        receipt_latitude = float(metadata.get("latitude"))
        receipt_longitude = float(metadata.get("longitude"))
        checkin_latitude = float(doc.get("custom_latitude") if doc.get("custom_latitude") is not None else doc.get("latitude"))
        checkin_longitude = float(doc.get("custom_longitude") if doc.get("custom_longitude") is not None else doc.get("longitude"))
    except (TypeError, ValueError):
        frappe.throw("The face verification location is invalid. Scan again.")
    if (not -90 <= receipt_latitude <= 90 or not -180 <= receipt_longitude <= 180
        or not -90 <= checkin_latitude <= 90 or not -180 <= checkin_longitude <= 180
        or abs(receipt_latitude - checkin_latitude) > 0.000001
        or abs(receipt_longitude - checkin_longitude) > 0.000001):
        frappe.throw("The attendance location does not match your face scan. Scan again.")
    reference_id = "GENIE-FACE-REF-" + frappe.utils.sha256_hash(current_user)[:32]
    reference = frappe.db.get_value(
        "File", reference_id, ["owner", "is_private", "attached_to_doctype", "attached_to_name", "content_hash"], as_dict=True,
    )
    if (
        not reference or reference.owner != "Administrator" or not reference.is_private
        or reference.attached_to_doctype != "User" or reference.attached_to_name != current_user
        or metadata.get("reference_file") != reference_id
        or metadata.get("reference_version") != (reference.content_hash or reference_id)
    ):
        frappe.throw("Your face reference has changed. Scan again.")
    if metadata.get("version") != 2 or metadata.get("evidence_file") or metadata.get("photo_url"):
        frappe.throw("The face receipt format has changed. Update the app and scan again.")
    metadata["used"] = True
    metadata["used_on"] = frappe.utils.now()
    metadata["used_for_doctype"] = "Employee Checkin"
    record.content = json.dumps(metadata).replace('&', '\\u0026').replace('<', '\\u003c').replace('>', '\\u003e')
    record.save(ignore_permissions=True)
    if include_timings:
        timings = frappe.response.get("attendance_timings_ms") or {}
        timings["receipt_lock"] = round(lock_ms, 3)
        timings["guard_total"] = max(0, round(frappe.utils.time_diff_in_seconds(
            frappe.utils.now_datetime(), guard_started
        ) * 1000, 3))
        frappe.response["attendance_timings_ms"] = timings
