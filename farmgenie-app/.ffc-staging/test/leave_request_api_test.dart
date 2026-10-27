import 'dart:convert';

import 'package:farmgenie/services/farmgenie_api.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Map<String, dynamic>> submit({
  bool halfDay = false,
  String? halfDayDate,
}) => FarmgenieApi.createLeaveRequest(
  fromDate: '2026-10-31',
  toDate: '2026-11-02',
  halfDay: halfDay,
  halfDayDate: halfDayDate,
  leaveType: 'Leave Without Pay',
  description: 'Personal work',
  employee: 'HR-EMP-00035',
  company: 'Farmgenie',
  leaveApprover: 'manager@example.test',
);

http.Response desk() =>
    http.Response('<script>frappe.csrf_token = "session-token";</script>', 200);

Matcher errorContaining(String message) => throwsA(
  isA<FarmgenieApiException>().having(
    (error) => error.message,
    'message',
    contains(message),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'farmgenie_sid': 'session-1'});
    FarmgenieApi.resetSessionCache();
  });

  test('half-day leave sends the chosen half_day_date', () async {
    final client = MockClient((request) async {
      if (request.method == 'GET') return desk();
      expect(request.bodyFields['half_day'], '1');
      expect(request.bodyFields['half_day_date'], '2026-11-01');
      return http.Response('{"message":{"ok":true}}', 200);
    });
    final result = await http.runWithClient(
      () => submit(halfDay: true, halfDayDate: '2026-11-01'),
      () => client,
    );
    expect(result['ok'], true);
  });

  test('full-day leave never sends half_day_date', () async {
    final client = MockClient((request) async {
      if (request.method == 'GET') return desk();
      expect(request.bodyFields['half_day'], '0');
      expect(request.bodyFields.containsKey('half_day_date'), isFalse);
      return http.Response('{"message":{"ok":true}}', 200);
    });
    final result = await http.runWithClient(
      () => submit(halfDayDate: '2026-11-01'),
      () => client,
    );
    expect(result['ok'], true);
  });

  test('desk redirect to login reports an expired session', () async {
    final before = FarmgenieApi.sessionExpired.value;
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      return http.Response('', 302, headers: {'location': '/login'});
    });
    await expectLater(
      http.runWithClient(submit, () => client),
      throwsA(isA<SessionExpiredException>()),
    );
    expect(FarmgenieApi.sessionExpired.value, before + 1);
  });

  test('leave bootstraps CSRF and preserves every submission field', () async {
    final methods = <String>[];
    final client = MockClient((request) async {
      methods.add(request.method);
      expect(request.headers['cookie'], 'sid=session-1');
      expect(request.followRedirects, isFalse);
      if (request.method == 'GET') {
        expect(request.url.path, '/app');
        return desk();
      }
      expect(request.url.path, FarmgenieApi.leaveRequestPath);
      expect(request.headers['x-frappe-csrf-token'], 'session-token');
      expect(request.bodyFields, {
        'from_date': '2026-10-31',
        'to_date': '2026-11-02',
        'half_day': '0',
        'leave_type': 'Leave Without Pay',
        'description': 'Personal work',
        'employee': 'HR-EMP-00035',
        'company': 'Farmgenie',
        'leave_approver': 'manager@example.test',
      });
      return http.Response(
        '{"message":{"ok":true,"data":{"name":"LEAVE-1"}}}',
        200,
      );
    });
    final result = await http.runWithClient(submit, () => client);
    expect(result['data']['name'], 'LEAVE-1');
    expect(methods, ['GET', 'POST']);
  });

  test(
    'leave displays Frappe validation message without retrying POST',
    () async {
      var posts = 0;
      final client = MockClient((request) async {
        if (request.method == 'GET') return desk();
        posts++;
        return http.Response(
          jsonEncode({
            '_server_messages': jsonEncode([
              jsonEncode({'message': 'Leave overlaps <b>LEAVE-2</b>.'}),
            ]),
          }),
          417,
        );
      });
      await expectLater(
        http.runWithClient(submit, () => client),
        errorContaining('Leave overlaps LEAVE-2.'),
      );
      expect(posts, 1);
    },
  );

  test('CSRF rejection explains that sign-in is required', () async {
    final client = MockClient(
      (request) async => request.method == 'GET'
          ? desk()
          : http.Response('{"exc_type":"CSRFTokenError"}', 400),
    );
    await expectLater(
      http.runWithClient(submit, () => client),
      errorContaining('security token expired'),
    );
  });

  test('missing token blocks leave before POST', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      return http.Response('<html>Login</html>', 200);
    });
    await expectLater(
      http.runWithClient(submit, () => client),
      errorContaining('could not initialize'),
    );
  });

  test('missing session sends no requests', () async {
    FlutterSecureStorage.setMockInitialValues({});
    FarmgenieApi.resetSessionCache();
    final client = MockClient((_) async => fail('Must not send a request'));
    await expectLater(
      http.runWithClient(submit, () => client),
      errorContaining('session expired'),
    );
  });

  test('account change during bootstrap blocks POST', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      // Simulates another login replacing the stored session mid-request.
      await const FlutterSecureStorage().write(
        key: 'farmgenie_sid',
        value: 'session-2',
      );
      FarmgenieApi.resetSessionCache();
      return desk();
    });
    await expectLater(
      http.runWithClient(submit, () => client),
      errorContaining('account changed'),
    );
  });

  test('external bootstrap redirect never receives the cookie', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response(
        '',
        302,
        headers: {'location': 'https://other.example.test/app'},
      );
    });
    await expectLater(
      http.runWithClient(submit, () => client),
      errorContaining('different site'),
    );
    expect(calls, 1);
  });

  test('same-origin bootstrap redirect is supported', () async {
    var gets = 0;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        return http.Response('{"message":{"ok":true}}', 200);
      }
      gets++;
      if (gets == 1) {
        return http.Response('', 302, headers: {'location': '/app/home'});
      }
      expect(request.url.path, '/app/home');
      return desk();
    });
    expect((await http.runWithClient(submit, () => client))['ok'], true);
    expect(gets, 2);
  });
}
