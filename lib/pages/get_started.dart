import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_harbest_1/pages/log_in.dart';
import 'package:flutter_application_harbest_1/security/email_verification.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/widgets/app_snackbar.dart';
import 'package:flutter_application_harbest_1/widgets/app_header.dart';
import 'package:flutter_application_harbest_1/widgets/app_text_field.dart';
import 'package:flutter_application_harbest_1/widgets/app_button.dart';

// disposable/fake email domains that are not allowed
const Set<String> _blockedDomains = {
  'mailinator.com',
  'guerrillamail.com',
  'tempmail.com',
  'yopmail.com',
  'trashmail.com',
  'maildrop.cc',
  'dispostable.com',
  'fakeinbox.com',
  'discard.email',
  'mailnesia.com',
  'spam4.me',
  'sharklasers.com',
};

// Exactly one "@", so the domain is everything after it.
final _emailRegex =
    RegExp(r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$');

// Returns true if the email passes format check and is not a blocked domain
bool _isValidEmail(String email) {
  final trimmed = email.trim();
  if (trimmed.contains('..') || !_emailRegex.hasMatch(trimmed)) return false;
  final domain = trimmed.substring(trimmed.indexOf('@') + 1).toLowerCase();
  return !_blockedDomains.contains(domain);
}

String _emailError(String email) {
  final trimmed = email.trim();
  if (trimmed.isEmpty) return 'Email address is required.';
  final domain =
      trimmed.contains('@') ? trimmed.split('@')[1].toLowerCase() : '';
  if (_blockedDomains.contains(domain)) {
    return 'Disposable email addresses are not allowed';
  }
  return 'Enter a valid email address. (e.g. example@gmail.com)';
}

// widget for the registration/sign-up screen
class GetStarted extends StatefulWidget {
  const GetStarted({super.key});

  @override
  State<GetStarted> createState() => _GetStartedState();
}

class _GetStartedState extends State<GetStarted> {
  // Slow phone connections need more than 12 s for sign-up steps.
  static const Duration _stepTimeout = Duration(seconds: 30);
  // The profile save may wait on a slow Firestore connection; it stays
  // queued on the phone, so do not make the user wait long for it.
  static const Duration _profileTimeout = Duration(seconds: 10);
  static const Duration _emailTimeout = Duration(seconds: 15);

  static final _uppercaseRegex = RegExp(r'[A-Z]');
  static final _digitRegex = RegExp(r'[0-9]');
  static final _specialCharRegex = RegExp(r'[!@#$%^&*(),.?":{}|<>]');

  // ── State ──

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _submitAttempted = false;
  bool _isSubmitting = false;

  bool _emailTouched = false;
  bool _passwordTouched = false;
  bool _confirmTouched = false;

  // Password strength requirement flags
  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasDigit = false;
  bool _hasSpecialChar = false;
  bool _passwordsMatch = false;

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  bool get _emailValid => _isValidEmail(_emailController.text);

  bool get _allRequirementsMet =>
      _hasMinLength &&
      _hasUppercase &&
      _hasDigit &&
      _hasSpecialChar &&
      _passwordsMatch;

  bool get _formIsValid =>
      _nameController.text.isNotEmpty &&
      _emailValid &&
      _passwordController.text.isNotEmpty &&
      _confirmPasswordController.text.isNotEmpty &&
      _allRequirementsMet;

  // ── Lifecycle ──

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ── Field changes ──

  void _onPasswordChanged(String value) {
    setState(() {
      _passwordTouched = true;
      _hasMinLength = value.length >= 8;
      _hasUppercase = value.contains(_uppercaseRegex);
      _hasDigit = value.contains(_digitRegex);
      _hasSpecialChar = value.contains(_specialCharRegex);
      _passwordsMatch = value == _confirmPasswordController.text;
    });
  }

  void _onConfirmPasswordChanged(String value) {
    setState(() {
      _confirmTouched = true;
      _passwordsMatch = value == _passwordController.text;
    });
  }

  // ── Create account ──

  // create account button tap
  Future<void> _onCreateAccount() async {
    setState(() {
      _submitAttempted = true;
      _emailTouched = true;
    });

    if (!_formIsValid) return;

    setState(() => _isSubmitting = true);

    // Tells AuthGate (main.dart) that a not-yet-verified user is expected
    // right now, so it must not sign them out.
    PendingSignup.active = true;
    var navigated = false;

    try {
      final name = _nameController.text.trim();
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      final auth = FirebaseAuth.instance;

      final user = await _createOrResumeAccount(email, password);

      // 1) Verification email FIRST, while the brand-new session is certainly
      //    valid. Slow steps after this can no longer stop it from being sent.
      var emailSent = await _sendVerificationWithRetry(user);

      // Backup copy of the name (the greeting falls back to it).
      try {
        await user.updateDisplayName(name).timeout(_profileTimeout);
      } catch (e) {
        debugPrint('SIGNUP: display name not saved: $e');
      }

      // 2) Save the profile in the background. It must never block or undo
      //    the sign-up: the account already exists and the app falls back to
      //    the display name above. If Firestore refuses (for example rules),
      //    the account is kept and the reason is only logged.
      unawaited(_saveProfile(user.uid, name, email));

      // 3) The verification page needs a signed-in user. If the session was
      //    lost along the way, sign back in with the same credentials.
      if (auth.currentUser == null) {
        debugPrint('SIGNUP: session was lost, signing in again.');
        final again = await _signIn(email, password);
        if (!emailSent) emailSent = await _sendVerificationWithRetry(again);
      }

      // Kept in memory only, so the verification page can sign back in if
      // the session was lost.
      PendingSignup.email = email;
      PendingSignup.password = password;
      PendingSignup.name = name;

      if (!mounted) return;

      navigated = true;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const EmailVerification()),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('SIGNUP: auth error ${e.code}: ${e.message}');
      if (!mounted) return;
      _showSnackBar(_mapFirebaseError(e));
    } on FirebaseException catch (e) {
      // Firestore errors (not FirebaseAuthException) land here.
      debugPrint('SIGNUP: firebase error ${e.plugin}/${e.code}: ${e.message}');
      if (!mounted) return;
      _showSnackBar(_mapFirestoreError(e));
    } on TimeoutException {
      if (!mounted) return;
      _showSnackBar(
        'This is taking too long. Check your connection and try again.',
      );
    } catch (e, st) {
      debugPrint('SIGNUP: unexpected error: $e\n$st');
      if (!mounted) return;
      _showSnackBar(
        isConnectionError(e)
            ? 'Network error. Check your connection.'
            : 'An unexpected error occurred. Please try again.',
      );
    } finally {
      // Sign-up did not reach the verification page: nothing is pending.
      if (!navigated) PendingSignup.clear();
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Creates the Auth account. If the email already exists, it may be a
  /// sign-up that finished on the server but timed out on the phone. Signing
  /// in with the same email + password proves it is the same person, so the
  /// sign-up simply continues. A different password, or an already verified
  /// account, still shows "account already exists".
  Future<User> _createOrResumeAccount(String email, String password) async {
    final auth = FirebaseAuth.instance;
    try {
      final cred = await auth
          .createUserWithEmailAndPassword(email: email, password: password)
          .timeout(_stepTimeout);
      return cred.user!;
    } on TimeoutException {
      // The phone stopped waiting, but the server may well have created the
      // account. Check by signing in with the same details; if that works,
      // carry on instead of telling the user it failed.
      try {
        return await _signIn(email, password);
      } on FirebaseAuthException catch (signInError) {
        debugPrint('SIGNUP: no account after timeout (${signInError.code})');
        // Never created: show the normal "taking too long" message.
        throw TimeoutException('Sign-up request timed out');
      }
    } on FirebaseAuthException catch (e) {
      if (e.code != 'email-already-in-use') rethrow;
      try {
        final user = await _signIn(email, password);
        await user.reload();
        final fresh = auth.currentUser ?? user;
        if (fresh.emailVerified) {
          await auth.signOut();
          throw e; // a finished account: really "already exists"
        }
        return fresh;
      } on FirebaseAuthException catch (signInError) {
        if (signInError.code == 'wrong-password' ||
            signInError.code == 'invalid-credential') {
          throw e; // someone else's account
        }
        rethrow;
      }
    }
  }

  Future<User> _signIn(String email, String password) async {
    final cred = await FirebaseAuth.instance
        .signInWithEmailAndPassword(email: email, password: password)
        .timeout(_stepTimeout);
    return cred.user!;
  }

  /// Sends the verification email, retrying on slow or flaky connections.
  /// Returns true once Firebase accepted it.
  Future<bool> _sendVerificationWithRetry(User user) async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await user.sendEmailVerification().timeout(_emailTimeout);
        return true;
      } on FirebaseAuthException catch (e) {
        debugPrint('SIGNUP: verification email attempt $attempt: ${e.code}');
        // Retrying cannot help with these.
        if (e.code == 'too-many-requests' ||
            e.code == 'user-disabled' ||
            e.code == 'no-current-user') {
          return false;
        }
      } catch (e) {
        debugPrint('SIGNUP: verification email attempt $attempt: $e');
      }
      if (attempt < 3) await Future.delayed(const Duration(seconds: 2));
    }
    return false;
  }

  /// Saves users/{uid}. Runs in the background; failures are only logged.
  Future<void> _saveProfile(String uid, String name, String email) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fullName': name,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
        'focus_crop': 'Mustard Green',
        'isVerified': false,
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      debugPrint('SIGNUP: profile not saved (${e.code}): ${e.message}');
    } catch (e) {
      debugPrint('SIGNUP: profile not saved: $e');
    }
  }

  // ── Error messages ──

  String _mapFirebaseError(FirebaseAuthException e) => switch (e.code) {
        'email-already-in-use' => 'An account with this email already exists.',
        'invalid-email' => 'The email address is not valid.',
        'weak-password' => 'Please choose a stronger password.',
        'network-request-failed' => 'Network error. Check your connection.',
        'too-many-requests' => 'Too many attempts. Please try again later.',
        _ => e.message ?? 'An unexpected error occurred.',
      };

  String _mapFirestoreError(FirebaseException e) => switch (e.code) {
        'permission-denied' => 'Could not save your profile (permission denied). '
            'Please contact support.',
        'unavailable' || 'deadline-exceeded' =>
          'Could not reach the server. Check your connection and try again.',
        _ => 'Could not finish creating your account (${e.code}). '
            'Please try again.',
      };

  void _showSnackBar(String message) {
    AppSnack.show(context, message, type: AppSnackType.error);
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    final emailValid = _emailValid;

    return AuthScaffold(
      // No "HarBest" text, and everything sits higher on the screen.
      showBrand: false,
      centerHeader: true,
      topGap: 4,
      cardGap: 16,
      title: 'Create account',
      subtitle: 'Join the field and monitor your crops',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuthField(
            label: 'Full name',
            hint: 'Enter your full name',
            icon: AppIcons.person,
            controller: _nameController,
            onChanged: (_) => setState(() {}),
            showError: _submitAttempted && _nameController.text.isEmpty,
            errorText: 'Full Name is required.',
          ),

          AuthField(
            label: 'Email address',
            hint: 'name@gmail.com',
            icon: AppIcons.mail,
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            showError: (_emailTouched || _submitAttempted) && !emailValid,
            errorText: _emailError(_emailController.text),
            onChanged: (_) => setState(() => _emailTouched = true),
            suffix: _emailTouched && _emailController.text.isNotEmpty
                ? Icon(
                    emailValid ? AppIcons.check : AppIcons.error,
                    color: emailValid ? AppColors.optimal : AppColors.critical,
                  )
                : null,
          ),

          AuthPasswordField(
            label: 'Password',
            hint: 'Create a password',
            controller: _passwordController,
            isVisible: _isPasswordVisible,
            onToggle: () =>
                setState(() => _isPasswordVisible = !_isPasswordVisible),
            onChanged: _onPasswordChanged,
            showError: _submitAttempted && _passwordController.text.isEmpty,
            errorText: 'Password is required.',
          ),

          if (_passwordTouched && !_allRequirementsMet)
            _buildPasswordRequirements(),

          AuthPasswordField(
            label: 'Confirm password',
            hint: 'Re-enter your password',
            controller: _confirmPasswordController,
            isVisible: _isConfirmPasswordVisible,
            onToggle: () => setState(
              () => _isConfirmPasswordVisible = !_isConfirmPasswordVisible,
            ),
            onChanged: _onConfirmPasswordChanged,
            showError:
                _submitAttempted && _confirmPasswordController.text.isEmpty,
            errorText: 'Please confirm your password.',
          ),

          if (_confirmTouched && _confirmPasswordController.text.isNotEmpty)
            _buildPasswordMatch(),

          const SizedBox(height: 36),

          AuthPrimaryButton(
            label: 'Create Account',
            active: _formIsValid && !_isSubmitting,
            loading: _isSubmitting,
            onPressed: _onCreateAccount,
          ),

          const SizedBox(height: 20),

          AuthFooterLink(
            prompt: 'Already have an account?',
            linkText: 'Sign in',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LogIn()),
            ),
          ),
        ],
      ),
    );
  }

  // password requirements checklist
  Widget _buildPasswordRequirements() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.rowBackground,
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Password must contain:',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          _req('At least 8 characters', _hasMinLength),
          _req('At least one uppercase letter (A-Z)', _hasUppercase),
          _req('At least one number (0-9)', _hasDigit),
          _req('At least one special character (!@#\$...)', _hasSpecialChar),
        ],
      ),
    );
  }

  Widget _req(String label, bool isMet) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            isMet ? AppIcons.check : AppIcons.unchecked,
            color: isMet ? AppColors.optimal : AppColors.textTertiary,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: isMet ? AppColors.optimal : AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // "Passwords match" / "do not match" line under the confirm field.
  Widget _buildPasswordMatch() {
    final color = _passwordsMatch ? AppColors.optimal : AppColors.critical;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Row(
        children: [
          Icon(
            _passwordsMatch ? AppIcons.check : AppIcons.cancel,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            _passwordsMatch ? 'Passwords match' : 'Passwords do not match',
            style: TextStyle(color: color, fontSize: 13),
          ),
        ],
      ),
    );
  }
}