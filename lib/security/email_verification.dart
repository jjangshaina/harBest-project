import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_harbest_1/pages/sign_in.dart';
import 'package:flutter_application_harbest_1/pages/user_dashboard.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/widgets/app_button.dart';
import 'package:flutter_application_harbest_1/widgets/app_snackbar.dart';

// The single, live verification screen. Reached from get_started.dart right
// after signup (user stays signed in) and from log_in.dart if someone tries
// to log in before verifying. Polls Firebase for verification status and
// keeps Firestore's isVerified field in sync once it detects success.
/// The email + password just used to sign up, kept in memory only (never
/// saved to disk) so this page can sign back in if the session was lost
/// before the user verified. Cleared as soon as it is no longer needed.
class PendingSignup {
  PendingSignup._();
  static String? email;
  static String? password;
  static String? name; // the full name typed on the Create account page

  /// True from the moment sign-up starts until verification finishes (or is
  /// cancelled). While true, AuthGate (main.dart) must not sign out the
  /// not-yet-verified user it sees.
  static bool active = false;

  static void clear() {
    email = null;
    password = null;
    name = null;
    active = false;
  }
}

class EmailVerification extends StatefulWidget {
  const EmailVerification({super.key});

  @override
  State<EmailVerification> createState() => _EmailVerificationState();
}

class _EmailVerificationState extends State<EmailVerification>
    with WidgetsBindingObserver {
  // The currently signed-in user, read fresh each time (a copy taken once at
  // start-up can go stale if the session changes).
  User? get _user => FirebaseAuth.instance.currentUser;

  // The signed-in user. If the session was lost, signs back in with the
  // sign-up details kept in memory. Null if there is no way to sign in.
  Future<User?> _ensureSignedIn() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser != null) return auth.currentUser;
    final email = PendingSignup.email, password = PendingSignup.password;
    if (email == null || password == null) return null;
    try {
      debugPrint('VERIFY: session was lost, signing in again.');
      final cred = await auth
          .signInWithEmailAndPassword(email: email, password: password)
          .timeout(kRequestTimeout * 2);
      return cred.user;
    } catch (e) {
      debugPrint('VERIFY: could not sign in again: $e');
      return null;
    }
  }

  bool _isResending = false; // Prevents spamming the resend button
  int _cooldownSeconds = 0; // Cooldown timer so user can only resend every 30 seconds
  Timer? _cooldownTimer; // Timer for managing the resend cooldown
  Timer? _checkTimer; // Polls Firebase every 5 seconds to check if email is verified
  bool _checking = false; // One check at a time
  bool _done = false; // Already moved on to the dashboard

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPolling(); // Begin checking verification status on page load
    _checkVerified(); // and check right away
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _checkTimer?.cancel();   // Stop polling when page is closed
    _cooldownTimer?.cancel(); // Stop cooldown timer when page is closed
    super.dispose();
  }

  // Coming back from the email app: check immediately instead of waiting for
  // the next 5-second round (timers can be paused while the app is away).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkVerified();
  }

  // Polls Firebase every 5 seconds to detect when the user verifies their email
  void _startPolling() {
    _checkTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkVerified(),
    );
  }

  Future<void> _checkVerified() async {
    if (_checking || _done || !mounted) return;
    _checking = true;
    try {
      final user = await _ensureSignedIn();
      if (user == null) return; // nobody to check; try again next round
      try {
        await user.reload().timeout(kRequestTimeout); // refresh from Firebase
      } catch (e) {
        debugPrint('VERIFY: reload failed: $e');
        return; // offline or slow; try again in 5 seconds
      }
      final refreshed = FirebaseAuth.instance.currentUser;
      if (refreshed?.emailVerified != true) return;

      _done = true;
      _checkTimer?.cancel(); // Stop polling once verified
      final signupName = PendingSignup.name;
      PendingSignup.clear();
      if (!mounted) return;

      // Keep Firestore in sync, but NEVER wait for it: on a slow connection a
      // Firestore write can hang, and the user must not be stuck here.
      unawaited(_syncProfile(refreshed!, signupName));

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const UserDashboard()),
        (_) => false,
      );
    } finally {
      _checking = false;
    }
  }

  // Marks the profile verified and makes sure the name typed at sign-up is
  // on it. If the sign-up could not save the profile earlier, creates it now.
  Future<void> _syncProfile(User user, String? signupName) async {
    try {
      final authName = user.displayName?.trim() ?? '';
      final name = authName.isNotEmpty ? authName : (signupName?.trim() ?? '');

      // Keep the login account's name too (the account page falls back to it).
      if (authName.isEmpty && name.isNotEmpty) {
        user.updateDisplayName(name).catchError((_) {});
      }

      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snap = await ref.get().timeout(kRequestTimeout);
      final storedName = ((snap.data()?['fullName'] as String?) ?? '').trim();

      await ref.set({
        'isVerified': true,
        if (storedName.isEmpty && name.isNotEmpty) 'fullName': name,
        if (!snap.exists) ...{
          'email': user.email,
          'focus_crop': 'Mustard Green',
          'createdAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('VERIFY: profile not synced: $e');
    }
  }

  // Resends the verification email and starts a 30-second cooldown
  Future<void> _resendEmail() async {
    setState(() => _isResending = true);
    try {
      final user = await _ensureSignedIn();
      if (user == null) {
        if (!mounted) return;
        AppSnack.show(
          context,
          'Your session ended. Please go back and sign in again.',
          type: AppSnackType.error,
        );
        return;
      }
      // Trigger Firebase to resend
      await user.sendEmailVerification().timeout(kRequestTimeout * 2);
      _startCooldown();
      if (!mounted) return;
      AppSnack.show(
        context,
        'Verification email resent. Please check your inbox.',
        type: AppSnackType.success,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      AppSnack.show(
        context,
        e.code == 'too-many-requests'
            ? 'Too many requests. Please wait a few minutes and try again.'
            : (e.message ?? 'Failed to resend. Please try again.'),
        type: AppSnackType.error,
      );
    } on TimeoutException {
      if (!mounted) return;
      AppSnack.show(
        context,
        'This is taking too long. Check your connection and try again.',
        type: AppSnackType.error,
      );
    } catch (_) {
      if (!mounted) return;
      AppSnack.show(
        context,
        'Failed to resend. Please try again.',
        type: AppSnackType.error,
      );
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  // Counts down 30 seconds before allowing the user to resend the verification email again
  void _startCooldown() {
    setState(() => _cooldownSeconds = 30);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _cooldownSeconds--;
        if (_cooldownSeconds <= 0) timer.cancel(); 
      });
    });
  }

  // Signs the user out and sends them back to the Login screen
  Future<void> _cancelAndSignOut() async {
    PendingSignup.clear();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LogIn()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Whether the resend button should be active
    final canResend = !_isResending && _cooldownSeconds <= 0;

    return Scaffold(
      backgroundColor: AppColors.authBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Email icon
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  AppIcons.emailUnread,
                  color: Colors.white,
                  size: 60,
                ),
              ),

              const SizedBox(height: 32),

              const Text('Verify your email', style: AppText.authTitle),

              const SizedBox(height: 16),

              // Instruction text showing which email address was used
              Text(
                'We sent a verification link to\n${_user?.email ?? PendingSignup.email ?? 'your email address'}',
                textAlign: TextAlign.center,
                style: AppText.authBody,
              ),

              const SizedBox(height: 8),

              // Auto-check note
              const Text(
                'This page will automatically continue\nonce your email is verified.',
                textAlign: TextAlign.center,
                style: AppText.authHint,
              ),

              const SizedBox(height: 40),

              // Resend button
              AppPillButton(
                // Show countdown text during cooldown, normal label otherwise
                label: _cooldownSeconds > 0
                    ? 'Resend in ${_cooldownSeconds}s'
                    : 'Resend Verification Email',
                active: canResend,
                loading: _isResending,
                onPressed: canResend ? _resendEmail : null,
              ),

              const SizedBox(height: 16),

              // Cancel link — signs out and returns to Login
              TextButton(
                onPressed: _cancelAndSignOut,
                child: const Text(
                  'Cancel and go back to Sign Up',
                  style: AppText.onDarkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}