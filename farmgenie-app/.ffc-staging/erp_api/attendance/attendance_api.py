# Server Script: Script Type = API; API Method = mobile_checkin; Allow Guest = OFF
# Paste this entire file into the Script field. No imports, def, or return required.
# action=status reads state; action=checkin records an IN/OUT.
# MariaDB SQL, matching the original AttendanceList implementation.
# Single radius setting for status, check-in and checkout (metres).
geofence_radius_meters = 100
try:
    user = frappe.session.user
    if not user or user == "Guest":
        frappe.throw("Please sign in before marking attendance")

    action = (frappe.form_dict.get("action") or "status").strip().lower()
    if action not in ["status", "checkin"]:
        frappe.throw("Invalid action")
    # Extra CSRF check using a non-reserved form key (Frappe may consume csrf_token).
    # Same rule as Frappe core: enforce only when the session actually holds a token.
    # Sessions created via /api/method/login have no token until a Desk/web page
    # generates one, so requiring it unconditionally blocked every check-in.
    if action == "checkin":
        session_token = frappe.session.csrf_token or ""
        sent_token = frappe.form_dict.get("attendance_security_token") or ""
        if session_token and sent_token != session_token:
            frappe.throw("Security token expired. Reload the attendance page")

    # Lock the employee during writes. All writers using this API serialize here.
    employee_query = """
        SELECT name, employee_name, grade, custom_is_operation,
               company, designation, branch, leave_approver, image
        FROM `tabEmployee`
        WHERE user_id = %(user)s AND status = 'Active'
        ORDER BY name LIMIT 2
    """
    if action == "checkin":
        employee_query = employee_query + " FOR UPDATE"
    employees = frappe.db.sql(employee_query, {"user": user}, as_dict=True)
    if len(employees) != 1:
        frappe.throw("Exactly one active Employee must be linked to your login")
    employee = employees[0]
    employee_id = employee.name
    requested_employee = (frappe.form_dict.get("employee_id") or "").strip()
    if requested_employee and requested_employee != employee_id:
        frappe.throw("You can only mark your own attendance")
    requested_user = (frappe.form_dict.get("user_id") or "").strip()
    if requested_user and requested_user != user:
        frappe.throw("You can only access your own attendance")

    is_labour = (employee.grade or "").strip().lower() == "labour"
    is_operation = frappe.utils.cint(employee.custom_is_operation) == 1
    now = frappe.utils.now_datetime()
    day = str(frappe.utils.getdate(now))
    midnight = frappe.utils.get_datetime(day + " 00:00:00")
    next_midnight = frappe.utils.add_days(midnight, 1)
    values = {"employee": employee_id, "midnight": midnight, "next_midnight": next_midnight}
    lock_suffix = " FOR UPDATE" if action == "checkin" else ""
    previous_rows = frappe.db.sql("""
        SELECT name, log_type, time FROM `tabEmployee Checkin`
        WHERE employee = %(employee)s AND time < %(midnight)s
        ORDER BY time DESC, creation DESC, name DESC LIMIT 1
    """ + lock_suffix, values, as_dict=True)
    today_logs = frappe.db.sql("""
        SELECT name, log_type, time FROM `tabEmployee Checkin`
        WHERE employee = %(employee)s AND time >= %(midnight)s AND time < %(next_midnight)s
        ORDER BY time ASC, creation ASC, name ASC
    """ + lock_suffix, values, as_dict=True)
    # A future-dated record must not become invisible to validation.
    future_rows = frappe.db.sql("""
        SELECT name FROM `tabEmployee Checkin`
        WHERE employee = %(employee)s AND time >= %(next_midnight)s LIMIT 1
    """ + lock_suffix, values, as_dict=True)
    if future_rows:
        frappe.throw("Future attendance record found. Ask HR to correct it")
    previous = previous_rows[0] if previous_rows else None
    latest = today_logs[-1] if today_logs else previous
    latest_id = latest.name if latest else ""
    open_log = previous if previous and previous.log_type == "IN" else None
    completed = False
    for row in today_logs:
        if frappe.utils.get_datetime(row.time) > now:
            frappe.throw("Future attendance record found. Ask HR to correct it")
        if row.log_type == "IN":
            if open_log:
                frappe.throw("Two IN records without OUT. Ask HR to correct attendance")
            open_log = row
        elif row.log_type == "OUT":
            if not open_log:
                frappe.throw("OUT without a matching IN. Ask HR to correct attendance")
            open_log = None
            completed = True
        else:
            frappe.throw("A punch has no IN/OUT type. Ask HR to correct attendance")
    if open_log and (now - frappe.utils.get_datetime(open_log.time)).total_seconds() > 86400:
        frappe.throw("An old check-in is still open. Ask HR to correct it")

    next_action = "OUT" if open_log else ("IN" if is_labour or not completed else None)
    if action == "status":
        frappe.response["message"] = {
            "status": "success", "employee": employee, "csrf_token": frappe.session.csrf_token,
            "is_labour": is_labour, "is_operation": is_operation,
            "geofence_radius_meters": geofence_radius_meters,
            "previous": previous, "today_logs": today_logs,
            "latest_checkin_id": latest_id, "next_action": next_action,
            "server_now": str(now), "midnight": str(midnight), "work_date": day
        }
    else:
        log_type = (frappe.form_dict.get("log_type") or "").strip().upper()
        if log_type not in ["IN", "OUT"]:
            frappe.throw("Invalid log type")
        # Optimistic token + employee row lock stop duplicate/stale submissions.
        # Retrying a request with the same token cannot create another punch.
        if "expected_last_checkin" not in frappe.form_dict:
            frappe.throw("Please reload the updated attendance page")
        expected = frappe.form_dict.get("expected_last_checkin") or ""
        if expected != latest_id:
            frappe.throw("Attendance changed. Refresh status before trying again")
        if log_type != next_action:
            if log_type == "IN" and completed and not is_labour and not open_log:
                frappe.throw("Attendance completed. Only Grade Labour can check in again")
            frappe.throw("Cannot check OUT without IN" if log_type == "OUT" else "Already checked IN")

        latitude = frappe.form_dict.get("latitude")
        longitude = frappe.form_dict.get("longitude")
        has_lat = latitude is not None and str(latitude).strip() != ""
        has_lon = longitude is not None and str(longitude).strip() != ""
        if has_lat != has_lon:
            frappe.throw("Both latitude and longitude are required")
        if not has_lat and not is_operation:
            frappe.throw("Location not received. Please enable GPS")
        if has_lat:
            latitude = float(latitude)
            longitude = float(longitude)
            # Also rejects NaN and infinity.
            if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
                frappe.throw("Invalid GPS coordinates")
        else:
            latitude = None
            longitude = None

        office = (frappe.form_dict.get("custom_office_type") or "").strip()
        offices = {
            "Head Office - Vanagaram": [13.0549854, 80.1545772],
            "Head Office - Aalapakkam": [13.0431622, 80.1609604],
            "Head Office - RWD GrandCorridor": [13.0570, 80.1371],
            "Head Office - Prestige": [13.0604, 80.15483]
        }
        if office not in offices and not (is_operation and office == "Operation"):
            frappe.throw("Please select a valid office")
        if not is_operation:
            # Haversine, evaluated by MariaDB to avoid imports in Server Script.
            center = offices[office]
            distances = frappe.db.sql("""
                SELECT 6371000 * 2 * ASIN(SQRT(LEAST(1,
                    POW(SIN(RADIANS(%(lat)s - %(site_lat)s) / 2), 2)
                    + COS(RADIANS(%(lat)s)) * COS(RADIANS(%(site_lat)s))
                    * POW(SIN(RADIANS(%(lon)s - %(site_lon)s) / 2), 2)
                ))) AS distance_m
            """, {"lat": latitude, "lon": longitude, "site_lat": center[0], "site_lon": center[1]}, as_dict=True)
            if float(distances[0].distance_m) > geofence_radius_meters:
                frappe.throw("You must be within " + str(geofence_radius_meters) + " metres of the selected office")

        # Restore the readable address. A failed lookup must not block attendance.
        address = None
        if latitude is not None and longitude is not None:
            try:
                geo_response = frappe.make_get_request(
                    "https://nominatim.openstreetmap.org/reverse",
                    params={
                        "format": "json",
                        "lat": latitude,
                        "lon": longitude,
                        "zoom": 18,
                        "addressdetails": 1
                    },
                    headers={"User-Agent": "Farmgenie-ERPNext-Attendance"},
                    timeout=5
                )
                address = (geo_response.get("display_name") or "").strip()
            except Exception:
                address = None
        if not address:
            address = "GPS unavailable" if latitude is None else "Lat " + str(latitude) + ", Lon " + str(longitude)

        # Respect the existing field's capacity; return the full address below.
        device_address = address
        device_field = frappe.get_meta("Employee Checkin").get_field("device_id")
        if device_field and device_field.fieldtype in ["Data", "Link", "Dynamic Link"]:
            device_address = address[:frappe.utils.cint(device_field.length or 140)]
        doc = frappe.get_doc({
            "doctype": "Employee Checkin", "employee": employee_id,
            "log_type": log_type, "time": str(now),
            "custom_latitude": latitude, "custom_longitude": longitude,
            "custom_office_type": office, "device_id": device_address,
            "custom_created_using_mobile_app": 1
        })
        doc.insert(ignore_permissions=True)
        frappe.db.commit()
        frappe.response["message"] = {
            "status": "success", "checkin_id": doc.name,
            "log_type": log_type, "time": str(now), "is_labour": is_labour,
            "address": address
        }
except Exception as e:
    # Exceptions are caught for a consistent JSON response: explicitly roll back.
    frappe.db.rollback()
    frappe.response["http_status_code"] = 400
    frappe.response["message"] = {"status": "error", "message": str(e)}

# #mobile_checkin
