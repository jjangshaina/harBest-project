import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_harbest_1/pages/log_in.dart';
import 'package:flutter_application_harbest_1/pages/user_dashboard.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/widgets/app_button.dart';
import 'package:flutter_application_harbest_1/widgets/app_snackbar.dart';

// The single, live verification screen. Reached from get_started.dart right
// after signup (user stays signed in) and from log_in.dart if someone tries
// to log in before verifying. Polls Firebase for verification status and
// keeps Firestore's isVerified field in sync once it detects success.
class EmailVerification extends StatefulWidget {
  const EmailVerification({super.key});

  @override
  State<EmailVerification> createState() => _EmailVerificationState();
}

class _EmailVerificationState extends State<EmailVerification> {
  // The currently signed-in user
  final _user = FirebaseAuth.instance.currentUser;

  bool _isResending = false; // Prevents spamming the resend button
  int _cooldownSeconds = 0; // Cooldown timer so user can only resend every 30 seconds
  Timer? _cooldownTimer; // Timer for managing the resend cooldown
  Timer? _checkTimer; // Polls Firebase every 5 seconds to check if email is verified

  @override
  void initState() {
    super.initState();
    _startPolling(); // Begin checking verification status on page load
  }

  @override
  void dispose() {
    _checkTimer?.cancel();   // Stop polling when page is closed
    _cooldownTimer?.cancel(); // Stop cooldown timer when page is closed
    super.dispose();
  }

  // Polls Firebase every 5 seconds to detect when the user verifies their email
  void _startPolling() {
    _checkTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _user?.reload(); // Refresh user data from Firebase
      final refreshedUser = FirebaseAuth.instance.currentUser;

      if (refreshedUser?.emailVerified == true) {
        _checkTimer?.cancel(); // Stop polling once verified
        if (!mounted) return;

        // Keep Firestore's isVerified field in sync with the real Auth
        // status, same as the login flow does. Non-critical if it fails —
        // don't block navigation on it.
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(refreshedUser!.uid)
              .set({'isVerified': true}, SetOptions(merge: true));
        } catch (_) {}

        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const UserDashboard()),
          (_) => false,
        );
      }
    });
  }

  // Resends the verification email and starts a 30-second cooldown
  Future<void> _resendEmail() async {
    setState(() => _isResending = true);
    try {
      // Trigger Firebase to resend
      await _user?.sendEmailVerification();
      _startCooldown();
      if (!mounted) return;
      AppSnack.show(
        context,
        'Verification email resent. Please check your inbox.',
        type: AppSnackType.success,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      // Show error if resend fails
      AppSnack.show(
        context,
        e.message ?? 'Failed to resend. Please try again.',
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
                  color: Colors.white.withOpacity(0.1),
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
                'We sent a verification link to\n${_user?.email ?? 'your email address'}',
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
                  'Cancel and go back to Sign In',
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