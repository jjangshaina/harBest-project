import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/widgets/app_snackbar.dart';
import 'package:flutter_application_harbest_1/widgets/app_header.dart';
import 'package:flutter_application_harbest_1/widgets/app_text_field.dart';
import 'package:flutter_application_harbest_1/widgets/app_button.dart';

class ForgotPassword extends StatefulWidget {
  const ForgotPassword({super.key, this.initialEmail});

  // Optional: pass in whatever the user already typed on the Log In page
  // so this field can arrive pre-filled.
  final String? initialEmail;

  @override
  State<ForgotPassword> createState() => _ForgotPasswordState();
}

class _ForgotPasswordState extends State<ForgotPassword> {
  bool _isSending = false;

  late final _emailController =
      TextEditingController(text: widget.initialEmail?.trim() ?? '');

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _onResetPassword() async {
    final email = _emailController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      _showSnackBar('Enter a valid email address.', isError: true);
      return;
    }

    setState(() => _isSending = true);

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;
      _showSnackBar(
        'Password reset link sent to $email.',
        isError: false,
      );

      // Give the user a moment to read the confirmation, then return them
      // to the Log In page.
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _showSnackBar(_mapResetError(e), isError: true);
    } catch (_) {
      if (!mounted) return;
      _showSnackBar('Something went wrong. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  // Note: many Firebase projects have "email enumeration protection"
  // enabled, in which case sendPasswordResetEmail succeeds silently even
  // for unknown emails (no 'user-not-found' is ever thrown). That's
  // expected behavior, not a bug — it stops attackers from probing which
  // emails have accounts.
  String _mapResetError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      default:
        return e.message ?? 'An unexpected error occurred.';
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    AppSnack.show(
      context,
      message,
      type: isError ? AppSnackType.error : AppSnackType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      showBrand: false,
      centerHeader: true,
      subtitleAlign: TextAlign.justify,
      subtitleSize: 12,
      topGap: MediaQuery.of(context).size.height * 0.1,
      title: 'Reset your password',
      subtitle: "Enter the email address associated with your account "
          "and we'll send you an email to reset your password.",
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
          ),

          const SizedBox(height: 14),

          AuthPrimaryButton(
            label: 'Reset password',
            loading: _isSending,
            onPressed: _onResetPassword,
          ),
        ],
      ),
    );
  }
}