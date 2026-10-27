# Farmgenie employee attendance API

> Current app integration: attendance status and writes now call the user's
> deployed `/api/method/mobile_checkin` script (200 metres), not the legacy script
> below. Do not deploy `attendance_api.py` as a replacement for `mobile_checkin`.
> See [current integration and receipt-hook rollout](../face/README.md).
> The remaining sections describe the retained legacy API for reference only.

These methods are intended to be installed in a Frappe/ERPNext custom app on
`https://farmgenie.itgenie.online`.

The API uses the logged-in Frappe session to identify the employee. The mobile
client must not be allowed to choose another employee by sending an employee ID
in the request body.

## Endpoints

Create one authenticated Frappe Server Script with API type:

```text
GET, POST /api/method/farmgenie_employee_attendance
```

Pass one action on every request:

```text
?action=status
?action=check_in
?action=check_out
```

For check-in, send `office_type`, `latitude`, `longitude`, and optional
`address` as form fields or query parameters. For check-out, send the current
`latitude`, `longitude`, and optional `address`; no office selection is needed.
ERP takes the office from the employee's open check-in record and requires
check-out within 100 meters of that office center (the same rule as check-in).
The app also validates fresh GPS before submission, including after confirmation.
A missing/unknown office blocks regular employee attendance.

Deploy `attendance_api.py` into the **existing authenticated API Server Script**
`farmgenie_employee_attendance` on `https://farmgenie.itgenie.online`.
This file is restricted Server Script code, not a custom-app Python module.
Keep authentication and Employee Checkin creation permissions enabled. No new
DocType or replacement endpoint is required. Rebuild/restart the Flutter app for
the client changes. Local verification does not deploy the script to ERP.

The server resolves `Employee.custom_is_operation` from the authenticated
employee. When it is 1, distance restrictions are bypassed for both actions,
but valid current GPS is still required and stored. If the field is absent,
the exemption defaults to false. A client-supplied exemption is never trusted.
Status and action responses include `is_operation` for the app.

Material Request uses the existing session saved in SharedPreferences to set
the WebView's ERP session cookie before loading. Account logout clears both
the saved app session and WebView cookies. An expired ERP session still requires
signing in again; passwords are not stored or replayed.

Office centers match the supplied attendance page; radius is **100 meters**:

| Existing app office name | Latitude | Longitude |
| --- | --- | --- |
| Head Office - Alapakkam | 13.0431622 | 80.1609604 |
| Head Office - RWD GrandCorridor | 13.0570 | 80.1371 |
| Head Office - Vanagaram | 13.0549854 | 80.1545772 |
| Head Office - Prestige | 13.0604 | 80.15483 |

`Head Office - Aalapakkam` from the page is accepted as an alias of the
existing app spelling `Head Office - Alapakkam`. Operation employees use
`Operation`; the existing four regular office choices remain unchanged.
Only those four existing app offices are enabled; the page's extra offices
are not added to the app.

The backend uses a parameterized read-only MariaDB calculation for Haversine
distance with Earth radius 6,371,000 meters, matching the Flutter calculation.
It rejects non-numeric, non-finite and out-of-range coordinates.

All endpoints require the normal Frappe session created by the existing login
flow. The API returns a consistent response shape:

```json
{
  "ok": true,
  "message": "Employee checked in.",
  "data": {
    "employee": "HR-EMP-0001",
    "employee_name": "Employee Name",
    "checked_in": true,
    "check_in_time": "2026-10-21 09:15:00",
    "check_out_time": null
  }
}
```

Attendance status uses only the current ERP date. Older Employee Checkin
records are not displayed or treated as an open check-in for today.

## Check-in request

```json
{
  "latitude": 13.0827,
  "longitude": 80.2707,
  "address": "Current address"
}
```

Validation performed:

- Resolves the employee from the authenticated Frappe user.
- Requires an active Employee record linked to that user.
- Validates latitude and longitude ranges.
- Stores the selected office in `custom_office_type`.
- Stores the GPS coordinates in `custom_latitude` and `custom_longitude`.
- Stores the location string in the Employee Checkin `device_id` field.
- Rejects a second check-in while today's attendance log is still open.
- Creates an `Employee Checkin` record with `log_type = IN`.

## Check-out request

The request body is the same as check-in. Validation performed:

- Resolves the employee from the authenticated Frappe user.
- Requires an open check-in for the employee on the current date.
- Rejects checkout when the employee is already checked out.
- Creates an `Employee Checkin` record with `log_type = OUT`.

## Deployment note

Open ERPNext Desk > Server Script and update the existing record:

1. API Method `farmgenie_employee_attendance`, using [attendance_api.py](./attendance_api.py).

Allow GET and POST, keep authentication enabled, and do not expose this API
publicly. The Employee role must be allowed to create Employee Checkin records;
the face guard (`../face/mobile_face_employee_checkin_guard.py`) blocks such
inserts from any other path for non-HR users.
