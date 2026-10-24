# Frappe Server Script
# Script Type: API
# API Method: farmgenie_employee_leave_request
# HTTP Method: POST
#
# Creates a Leave Application for the authenticated employee.

from_date = (frappe.form_dict.get("from_date") or "").strip()
to_date = (frappe.form_dict.get("to_date") or "").strip()
leave_type = (frappe.form_dict.get("leave_type") or "").strip()
description = (frappe.form_dict.get("description") or "").strip()
employee_id = (frappe.form_dict.get("employee") or "").strip()
company = (frappe.form_dict.get("company") or "").strip()
leave_approver = (frappe.form_dict.get("leave_approver") or "").strip()
half_day = bool(frappe.utils.cint(frappe.form_dict.get("half_day") or 0))

if not frappe.session.user or frappe.session.user == "Guest":
    frappe.throw("Login is required.")

if not from_date or not to_date:
    frappe.throw("From date and to date are required.")
if not leave_type:
    frappe.throw("Leave type is required.")
if not description:
    frappe.throw("Reason is required.")

employee = frappe.db.get_value(
    "Employee",
    {"user_id": frappe.session.user, "status": "Active"},
    ["name", "employee_name", "company", "leave_approver"],
    as_dict=True,
)
if not employee:
    employee = frappe.db.get_value(
        "Employee",
        {"company_email": frappe.session.user, "status": "Active"},
        ["name", "employee_name", "company", "leave_approver"],
        as_dict=True,
    )
if not employee:
    employee = frappe.db.get_value(
        "Employee",
        {"personal_email": frappe.session.user, "status": "Active"},
        ["name", "employee_name", "company", "leave_approver"],
        as_dict=True,
    )
if not employee:
    employee = frappe.db.get_value(
        "Employee",
        {"name": frappe.session.user, "status": "Active"},
        ["name", "employee_name", "company", "leave_approver"],
        as_dict=True,
    )
if not employee:
    frappe.throw("No active Employee record matches the logged-in user.")

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
        "half_day_date": from_date if half_day else None,
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
        "leave_type": leave_type,
        "description": description,
        "status": leave_application.status,
    },
}
