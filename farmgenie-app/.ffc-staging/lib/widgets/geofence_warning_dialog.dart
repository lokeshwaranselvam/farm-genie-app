import 'package:flutter/material.dart';

class GeofenceWarningDialog extends StatelessWidget {
  const GeofenceWarningDialog({super.key, required this.message});

  final String message;

  /// Covers both the current ERP policy and older location validation messages.
  static bool matchesMessage(String message) {
    final text = message.toLowerCase();
    return text.contains('geofence') ||
        text.contains('working location') ||
        text.contains('outside the selected office area') ||
        text.contains('outside the allowed') ||
        (text.contains('within') &&
            (text.contains('meters') ||
                text.contains('metres') ||
                text.contains('meter radius'))) ||
        text.contains('office location is missing') ||
        text.contains('office location is not configured') ||
        text.contains('this office is not available yet') ||
        text.contains('check-in location is missing') ||
        text.contains('valid gps coordinates');
  }

  @override
  Widget build(BuildContext context) {
    final text = message.toLowerCase();
    final hidesDistance =
        text.contains('meters from') ||
        text.contains('metres from') ||
        text.contains('meter radius') ||
        text.contains('working location');
    final displayMessage = hidesDistance
        ? 'You are out of your working location. Please reach your working location and try again.'
        : message;
    return AlertDialog(
    backgroundColor: const Color(0xFFF1FFF6),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: Colors.white, width: 2),
    ),
    icon: const Icon(
      Icons.location_off_outlined,
      color: Color(0xFFBC6324),
      size: 36,
    ),
    title: const Text(
      'Location warning',
      style: TextStyle(fontWeight: FontWeight.w800),
    ),
    scrollable: true,
    content: Text(displayMessage, style: const TextStyle(height: 1.5)),
    actions: [
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF075C3D)),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('OK'),
      ),
    ],
    );
  }
}
