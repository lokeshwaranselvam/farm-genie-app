import 'dart:async';

import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;

import '../widgets/warning_popup.dart';
import '../services/farmgenie_api.dart';
import '../services/remembered_login_store.dart';
import '../widgets/glass_home.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onLoggedIn});

  final VoidCallback onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with WarningPopupState {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _rememberedLogin = RememberedLoginStore();
  bool _restoringLogin = true;
  bool _savingPreference = false;
  bool _loading = false;
  bool _obscure = true;
  bool _rememberMe = true;

  @override
  void initState() {
    super.initState();
    _restoreLogin();
  }

  Future<void> _restoreLogin() async {
    try {
      final saved = await _rememberedLogin.read();
      if (!mounted) return;
      _rememberMe = saved.remember;
      // Do not overwrite anything the user has already started entering.
      if (_username.text.isEmpty && _password.text.isEmpty) {
        _username.text = saved.username;
        _password.text = saved.password;
      }
    } catch (_) {
      // Storage problems must not prevent normal ERP login.
    } finally {
      if (mounted) setState(() => _restoringLogin = false);
    }
  }

  Future<void> _changeRememberMe(bool? value) async {
    final remember = value ?? false;
    setState(() => _savingPreference = true);
    try {
      // Persist opting out immediately, without clearing the current inputs.
      await _rememberedLogin.save(remember: remember);
      if (mounted) setState(() => _rememberMe = remember);
    } catch (_) {
      if (mounted) {
        setState(
          () => warningMessage = 'Could not update Remember me. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _savingPreference = false);
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading || _restoringLogin || _savingPreference) return;
    if (!_formKey.currentState!.validate()) {
      WarningPopup.show(
        context,
        [
          if (_username.text.trim().isEmpty) 'Username is required',
          if (_password.text.isEmpty) 'Password is required',
        ].join('\n'),
      );
      return;
    }
    final username = _username.text.trim();
    final password = _password.text;
    setState(() {
      _loading = true;
      warningMessage = null;
    });
    try {
      await FarmgenieApi.login(username, password);
      try {
        await _rememberedLogin.save(
          remember: _rememberMe,
          username: username,
          password: password,
        );
      } catch (_) {
        if (mounted) {
          await WarningPopup.show(
            context,
            'Signed in, but could not save login details.',
          );
        }
      }
      if (mounted) widget.onLoggedIn();
    } on FarmgenieApiException catch (error) {
      if (mounted) setState(() => warningMessage = error.message);
    } on http.ClientException {
      if (mounted) setState(() => warningMessage = 'No internet connection.');
    } on TimeoutException {
      if (mounted) {
        setState(() => warningMessage = 'ERP is taking too long. Try again.');
      }
    } catch (_) {
      if (mounted) setState(() => warningMessage = 'Could not connect to ERP.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const BotanicalBackground(child: SizedBox.shrink()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 34),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 390),
                  child: FarmgenieGlassCard(
                    padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Image.asset(
                            'assets/images/farmgenie_logo.png',
                            height: 112,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Employee Login',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF101713),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Sign in to access your workspace',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF68726C),
                            ),
                          ),
                          const SizedBox(height: 22),
                          TextFormField(
                            controller: _username,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: _fieldDecoration(
                              label: 'ERP username or email',
                              icon: Icons.person_outline,
                            ),
                            errorBuilder: (context, error) =>
                                const SizedBox.shrink(),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Username is required'
                                : null,
                          ),
                          const SizedBox(height: 13),
                          TextFormField(
                            controller: _password,
                            obscureText: _obscure,
                            onFieldSubmitted: (_) => _login(),
                            decoration:
                                _fieldDecoration(
                                  label: 'Password',
                                  icon: Icons.lock_outline,
                                ).copyWith(
                                  suffixIcon: IconButton(
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: const Color(0xFF647069),
                                    ),
                                  ),
                                ),
                            errorBuilder: (context, error) =>
                                const SizedBox.shrink(),
                            validator: (value) => value == null || value.isEmpty
                                ? 'Password is required'
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              SizedBox(
                                width: 28,
                                height: 28,
                                child: Checkbox(
                                  value: _rememberMe,
                                  activeColor: const Color(0xFF2D7842),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  onChanged:
                                      _loading ||
                                          _restoringLogin ||
                                          _savingPreference
                                      ? null
                                      : _changeRememberMe,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Remember me',
                                style: TextStyle(fontSize: 12),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: () => WarningPopup.show(
                                  context,
                                  'Contact your ERP administrator to reset your password.',
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF27733D),
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 36),
                                ),
                                child: const Text(
                                  'Forgot password?',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF08B882), forestGreen],
                              ),
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF236637)
                                      .withValues(alpha: .24),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: FilledButton.icon(
                              onPressed:
                                  _loading ||
                                      _restoringLogin ||
                                      _savingPreference
                                  ? null
                                  : _login,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                disabledBackgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              icon: _loading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_loading ? 'Signing in...' : 'Log in'),
                                  if (!_loading) ...[
                                    const SizedBox(width: 8),
                                    const Icon(Icons.arrow_forward, size: 18),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Row(
                            children: [
                              Expanded(child: Divider()),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.verified_user_outlined,
                                      size: 15,
                                      color: Color(0xFF7A847E),
                                    ),
                                    SizedBox(width: 5),
                                    Text(
                                      'Secure ERP access',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF7A847E),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(child: Divider()),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 12),
      prefixIcon: Icon(icon, color: const Color(0xFF66716B)),
      filled: true,
      fillColor: const Color(0x99FFFFFF),
      contentPadding: const EdgeInsets.symmetric(vertical: 15),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFCCD3CE)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF398B4B), width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFC62828)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFC62828), width: 1.4),
      ),
    );
  }
}
