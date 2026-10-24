import 'dart:convert';

import 'package:farmgenie/services/farmgenie_api.dart';
import 'package:farmgenie/utils/api/face_auth_api.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() async {
    await dotenv.load(fileName: '.env');
    FarmgenieApi.employeeProfile.value = {};
  });

  test('bundled environment points to FarmGenie mobile_checkin', () {
    expect(FarmgenieApi.baseUrl, 'https://farmgenie.itgenie.online');
    expect(
      FarmgenieApi.attendanceUrl,
      'https://farmgenie.itgenie.online/api/method/mobile_checkin',
    );
  });

  test(
    'configured URLs drive attendance, face and authenticated photos',
    () async {
      dotenv.testLoad(
        fileInput: '''
URL=https://farmgenie.example.test/api/method/test_checkin
SITE_URL=https://farmgenie.example.test/
''',
      );
      SharedPreferences.setMockInitialValues({'farmgenie_sid': 'test-session'});
      expect(
        FaceAuthApi.instance.site.origin,
        'https://farmgenie.example.test',
      );
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        expect(request.url.host, 'farmgenie.example.test');
        expect(request.headers['cookie'], 'sid=test-session');
        if (request.url.path == '/private/files/avatar.jpg') {
          return http.Response.bytes([1, 2, 3], 200);
        }
        expect(request.url.path, '/api/method/test_checkin');
        expect(request.bodyFields['action'], 'checkin');
        expect(request.bodyFields['log_type'], 'IN');
        return http.Response(
          jsonEncode({
            'message': {
              'status': 'success',
              'log_type': 'IN',
              'checkin_id': 'CHECKIN-1',
              'time': '2026-10-24 09:00:00',
              'is_labour': false,
            },
          }),
          200,
        );
      });
      await http.runWithClient(() async {
        await FarmgenieApi.attendanceAction(
          action: 'check_in',
          latitude: 13.01,
          longitude: 80.1,
          officeType: 'Operation',
          address: 'Current location',
          faceVerification: 'receipt',
          faceCsrfToken: 'csrf',
          expectedLastCheckin: '',
        );
        expect(await FarmgenieApi.employeePhoto('/private/files/avatar.jpg'), [
          1,
          2,
          3,
        ]);
        expect(
          await FarmgenieApi.employeePhoto(
            'https://other.example.test/avatar.jpg',
          ),
          isNull,
        );
      }, () => client);
      expect(requests, hasLength(2));
    },
  );
}
