import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_harbest_1/pages/log_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

// Returns true if the email passes format check and is not a blocked domain
bool _isValidEmail(String email) {
  final trimmed = email.trim();
  final regex = RegExp(r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$');
  if (!regex.hasMatch(trimmed)) return false;
  final parts = trimmed.split('@');
  if (parts.length != 2) return false;
  final domain = parts[1].toLowerCase();
  if (_blockedDomains.contains(domain)) return false;
  if (trimmed.contains('..')) return false;
  return true;
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
  bool _isAgreed = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _submitAttempted = false;
  bool _isSubmitting = false;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // Password strength requirement flags
  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasDigit = false;
  bool _hasSpecialChar = false;
  bool _passwordsMatch = false;

  bool _passwordTouched = false;
  bool _confirmTouched = false;
  bool _emailTouched = false;

  // Tap handlers for the "Terms of Service" / "Privacy Policy" links.
  late final TapGestureRecognizer _termsTap = TapGestureRecognizer()
    ..onTap = _onTermsTap;
  late final TapGestureRecognizer _privacyTap = TapGestureRecognizer()
    ..onTap = _onPrivacyTap;

  // TODO: open the real Terms of Service page once it is written.
  void _onTermsTap() {
    AppSnack.show(context, 'Terms of Service will be available soon.');
  }

  // TODO: open the real Privacy Policy page once it is written.
  void _onPrivacyTap() {
    AppSnack.show(context, 'Privacy Policy will be available soon.');
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _onPasswordChanged(String value) {
    setState(() {
      _passwordTouched = true;
      _hasMinLength = value.length >= 8;
      _hasUppercase = value.contains(RegExp(r'[A-Z]'));
      _hasDigit = value.contains(RegExp(r'[0-9]'));
      _hasSpecialChar = value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
      _passwordsMatch = value == _confirmPasswordController.text;
    });
  }

  void _onConfirmPasswordChanged(String value) {
    setState(() {
      _confirmTouched = true;
      _passwordsMatch = value == _passwordController.text;
    });
  }

  bool get _allRequirementsMet =>
      _hasMinLength &&
      _hasUppercase &&
      _hasDigit &&
      _hasSpecialChar &&
      _passwordsMatch;

  bool get _emailValid => _isValidEmail(_emailController.text);

  bool get _formIsValid =>
      _nameController.text.isNotEmpty &&
      _emailValid &&
      _passwordController.text.isNotEmpty &&
      _confirmPasswordController.text.isNotEmpty &&
      _allRequirementsMet &&
      _isAgreed;

  String _mapFirebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'An account with this email already exists.';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'weak-password':
        return 'Please choose a stronger password.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return e.message ?? 'An unexpected error occurred.';
    }
  }

  // create account button tap
  Future<void> _onCreateAccount() async {
    setState(() {
      _submitAttempted = true;
      _emailTouched = true;
    });

    if (!_emailValid || !_formIsValid) return;

    setState(() => _isSubmitting = true);

    try {
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );

      // save user record to Firestore first. If this fails, roll back the
      // just-created Auth account so we don't leave an orphaned account with
      // no Firestore doc — which would silently break the rest of the app
      // and block the user from ever signing up again with this email.
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .set({
              'fullName': _nameController.text.trim(),
              'email': _emailController.text.trim(),
              'createdAt': FieldValue.serverTimestamp(),
              'focus_crop': 'Mustard Green',
              'isVerified': false,
            });
      } catch (firestoreError) {
        try {
          await userCredential.user!.delete();
        } catch (_) {}
        rethrow;
      }

      await userCredential.user!.sendEmailVerification();

      if (!context.mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const EmailVerification()),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!context.mounted) return;
      _showSnackBar(_mapFirebaseError(e));
    } catch (e) {
      if (!context.mounted) return;
      _showSnackBar('An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }


  void _showSnackBar(String message) {
    AppSnack.show(context, message, type: AppSnackType.error);
  }

  @override
  Widget build(BuildContext context) {
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
            hint: 'name@example.com',
            icon: AppIcons.mail,
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            showError: (_emailTouched || _submitAttempted) && !_emailValid,
            errorText: _emailError(_emailController.text),
            onChanged: (_) => setState(() => _emailTouched = true),
            suffix: _emailTouched && _emailController.text.isNotEmpty
                ? Icon(
                    _emailValid ? AppIcons.check : AppIcons.error,
                    color:
                        _emailValid ? AppColors.optimal : AppColors.critical,
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
            helperText: _passwordTouched ? null : 'At least 8 characters',
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
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Row(
                children: [
                  Icon(
                    _passwordsMatch ? AppIcons.check : AppIcons.cancel,
                    color: _passwordsMatch
                        ? AppColors.optimal
                        : AppColors.critical,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _passwordsMatch
                        ? 'Passwords match'
                        : 'Passwords do not match',
                    style: TextStyle(
                      color: _passwordsMatch
                          ? AppColors.optimal
                          : AppColors.critical,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

          // Terms of Service checkbox row
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Checkbox(
                value: _isAgreed,
                onChanged: (val) => setState(() => _isAgreed = val ?? false),
                side: const BorderSide(color: AppColors.darkGreen, width: 1.4),
                activeColor: AppColors.green,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: AppText.subtitle.copyWith(fontSize: 12.5),
                    children: [
                      const TextSpan(
                        text: "I have read and agree with HarBest's ",
                      ),
                      TextSpan(
                        text: 'Terms of Service',
                        recognizer: _termsTap,
                        style: const TextStyle(
                          color: AppColors.darkGreen,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      const TextSpan(text: ' and '),
                      TextSpan(
                        text: 'Privacy Policy',
                        recognizer: _privacyTap,
                        style: const TextStyle(
                          color: AppColors.darkGreen,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 30),

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
}