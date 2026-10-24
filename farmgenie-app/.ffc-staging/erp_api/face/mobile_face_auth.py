# Restricted Frappe Server Script: API, mobile_face_auth, Allow Guest OFF.
# Enable rate limiting (for example, 60 requests/minute).
# Enrollment stores one private User JPEG. Attendance stores metadata only.
# Matching/blink are DEVICE-REPORTED, not independently verified by ERP.
# No imports, custom functions, new DocTypes, or explicit transaction commits.

include_timings = frappe.form_dict.get("include_timings") in (True, 1, "1", "true")
verification_started = frappe.utils.now_datetime() if include_timings else None
timings = {}
current_user = frappe.session.user
if not current_user or current_user == "Guest":
    frappe.throw("Sign in before registering or verifying your face.")
action = (frappe.form_dict.get("action") or "status").strip().lower()
if action not in ("status", "enroll", "record_verification"):
    frappe.throw("Use status, enroll, or record_verification.")
csrf_token = frappe.session.get("csrf_token") or (frappe.session.get("data") or {}).get("csrf_token")
model_version = frappe.form_dict.get("model_version") or "opencv-sface-2021dec-v1"
if model_version not in ("opencv-sface-2021dec-v1", "opencv-sface-2021dec-int8bq-v1"):
    frappe.throw("The face model has changed. Update the app before registering or verifying.")
minimum_similarity = 0.5
max_jpeg_bytes = 2 * 1024 * 1024
reference_name = "GENIE-FACE-REF-" + frappe.utils.sha256_hash(current_user)[:32]
reference = None
row = frappe.db.get_value(
    "File", reference_name,
    ["name", "owner", "is_private", "attached_to_doctype", "attached_to_name",
     "file_url", "content_hash", "file_name"], as_dict=True,
)
if row:
    if (row.owner != current_user or not row.is_private
        or row.attached_to_doctype != "User" or row.attached_to_name != current_user
        or not (row.file_url or "").startswith("/private/files/")):
        frappe.throw("Your face reference is invalid. Contact your administrator.")
    reference = {"name": row.name, "url": row.file_url,
                 "version": row.content_hash or row.name}

if action in ("enroll", "record_verification"):
    if not csrf_token or frappe.form_dict.get("csrf_token") != csrf_token:
        frappe.throw("Your session token has changed. Reload and try again.")
    if frappe.form_dict.get("model_version") != model_version:
        frappe.throw("The face model has changed. Update the app before registering or verifying.")
    if frappe.form_dict.get("blink_completed") not in (True, 1, "1", "true"):
        frappe.throw("Complete the live blink scan before registering or verifying your face.")

if action == "enroll":
    if reference:
        frappe.throw("Your face is already registered. Contact your administrator to reset it.")
    encoded = frappe.form_dict.get("image_base64")
    if not isinstance(encoded, str) or not encoded:
        frappe.throw("A live selfie JPEG is required.")
    if len(encoded) > ((max_jpeg_bytes + 2) // 3) * 4:
        frappe.throw("The selfie must be smaller than 2 MB.")
    if len(encoded) % 4 or encoded.strip(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="
    ):
        frappe.throw("The selfie encoding is invalid.")
    file_doc = frappe.get_doc({
        "doctype": "File", "file_name": "genie-face-reference-v1.jpg", "is_private": 1,
        "folder": "Home/Attachments", "content": encoded, "decode": True,
        "attached_to_doctype": "User", "attached_to_name": current_user,
    })
    try:
        content = file_doc.get_content()
    except Exception:
        frappe.throw("The selfie encoding is invalid.")
    if not isinstance(content, bytes):
        frappe.throw("ERP did not decode the selfie into binary JPEG data.")
    if not content or len(content) > max_jpeg_bytes:
        frappe.throw("The selfie must be a nonempty JPEG smaller than 2 MB.")
    if not content.startswith(b"\xff\xd8\xff") or not content.endswith(b"\xff\xd9"):
        frappe.throw("The selfie must be a JPEG image.")
    file_doc.content = content
    file_doc.decode = False
    # Deterministic PK prevents concurrent duplicate enrollments and overwrites.
    file_doc.insert(ignore_permissions=True, set_name=reference_name)
    reference = {"name": file_doc.name, "url": file_doc.file_url,
                 "version": file_doc.content_hash or file_doc.name}

if action in ("status", "enroll"):
    frappe.response["message"] = {
        "status": "success", "current_user": current_user,
        "enrolled": bool(reference), "reference_file": reference,
        "model_version": model_version, "minimum_similarity": minimum_similarity,
        "csrf_token": csrf_token, "verification_receipt_version": 2,
    }

if action == "record_verification":
    verification_stage = "validating match and GPS values"
    try:
        if not reference:
            frappe.throw("Register your face before checking in or out.")
        if (frappe.form_dict.get("reference_file") != reference["name"]
            or frappe.form_dict.get("reference_version") != reference["version"]):
            frappe.throw("The face reference has changed. Scan your face again.")
        verification_action = (frappe.form_dict.get("verification_action") or "").strip()
        if verification_action not in ("attendance_in", "attendance_out"):
            frappe.throw("Face verification is only available for attendance check-in and check-out.")
        if frappe.form_dict.get("event"):
            frappe.throw("Face verification receipts cannot be used for Events.")
        # Strict conversions reject malformed text as well as NaN and infinity.
        try:
            similarity = float(frappe.form_dict.get("similarity"))
            latitude = float(frappe.form_dict.get("latitude"))
            longitude = float(frappe.form_dict.get("longitude"))
        except (TypeError, ValueError):
            frappe.throw("A valid face score and fresh GPS coordinates are required.")
        if not minimum_similarity <= similarity <= 1:
            frappe.throw("Your face did not match your registered selfie. Please try again.")
        if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
            frappe.throw("The GPS coordinates are invalid.")
        if include_timings:
            timings["request_validation"] = max(0, round(frappe.utils.time_diff_in_seconds(
                frappe.utils.now_datetime(), verification_started) * 1000, 3))
        stage_started = frappe.utils.now_datetime() if include_timings else None
        verification_stage = "saving verification receipt"
        metadata = {
            "version": 2, "current_user": current_user, "action": verification_action,
            "reference_file": reference["name"], "reference_version": reference["version"],
            "model_version": model_version, "similarity": similarity, "blink_completed": True,
            "latitude": latitude, "longitude": longitude,
            "captured_on": str(frappe.form_dict.get("captured_on") or "")[:64],
            "received_on": frappe.utils.now(), "verification_source": "device_reported", "used": False,
        }
        record = frappe.get_doc({
            "doctype": "Comment", "comment_type": "Info",
            "reference_doctype": "User", "reference_name": current_user,
            "subject": "Genie Face Verification v1",
            "content": json.dumps(metadata).replace('&', '\\u0026').replace('<', '\\u003c').replace('>', '\\u003e'),
        })
        record.insert(ignore_permissions=True)
        if include_timings:
            timings["receipt_insert"] = max(0, round(frappe.utils.time_diff_in_seconds(
                frappe.utils.now_datetime(), stage_started) * 1000, 3))
        stage_started = frappe.utils.now_datetime() if include_timings else None
        # Narrow elevation: users cannot edit the system-owned verification receipt.
        verification_stage = "securing verification receipt"
        frappe.db.set_value("Comment", record.name, "owner", "Administrator")
        if include_timings:
            timings["receipt_secure"] = max(0, round(frappe.utils.time_diff_in_seconds(
                frappe.utils.now_datetime(), stage_started) * 1000, 3))
            timings["verification_total"] = max(0, round(frappe.utils.time_diff_in_seconds(
                frappe.utils.now_datetime(), verification_started) * 1000, 3))
            frappe.response["attendance_timings_ms"] = timings
        frappe.response["message"] = {
            "status": "success", "current_user": current_user, "record_id": record.name,
            "receipt_version": 2, "verification_source": "device_reported",
            "csrf_token": csrf_token, "verification_receipt_version": 2,
        }
    except TypeError as error:
        frappe.log_error(title="Genie Face Verification TypeError",
            message="Stage: " + verification_stage + "\nError: " + str(error),
            defer_insert=True)
        raise
