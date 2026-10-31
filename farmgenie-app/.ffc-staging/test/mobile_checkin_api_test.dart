import 'dart:convert';

import 'package:farmgenie/services/farmgenie_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response reply(Object message, [int code = 200]) =>
    http.Response(jsonEncode({'message': message}), code);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'farmgenie_sid': 'session-1',
    });
    FarmgenieApi.resetSessionCache();
    FarmgenieApi.employeeProfile.value = {};
  });

  for (final next in ['IN', 'OUT', null]) {
    test(
      'mobile status maps $next and preserves employee profile fields',
      () async {
        final client = MockClient((request) async {
          expect(request.headers['cookie'], 'sid=session-1');
          expect(
            request.url.path,
            isNot(contains('farmgenie_employee_attendance')),
          );
          if (request.url.path == '/api/method/mobile_checkin') {
            expect(request.url.queryParameters['action'], 'status');
            return reply({
              'status': 'success',
              'employee': {
                'name': 'EMP-1',
                'employee_name': 'Test Employee',
                'company': 'Farm',
                'department': 'Accounts',
                'designation': 'Billing Associate',
                'branch': 'Alapakkam',
                'leave_approver': 'hr@example.test',
                'image': '/private/files/me.jpg',
              },
              'next_action': next,
              'latest_checkin_id': 'CHECKIN-1',
              'is_operation': false,
              'geofence_radius_meters': 275,
              'is_labour': false,
              'today_logs': [
                {
                  'name': 'CHECKIN-1',
                  'log_type': 'IN',
                  'time': '2026-10-22 09:00:00',
                },
              ],
            });
          }
          expect(request.url.path, '/api/method/frappe.client.get_value');
          final filters =
              jsonDecode(request.url.queryParameters['filters']!) as Map;
          if (request.url.queryParameters['doctype'] == 'Employee Checkin') {
            expect(filters, {'name': 'CHECKIN-1', 'employee': 'EMP-1'});
            return reply({'custom_office_type': 'Head Office - Aalapakkam'});
          }
          fail('Profile must not make a separate Employee request');
        });
        final result = await http.runWithClient(
          FarmgenieApi.attendanceStatus,
          () => client,
        );
        final data = result['data'] as Map;
        expect(data['employee'], 'EMP-1');
        expect(data['company'], 'Farm');
        expect(data['department'], 'Accounts');
        expect(data['designation'], 'Billing Associate');
        expect(data['branch'], 'Alapakkam');
        expect(data['image'], '/private/files/me.jpg');
        expect(FarmgenieApi.employeeProfile.value['image'], data['image']);
        expect(data['leave_approver'], 'hr@example.test');
        expect(data['checked_in'], next == 'OUT');
        expect(data['work_completed'], next == null);
        expect(data['latest_checkin_id'], 'CHECKIN-1');
        expect(data['geofence_radius_meters'], 275);
        if (next == 'OUT') {
          expect(data['office_type'], 'Head Office - Aalapakkam');
        }
      },
    );
  }

  test(
    'stale submission returns server message and never retries the punch',
    () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return reply({
          'status': 'error',
          'message': 'Attendance changed. Refresh status before trying again',
        }, 400);
      });
      await expectLater(
        http.runWithClient(
          () => FarmgenieApi.attendanceAction(
            action: 'check_in',
            latitude: 13,
            longitude: 80,
            officeType: 'Operation',
            address: 'Address',
            faceVerification: 'receipt',
            faceCsrfToken: 'csrf',
            expectedLastCheckin: 'old-id',
          ),
          () => client,
        ),
        throwsA(
          isA<FarmgenieApiException>().having(
            (error) => error.message,
            'message',
            contains('Attendance changed'),
          ),
        ),
      );
      expect(calls, 1);
    },
  );

  test(
    'Alapakkam spelling maps to the supplied API and Labour can check in again',
    () async {
      final client = MockClient((request) async {
        expect(
          request.bodyFields['custom_office_type'],
          'Head Office - Aalapakkam',
        );
        return reply({
          'status': 'success',
          'log_type': 'OUT',
          'checkin_id': 'OUT-1',
          'time': '2026-10-22 18:00:00',
          'is_labour': true,
        });
      });
      final result = await http.runWithClient(
        () => FarmgenieApi.attendanceAction(
          action: 'check_out',
          latitude: 13,
          longitude: 80,
          officeType: 'Head Office - Alapakkam',
          address: 'Address',
          faceVerification: 'receipt',
          faceCsrfToken: 'csrf',
          expectedLastCheckin: 'IN-1',
        ),
        () => client,
      );
      expect((result['data'] as Map)['work_completed'], isFalse);
      expect((result['data'] as Map)['next_action'], 'IN');
    },
  );

  test(
    'calendar reads the same employee Attendance records without the old API',
    () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/method/mobile_checkin') {
          return reply({
            'status': 'success',
            'employee': {'name': 'EMP-1', 'employee_name': 'Employee'},
            'today_logs': [],
            'latest_checkin_id': '',
            'next_action': 'IN',
            'is_operation': false,
          });
        }
        expect(request.url.path, '/api/method/frappe.client.get_list');
        final filters =
            jsonDecode(request.url.queryParameters['filters']!) as List;
        expect(filters, contains(equals(['employee', '=', 'EMP-1'])));
        expect(
          filters,
          contains(equals(['attendance_date', '>=', '2026-10-01'])),
        );
        expect(
          filters,
          contains(equals(['attendance_date', '<', '2026-11-01'])),
        );
        return reply([
          {
            'attendance_date': '2026-10-02',
            'status': 'On Leave',
            'late_entry': 0,
          },
          {
            'attendance_date': '2026-10-03',
            'status': 'Half Day',
            'early_exit': 1,
          },
        ]);
      });
      final records = await http.runWithClient(
        () => FarmgenieApi.attendanceCalendar(DateTime(2026, 10)),
        () => client,
      );
      expect(records[0]['date'], '2026-10-02');
      expect(records[0]['status'], 'leave');
      expect(records[1]['half_day'], isTrue);
      expect(records[1]['early_exit'], 1);
    },
  );
}
