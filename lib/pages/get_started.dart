import 'package:flutter/material.dart';
import 'package:flutter_application_harbest_1/pages/log_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_harbest_1/security/email_verification.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/widgets/app_button.dart';
import 'package:flutter_application_harbest_1/widgets/app_snackbar.dart';
import 'package:flutter_application_harbest_1/widgets/app_text_field.dart';

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
  final trimmed = email.trim(); // Remove leading/trailing spaces
  final regex = RegExp(
    r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
  ); // Standard email format regex
  if (!regex.hasMatch(trimmed)) return false; // Fail if format doesn't match
  final parts = trimmed.split('@'); // Split into local and domain parts
  if (parts.length != 2) return false; // Must have exactly one '@'
  final domain = parts[1].toLowerCase(); // Extract domain in lowercase
  if (_blockedDomains.contains(domain)) return false; // Reject blocked domains
  if (trimmed.contains('..')) return false; // Reject consecutive dots
  return true; // Email passed all checks
}

String _emailError(String email) {
  final trimmed = email.trim();
  if (trimmed.isEmpty) return 'Email address is required.'; // Empty field
  final domain = trimmed.contains('@')
      ? trimmed.split('@')[1].toLowerCase()
      : '';
  if (_blockedDomains.contains(domain)) {
    return 'Disposable email addresses are not allowed'; // Blocked domain
  }
  return 'Enter a valid email address. (e.g. example@gmail.com)'; // Generic format error
}

// widget for the registration/sign-up screen
class GetStarted extends StatefulWidget {
  const GetStarted({super.key});

  @override
  State<GetStarted> createState() => _GetStartedState();
}

class _GetStartedState extends State<GetStarted> {
  // Tracks whether the user agreed to the terms
  bool _isAgreed = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _submitAttempted = false;
  // True while the Firebase request is in progress
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

  // Disposes all controllers when the widget is removed to free memory
  @override
  void dispose() {
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
      _passwordsMatch =
          value == _confirmPasswordController.text; // Re-check match
    });
  }

  // Called every time the confirm password field changes; checks if passwords match
  void _onConfirmPasswordChanged(String value) {
    setState(() {
      _confirmTouched = true;
      _passwordsMatch = value == _passwordController.text;
    });
  }

  // True only when all four password requirements are satisfied and passwords match
  bool get _allRequirementsMet =>
      _hasMinLength &&
      _hasUppercase &&
      _hasDigit &&
      _hasSpecialChar &&
      _passwordsMatch;

  // getters that validates the current email field value
  bool get _emailValid => _isValidEmail(_emailController.text);

  // True only when every field is filled, email is valid, password requirements are met, and terms are agreed
  bool get _formIsValid =>
      _nameController.text.isNotEmpty &&
      _emailValid &&
      _passwordController.text.isNotEmpty &&
      _confirmPasswordController.text.isNotEmpty &&
      _allRequirementsMet &&
      _isAgreed;

  // firebase errors 
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

  // createa+ccount button tap
Future<void> _onCreateAccount() async {
  setState(() {
    _submitAttempted = true;
    _emailTouched = true;
  });

  if (!_emailValid || !_formIsValid) return;

  setState(() => _isSubmitting = true);

  try {
    // creating authentication account
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
            // Reflects real verification status; the user hasn't clicked
            // the verification email yet at this point in the flow.
            'isVerified': false,
          });
    } catch (firestoreError) {
      try {
        await userCredential.user!.delete();
      } catch (_) {
        // Best-effort cleanup; if this also fails we still rethrow below
        // so the user sees an error rather than a false "success".
      }
      rethrow;
    }

    // trigger verification email
    await userCredential.user!.sendEmailVerification();

    if (!context.mounted) return;

    // Keep the user signed in and send them to the dedicated verification
    // screen, which polls for verification and auto-continues into the
    // Dashboard once confirmed — no separate re-login required.
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
                  const SizedBox(height: 30),

                  // Back button — navigates to the previous screen
                  const AppBackButton(),
                  const SizedBox(height: 60),

                  const Center(
                    child: Text('Create an Account', style: AppText.authTitle),
                  ),
                  const SizedBox(height: 20),

                  // Name input field
                  AppTextField(
                    hint: 'Full Name',
                    controller: _nameController,
                    onChanged: (_) => setState(() {}),
                    showError: _submitAttempted && _nameController.text.isEmpty,
                    errorText: 'Full Name is required.',
                  ),

                  // Email input field with real-time validation feedback
                  AppTextField(
                    hint: 'example@gmail.com',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    showError:
                        (_emailTouched || _submitAttempted) && !_emailValid,
                    errorText: _emailError(_emailController.text),
                    onChanged: (_) => setState(() => _emailTouched = true),
                    suffix: _emailTouched && _emailController.text.isNotEmpty
                        ? Icon(
                            _emailValid ? AppIcons.check : AppIcons.error,
                            color: _emailValid
                                ? AppColors.optimal
                                : AppColors.onDarkError,
                          )
                        : null,
                  ),

                  // Password input field
                  AppPasswordField(
                    hint: 'Password',
                    controller: _passwordController,
                    isVisible: _isPasswordVisible,
                    onToggle: () => setState(
                      () => _isPasswordVisible = !_isPasswordVisible,
                    ),
                    onChanged: _onPasswordChanged,
                    showError:
                        _submitAttempted && _passwordController.text.isEmpty,
                    errorText: 'Password is required.',
                  ),

                  // Show password requirements checklist if user is typing but not done yet
                  if (_passwordTouched && !_allRequirementsMet)
                    _buildPasswordRequirements(),

                  AppPasswordField(
                    hint: 'Confirm Password',
                    controller: _confirmPasswordController,
                    isVisible: _isConfirmPasswordVisible,
                    onToggle: () => setState(
                      () => _isConfirmPasswordVisible =
                          !_isConfirmPasswordVisible,
                    ),
                    onChanged: _onConfirmPasswordChanged,
                    showError:
                        _submitAttempted &&
                        _confirmPasswordController.text.isEmpty,
                    errorText: 'Please confirm your password.',
                  ),

                  // Show match/mismatch indicator once user starts typing in confirm field
                  if (_confirmTouched &&
                      _confirmPasswordController.text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
                      child: Row(
                        children: [
                          Icon(
                            _passwordsMatch ? AppIcons.check : AppIcons.cancel,
                            color: _passwordsMatch
                                ? AppColors.onDarkSuccess
                                : AppColors.onDarkError,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _passwordsMatch
                                ? 'Passwords match'
                                : 'Passwords do not match',
                            style: TextStyle(
                              color: _passwordsMatch
                                  ? AppColors.onDarkSuccess
                                  : AppColors.onDarkError,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 8),

                  // Terms of Service checkbox row
                  Row(
                    children: [
                      Checkbox(
                        value: _isAgreed,
                        onChanged: (val) => setState(() => _isAgreed = val!),
                        side: const BorderSide(color: Colors.white),
                        activeColor: AppColors.authAccent,
                      ),
                      const Expanded(
                        child: Text(
                          'I agree to the Terms of Service and Privacy Policy',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ],
                  ),

                  const Spacer(),

                  AppPillButton(
                    label: 'Create Account',
                    active: _formIsValid && !_isSubmitting,
                    loading: _isSubmitting,
                    onPressed: _onCreateAccount,
                  ),

                  const SizedBox(height: 16),

                  // "Already have an account? Sign in" link
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "Already have an account? ",
                          style: AppText.onDark,
                        ),
                        GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const LogIn()),
                          ),
                          child: const Text("Sign in", style: AppText.onDarkLink),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // password requirements checklist
  Widget _buildPasswordRequirements() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Password must contain:',
            style: TextStyle(
              color: Colors.white,
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

  // Builds a single requirement row with a check/unchecked icon and label
  Widget _req(String label, bool isMet) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            isMet ? AppIcons.check : AppIcons.unchecked,
            color: isMet ? AppColors.onDarkSuccess : Colors.white54,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: isMet ? AppColors.onDarkSuccess : Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}