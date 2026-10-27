# Restricted Frappe Server Script: DocType Event, File, Before Delete.
# Install with mobile_face_auth. A registered face reference can only be reset
# by HR; otherwise an employee could delete it and enroll someone else's face.

if (doc.name or "").startswith("GENIE-FACE-REF-"):
    current_user = frappe.session.user
    if current_user != "Administrator" and not any(
        role in frappe.get_roles(current_user) for role in ("System Manager", "HR Manager")
    ):
        frappe.throw("Only HR can reset a registered face. Contact your administrator.")
