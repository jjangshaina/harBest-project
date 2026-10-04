import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Place this file at: lib/security/change_password.dart
class ChangePassword extends StatefulWidget {
  const ChangePassword({super.key});

  @override
  State<ChangePassword> createState() => _ChangePasswordState();
}

class _ChangePasswordState extends State<ChangePassword> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController =
      TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSubmitting = false;

  // Live requirement flags, recalculated on every keystroke of the new
  // password field so the checklist below updates in real time.
  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasNumber = false;
  bool _hasSpecialChar = false;

  @override
  void initState() {
    super.initState();
    _newPasswordController.addListener(_updateRequirements);
  }

  @override
  void dispose() {
    _newPasswordController.removeListener(_updateRequirements);
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _updateRequirements() {
    final value = _newPasswordController.text;
    setState(() {
      _hasMinLength = value.length >= 8;
      _hasUppercase = RegExp(r'[A-Z]').hasMatch(value);
      _hasNumber = RegExp(r'[0-9]').hasMatch(value);
      _hasSpecialChar = RegExp(r'[!@#$%^&*(),.?":{}|<>_\-\[\]/\\+=~`]')
          .hasMatch(value);
    });
  }

  bool get _meetsAllRequirements =>
      _hasMinLength && _hasUppercase && _hasNumber && _hasSpecialChar;

  Future<void> _handleSetPassword() async {
    // Basic field validation first
    if (!_formKey.currentState!.validate()) return;

    if (!_meetsAllRequirements) {
      _showSnack('Your new password doesn\'t meet all requirements yet.');
      return;
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      _showSnack('New password and confirmation do not match.');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      _showSnack('No signed-in user found. Please log in again.');
      return;
    }

    if (_newPasswordController.text == _currentPasswordController.text) {
      _showSnack('New password must be different from your current password.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Firebase requires a recent sign-in before letting you change the
      // password, so re-authenticate with the current password first.
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: _currentPasswordController.text,
      );
      await user.reauthenticateWithCredential(credential);

      // Re-auth succeeded, now actually update the password.
      await user.updatePassword(_newPasswordController.text);

      if (!mounted) return;
      _showSnack('Password updated successfully.');
      Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          message = 'Current password is incorrect.';
          break;
        case 'weak-password':
          message = 'New password is too weak.';
          break;
        case 'requires-recent-login':
          message =
              'For security, please log out and log back in before changing your password.';
          break;
        case 'too-many-requests':
          message = 'Too many attempts. Please try again later.';
          break;
        default:
          message = e.message ?? 'Failed to update password.';
      }
      _showSnack(message);
    } catch (e) {
      _showSnack('Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(
        children: [
          // Header — matches AccountScreen's header exactly
          Container(
            padding: const EdgeInsets.only(
                top: 65, left: 20, right: 20, bottom: 27),
            decoration: const BoxDecoration(
              color: Color(0xFF7CB342),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Colors.black87,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                const Text(
                  'Change Password',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPasswordField(
                      label: 'Current Password',
                      controller: _currentPasswordController,
                      obscure: _obscureCurrent,
                      onToggleObscure: () =>
                          setState(() => _obscureCurrent = !_obscureCurrent),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your current password';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),

                    _buildPasswordField(
                      label: 'New Password',
                      controller: _newPasswordController,
                      obscure: _obscureNew,
                      onToggleObscure: () =>
                          setState(() => _obscureNew = !_obscureNew),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a new password';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // Live requirement checklist
                    _buildRequirement('At least 8 characters', _hasMinLength),
                    _buildRequirement('At least one uppercase letter', _hasUppercase),
                    _buildRequirement('At least one number', _hasNumber),
                    _buildRequirement('At least one special character', _hasSpecialChar),

                    const SizedBox(height: 18),

                    _buildPasswordField(
                      label: 'Confirm New Password',
                      controller: _confirmPasswordController,
                      obscure: _obscureConfirm,
                      onToggleObscure: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please confirm your new password';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 40),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _handleSetPassword,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7CB342),
                          disabledBackgroundColor:
                              const Color(0xFF7CB342).withOpacity(0.6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 0,
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text(
                                'Set Password',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordField({
    required String label,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggleObscure,
    required String? Function(String?) validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFEDEDED),
            borderRadius: BorderRadius.circular(14),
          ),
          child: TextFormField(
            controller: controller,
            obscureText: obscure,
            validator: validator,
            style: const TextStyle(fontSize: 15, color: Colors.black87),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(
                color: Colors.black54,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              border: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              suffixIcon: IconButton(
                icon: Icon(
                  obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: Colors.black45,
                  size: 20,
                ),
                onPressed: onToggleObscure,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRequirement(String text, bool met) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle : Icons.circle_outlined,
            size: 15,
            color: met ? const Color(0xFF4CAF50) : Colors.black38,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              color: met ? const Color(0xFF4CAF50) : Colors.black54,
              fontWeight: met ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}