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

class LogIn extends StatefulWidget {
  const LogIn({super.key});

  @override
  State<LogIn> createState() => _LogInState();
}

class _LogInState extends State<LogIn> {
  bool _obscurePassword = true;
  bool _isSubmitting = false;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // Failed-login lockout, tracked per email address. Client-side UX layer
  // only; Firebase's own 'too-many-requests' throttling is the real
  // backend protection. Persisted via SharedPreferences so a restart
  // doesn't reset the count.
  static const int _maxLoginAttempts = 3;
  static const int _lockoutDurationSeconds = 30;
  static const String _lockoutPrefsKey = 'login_lockout_state_v1';
  final Map<String, int> _failedAttemptsByEmail = {};
  final Map<String, DateTime> _lockedUntilByEmail = {};
  Timer? _lockoutTicker;
  SharedPreferences? _prefs;

  String get _emailKey => _emailController.text.trim().toLowerCase();

  int get _currentLockoutSecondsRemaining {
    final until = _lockedUntilByEmail[_emailKey];
    if (until == null) return 0;
    final diff = until.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  bool get _isCurrentlyLockedOut => _currentLockoutSecondsRemaining > 0;

  Future<void> _loadLockoutState() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;

    final raw = prefs.getString(_lockoutPrefsKey);
    if (raw == null) return;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final now = DateTime.now();

      decoded.forEach((email, value) {
        final data = value as Map<String, dynamic>;
        final lockedUntilMillis = data['lockedUntil'] as int?;

        if (lockedUntilMillis != null) {
          final lockedUntil =
              DateTime.fromMillisecondsSinceEpoch(lockedUntilMillis);
          if (lockedUntil.isAfter(now)) {
            _lockedUntilByEmail[email] = lockedUntil;
          }
        } else {
          final attempts = data['attempts'] as int? ?? 0;
          if (attempts > 0) _failedAttemptsByEmail[email] = attempts;
        }
      });
    } catch (_) {
      // Corrupt or unreadable saved state — ignore and start fresh.
    }

    if (!mounted) return;
    setState(() {});
    if (_lockedUntilByEmail.isNotEmpty) _startLockoutTicker();
  }

  Future<void> _persistLockoutState() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;

    final Map<String, dynamic> toSave = {};
    _failedAttemptsByEmail.forEach((email, count) {
      toSave[email] = {'attempts': count};
    });
    _lockedUntilByEmail.forEach((email, until) {
      toSave[email] = {'lockedUntil': until.millisecondsSinceEpoch};
    });

    await prefs.setString(_lockoutPrefsKey, jsonEncode(toSave));
  }

  void _startLockoutTicker() {
    _lockoutTicker?.cancel();
    _lockoutTicker = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      final expired = _lockedUntilByEmail.entries
          .where((e) => !e.value.isAfter(now))
          .map((e) => e.key)
          .toList();

      if (expired.isNotEmpty) {
        for (final email in expired) {
          _lockedUntilByEmail.remove(email);
        }
        await _persistLockoutState();
      }

      if (_lockedUntilByEmail.isEmpty) {
        timer.cancel();
      }

      if (mounted) setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    _loadLockoutState();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _lockoutTicker?.cancel();
    super.dispose();
  }

  // handling sign in button tap
  Future<void> _onSignIn() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      _showSnackBar('Please enter your email and password.');
      return;
    }

    if (_isCurrentlyLockedOut) {
      _showSnackBar(
        'Too many failed attempts. Please try again in '
        '${_currentLockoutSecondsRemaining}s.',
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      // Successful sign-in — clear any prior failed attempts for this email.
      _failedAttemptsByEmail.remove(_emailKey);
      _lockedUntilByEmail.remove(_emailKey);
      await _persistLockoutState();

      final user = FirebaseAuth.instance.currentUser;

      // Unverified users go to the verification screen (stay signed in).
      if (user != null && !user.emailVerified) {
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const EmailVerification()),
          (_) => false,
        );
        return;
      }

      // Keep Firestore's isVerified in sync with the real Auth status.
      if (user != null) {
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({'isVerified': true}, SetOptions(merge: true));
        } catch (_) {
          // Non-critical; the account page retries this sync on load.
        }
      }

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const UserDashboard()),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      // Only real wrong-credential attempts count toward the lockout.
      const mismatchCodes = {
        'wrong-password',
        'invalid-credential',
        'user-not-found',
      };
      if (mismatchCodes.contains(e.code)) {
        final attempts = (_failedAttemptsByEmail[_emailKey] ?? 0) + 1;

        if (attempts >= _maxLoginAttempts) {
          _failedAttemptsByEmail.remove(_emailKey);
          _lockedUntilByEmail[_emailKey] = DateTime.now().add(
            const Duration(seconds: _lockoutDurationSeconds),
          );
          await _persistLockoutState();
          _startLockoutTicker();
          _showSnackBar(
            'Too many failed attempts. Please try again in '
            '${_lockoutDurationSeconds}s.',
          );
        } else {
          _failedAttemptsByEmail[_emailKey] = attempts;
          await _persistLockoutState();
          final remaining = _maxLoginAttempts - attempts;
          _showSnackBar(
            '${_mapFirebaseError(e)} $remaining attempt'
            '${remaining == 1 ? '' : 's'} remaining.',
          );
        }
      } else {
        _showSnackBar(_mapFirebaseError(e));
      }
    } catch (_) {
      if (!mounted) return;
      _showSnackBar('An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }


  String _mapFirebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-credential':
        return 'Incorrect email or password. Please try again.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      default:
        return e.message ?? 'An unexpected error occurred.';
    }
  }

  void _showSnackBar(String message) {
    AppSnack.show(context, message, type: AppSnackType.error);
  }

  @override
  Widget build(BuildContext context) {
    final locked = _isCurrentlyLockedOut;

    return AuthScaffold(
      // Same vertical level and centered heading as the previous design:
      // title sits about a third of the way down the screen.
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
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            // Lockout is per email, so refresh the button when it changes.
            onChanged: (_) => setState(() {}),
          ),

          AuthPasswordField(
            label: 'Password',
            hint: 'Enter your password',
            controller: _passwordController,
            isVisible: !_obscurePassword,
            onToggle: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),

          // Forgot password link, right-aligned under the password field
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ForgotPassword(initialEmail: _emailController.text),
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
            label: locked
                ? 'Try again in ${_currentLockoutSecondsRemaining}s'
                : 'Sign in',
            active: !locked,
            loading: _isSubmitting,
            onPressed: locked ? null : _onSignIn,
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