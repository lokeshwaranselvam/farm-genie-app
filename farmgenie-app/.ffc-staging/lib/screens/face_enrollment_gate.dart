import 'package:flutter/material.dart';

import '../widgets/warning_popup.dart';
import '../utils/api/face_auth_api.dart';
import '../utils/face/face_auth_flow.dart';
import '../widgets/glass_home.dart';

/// Server enrollment status controls first use, including restored sessions.
/// A local preference cannot skip enrollment or overwrite the user's reference.
class FaceEnrollmentGate extends StatefulWidget {
  const FaceEnrollmentGate({
    super.key,
    required this.child,
    this.loadStatus,
    this.enrollSelfie,
    required this.onSignOut,
    this.onReady,
  });

  final Widget child;
  final Future<FaceEnrollmentStatus> Function()? loadStatus;
  final Future<FaceEnrollmentStatus?> Function(
    BuildContext,
    FaceEnrollmentStatus,
  )?
  enrollSelfie;
  final Future<void> Function() onSignOut;
  final VoidCallback? onReady;

  @override
  State<FaceEnrollmentGate> createState() => _FaceEnrollmentGateState();
}

class _FaceEnrollmentGateState extends State<FaceEnrollmentGate>
    with WarningPopupState {
  bool _busy = true;
  bool _ready = false;
  FaceEnrollmentStatus? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      warningMessage = null;
    });
    try {
      final status = await (widget.loadStatus ?? FaceAuthApi.instance.status)();
      if (!mounted) return;
      setState(() => _status = status);
      if (status.enrolled) {
        setState(() {
          _ready = true;
          _busy = false;
        });
        widget.onReady?.call();
        return;
      }
      await _enroll(status);
    } catch (error) {
      if (mounted) {
        setState(() {
          warningMessage = error.toString();
          _busy = false;
        });
      }
    }
  }

  Future<void> _enroll(FaceEnrollmentStatus status) async {
    final result = await (widget.enrollSelfie ?? FaceAuthFlow.instance.enroll)(
      context,
      status,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ready = result?.enrolled == true;
      _status = result ?? status;
      warningMessage = _ready
          ? null
          : 'Take your first-login selfie to finish setup.';
    });
    if (_ready) widget.onReady?.call();
  }

  Future<void> _retry() async {
    if (_busy) return;
    // Refresh server state first: another successful request may have saved
    // the photo even when its response was interrupted on this phone.
    await _load();
  }

  Future<void> _signOut() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onSignOut().timeout(const Duration(seconds: 15));
    } catch (error) {
      if (mounted) {
        setState(() => warningMessage = 'Could not sign out. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;
    // Checking server status is not selfie setup. Only show enrollment copy
    // after the server confirms that this user has no reference photo.
    final needsSelfie = _status != null && !_status!.enrolled;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: needsSelfie
            ? AppBar(
                automaticallyImplyLeading: false,
                title: const Text('Set up your selfie'),
              )
            : null,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: FarmgenieGlassCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (needsSelfie) ...[
                      const Icon(
                        Icons.face_retouching_natural,
                        size: 72,
                        color: Color(0xFF075C3D),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Your attendance face photo',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Look at the front camera and blink once. Your selfie will be saved privately on your ERP User record and used for attendance check-in and check-out.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, height: 1.5),
                      ),
                    ],
                    if (_status != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _status!.currentUser,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (_busy)
                      const CircularProgressIndicator(color: Color(0xFF075C3D))
                    else ...[
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF075C3D),
                          ),
                          onPressed: _retry,
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: Text(
                            _status == null ? 'Retry' : 'Take selfie',
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _signOut,
                        child: const Text('Sign out'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
