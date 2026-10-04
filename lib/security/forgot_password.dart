import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  final FocusNode _emailFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _emailFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _emailFocus.dispose();
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? Colors.redAccent.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          // Green header with rounded bottom corners — matches the My
          // Account page: circular white back button + bold white title.
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Color(0xFF7DB343),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 20, 28),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.white.withOpacity(0.9),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new,
                            color: Colors.black, size: 18),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      'Reset your password',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Body — text and field scroll if needed, button always pinned
          // to the bottom of the screen.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 44, 24, 24),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Enter the email address associated with your account "
                            "and we'll send you an email to reset your password.",
                            textAlign: TextAlign.justify,
                            style: TextStyle(
                              color: Colors.black87,
                              fontSize: 15,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 24),
                          _buildEmailField(),
                        ],
                      ),
                    ),
                  ),

                  // Reset password button, anchored at the bottom
                  Container(
                    width: double.infinity,
                    height: 62,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      color: const Color(0xFF7DB343),
                    ),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                      onPressed: _isSending ? null : _onResetPassword,
                      child: _isSending
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5),
                            )
                          : const Text(
                              'Reset password',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailField() {
    final isFocused = _emailFocus.hasFocus;

    return TextField(
      controller: _emailController,
      focusNode: _emailFocus,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      decoration: InputDecoration(
        hintText: 'Email Address',
        fillColor: isFocused ? Colors.white : const Color(0xFFD9D9D9),
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF7DB343), width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    );
  }
}