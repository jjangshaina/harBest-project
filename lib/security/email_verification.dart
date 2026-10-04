import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_harbest_1/pages/log_in.dart';
import 'package:flutter_application_harbest_1/pages/user_dashboard.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: 
          const Text('Verification email resent. Please check your inbox.'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      // Show error if resend fails
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Failed to resend. Please try again.'),
          backgroundColor: Colors.redAccent.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
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
      backgroundColor: const Color(0xFF2D5A27), 
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
                child: const Icon(Icons.mark_email_unread_outlined, color: Colors.white, size: 60),
              ),

              const SizedBox(height: 32),

              const Text(
                'Verify your email',
                style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 16),

              // Instruction text showing which email address was used
              Text(
                'We sent a verification link to\n${_user?.email ?? 'your email address'}',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 15, height: 1.5),
              ),

              const SizedBox(height: 8),

              // Auto-check note
              Text(
                'This page will automatically continue\nonce your email is verified.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13, height: 1.5),
              ),

              const SizedBox(height: 40),

              // Resend button 
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canResend ? const Color(0xFF7DB343) : Colors.white24,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 0,
                  ),
                  onPressed: canResend ? _resendEmail : null,
                  child: _isResending
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          // Show countdown text during cooldown, normal label otherwise
                          _cooldownSeconds > 0
                              ? 'Resend in ${_cooldownSeconds}s'
                              : 'Resend Verification Email',
                          style: const TextStyle(fontSize: 15),
                        ),
                ),
              ),

              const SizedBox(height: 16),

              // Cancel link — signs out and returns to Login
              TextButton(
                onPressed: _cancelAndSignOut,
                child: Text(
                  'Cancel and go back to Sign In',
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}