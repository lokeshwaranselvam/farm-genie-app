import 'dart:convert';

import 'package:farmgenie/screens/attendance_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:farmgenie/services/farmgenie_api.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:farmgenie/widgets/warning_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('attendance warning appears only in its popup', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'farmgenie_sid': 'test-session',
    });
    FarmgenieApi.resetSessionCache();
    final previousLocation = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = _DisabledLocation();
    addTearDown(() => GeolocatorPlatform.instance = previousLocation);
    const message =
        'Duplicate Checkin: You must wait at least 10 minutes between IN and OUT.';
    var sawAttendanceWarning = false;
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: AttendanceScreen())),
        );
        await tester.pumpAndSettle();
        // GPS may report its own warning on the test platform.
        for (
          var i = 0;
          i < 4 && find.byType(AlertDialog).evaluate().isNotEmpty;
          i++
        ) {
          final content =
              tester.widget<AlertDialog>(find.byType(AlertDialog)).content!
                  as Text;
          expect(find.text(content.data!, skipOffstage: false), findsOneWidget);
          if (content.data == message) sawAttendanceWarning = true;
          await tester.tap(find.text('OK'));
          await tester.pumpAndSettle();
        }
        expect(sawAttendanceWarning, isTrue);
        expect(find.text(message, skipOffstage: false), findsNothing);
        expect(tester.takeException(), isNull);
      },
      () => MockClient(
        (_) async => http.Response(jsonEncode({'message': message}), 417),
      ),
    );
  });

  testWidgets('concurrent warnings are queued and duplicates are shown once', (
    tester,
  ) async {
    late BuildContext source;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            source = context;
            return const Scaffold();
          },
        ),
      ),
    );
    final first = WarningPopup.show(source, 'Work completed for today.');
    final duplicate = WarningPopup.show(source, 'Work completed for today.');
    final second = WarningPopup.show(
      source,
      'Location permission is required.',
    );
    expect(identical(first, duplicate), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Work completed for today.'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Work completed for today.'), findsNothing);
    expect(find.text('Location permission is required.'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await Future.wait([first, duplicate, second]);
    expect(find.byType(AlertDialog), findsNothing);
    // A new attempt can report the same warning again after acknowledgement.
    WarningPopup.show(source, 'Work completed for today.');
    await tester.pumpAndSettle();
    expect(find.text('Work completed for today.'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  });

  testWidgets('a queued warning from a disposed screen is skipped', (
    tester,
  ) async {
    late BuildContext source;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            source = context;
            return const Scaffold();
          },
        ),
      ),
    );
    final pending = WarningPopup.show(source, 'Network unavailable.');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await pending;
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _DisabledLocation extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => false;
}
