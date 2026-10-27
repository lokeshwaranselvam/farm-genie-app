# Frappe Server Script
# Script Type: API
# API Method: farmgenie_employee_attendance
# HTTP Method: GET, POST
#
# One authenticated endpoint for employee attendance.
# Request action: status, check_in, or check_out.
# POST fields for check_in/check_out: latitude, longitude, address

action = (frappe.form_dict.get("action") or "").strip().lower()

if action not in ("status", "calendar", "check_in", "check_out"):
    frappe.throw("action must be status, calendar, check_in, or check_out.")

office_type = (frappe.form_dict.get("office_type") or "").strip()
office_types = (
    "Head Office - Alapakkam",
    "Head Office - RWD GrandCorridor",
    "Head Office - Vanagaram",
    "Head Office - Prestige",
)
office_config = {
    "Head Office - Alapakkam": {
        "latitude": 13.0431622,
        "longitude": 80.1609604,
        "radius_meters": 100,
    },
    "Head Office - RWD GrandCorridor": {
        "latitude": 13.0570,
        "longitude": 80.1371,
        "radius_meters": 100,
    },
    "Head Office - Vanagaram": {
        "latitude": 13.0549854,
        "longitude": 80.1545772,
        "radius_meters": 100,
    },
    "Head Office - Prestige": {
        "latitude": 13.0604,
        "longitude": 80.15483,
        "radius_meters": 100,
    }
}

# Preserve the app's existing spelling while accepting the page's spelling.
if office_type == "Head Office - Aalapakkam":
    office_type = "Head Office - Alapakkam"

latitude = None
longitude = None
address = frappe.form_dict.get("address")
address = address.strip()[:140] if isinstance(address, str) and address.strip() else "Farmgenie Mobile"

if action in ("check_in", "check_out"):
    latitude_text = frappe.form_dict.get("latitude")
    longitude_text = frappe.form_dict.get("longitude")

    if latitude_text in (None, "") or longitude_text in (None, ""):
        frappe.throw("Latitude and longitude are required for location verification.")

    try:
        latitude = float(latitude_text)
        longitude = float(longitude_text)
    except (ValueError, TypeError):
        frappe.throw("Latitude and longitude must be valid numbers.")

    if not -90 <= latitude <= 90:
        frappe.throw("Latitude must be between -90 and 90.")
    if not -180 <= longitude <= 180:
        frappe.throw("Longitude must be between -180 and 180.")

user = frappe.session.user

if not user or user == "Guest":
    frappe.throw("Login is required.")

# Only Employee.user_id links a login to an Employee. Email fallbacks could
# resolve to a different person when emails are reused or mistyped.
employees = frappe.get_all(
    "Employee",
    filters={"user_id": user, "status": "Active"},
    fields=["name", "employee_name", "company", "status", "department", "designation", "branch", "leave_approver", "image"],
    limit_page_length=2,
)

if len(employees) != 1:
    frappe.throw(
        "No single active Employee record matches the logged-in user. "
        "Set Employee.user_id to the ERP login. Contact HR."
    )
employee = employees[0]

# Only the authenticated Employee record can grant an exemption.
# Missing custom field defaults to normal geofence enforcement.
is_operation = False
if frappe.get_meta("Employee").has_field("custom_is_operation"):
    is_operation = frappe.utils.cint(
        frappe.db.get_value("Employee", employee.name, "custom_is_operation")
    ) == 1

# Serialize check-in/check-out per employee. Two concurrent requests must not
# both see "not checked in" and insert duplicate logs.
if action in ("check_in", "check_out"):
    frappe.db.get_value("Employee", employee.name, "name", for_update=True)

now = frappe.utils.now_datetime()
today = frappe.utils.getdate(now)
tomorrow = frappe.utils.add_days(today, 1)
today_start = frappe.utils.get_datetime(str(today) + " 00:00:00")
tomorrow_start = frappe.utils.get_datetime(str(tomorrow) + " 00:00:00")
# An IN older than this is a forgotten check-out, not an active shift.
max_shift_hours = 20

log_fields = ["name", "log_type", "time", "latitude", "longitude", "custom_latitude", "custom_longitude", "custom_office_type"]
logs = frappe.get_all(
    "Employee Checkin",
    filters={
        "employee": employee.name,
        "time": ["between", [today_start, tomorrow_start]],
    },
    # custom_office_type exists only on Employee Checkin. It is used for the
    # active check-in/check-out flow and is never queried from Attendance.
    fields=log_fields,
    order_by="time desc, creation desc",
    limit_page_length=2,
)
# The open shift may have started before midnight (night shift).
latest_rows = frappe.get_all(
    "Employee Checkin",
    filters={"employee": employee.name},
    fields=log_fields,
    order_by="time desc, creation desc",
    limit_page_length=1,
)

if action == "calendar":
    start_date = frappe.form_dict.get("start_date") or str(today)
    end_date = frappe.form_dict.get("end_date") or str(tomorrow)
    attendance_rows = frappe.get_all(
        "Attendance",
        filters={
            "employee": employee.name,
            "attendance_date": [
                "between",
                [
                    frappe.utils.getdate(start_date),
                    frappe.utils.add_days(frappe.utils.getdate(end_date), -1),
                ],
            ],
            "docstatus": ["<", 2],
        },
        fields=[
            "attendance_date",
            "status",
            "late_entry",
            "early_exit",
        ],
        order_by="attendance_date asc, creation asc",
        limit_page_length=500,
    )

    daily = {}
    for attendance in attendance_rows:
        raw_status = (attendance.status or "").strip().lower()
        if "leave" in raw_status:
            status = "leave"
        elif raw_status == "half day":
            status = "half"
        elif raw_status == "present":
            status = "present"
        elif raw_status == "absent":
            status = "absent"
        else:
            status = raw_status.replace(" ", "_") or None

        date_key = str(frappe.utils.getdate(attendance.attendance_date))
        daily[date_key] = {
            "date": date_key,
            "attendance_date": date_key,
            "status": status,
            "half_day": status == "half",
            "late_entry": attendance.late_entry,
            "early_exit": attendance.early_exit,
        }

    records = []
    for date_key in sorted(daily):
        records.append(daily[date_key])

    frappe.response["message"] = {
        "ok": True,
        "data": records,
    }

latest = latest_rows[0] if latest_rows else None
last_in = None
last_out = None

for log in logs:
    if not last_in and log.log_type == "IN":
        last_in = log
    if not last_out and log.log_type == "OUT":
        last_out = log

checked_in = bool(
    latest and latest.log_type == "IN"
    and frappe.utils.time_diff_in_hours(now, latest.time) <= max_shift_hours
)
if checked_in:
    # Report the open shift's IN even when it started yesterday.
    last_in = latest
    last_out = None
work_completed = bool(not checked_in and last_in and last_out)

# Check-out remains bound to the office in the authenticated employee's IN log.
if action == "check_out" and not checked_in:
    frappe.throw("Employee is not checked in. Check-in is required before checkout.")

if action == "check_out" and checked_in:
    office_type = latest.custom_office_type or ""
    if office_type == "Head Office - Aalapakkam":
        office_type = "Head Office - Alapakkam"
    # The shift started as Operation; a later flag change must not block checkout.
    if office_type == "Operation":
        is_operation = True

if action in ("check_in", "check_out"):
    if not is_operation and office_type not in office_config:
        frappe.throw("Your office location is missing or not configured. Contact HR.")
    if is_operation and action == "check_in":
        office_type = "Operation"
    if not is_operation:
        configured = office_config[office_type]
        # Exact spherical distance using MariaDB math, available through safe SQL.
        # Bound parameters only; no user input is interpolated into SQL.
        distance_rows = frappe.db.sql(
            """SELECT 6371000 * 2 * ASIN(SQRT(LEAST(1, GREATEST(0,
                POW(SIN(RADIANS(%s - %s) / 2), 2)
                + COS(RADIANS(%s)) * COS(RADIANS(%s))
                * POW(SIN(RADIANS(%s - %s) / 2), 2)
            ))))""",
            (latitude, configured["latitude"], configured["latitude"],
             latitude, longitude, configured["longitude"]),
        )
        distance_meters = distance_rows[0][0]
        if distance_meters is None or distance_meters > configured["radius_meters"]:
            frappe.throw(
                "Move within 100 meters of " + office_type
                + " to check " + ("in." if action == "check_in" else "out.")
            )

if action == "status":
    frappe.response["message"] = {
        "ok": True,
        "data": {
            "is_operation": is_operation,
            "employee": employee.name,
            "employee_id": employee.name,
            "employee_name": employee.employee_name,
            "company": employee.company,
            "branch": employee.branch,
            "leave_approver": employee.leave_approver,
            "checked_in": checked_in,
            "work_completed": work_completed,
            "department": employee.department,
            "designation": employee.designation,
            "image": employee.image,
            "office_type": last_in.custom_office_type if last_in else None,
            "check_in_time": last_in.time if last_in else None,
            "check_out_time": last_out.time if last_out else None,
        },
    }

if action == "check_in":
    if work_completed:
        frappe.throw("Work for today is already completed. You cannot check in again today.")
    if checked_in:
        frappe.throw("Employee is already checked in. Check out before checking in again.")

    checkin = frappe.get_doc(
        {
            "doctype": "Employee Checkin",
            "employee": employee.name,
            "employee_name": employee.employee_name,
            "log_type": "IN",
            "time": now,
            "latitude": latitude,
            "longitude": longitude,
            "device_id": address,
            "custom_latitude": latitude,
            "custom_longitude": longitude,
            "custom_office_type": office_type,
        }
    )
    checkin.insert()

    frappe.response["message"] = {
        "ok": True,
        "message": "Employee checked in.",
        "data": {
            "is_operation": is_operation,
            "employee": employee.name,
            "employee_id": employee.name,
            "employee_name": employee.employee_name,
            "company": employee.company,
            "branch": employee.branch,
            "leave_approver": employee.leave_approver,
            "checked_in": True,
            "work_completed": False,
            "department": employee.department,
            "designation": employee.designation,
            "image": employee.image,
            "office_type": office_type,
            "check_in_time": checkin.time,
        },
    }

if action == "check_out":
    if not checked_in:
        frappe.throw("Employee is not checked in. Check-in is required before checkout.")

    checkout = frappe.get_doc(
        {
            "doctype": "Employee Checkin",
            "employee": employee.name,
            "employee_name": employee.employee_name,
            "log_type": "OUT",
            "time": now,
            "latitude": latitude,
            "longitude": longitude,
            "device_id": address,
            "custom_latitude": latitude,
            "custom_longitude": longitude,
            "custom_office_type": office_type,
        }
    )
    checkout.insert()

    frappe.response["message"] = {
        "ok": True,
        "message": "Employee checked out.",
        "data": {
            "is_operation": is_operation,
            "employee": employee.name,
            "employee_id": employee.name,
            "employee_name": employee.employee_name,
            "company": employee.company,
            "branch": employee.branch,
            "leave_approver": employee.leave_approver,
            "checked_in": False,
            "work_completed": True,
            "department": employee.department,
            "designation": employee.designation,
            "image": employee.image,
            "office_type": office_type,
            "check_in_time": latest.time,
            "check_out_time": checkout.time,
        },
    }
