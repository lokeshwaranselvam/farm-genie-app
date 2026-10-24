# Restricted Frappe Server Script: DocType Event, Employee Checkin, After Insert.
# Install with mobile_face_employee_checkin_guard. No attendance image is stored.
command = str(frappe.form_dict.get("cmd") or "")
requested_action = str(frappe.form_dict.get("action") or "").strip().lower()
is_mobile_checkin = command == "mobile_checkin" and requested_action == "checkin"
if is_mobile_checkin:
    log_type = str(frappe.form_dict.get("log_type") or "").strip().upper()
    if log_type not in ("IN", "OUT"):
        frappe.throw("The attendance action is invalid.")
    requested_action = "check_in" if log_type == "IN" else "check_out"
if is_mobile_checkin or (command == "farmgenie_employee_attendance" and requested_action in ("check_in", "check_out")):
    include_timings = frappe.form_dict.get("include_timings") in (True, 1, "1", "true")
    attach_started = frappe.utils.now_datetime() if include_timings else None
    current_user = frappe.session.user
    if not current_user or current_user == "Guest":
        frappe.throw("Sign in before checking in or out.")
    record_id = frappe.form_dict.get("face_verification")
    if not isinstance(record_id, str) or not record_id.strip():
        frappe.throw("The face verification receipt is missing.")
    record = frappe.get_doc("Comment", record_id.strip(), for_update=True)
    if (record.owner != "Administrator" or record.comment_type != "Info"
        or record.subject != "Genie Face Verification v1"
        or record.reference_doctype != "User" or record.reference_name != current_user):
        frappe.throw("The face verification does not belong to your account.")
    try:
        metadata = json.loads(record.content or "{}")
    except Exception:
        frappe.throw("The face verification is invalid. Scan again.")
    expected_action = "attendance_in" if requested_action == "check_in" else "attendance_out"
    expected_log_type = "IN" if requested_action == "check_in" else "OUT"
    if (not isinstance(metadata, dict) or metadata.get("current_user") != current_user
        or metadata.get("used") is not True or metadata.get("used_for_doctype") != "Employee Checkin"
        or metadata.get("event") or metadata.get("action") != expected_action
        or doc.log_type != expected_log_type):
        frappe.throw("The face verification does not belong to this check-in.")
    if metadata.get("version") != 2 or metadata.get("evidence_file") or metadata.get("photo_url"):
        frappe.throw("The face receipt format has changed. Update the app and scan again.")
    if metadata.get("used_for_name"):
        frappe.throw("The face verification is already linked to attendance.")
    metadata["used_for_name"] = doc.name
    record.content = json.dumps(metadata).replace('&', '\\u0026').replace('<', '\\u003c').replace('>', '\\u003e')
    record.save(ignore_permissions=True)
    if include_timings:
        timings = frappe.response.get("attendance_timings_ms") or {}
        timings["attach_total"] = max(0, round(frappe.utils.time_diff_in_seconds(
            frappe.utils.now_datetime(), attach_started) * 1000, 3))
        frappe.response["attendance_timings_ms"] = timings
