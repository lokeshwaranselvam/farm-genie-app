# FarmGenie face enrollment and attendance

Flutter project: `farmgenie-app/.ffc-staging`.
ERP origin: `https://farmgenie.itgenie.online` (the app's existing origin).
Reference checkout: `automate-genie-app/Genie1`.

## App behavior

After login or a restored session, the app checks ERP enrollment. An unenrolled
account must complete the front-camera blink and selfie setup before Home opens.
An enrolled account proceeds without taking another enrollment photo.
Each attendance check-in/check-out performs the same live blink, photo quality,
five-point alignment and local SFace match used by the reference checkout.
After matching, the existing fresh GPS/geofence checks must pass before the app
creates a receipt and calls the existing attendance API.
The action order is office selection (check-in), confirmation, live blink/face
match, fresh GPS/geofence, verification receipt, attendance submission. An
out-of-range location no longer prevents opening the attendance face scan.

The enrollment JPEG is private and attached to the authenticated User. Only that
photo is uploaded; attendance sends the score, model/reference identity, GPS and
receipt ID. Candidate images are temporary and deleted after the scan.
The account/reference/model-bound template uses secure storage and is cleared
on logout. Users cannot overwrite their enrolled reference through the face API.

The model is copied exactly, including the existing block-quantized artifact;
this port does not change its quantization or matching threshold:

- Asset: `assets/face_recognition/sface_2021dec.onnx`
- Version: `opencv-sface-2021dec-int8bq-v1`
- SHA-256: `487a139eb85ccd5ff30aef7d0add7f12d2bb7abb90c5f08a7f481b452a660e00`
- RGB float32 NCHW 112x112, 128-dimensional normalized embedding.
- ERP similarity threshold: `0.5`, matching the reference scripts.
- Android uses the reference `1.28.0-sface1` runtime under `android/runtime-maven`.
- Preserve the accompanying model/runtime license files when distributing.

## Install the three restricted Server Scripts

These files are **restricted Frappe Server Script bodies**, not importable custom
app modules. Paste each complete file into ERP Desk > Server Script. No imports,
custom Python functions, new DocTypes or schema migration are required.
Reuse an existing script record for the same method/event if already installed;
do not leave duplicate receipt guards enabled.

| File | Script Type | API Method / Reference DocType | Event |
| --- | --- | --- | --- |
| [mobile_face_auth.py](./mobile_face_auth.py) | API | `mobile_face_auth` | - |
| [mobile_face_employee_checkin_guard.py](./mobile_face_employee_checkin_guard.py) | DocType Event | `Employee Checkin` | Before Insert |
| [mobile_face_employee_checkin_attach.py](./mobile_face_employee_checkin_attach.py) | DocType Event | `Employee Checkin` | After Insert |

Keep Allow Guest disabled. Enable API rate limiting, for example 60 requests per
60 seconds. Server Scripts must already be enabled by the site administrator.
The installed ERP's exact version and runtime behavior still need a live check.
The scripts use the documented safe-exec session, File/Comment document and
database APIs; official implementation:
https://github.com/frappe/frappe/blob/version-15/frappe/utils/safe_exec.py

Install/update `mobile_face_auth` first. Coordinate enabling both Employee Checkin
hooks with distribution of the updated app: older FarmGenie clients do not send
receipts and will be rejected after the guard is enabled. Run the complete
login/enrollment/check-in/check-out verification before employee rollout.

The app now uses the supplied **API Method `mobile_checkin`** for status and both
attendance actions. Keep that deployed script, including its 200-metre validation,
session employee lookup, optimistic token and Labour/Operation rules. It uses
normal `doc.insert()`, so both receipt hooks run. No replacement attendance API
script is required. The older `farmgenie_employee_attendance` API is no longer
called by Flutter. Do not delete existing server records as part of this change.

Update BOTH receipt hook records from the files in this directory. They now
recognize `mobile_checkin`, `action=checkin` and `log_type=IN/OUT`, while retaining
support for the previous endpoint during rollout. `mobile_face_auth` is unchanged.
After installing these hooks, every writer using `mobile_checkin` action=checkin
must provide a face receipt, including any web clients sharing the endpoint.
Coordinate their rollout before enabling the updated hooks. Do not treat the
old deployed hooks as enforcing face receipts on the new endpoint.

Profile/leave details use Frappe's permission-checked `frappe.client.get_value`
for the Employee identified by `mobile_checkin`. The office for an open IN uses
the same API on that employee's Checkin. The calendar reads the same Attendance
records through `frappe.client.get_list`, filtered to that employee and month.
Employee accounts need existing read access to these own records and fields.
No permissions are bypassed or widened. Verify these reads with a normal employee
account before rollout. The request shapes were checked against Frappe's source:
https://github.com/frappe/frappe/blob/version-15/frappe/client.py

The two supplied guard attachments contain commented-out copies of the same
Before Insert guard. The files here are executable scripts adapted to FarmGenie's
`mobile_checkin` command and `action=checkin`, `log_type=IN/OUT` contract.
The After Insert hook links the consumed receipt to the actual Checkin name.

## API contract

All requests use the existing authenticated `sid` cookie. Never send a client
chosen employee or user as the identity for face enrollment/verification.

1. `GET /api/method/mobile_face_auth?action=status&model_version=opencv-sface-2021dec-int8bq-v1`

   `message` contains `status`, `current_user`, `enrolled`, `reference_file`
   (`name`, `url`, `version`, or null), `model_version`, `minimum_similarity`,
   `csrf_token` and `verification_receipt_version: 2`.
   If the session token has not been initialized, the app loads `/app` with the
   same session to initialize it; the account needs access to that Desk page.

2. `POST /api/method/mobile_face_auth` for first enrollment:

   ```json
   {
     "action": "enroll",
     "model_version": "opencv-sface-2021dec-int8bq-v1",
     "blink_completed": true,
     "csrf_token": "SESSION_CSRF_TOKEN",
     "image_base64": "LIVE_JPEG_BASE64"
   }
   ```

   Send `X-Frappe-CSRF-Token` with the same token. Maximum JPEG size: 2 MiB.
   Returns the enrolled status and private reference identity.

3. After a successful local face match and fresh GPS, POST to the same method:

   ```json
   {
     "action": "record_verification",
     "verification_action": "attendance_in",
     "model_version": "opencv-sface-2021dec-int8bq-v1",
     "reference_file": "REFERENCE_NAME_FROM_STATUS",
     "reference_version": "REFERENCE_VERSION_FROM_STATUS",
     "similarity": 0.75,
     "blink_completed": true,
     "latitude": 13.0431622,
     "longitude": 80.1609604,
     "captured_on": "2026-10-22T03:30:00Z",
     "csrf_token": "SESSION_CSRF_TOKEN"
   }
   ```

   Send the CSRF header too. For checkout use `attendance_out`. The response
   `message` contains `record_id`, `receipt_version: 2`, `current_user` and
   `verification_source: device_reported`. No attendance image is uploaded.

4. Submit immediately to the existing attendance endpoint, preserving its
   existing query parameters and adding the receipt in the POST form body:

   ```text
   POST /api/method/mobile_checkin
   Cookie: sid=EXISTING_SESSION
   X-Frappe-CSRF-Token: SESSION_CSRF_TOKEN
   Content-Type: application/x-www-form-urlencoded

   action=checkin&log_type=IN&latitude=13.0431622&longitude=80.1609604&custom_office_type=Head%20Office%20-%20Aalapakkam&expected_last_checkin=LATEST_ID_FROM_STATUS&attendance_security_token=SESSION_CSRF_TOKEN&face_verification=RECORD_ID_FROM_STEP_3
   ```

   For checkout use `log_type=OUT` and a new `attendance_out` receipt.
   Get `latest_checkin_id` from `GET /api/method/mobile_checkin?action=status`
   before scanning; send it as `expected_last_checkin`, including an empty string
   for a first punch. Never automatically retry a rejected/stale write.
   Flutter maps the supplied endpoint's status/response into its existing UI data.
   The hooks bind each
   receipt to the session user, active employee, action, reference version and
   submitted GPS. Receipts expire after 120 seconds and are single-use, with a
   row lock held through the attendance transaction. The After Insert hook
   records `used_for_name` without storing a new photo.

## Verification and limits

From `.ffc-staging`:

```powershell
flutter pub get
flutter test test/face_alignment_test.dart test/face_blink_controller_test.dart test/face_auth_api_test.dart test/face_enrollment_gate_test.dart test/face_attendance_submission_test.dart
python -m unittest discover -s test -p '*test.py'
flutter build apk --debug
```

On a real phone and the target ERP, verify new/existing enrollment, cancel/retry,
camera permission denial, wrong face, correct face, expired session, logout and
account switch, office geofence and existing Operation exemption, check-in and
checkout. Confirm missing/expired/reused/wrong-account receipts fail, and the
successful receipt links to its Employee Checkin. Verify unrelated Leave,
Material Request, Sales and attendance calendar screens still work.

Matching and blink results are **device-reported**, exactly as in the supplied
reference design. ERP validates receipt ownership and lifecycle; it does not
independently run SFace or establish that a modified client really blinked.
Do not describe this as server-verified biometric identity or strong anti-spoofing.
Enrollment lets the signed-in account choose its first reference face.
An authorized administrator must deliberately remove the account's private
`GENIE-FACE-REF-...` File to reset enrollment; the app offers no self-reset.

The reference implementation is native Android/iOS. Browser/PWA face capture is
not provided by these native ML Kit/ONNX files. iOS needs a Mac/device build and
plugin deployment-target verification before distribution. Local unit tests and
an Android build do not establish live ERP or physical-camera accuracy.
