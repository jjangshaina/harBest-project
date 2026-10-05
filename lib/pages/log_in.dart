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
import 'package:flutter_application_harbest_1/widgets/app_button.dart';
import 'package:flutter_application_harbest_1/widgets/app_snackbar.dart';
import 'package:flutter_application_harbest_1/widgets/app_text_field.dart';

class LogIn extends StatefulWidget {
  const LogIn({super.key});

  @override
  State<LogIn> createState() => _LogInState();
}

class _LogInState extends State<LogIn> {
  bool _obscurePassword = true;
  bool _isSubmitting = false; // True while Firebase sign-in request is in progress

  // Controllers to read email and password input values
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();


  // Failed-login lockout, tracked per email address (not just per screen
  // visit) so guessing at one account doesn't get mixed up with a
  // separate attempt on a different one. This is a client-side UX layer
  // only — it discourages fat-fingered retries through this screen, but
  // can't stop someone hitting Firebase's API directly. Firebase Auth's
  // own automatic throttling (the 'too-many-requests' error already
  // handled below) is the real backend-level protection underneath it.
  //
  // Persisted to local device storage (SharedPreferences) so a closed or
  // restarted app doesn't reset the count — only a genuinely expired
  // lockout or a successful login clears it. Uninstalling the app still
  // clears this data (SharedPreferences isn't Keychain-backed), so it
  // doesn't carry the reinstall-survival quirk the old StoringData had.
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

  // Loads any lockout/attempt state saved from a previous app session.
  // Expired lockouts are dropped rather than restored, so an old lockout
  // that already ran out while the app was closed doesn't linger.
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
          // Already expired while the app was closed — don't restore it.
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

  // Writes the current attempt/lockout state to disk so it survives an
  // app restart. Called after every change to either map.
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
    // Empty field validation
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      _showSnackBar('Please enter your email and password.');
      return;
    }

    // Locked out after too many failed attempts for this email
    if (_isCurrentlyLockedOut) {
      _showSnackBar(
        'Too many failed attempts. Please try again in '
        '${_currentLockoutSecondsRemaining}s.',
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Attempt to sign in with Firebase Authentication
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      // Successful sign-in — clear any prior failed attempts for this email.
      _failedAttemptsByEmail.remove(_emailKey);
      _lockedUntilByEmail.remove(_emailKey);
      await _persistLockoutState();

      final user = FirebaseAuth.instance.currentUser;

      // If the user hasn't verified their email yet, send them to the
      // dedicated verification screen instead of signing them back out.
      // It keeps them signed in, polls for verification automatically,
      // and offers Resend from one consistent place — the same screen
      // used right after signup.
      if (user != null && !user.emailVerified) {
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const EmailVerification()),
          (_) => false,
        );
        return; // Stop further execution since email is not verified
      }

      // At this point the user is signed in and verified. Keep Firestore's
      // isVerified field in sync with the real Firebase Auth status —
      // this is the only place that ever gets a chance to flip it from
      // false to true after signup, so accounts don't stay stuck with a
      // stale/incorrect value forever.
      if (user != null) {
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({'isVerified': true}, SetOptions(merge: true));
        } catch (_) {
          // Non-critical: don't block sign-in if this sync fails (e.g.
          // transient network issue). The account page will retry this
          // same sync the next time it loads.
        }
      }

      // Firebase Auth persists the signed-in session on its own, so no
      // separate "remember me" flag is needed here — AuthGate in main.dart
      // reads the real session via authStateChanges() on next launch.

      if (!mounted) return;
      // Navigate to Dashboard                                                                
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => UserDashboard()), 
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      // Only count actual wrong-credential attempts toward the lockout —
      // not network errors, disabled accounts, or Firebase's own
      // too-many-requests throttling (that's already a lockout in itself).
      const mismatchCodes = {'wrong-password', 'invalid-credential', 'user-not-found'};
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
        _showSnackBar(_mapFirebaseError(e)); // Show error message
      }
    } catch (_) {
      if (!mounted) return;
      _showSnackBar('An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // firebase auth error
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
  // error snackbar at the bottom of the screen (shared style)
  void _showSnackBar(String message) {
    AppSnack.show(context, message, type: AppSnackType.error);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: AppColors.authBackground,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: screenHeight - MediaQuery.of(context).padding.top,
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: screenHeight * 0.015),

                  // Back button
                  const AppBackButton(),

                  const Spacer(),

                  // Screen title
                  const Center(
                    child: Text('Welcome back!', style: AppText.authTitle),
                  ),

                  const SizedBox(height: 8),

                  const Center(
                    child: Text(
                      'Access your crop analytics dashboard',
                      style: AppText.authSubtitle,
                    ),
                  ),

                  SizedBox(height: screenHeight * 0.04),

                  // Email input field
                  AppTextField(
                    hint: 'Email Address',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                  ),

                  // Password input field
                  AppPasswordField(
                    hint: 'Password',
                    controller: _passwordController,
                    isVisible: !_obscurePassword,
                    onToggle: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),

                  const SizedBox(height: 12),

                  // Forgot Password link
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ForgotPassword(
                            initialEmail: _emailController.text,
                          ),
                        ),
                      ),
                      child: const Text(
                        'Forgot password?',
                        style: AppText.onDarkUnderline,
                      ),
                    ),
                  ),

                  SizedBox(height: screenHeight * 0.03),

                  // Sign In button with spinner while loading
                  AppPillButton(
                    label: _isCurrentlyLockedOut
                        ? 'Try again in ${_currentLockoutSecondsRemaining}s'
                        : 'Sign in',
                    loading: _isSubmitting,
                    onPressed: _isCurrentlyLockedOut ? null : _onSignIn,
                  ),

                  SizedBox(height: screenHeight * 0.025),

                  // Sign Up link for users without an account
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Don't have an account? ",
                          style: AppText.onDark.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const GetStarted(),
                            ),
                          ),
                          child: Text(
                            "Sign up",
                            style: AppText.onDarkLink.copyWith(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}