import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_harbest_1/pages/get_started.dart';
import 'package:flutter_application_harbest_1/pages/user_dashboard.dart';
import 'package:flutter_application_harbest_1/security/forgot_password.dart';
import 'package:flutter_application_harbest_1/security/email_verification.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/widgets/app_snackbar.dart';
import 'package:flutter_application_harbest_1/widgets/app_header.dart';
import 'package:flutter_application_harbest_1/widgets/app_text_field.dart';
import 'package:flutter_application_harbest_1/widgets/app_button.dart';

// Must look like name@domain.tld
final _emailRegex = RegExp(
  r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9\-]+(\.[a-zA-Z0-9\-]+)*\.[a-zA-Z]{2,}$',
);
bool _hasValidEmailFormat(String email) =>
    !email.contains('..') && _emailRegex.hasMatch(email.trim());

/// True while this page is still checking a sign-in. AuthGate (main.dart)
/// waits while it is true, so the dashboard is never built for a login that
/// is about to be rejected.
final ValueNotifier<bool> loginInProgress = ValueNotifier<bool>(false);

const _badCredentials = 'Incorrect email or password. Please try again.';

class LogIn extends StatefulWidget {
  const LogIn({super.key});

  @override
  State<LogIn> createState() => _LogInState();
}

class _LogInState extends State<LogIn> {
  // Client-side lockout per email
  static const _maxAttempts = 3;
  static const _lockSeconds = 30;
  static const _prefsKey = 'login_lockout_state_v1';

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _attempts = <String, int>{};
  final _lockedUntil = <String, DateTime>{};
  bool _hidePassword = true;
  bool _busy = false;
  bool _leaving = false; // true once we've navigated to the next screen
  Timer? _ticker;

  String get _key => _email.text.trim().toLowerCase();

  int get _secondsLeft {
    final s = _lockedUntil[_key]?.difference(DateTime.now()).inSeconds ?? 0;
    return s > 0 ? s : 0;
  }

  @override
  void initState() {
    super.initState();
    _loadLockouts();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  // ── Lockout storage ──

  Future<void> _loadLockouts() async {
    final raw = (await SharedPreferences.getInstance()).getString(_prefsKey);
    if (raw == null) return;
    try {
      final now = DateTime.now();
      (jsonDecode(raw) as Map<String, dynamic>).forEach((email, v) {
        final ms = v['lockedUntil'] as int?;
        if (ms != null) {
          final until = DateTime.fromMillisecondsSinceEpoch(ms);
          if (until.isAfter(now)) _lockedUntil[email] = until;
        } else if ((v['attempts'] as int? ?? 0) > 0) {
          _attempts[email] = v['attempts'] as int;
        }
      });
    } catch (_) {} // unreadable saved state: start fresh
    if (!mounted) return;
    setState(() {});
    if (_lockedUntil.isNotEmpty) _startTicker();
  }

  Future<void> _saveLockouts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        for (final e in _attempts.entries) e.key: {'attempts': e.value},
        for (final e in _lockedUntil.entries)
          e.key: {'lockedUntil': e.value.millisecondsSinceEpoch},
      }),
    );
  }

  // Refreshes the "Try again in Ns" button and drops expired lockouts.
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      final now = DateTime.now();
      final before = _lockedUntil.length;
      _lockedUntil.removeWhere((_, until) => !until.isAfter(now));
      if (_lockedUntil.length != before) _saveLockouts();
      if (_lockedUntil.isEmpty) t.cancel();
      setState(() {});
    });
  }

  Future<void> _recordFailure(String message) async {
    final n = (_attempts[_key] ?? 0) + 1;
    if (n >= _maxAttempts) {
      _attempts.remove(_key);
      _lockedUntil[_key] =
          DateTime.now().add(const Duration(seconds: _lockSeconds));
      _startTicker();
      message = 'Too many failed attempts. Please try again in ${_lockSeconds}s.';
    } else {
      _attempts[_key] = n;
      final left = _maxAttempts - n;
      message = '$message $left attempt${left == 1 ? '' : 's'} remaining.';
    }
    await _saveLockouts();
    _snack(message);
  }

  // ── Sign in ──

  
  Future<bool> _emailMatchesRegistered(User user, String typed) async {
    var registered = user.email ?? '';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final stored = (doc.data()?['email'] as String?)?.trim();
      if (stored != null && stored.isNotEmpty) registered = stored;
    } catch (_) {}
    return typed == registered;
  }

  String? _inputError(String email) {
    if (email.isEmpty || _password.text.isEmpty) {
      return 'Please enter your email and password.';
    }
    if (!_hasValidEmailFormat(email)) {
      return 'Enter a valid email address with a domain (e.g. name@gmail.com).';
    }
    if (_secondsLeft > 0) {
      return 'Too many failed attempts. Please try again in ${_secondsLeft}s.';
    }
    return null;
  }

  Future<void> _onSignIn() async {
    final email = _email.text.trim();
    final error = _inputError(email);
    if (error != null) {
      _snack(error);
      return;
    }

    setState(() => _busy = true);
    loginInProgress.value = true; // AuthGate waits until our checks finish
    try {
      final user = (await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _password.text,
      ))
          .user!;

      if (!await _emailMatchesRegistered(user, email)) {
        await FirebaseAuth.instance.signOut();
        await _recordFailure(_badCredentials);
        return;
      }

      _attempts.remove(_key);
      _lockedUntil.remove(_key);
      await _saveLockouts();
      if (!mounted) return;

      if (!user.emailVerified) {
        _snack('Your email is not verified yet. Please verify it to continue.');
        _goTo(const EmailVerification());
        return;
      }

      // Keep Firestore's isVerified in sync with the real Auth status.
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({'isVerified': true}, SetOptions(merge: true));
      } catch (_) {
        // Non-critical; the account page retries this sync on load.
      }
      if (!mounted) return;
      _goTo(const UserDashboard());
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        _snack('No account found with this email. Please create an account.');
      } else if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        await _recordFailure(_errorText(e));
      } else {
        _snack(_errorText(e));
      }
    } catch (_) {
      _snack('An unexpected error occurred. Please try again.');
    } finally {
      // Stay "in progress" only if we're leaving for the next screen.
      if (!_leaving) loginInProgress.value = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  String _errorText(FirebaseAuthException e) => switch (e.code) {
        'wrong-password' => 'Incorrect password. Please try again.',
        'invalid-credential' => _badCredentials,
        'user-disabled' => 'This account has been disabled.',
        'too-many-requests' => 'Too many attempts. Please try again later.',
        'network-request-failed' => 'Network error. Check your connection.',
        _ => e.message ?? 'An unexpected error occurred.',
      };

  void _goTo(Widget page) {
    _leaving = true;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => page),
      (_) => false,
    );
  }

  void _snack(String message) {
    if (mounted) AppSnack.show(context, message, type: AppSnackType.error);
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    final left = _secondsLeft;

    return AuthScaffold(
      showBrand: false,
      topGap: MediaQuery.of(context).size.height * 0.22,
      centerHeader: true,
      title: 'Welcome back!',
      subtitle: 'Log in to access your crop analytics dashboard',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuthField(
            label: 'Email address',
            hint: 'name@example.com',
            icon: AppIcons.mail,
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            onChanged: (_) => setState(() {}), // lockout is per email
          ),
          AuthPasswordField(
            label: 'Password',
            hint: 'Enter your password',
            controller: _password,
            isVisible: !_hidePassword,
            onToggle: () => setState(() => _hidePassword = !_hidePassword),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ForgotPassword(initialEmail: _email.text),
                ),
              ),
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Forgot password?',
                  style: TextStyle(
                    color: AppColors.darkGreen,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.darkGreen,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          AuthPrimaryButton(
            label: left > 0 ? 'Try again in ${left}s' : 'Sign in',
            active: left == 0,
            loading: _busy,
            onPressed: left > 0 ? null : _onSignIn,
          ),
          const SizedBox(height: 28),
          AuthFooterLink(
            prompt: "Don't have an account?",
            linkText: 'Create account',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GetStarted()),
            ),
          ),
        ],
      ),
    );
  }
}