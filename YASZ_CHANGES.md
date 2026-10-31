# Yasz: face verification and attendance integration

This branch collects the FarmGenie mobile app updates for face capture,
employee attendance, profile data, permissions, and UI improvements.
The Flutter app is in `farmgenie-app/.ffc-staging`.

## Face verification and enrollment

- Retain blink-based selfie capture for enrollment and attendance verification.
- Patch the Android camera plugin to handle late autofocus callbacks after the
  camera or capture session closes.
- Prevent duplicate photo-result replies and keep image saving tied to the
  original capture request.
- Include the patched plugin as a local dependency with its upstream license,
  source, tests, and patch notes.
- Preserve ONNX Runtime classes in Android release builds and improve face
  inference resource handling.
- Keep the face oval clear and blur the surrounding camera preview. This is a
  visual positioning aid; it does not change the detector's input region.

## API integration and employee profiles

- Use the working `mobile_checkin` API for attendance status and IN/OUT actions,
  including session ownership checks and stale-submission protection.
- Return company, department, designation, branch, leave approver, and
  `Employee.image` in the authenticated employee response.
- Read profile fields directly from that response instead of issuing a separate
  Employee lookup that can fail with `frappe.exceptions.PermissionError`.
- Use the returned employee image path for the existing authenticated avatar
  loader. Private files still require ERP access for the signed-in user.
- The reference API supplied for profile fields was not used to replace the
  working check-in or checkout logic.

## Location, permissions, and UI

- Use the radius returned by the API instead of a frontend radius constant.
- Apply location/radius validation to both check-in and checkout, retaining the
  existing Operation exemption. The server setting is currently 100 metres.
- Handle missing or invalid radius values without inventing a client default.
- Add a camera/location permission gate and recheck permissions on app resume.
- Update the home and attendance presentation and add persisted theme choices
  in Profile: Farmgenie Green, Ocean Blue, and Earth Brown.

## Validation and deployment

- Latest focused validation: 18 Flutter tests and 2 Python server-script tests
  passed; analysis of the profile API changes and tests reported no issues.
- Earlier camera-patch validation covered 81 native camera/result tests.
- These checks do not establish that the final branch has passed an end-to-end
  release checkout on a physical device.
- Deploy `farmgenie-app/.ffc-staging/erp_api/attendance/attendance_api.py` to the
  ERP API Server Script named `mobile_checkin`, with guest access disabled.
- Rebuild the mobile app after deploying the updated API:

  ```powershell
  cd farmgenie-app/.ffc-staging
  flutter pub get
  flutter build apk --release
  ```

- APK output: `build/app/outputs/flutter-apk/app-release.apk` within the Flutter
  project. Publishing this branch does not deploy ERP or install the APK.
