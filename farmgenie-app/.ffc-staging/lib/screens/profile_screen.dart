import 'package:flutter/material.dart';

import '../widgets/warning_popup.dart';
import '../services/farmgenie_api.dart';
import '../widgets/employee_avatar.dart';
import '../widgets/glass_home.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with WarningPopupState {
  Map<String, dynamic> _data = {};
  String _username = '';
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      warningMessage = null;
    });
    try {
      final username = await FarmgenieApi.currentUser() ?? '';
      final response = await FarmgenieApi.attendanceStatus();
      if (!mounted) return;
      setState(() {
        _username = username;
        _data = Map<String, dynamic>.from(response['data'] as Map? ?? {});
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => warningMessage = 'Could not load your profile. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _field(IconData icon, String label, String? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF75839A)),
        const SizedBox(width: 12),
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF526078), fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value == null || value.isEmpty ? 'Not available' : value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final name = _data['employee_name']?.toString() ?? 'Employee';
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Profile',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : warningMessage != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 16),
                Center(
                  child: EmployeeAvatar(
                    name: name,
                    image: _data['image']?.toString(),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _data['designation']?.toString() ?? 'Farmgenie Employee',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF526078)),
                ),
                const SizedBox(height: 28),
                FarmgenieGlassCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 6,
                  ),
                  child: Column(
                    children: [
                      _field(
                        Icons.badge_outlined,
                        'Employee ID',
                        (_data['employee_id'] ?? _data['employee'])?.toString(),
                      ),
                      _field(Icons.mail_outline, 'Email / User', _username),
                      _field(
                        Icons.business_outlined,
                        'Company',
                        _data['company']?.toString(),
                      ),
                      _field(
                        Icons.groups_outlined,
                        'Department',
                        _data['department']?.toString(),
                      ),
                      _field(
                        Icons.location_on_outlined,
                        'Location',
                        _data['branch']?.toString(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
