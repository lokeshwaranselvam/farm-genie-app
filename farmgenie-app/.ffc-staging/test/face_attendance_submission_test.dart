import 'dart:convert';

import 'package:farmgenie/services/farmgenie_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'farmgenie_sid': 'session-1',
    });
    FarmgenieApi.resetSessionCache();
  });

  for (final action in ['check_in', 'check_out']) {
    test(
      '$action carries receipt, CSRF and optimistic token to mobile_checkin',
      () async {
        var requests = 0;
        final client = MockClient((request) async {
          requests++;
          expect(request.method, 'POST');
          expect(request.url.origin, FarmgenieApi.baseUrl);
          expect(request.url.path, FarmgenieApi.attendancePath);
          expect(request.url.path, '/api/method/mobile_checkin');
          expect(request.url.queryParameters, isEmpty);
          expect(request.headers['cookie'], 'sid=session-1');
          expect(
            request.headers['x-frappe-csrf-token'],
            'verified-session-csrf',
          );
          expect(request.bodyFields, {
            'action': 'checkin',
            'log_type': action == 'check_in' ? 'IN' : 'OUT',
            'latitude': '13.0100000',
            'longitude': '80.1000000',
            'custom_office_type': 'Operation',
            'face_verification': 'receipt-1',
            'attendance_security_token': 'verified-session-csrf',
            'expected_last_checkin': 'CHECKIN-0',
          });
          return http.Response(
            jsonEncode({
              'message': {
                'status': 'success',
                'checkin_id': 'CHECKIN-1',
                'log_type': action == 'check_in' ? 'IN' : 'OUT',
                'time': '2026-10-22 10:00:00',
                'is_labour': false,
              },
            }),
            200,
          );
        });
        await http.runWithClient(
          () => FarmgenieApi.attendanceAction(
            action: action,
            latitude: 13.01,
            longitude: 80.1,
            officeType: 'Operation',
            address: 'Current location',
            faceVerification: 'receipt-1',
            faceCsrfToken: 'verified-session-csrf',
            expectedLastCheckin: 'CHECKIN-0',
          ),
          () => client,
        );
        expect(requests, 1);
      },
    );
  }

  test('missing receipt or CSRF blocks attendance before sending', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('{}', 500);
    });
    for (final values in [('', 'token'), ('receipt', '')]) {
      await expectLater(
        http.runWithClient(
          () => FarmgenieApi.attendanceAction(
            action: 'check_in',
            latitude: 13.01,
            longitude: 80.1,
            officeType: 'Operation',
            address: 'Current location',
            faceVerification: values.$1,
            faceCsrfToken: values.$2,
            expectedLastCheckin: '',
          ),
          () => client,
        ),
        throwsA(isA<FarmgenieApiException>()),
      );
    }
    expect(requests, 0);
  });
}
