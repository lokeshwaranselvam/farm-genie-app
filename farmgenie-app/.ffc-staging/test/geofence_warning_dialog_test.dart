import 'package:farmgenie/widgets/geofence_warning_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'recognizes app and ERP geofence failures without matching other errors',
    () {
      for (final message in [
        'You are 250 meters from Head Office - Vanagaram. Move within 100 meters to check in.',
        'Move within 100 meters of Head Office - Prestige to check out.',
        'Move within 200 meters of your check-in location to check out.',
        'You must be within 200 metres of the selected office',
        'You are outside the selected office area.',
        'Your office location is missing or not configured. Contact HR.',
        'This office is not available yet.',
      ]) {
        expect(GeofenceWarningDialog.matchesMessage(message), isTrue);
      }
      for (final message in [
        'Your session expired. Please log in again.',
        'Work completed for today. You cannot check in again today.',
        'Attendance request failed.',
      ]) {
        expect(GeofenceWarningDialog.matchesMessage(message), isFalse);
      }
    },
  );

  testWidgets('warning shows the distance message and closes with OK', (
    tester,
  ) async {
    const message =
        'You are 250 meters from Head Office - Vanagaram. '
        'Move within 100 meters to check out.';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const GeofenceWarningDialog(message: message),
                ),
                child: const Text('Show warning'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Show warning'));
    await tester.pumpAndSettle();
    expect(find.text('Location warning'), findsOneWidget);
    expect(find.text(message), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(GeofenceWarningDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(GeofenceWarningDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
