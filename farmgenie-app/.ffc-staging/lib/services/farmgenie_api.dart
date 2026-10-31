import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../utils/face/face_template_cache.dart';
import '../utils/face/face_embedding_service.dart';
import 'attendance_geofence.dart';

class FarmgenieApiException implements Exception {
  const FarmgenieApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// ERP no longer accepts the stored session; the app must return to login.
class SessionExpiredException extends FarmgenieApiException {
  const SessionExpiredException()
    : super('Your session expired. Please log in again.');
}

class FarmgenieApi {
  FarmgenieApi._();
  static final employeeProfile = ValueNotifier<Map<String, dynamic>>({});

  /// Incremented whenever ERP reports that the stored session is gone.
  static final sessionExpired = ValueNotifier<int>(0);

  static void notifySessionExpired() => sessionExpired.value++;

  static Future<Uint8List?> employeePhoto(String path) async {
    final uri = Uri.parse(baseUrl).resolve(path);
    // Never forward the ERP session to a different image host or redirect.
    if (uri.origin != Uri.parse(baseUrl).origin) return null;
    final client = http.Client();
    try {
      final request = http.Request('GET', uri)..followRedirects = false;
      request.headers.addAll(_headers(await _sid()));
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      return await response.stream.toBytes().timeout(
        const Duration(seconds: 15),
      );
    } finally {
      client.close();
    }
  }

  static String get baseUrl =>
      dotenv.get('SITE_URL').trim().replaceFirst(RegExp(r'/+$'), '');
  // URL is the complete Server Script endpoint, not a dotted method prefix.
  static String get attendanceUrl => dotenv.get('URL').trim();
  static String get attendancePath => Uri.parse(attendanceUrl).path;
  static const leaveRequestPath =
      '/api/method/farmgenie_employee_leave_request';

  static Future<SharedPreferences> get _preferences async =>
      SharedPreferences.getInstance();

  static const _sidKey = 'farmgenie_sid';
  static const _secureStorage = FlutterSecureStorage();
  // Secure storage reads are slow; keep the session in memory once loaded.
  static String? _cachedSid;
  static bool _sidLoaded = false;

  static Future<String?> _sid() async {
    if (_sidLoaded) return _cachedSid;
    String? sid;
    try {
      sid = await _secureStorage.read(key: _sidKey);
    } catch (_) {
      // An unreadable keystore must not break every request; treat as no
      // session so the user signs in again.
    }
    if (sid == null || sid.isEmpty) {
      // One-time migration from the old plain-text SharedPreferences copy.
      final preferences = await _preferences;
      final legacy = preferences.getString(_sidKey);
      if (legacy != null && legacy.isNotEmpty) {
        sid = legacy;
        try {
          await _secureStorage.write(key: _sidKey, value: legacy);
          await preferences.remove(_sidKey);
        } catch (_) {
          // Keep the legacy copy so a later launch can retry the move.
        }
      }
    }
    // A concurrent login/logout may have stored a newer value meanwhile.
    if (_sidLoaded) return _cachedSid;
    _cachedSid = sid == null || sid.isEmpty ? null : sid;
    _sidLoaded = true;
    return _cachedSid;
  }

  static Future<void> _storeSid(String? sid) async {
    _cachedSid = sid;
    _sidLoaded = true;
    if (sid == null) {
      try {
        await _secureStorage.delete(key: _sidKey);
      } catch (_) {
        // The in-memory session is already cleared; ERP rejects a stale sid.
      }
    } else {
      await _secureStorage.write(key: _sidKey, value: sid);
    }
  }

  /// Forget the in-memory session so the next read comes from storage.
  @visibleForTesting
  static void resetSessionCache() {
    _cachedSid = null;
    _sidLoaded = false;
    _faceVerifiedSid = null;
    _faceVerifiedUser = null;
  }

  static Future<String?> faceSessionId() => _sid();
  static String? _faceVerifiedSid;
  static String? _faceVerifiedUser;

  /// Resolve ERP's canonical account name; login aliases are not biometric IDs.
  static Future<String?> faceSessionUser() async {
    final sid = await _sid();
    if (sid == null || sid.isEmpty) return null;
    if (_faceVerifiedSid == sid && _faceVerifiedUser != null) {
      return _faceVerifiedUser;
    }
    final client = http.Client();
    try {
      final request =
          http.Request(
              'GET',
              Uri.parse('$baseUrl/api/method/frappe.auth.get_logged_user'),
            )
            ..followRedirects = false
            ..headers.addAll(_headers(sid));
      final response = await (() async {
        return http.Response.fromStream(await client.send(request));
      })().timeout(const Duration(seconds: 15));
      final user = _json(response)['message'];
      if (user == 'Guest' || _indicatesExpiredSession(response)) {
        if (await _sid() == sid) notifySessionExpired();
        throw const SessionExpiredException();
      }
      if (response.statusCode != 200 || user is! String || user.isEmpty) {
        throw const FarmgenieApiException(
          'Your session expired. Please log in again.',
        );
      }
      if (await _sid() != sid) {
        throw const FarmgenieApiException(
          'Your account changed. Start the face scan again.',
        );
      }
      _faceVerifiedSid = sid;
      _faceVerifiedUser = user;
      return user;
    } finally {
      client.close();
    }
  }

  /// Ask ERP whether the stored session is still valid.
  ///
  /// Returns true when ERP confirms a signed-in user, false when there is no
  /// session or ERP reports Guest/expired, and null when ERP could not be
  /// reached, so callers can keep offline users signed in.
  static Future<bool?> validateSession() async {
    final sid = await _sid();
    if (sid == null || sid.isEmpty) return false;
    final client = http.Client();
    try {
      final request =
          http.Request(
              'GET',
              Uri.parse('$baseUrl/api/method/frappe.auth.get_logged_user'),
            )
            ..followRedirects = false
            ..headers.addAll(_headers(sid));
      final response = await (() async {
        return http.Response.fromStream(await client.send(request));
      })().timeout(const Duration(seconds: 10));
      final user = _json(response)['message'];
      if (user == 'Guest' || _indicatesExpiredSession(response)) return false;
      if (response.statusCode == 200 && user is String && user.isNotEmpty) {
        return true;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static Future<void> prepareWebSession() async {
    await _prepareWebSessionForHost(Uri.parse(baseUrl).host);
  }

  static Future<void> prepareSalesDashboardSession() async {
    await prepareWebSession();
  }

  static Future<void> _prepareWebSessionForHost(String host) async {
    final sid = await _sid();
    if (sid == null || sid.isEmpty) {
      throw const FarmgenieApiException(
        'Your session expired. Please log in again.',
      );
    }
    final cookies = WebViewCookieManager();
    await cookies.clearCookies();
    await cookies.setCookie(
      WebViewCookie(name: 'sid', value: sid, domain: host, path: '/'),
    );
  }

  static Map<String, String> _headers(String? sid, {bool jsonBody = false}) => {
    'Accept': 'application/json',
    if (jsonBody) 'Content-Type': 'application/json',
    if (sid != null && sid.isNotEmpty) 'Cookie': 'sid=$sid',
  };

  static Map<String, dynamic> _json(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return <String, dynamic>{};
  }

  /// True when ERP says the request was made without a valid login.
  static bool _indicatesExpiredSession(http.Response response) {
    final excType = _json(response)['exc_type']?.toString() ?? '';
    if (excType == 'SessionExpired' || excType == 'AuthenticationError') {
      return true;
    }
    if (response.statusCode != 401 && response.statusCode != 403) {
      return false;
    }
    final body = response.body;
    return body.contains('Login is required') ||
        body.contains('SessionExpired') ||
        (body.contains('PermissionError') && body.contains('Guest'));
  }

  /// Failure for an authenticated request; signals session expiry globally.
  static FarmgenieApiException _failure(http.Response response) {
    if (_indicatesExpiredSession(response)) {
      notifySessionExpired();
      return const SessionExpiredException();
    }
    return FarmgenieApiException(_error(response));
  }

  static String _error(http.Response response) {
    final decoded = _json(response);
    final message = decoded['message'];
    if (message is Map && message['message'] is String) {
      return _friendlyError(message['message'] as String);
    }
    if (message is String && message.isNotEmpty) {
      return _friendlyError(message);
    }
    final exception = decoded['exception'];
    if (exception is String && exception.isNotEmpty) {
      return _friendlyError(exception);
    }
    return 'ERP request failed (${response.statusCode}).';
  }

  static String _friendlyError(String value) {
    final message = value.replaceFirst(RegExp(r'^.*?ValidationError:\s*'), '');
    if (message.contains('outside the allowed')) {
      return 'You are outside the selected office area.';
    }
    if (message.contains('No active Employee')) {
      return 'Your ERP account is not linked to an active employee.';
    }
    if (message.contains('already checked in')) {
      return 'You are already checked in. Check out first.';
    }
    if (message.contains('already completed') ||
        message.contains('Work for today')) {
      return 'Work completed for today. You cannot check in again today.';
    }
    if (message.contains('not checked in')) {
      return 'You are not checked in. Check in first.';
    }
    if (message.contains('not configured')) {
      return 'This office is not available yet.';
    }
    if (message.contains('Invalid login credentials')) {
      return 'Username or password is incorrect.';
    }
    if (message.contains('Login is required')) {
      return 'Your session expired. Please log in again.';
    }
    return message.trim();
  }

  static Map<String, dynamic> _message(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _failure(response);
    }
    final decoded = _json(response);
    final message = decoded['message'];
    if (message is Map<String, dynamic>) return message;
    if (message is String && message.isNotEmpty) {
      return <String, dynamic>{'message': message};
    }
    return decoded;
  }

  static Future<bool> hasSession() async => (await _sid())?.isNotEmpty == true;

  static Future<String?> currentUser() async {
    final preferences = await _preferences;
    return preferences.getString('farmgenie_user');
  }

  static Future<void> login(String username, String password) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/method/login'),
          headers: _headers(null),
          body: {'usr': username, 'pwd': password},
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FarmgenieApiException(_error(response));
    }

    // package:http joins multiple Set-Cookie headers with commas, so sid may
    // follow another cookie instead of starting the header.
    final setCookie = response.headers['set-cookie'] ?? '';
    final sid = RegExp(
      r'(?:^|[;,]\s*)sid=([^;,]+)',
    ).firstMatch(setCookie)?.group(1)?.trim();
    if (sid == null || sid.isEmpty || sid == 'Guest') {
      throw const FarmgenieApiException(
        'Login succeeded but ERP did not return a session cookie.',
      );
    }

    _faceVerifiedSid = null;
    _faceVerifiedUser = null;
    await _storeSid(sid);
    final preferences = await _preferences;
    await preferences.setString('farmgenie_user', username);
  }

  /// Clears the local session; [remote] also closes it on ERP.
  static Future<void> logout({bool remote = true}) async {
    final sid = await _sid();
    try {
      if (remote) {
        await http
            .post(
              Uri.parse('$baseUrl/api/method/logout'),
              headers: _headers(sid),
            )
            .timeout(const Duration(seconds: 10));
      }
    } finally {
      await _storeSid(null);
      final preferences = await _preferences;
      await preferences.remove(_sidKey);
      await preferences.remove('farmgenie_user');
      _faceVerifiedSid = null;
      _faceVerifiedUser = null;
      await FaceTemplateCache.instance.clear();
      await FaceEmbeddingService.instance.clear();
      employeeProfile.value = {};
      await WebViewCookieManager().clearCookies();
    }
  }

  static Future<Map<String, dynamic>> attendanceStatus() async {
    final sid = await _sid();
    final uri = Uri.parse(attendanceUrl)
        .replace(queryParameters: const {'action': 'status'});
    final response = await http
        .get(uri, headers: _headers(sid))
        .timeout(const Duration(seconds: 15));
    final payload = _mobileAttendanceMessage(response);
    final employee = payload['employee'];
    if (employee is! Map ||
        employee['name'] is! String ||
        payload['today_logs'] is! List ||
        payload['latest_checkin_id'] is! String ||
        !payload.containsKey('next_action') ||
        ![null, 'IN', 'OUT'].contains(payload['next_action'])) {
      throw const FarmgenieApiException(
        'ERP returned incomplete attendance status.',
      );
    }
    // Profile fields come from the session-bound mobile_checkin response.
    // A separate Employee read may be denied for employee self-service users.
    final profile = <String, dynamic>{
      for (final field in [
        'company',
        'department',
        'designation',
        'branch',
        'leave_approver',
        'image',
      ])
        field: employee[field],
    };
    Map? lastIn;
    Map? lastOut;
    final previous = payload['previous'];
    if (previous is Map && previous['log_type'] == 'IN') lastIn = previous;
    for (final row in payload['today_logs'] as List) {
      if (row is! Map) continue;
      if (row['log_type'] == 'IN') {
        lastIn = row;
        lastOut = null;
      }
      if (row['log_type'] == 'OUT') lastOut = row;
    }
    String? office;
    if (payload['next_action'] == 'OUT' && lastIn != null) {
      final location = await _readEmployeeValue(
        sid,
        'Employee Checkin',
        {'name': lastIn['name'], 'employee': employee['name']},
        ['custom_office_type'],
      );
      office = location['custom_office_type']?.toString();
    }
    if (await _sid() != sid) {
      throw const FarmgenieApiException(
        'Your account changed. Refresh attendance.',
      );
    }
    final data = <String, dynamic>{
      ...profile,
      'employee': employee['name'],
      'employee_id': employee['name'],
      'employee_name': employee['employee_name'],
      'is_operation': payload['is_operation'],
      'geofence_radius_meters': AttendanceGeofence.parseRadiusMeters(
        payload['geofence_radius_meters'],
      ),
      'is_labour': payload['is_labour'],
      'checked_in': payload['next_action'] == 'OUT',
      'work_completed': payload['next_action'] == null,
      'office_type': office,
      'check_in_time': lastIn?['time'],
      'check_out_time': lastOut?['time'],
      'latest_checkin_id': payload['latest_checkin_id'],
      'next_action': payload['next_action'],
    };
    employeeProfile.value = data;
    return {'ok': true, 'data': data};
  }

  static Map<String, dynamic> _mobileAttendanceMessage(http.Response response) {
    final message = _message(response);
    if (message['status'] != 'success') {
      throw FarmgenieApiException(
        message['message']?.toString() ?? 'ERP could not confirm attendance.',
      );
    }
    return message;
  }

  static Future<Map<String, dynamic>> _readEmployeeValue(
    String? sid,
    String doctype,
    Map<String, dynamic> filters,
    List<String> fields,
  ) async {
    final uri = Uri.parse('$baseUrl/api/method/frappe.client.get_value')
        .replace(
          queryParameters: {
            'doctype': doctype,
            'filters': jsonEncode(filters),
            'fieldname': jsonEncode(fields),
          },
        );
    final response = await http
        .get(uri, headers: _headers(sid))
        .timeout(const Duration(seconds: 15));
    return _message(response);
  }

  static Future<List<Map<String, dynamic>>> attendanceCalendar(
    DateTime month,
  ) async {
    final sid = await _sid();
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    // mobile_checkin does not implement calendar. Read the same Attendance
    // records through Frappe's permission-checked API instead of the old script.
    final status = await attendanceStatus();
    final employee = (status['data'] as Map)['employee'];
    final uri = Uri.parse('$baseUrl/api/method/frappe.client.get_list').replace(
      queryParameters: {
        'doctype': 'Attendance',
        'fields': jsonEncode([
          'attendance_date',
          'status',
          'late_entry',
          'early_exit',
        ]),
        'filters': jsonEncode([
          ['employee', '=', employee],
          ['attendance_date', '>=', _date(start)],
          ['attendance_date', '<', _date(end)],
          ['docstatus', '<', 2],
        ]),
        'order_by': 'attendance_date asc, creation asc',
        'limit_page_length': '500',
      },
    );
    final response = await http
        .get(uri, headers: _headers(sid))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw _failure(response);
    }
    final records = _json(response)['message'];
    if (records is! List) {
      throw const FarmgenieApiException(
        'ERP returned invalid attendance records.',
      );
    }
    final daily = <String, Map<String, dynamic>>{};
    for (final record in records.whereType<Map>()) {
      final date = record['attendance_date']?.toString();
      if (date == null) continue;
      final rawStatus = record['status']?.toString().toLowerCase() ?? '';
      final normalized = rawStatus.contains('leave')
          ? 'leave'
          : rawStatus == 'half day'
          ? 'half'
          : rawStatus.replaceAll(' ', '_');
      daily[date] = {
        ...Map<String, dynamic>.from(record),
        'date': date,
        'status': normalized,
        'half_day': normalized == 'half',
      };
    }
    return daily.values.toList();
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static Future<Map<String, dynamic>> attendanceAction({
    required String action,
    required double latitude,
    required double longitude,
    required String officeType,
    required String address,
    required String faceVerification,
    required String faceCsrfToken,
    required String expectedLastCheckin,
  }) async {
    if (faceVerification.trim().isEmpty || faceCsrfToken.isEmpty) {
      throw const FarmgenieApiException(
        'Complete face verification before attendance.',
      );
    }
    final sid = await _sid();
    if (action != 'check_in' && action != 'check_out') {
      throw const FarmgenieApiException('Invalid attendance action.');
    }
    final before = Map<String, dynamic>.from(employeeProfile.value);
    final uri = Uri.parse(attendanceUrl);
    final response = await http
        .post(
          uri,
          headers: {..._headers(sid), 'X-Frappe-CSRF-Token': faceCsrfToken},
          body: {
            'action': 'checkin',
            'log_type': action == 'check_in' ? 'IN' : 'OUT',
            'latitude': latitude.toStringAsFixed(7),
            'longitude': longitude.toStringAsFixed(7),
            'custom_office_type': officeType == 'Head Office - Alapakkam'
                ? 'Head Office - Aalapakkam'
                : officeType,
            'face_verification': faceVerification,
            'attendance_security_token': faceCsrfToken,
            'expected_last_checkin': expectedLastCheckin,
          },
        )
        .timeout(const Duration(seconds: 15));
    final message = _mobileAttendanceMessage(response);
    final logType = action == 'check_in' ? 'IN' : 'OUT';
    if (message['log_type'] != logType ||
        message['checkin_id'] is! String ||
        message['time'] is! String) {
      throw const FarmgenieApiException(
        'ERP did not confirm the attendance record. Refresh status.',
      );
    }
    if (await _sid() != sid) {
      throw const FarmgenieApiException(
        'Your account changed. Refresh attendance.',
      );
    }
    final data = <String, dynamic>{
      ...before,
      'checked_in': logType == 'IN',
      'work_completed': logType == 'OUT' && message['is_labour'] != true,
      'office_type': officeType,
      'is_labour': message['is_labour'],
      'latest_checkin_id': message['checkin_id'],
      'next_action': logType == 'IN'
          ? 'OUT'
          : message['is_labour'] == true
          ? 'IN'
          : null,
      if (logType == 'IN') 'check_in_time': message['time'],
      if (logType == 'IN') 'check_out_time': null,
      if (logType == 'OUT') 'check_out_time': message['time'],
    };
    employeeProfile.value = data;
    return {'ok': true, 'data': data};
  }

  static FarmgenieApiException _leaveFailure(http.Response response) {
    if (_indicatesExpiredSession(response)) return _failure(response);
    return FarmgenieApiException(_leaveError(response));
  }

  static String _leaveError(http.Response response) {
    final decoded = _json(response);
    if (decoded['exc_type'] == 'CSRFTokenError') {
      return 'Your ERP security token expired. Please sign in again and retry.';
    }
    try {
      final raw = decoded['_server_messages'];
      final messages = raw is String ? jsonDecode(raw) : raw;
      if (messages is List) {
        for (final entry in messages) {
          final value = entry is String ? jsonDecode(entry) : entry;
          if (value is Map && value['message'] is String) {
            final message = (value['message'] as String)
                .replaceAll(RegExp(r'<[^>]*>'), '')
                .trim();
            if (message.isNotEmpty) return _friendlyError(message);
          }
        }
      }
    } catch (_) {}
    return _error(response);
  }

  static Future<String> _leaveCsrfToken(http.Client client, String sid) async {
    final site = Uri.parse(baseUrl);
    var uri = site.resolve('/app');
    for (var redirects = 0; redirects <= 3; redirects++) {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers.addAll({
          ..._headers(sid),
          'Accept': 'text/html',
          'Cache-Control': 'no-cache, no-store',
        });
      final response = await (() async {
        return http.Response.fromStream(await client.send(request));
      })().timeout(const Duration(seconds: 15));
      if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
        final location = response.headers['location'];
        if (location == null || location.isEmpty) break;
        final next = uri.resolve(location);
        if (next.origin != site.origin || next.userInfo.isNotEmpty) {
          throw const FarmgenieApiException(
            'ERP redirected to a different site. Check the ERP site URL.',
          );
        }
        // Desk sends signed-out users to the login page.
        if (next.path == '/login') {
          notifySessionExpired();
          throw const SessionExpiredException();
        }
        uri = next;
        continue;
      }
      if (response.statusCode != 200) {
        throw _leaveFailure(response);
      }
      final match = RegExp(r'''frappe\.csrf_token\s*=\s*["']([^"']+)["']''')
          .firstMatch(response.body);
      final token = match?.group(1)?.trim();
      if (token != null &&
          token.isNotEmpty &&
          token != 'None' &&
          token != 'null') {
        return token;
      }
      break;
    }
    throw const FarmgenieApiException(
      'ERP could not initialize the leave security token. '
      'Please sign in again. If this continues, check ERP Desk access.',
    );
  }

  static Future<Map<String, dynamic>> createLeaveRequest({
    required String fromDate,
    required String toDate,
    required bool halfDay,
    String? halfDayDate,
    required String leaveType,
    required String description,
    required String employee,
    required String company,
    required String leaveApprover,
  }) async {
    final sid = await _sid();
    if (sid == null || sid.isEmpty) {
      throw const FarmgenieApiException(
        'Your session expired. Please log in again.',
      );
    }
    final client = http.Client();
    try {
      final csrfToken = await _leaveCsrfToken(client, sid);
      if (await _sid() != sid) {
        throw const FarmgenieApiException(
          'Your account changed. Please reopen the leave request.',
        );
      }
      final request =
          http.Request('POST', Uri.parse(baseUrl + leaveRequestPath))
            ..followRedirects = false
            ..headers.addAll({
              ..._headers(sid),
              'X-Frappe-CSRF-Token': csrfToken,
            })
            ..bodyFields = {
              'from_date': fromDate,
              'to_date': toDate,
              'half_day': halfDay ? '1' : '0',
              if (halfDay && halfDayDate != null) 'half_day_date': halfDayDate,
              'leave_type': leaveType,
              'description': description,
              'employee': employee,
              'company': company,
              'leave_approver': leaveApprover,
            };
      final response = await (() async {
        return http.Response.fromStream(await client.send(request));
      })().timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _leaveFailure(response);
      }
      return _message(response);
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>> createMaterialRequest({
    required String itemCode,
    required double quantity,
    required String purpose,
  }) async {
    final sid = await _sid();
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/resource/Material%20Request'),
          headers: _headers(sid, jsonBody: true),
          body: jsonEncode({
            'data': {
              'material_request_type': 'Purchase',
              'transaction_date': DateTime.now()
                  .toIso8601String()
                  .split('T')
                  .first,
              'purpose': purpose,
              'items': [
                {
                  'item_code': itemCode,
                  'qty': quantity,
                  'schedule_date': DateTime.now()
                      .add(const Duration(days: 1))
                      .toIso8601String()
                      .split('T')
                      .first,
                },
              ],
            },
          }),
        )
        .timeout(const Duration(seconds: 15));
    return _message(response);
  }
}
