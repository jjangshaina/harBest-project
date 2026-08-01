import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_application_harbest_1/pages/get_started.dart';
import 'package:flutter_application_harbest_1/pages/home_page.dart';
import 'package:flutter_application_harbest_1/pages/user_dashboard.dart';
import 'package:flutter_application_harbest_1/security/storing_data.dart';

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

  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _emailFocus.addListener(() => setState(() {}));
    _passwordFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
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

    setState(() => _isSubmitting = true);

    try {
      // Attempt to sign in with Firebase Authentication
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      final user = FirebaseAuth.instance.currentUser;

      // Block login if the user has not verified their email yet
      if (user != null && !user.emailVerified) {
        await FirebaseAuth.instance.signOut(); // Sign out immediately for safety
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please verify your email before signing in. Check your inbox.'),
            backgroundColor: Colors.redAccent.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 5),
            // Resend button inside the snackbar
            action: SnackBarAction(
              label: 'Resend',
              textColor: Colors.white,
              onPressed: () async {
                try {
                  // Re-sign in briefly just to resend the verification email
                  final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
                    email: _emailController.text.trim(),
                    password: _passwordController.text,
                  );
                  await credential.user?.sendEmailVerification();
                  await FirebaseAuth.instance.signOut();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Verification email resent. Check your inbox.'),
                      backgroundColor: Colors.green.shade700,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                } catch (_) {}
              },
            ),
          ),
        );
        return; // Stop — do not navigate to HomePage
      }

      // Email is verified — save login session to device storage
      // This is what keeps the user logged in after app restart
      await StoringData().setLoginStatus(true);

      if (!mounted) return;
      // Navigate to Dashboard and remove all previous routes
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => UserDashboard()), 
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _showSnackBar(_mapFirebaseError(e)); // Show friendly error message
    } catch (_) {
      if (!mounted) return;
      _showSnackBar('An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // Firebase error codes 
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
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFF2D5A27),
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

                  // Back button — returns to previous screen
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.white.withOpacity(0.9),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 18),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const HomePage()),
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Screen title
                  const Center(
                    child: Text(
                      'Welcome back!',
                      style: TextStyle(
                        color: Colors.white, 
                        fontSize: 28, 
                        fontWeight: FontWeight.bold
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Center(
                    child: Text(
                      'Access your crop analytics dashboard',
                      style: TextStyle(color: Colors.white70, fontSize: 15),
                    ),
                  ),

                  SizedBox(height: screenHeight * 0.04),

                  // Email input field
                  _buildTextField(
                    hint: 'Email Address',
                    controller: _emailController,
                    focusNode: _emailFocus,
                    keyboardType: TextInputType.emailAddress,
                  ),

                  const SizedBox(height: 12),

                  // Password input field
                  _buildTextField(
                    hint: 'Password',
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    isPassword: true,
                  ),

                  const SizedBox(height: 12),

                  // Forgot Password link
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () {}, // implement forgot password
                      child: const Text(
                        'Forgot password?',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),

                  SizedBox(height: screenHeight * 0.03),

                  // Sign In button shows spinner while loading
                  Container(
                    width: double.infinity,
                    height: 55,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF7DB343), Color(0xFF4C7A2D)],
                      ),
                      boxShadow: const [BoxShadow(
                        color: Colors.black26, 
                        blurRadius: 10, 
                        offset: Offset(0, 4))
                      ],
                    ),
                    
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                      ),
                      onPressed: _isSubmitting ? null : _onSignIn,
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 22, 
                              width: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white, 
                                strokeWidth: 2.5),
                            )
                          : const Text(
                              'Sign in',
                              style: TextStyle(
                                fontSize: 18, 
                                color: Colors.white, 
                                fontWeight: FontWeight.w600),
                     ),
                    ),
                  ),

                  SizedBox(height: screenHeight * 0.025),

                  // Sign Up link for users without an account
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "Don't have an account? ",
                          style: TextStyle(
                            color: Colors.white, 
                            fontWeight: FontWeight.bold, 
                            fontSize: 13),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const GetStarted()),
                          ),
                          child: const Text(
                            "Sign up",
                            style: TextStyle(
                              color: Color(0xFF7DB343), 
                              fontWeight: FontWeight.bold, 
                              fontSize: 13,
                              decoration: TextDecoration.underline, 
                              decorationColor: Color(0xFF7DB343), 
                              decorationThickness: 1.5,
                              ),
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

  Widget _buildTextField({
    required String hint,
    required TextEditingController controller,
    required FocusNode focusNode,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final isFocused = focusNode.hasFocus;

    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: isPassword && _obscurePassword,
      keyboardType: keyboardType,
      autocorrect: false,
      decoration: InputDecoration(
        hintText: hint,
        fillColor: isFocused ? Colors.white : const Color(0xFFD9D9D9), // White when focused
        filled: true,
        
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), 
          borderSide: BorderSide.none),

        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF7DB343), width: 2), // Green border on focus
        ),
        contentPadding: 
        const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
  
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: Colors.black45,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              )
            : null,
      ),
    );        
  }
}