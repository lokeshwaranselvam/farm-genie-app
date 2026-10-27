# Mobile device binding (one phone per user)

`mobile_auth.py` is a module for the custom Frappe app, not a Server Script.

1. Copy it to `apps/itgenie/itgenie/mobile_auth.py` and restart bench.
2. Run once from `bench --site <site> console` as Administrator:
   `from itgenie import mobile_auth; mobile_auth.install()`
3. Add `fcm_device_reset_button.js` as a Client Script on **FCM Device** (Form).
   HR Manager / System Manager users get a **Reset Mobile Device** button for
   lost or replaced phones. It calls `itgenie.mobile_auth.reset_device`.

Not yet wired into the app: the app still signs in through the standard
`/api/method/login`. Web check-in (iOS User role) also uses the standard login,
so it must stay open.
