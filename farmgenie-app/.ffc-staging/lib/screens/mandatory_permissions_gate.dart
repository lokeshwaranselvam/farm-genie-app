import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class MandatoryPermissionsGate extends StatefulWidget {
  const MandatoryPermissionsGate({
    super.key,
    required this.child,
    required this.onSignOut,
  });

  final Widget child;
  final Future<void> Function() onSignOut;

  @override
  State<MandatoryPermissionsGate> createState() =>
      _MandatoryPermissionsGateState();
}

class _MandatoryPermissionsGateState extends State<MandatoryPermissionsGate>
    with WidgetsBindingObserver {
  bool _checking = true;
  bool _cameraGranted = false;
  bool _locationGranted = false;
  bool _locationServicesEnabled = false;
  bool _openAppSettingsRequired = false;

  bool get _ready =>
      _cameraGranted && _locationGranted && _locationServicesEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPermissions(requestMissing: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions(requestMissing: false);
    }
  }

  Future<void> _checkPermissions({required bool requestMissing}) async {
    if (!mounted || (_checking && !requestMissing)) return;
    setState(() => _checking = true);

    try {
      var camera = await Permission.camera.status;
      if (requestMissing && !camera.isGranted && !camera.isPermanentlyDenied) {
        camera = await Permission.camera.request();
      }

      var location = await Geolocator.checkPermission();
      if (requestMissing && location == LocationPermission.denied) {
        location = await Geolocator.requestPermission();
      }
      final servicesEnabled = await Geolocator.isLocationServiceEnabled();

      if (!mounted) return;
      setState(() {
        _cameraGranted = camera.isGranted;
        _locationGranted =
            location == LocationPermission.whileInUse ||
            location == LocationPermission.always;
        _locationServicesEnabled = servicesEnabled;
        _openAppSettingsRequired =
            camera.isPermanentlyDenied ||
            camera.isRestricted ||
            location == LocationPermission.deniedForever ||
            location == LocationPermission.unableToDetermine;
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _continue() async {
    if (_checking) return;
    if (_openAppSettingsRequired) {
      await openAppSettings();
      return;
    }
    if (_cameraGranted && _locationGranted && !_locationServicesEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }
    await _checkPermissions(requestMissing: true);
  }

  Widget _permissionRow({
    required IconData icon,
    required String title,
    required bool granted,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Icon(icon, color: const Color(0xFF2D7842)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Icon(
          granted ? Icons.check_circle : Icons.error_outline,
          color: granted ? const Color(0xFF2D7842) : Colors.orange.shade800,
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;

    final buttonLabel = _openAppSettingsRequired
        ? 'Open app settings'
        : _cameraGranted && _locationGranted && !_locationServicesEnabled
        ? 'Turn on location'
        : 'Grant required permissions';

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(
                          Icons.admin_panel_settings_outlined,
                          size: 54,
                          color: Color(0xFF2D7842),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Permissions required',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'FarmGenie needs camera access for face verification '
                          'and location access for attendance. You can continue '
                          'after all required access is enabled.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        _permissionRow(
                          icon: Icons.camera_alt_outlined,
                          title: 'Camera access',
                          granted: _cameraGranted,
                        ),
                        _permissionRow(
                          icon: Icons.location_on_outlined,
                          title: 'Location access',
                          granted: _locationGranted,
                        ),
                        _permissionRow(
                          icon: Icons.location_searching,
                          title: 'Location services',
                          granted: _locationServicesEnabled,
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _checking ? null : _continue,
                          icon: _checking
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.settings_outlined),
                          label: Text(_checking ? 'Checking?' : buttonLabel),
                        ),
                        TextButton(
                          onPressed: _checking ? null : widget.onSignOut,
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
