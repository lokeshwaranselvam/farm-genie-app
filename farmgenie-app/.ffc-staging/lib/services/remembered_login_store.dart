import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Separate from ERP sessions so signing out retains opted-in login fields.
class RememberedLoginStore {
  static const _key = 'farmgenie_remembered_login_v1';
  final _storage = const FlutterSecureStorage();

  Future<({bool remember, String username, String password})> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return (remember: false, username: '', password: '');
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final remember = data['remember'] == true;
    return (
      remember: remember,
      username: remember && data['username'] is String
          ? data['username'] as String
          : '',
      password: remember && data['password'] is String
          ? data['password'] as String
          : '',
    );
  }

  Future<void> save({
    required bool remember,
    String username = '',
    String password = '',
  }) => _storage.write(
    key: _key,
    value: jsonEncode({
      'remember': remember,
      if (remember) 'username': username,
      if (remember) 'password': password,
    }),
  );
}
