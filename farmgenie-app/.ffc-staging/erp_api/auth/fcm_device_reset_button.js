// Frappe Client Script: DocType "FCM Device", Apply To: Form, Enabled.
// Lets HR free an employee's account from a lost or replaced phone.
frappe.ui.form.on("FCM Device", {
	refresh(frm) {
		if (frm.is_new() || !frm.doc.user) return;
		if (!frappe.user.has_role(["System Manager", "HR Manager"])) return;
		frm.add_custom_button(__("Reset Mobile Device"), () => {
			frappe.confirm(
				__("Sign {0} out of the Genie app and allow sign-in from a new phone?", [frm.doc.user]),
				() =>
					frappe
						.call({
							method: "itgenie.mobile_auth.reset_device",
							args: { user: frm.doc.user },
							freeze: true,
						})
						.then((r) => {
							const reset = r.message && r.message.status === "reset";
							frappe.show_alert({
								message: reset ? __("Mobile device reset") : __("No phone was registered"),
								indicator: reset ? "green" : "orange",
							});
							frm.reload_doc();
						})
			);
		});
	},
});
