# Camera2 post-capture crash fix

Based on camera_android 0.10.12; upstream source and BSD license are retained.
The app uses this path dependency so release builds contain the fix without
depending on edits to a developer's Pub cache.

On the Infinix X6815C, AndroidRuntime repeatedly reported a fatal
`IllegalStateException: CameraDevice was already closed` on CameraBackground.
The release mapping resolves `d9.q` to `Camera.unlockAutoFocus`, at both
`capture()` calls, reached from `Camera$4.onCaptureCompleted` (`a9`).
JPEG delivery and capture-completion callbacks are asynchronous. By the time
autofocus resets, Dart or the OS can already have closed the camera. The upstream
implementation catches CameraAccessException but not IllegalStateException.

Changes are limited to Camera.java and regression cases in CameraTest.java:

- Ignore still-photo completion callbacks belonging to an obsolete session.
- Retain a local session reference across the two autofocus reset requests.
- Treat a closed session/device during post-photo autofocus cleanup as finished
  cleanup, rather than an uncaught native exception. Other access errors retain
  the upstream error handling.

Run native tests from the app's android directory with
`gradlew :camera_android:testDebugUnitTest --tests io.flutter.plugins.camera.CameraTest`.
Recheck this patch when updating the camera dependency.

The later 16:12 device crash exposed a second cleanup race: `Reply already
submitted` from DartMessenger.error after the JPEG success response. Autofocus
preview restart errors now use the camera event channel, not the completed
photo request. Each takePicture result also accepts only its first completion,
and ImageSaver retains that capture's result rather than reading a later one.
CameraTest covers preview restart failure, and CaptureResultTest covers late
success/error callbacks in both orders.

Validation (2026-10-31): 78 CameraTest cases pass, including closure before
CANCEL, between CANCEL and IDLE, and clearing the session during CANCEL.
The app's 98 face/enrollment/attendance Flutter tests pass. Static analysis
passes for the changed Dart files. A signed release APK was built, its DEX
was checked for this patch, and it was installed successfully as an update on
the Infinix X6815C. Live selfie completion still requires a person on-device.
