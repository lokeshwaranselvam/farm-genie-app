# Frappe Server Script
# Script Type: API
# API Method: farmgenie_employee_leave_request
# HTTP Method: POST
#
# Creates a Leave Application for the authenticated employee.

# JSON bodies can carry lists/numbers; reject them instead of failing on strip().
fields = {}
for fieldname in ("from_date", "to_date", "leave_type", "description", "employee",
                  "company", "leave_approver", "half_day_date"):
    value = frappe.form_dict.get(fieldname)
    if value is not None and not isinstance(value, str):
        frappe.throw("Invalid value for " + fieldname + ".")
    fields[fieldname] = (value or "").strip()

from_date = fields["from_date"]
to_date = fields["to_date"]
leave_type = fields["leave_type"]
description = fields["description"]
employee_id = fields["employee"]
company = fields["company"]
leave_approver = fields["leave_approver"]
half_day_date = fields["half_day_date"]
half_day = bool(frappe.utils.cint(frappe.form_dict.get("half_day") or 0))

if not frappe.session.user or frappe.session.user == "Guest":
    frappe.throw("Login is required.")

if not from_date or not to_date:
    frappe.throw("From date and to date are required.")
if not leave_type:
    frappe.throw("Leave type is required.")
if not description:
    frappe.throw("Reason is required.")

# Only Employee.user_id links a login to an Employee; email fallbacks could
# resolve to a different person.
employees = frappe.get_all(
    "Employee",
    filters={"user_id": frappe.session.user, "status": "Active"},
    fields=["name", "employee_name", "company", "leave_approver"],
    limit_page_length=2,
)
if len(employees) != 1:
    frappe.throw("No active Employee record matches the logged-in user.")
employee = employees[0]

# Use the authenticated employee/company as the source of truth. The values
# sent by the mobile app are checked so an app cannot submit for another user.
if employee_id and employee_id != employee.name:
    frappe.throw("Employee does not match the logged-in user.")
if company and company != employee.company:
    frappe.throw("Company does not match the logged-in employee.")
if leave_approver and leave_approver != (employee.leave_approver or ""):
    frappe.throw("Leave approver does not match the logged-in employee.")

if frappe.utils.getdate(to_date) < frappe.utils.getdate(from_date):
    frappe.throw("To date cannot be before from date.")
if half_day:
    # Older app builds omit half_day_date; that is only unambiguous for one day.
    if not half_day_date:
        if from_date != to_date:
            frappe.throw("Choose which day is the half day.")
        half_day_date = from_date
    if not (frappe.utils.getdate(from_date) <= frappe.utils.getdate(half_day_date)
            <= frappe.utils.getdate(to_date)):
        frappe.throw("The half day must be between the from and to dates.")

leave_application = frappe.get_doc(
    {
        "doctype": "Leave Application",
        "employee": employee.name,
        "employee_name": employee.employee_name,
        "company": employee.company,
        "leave_approver": employee.leave_approver,
        "leave_type": leave_type,
        "from_date": from_date,
        "to_date": to_date,
        "half_day": half_day,
        "half_day_date": half_day_date if half_day else None,
        "description": description,
    }
)
leave_application.insert()

frappe.response["message"] = {
    "ok": True,
    "message": "Leave request submitted.",
    "data": {
        "name": leave_application.name,
        "employee": employee.name,
        "employee_id": employee.name,
        "company": employee.company,
        "leave_approver": employee.leave_approver,
        "from_date": from_date,
        "to_date": to_date,
        "half_day": half_day,
        "half_day_date": half_day_date if half_day else None,
        "leave_type": leave_type,
        "description": description,
        "status": leave_application.status,
    },
}
