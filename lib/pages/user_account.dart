import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_application_harbest_1/security/storing_data.dart';
import 'package:flutter_application_harbest_1/pages/home_page.dart';
import 'package:flutter_application_harbest_1/pages/user_dashboard.dart';

class UserAccount extends StatelessWidget {
  const UserAccount({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Sans-Serif'),
      home: const AccountScreen(),
    );
  }
}

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _isPersonalDetailsExpanded = false;
  bool _isPasswordSecurityExpanded = false;

   Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color.fromARGB(137, 48, 47, 47)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(
                'Logout',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );

     if (confirmed == true) {
      // Clear the stored login session so app doesn't auto-login next time
      await StoringData().logout();

      // Sign out from Firebase as well
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      // Navigate to HomePage (welcome screen) and clear all routes
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomePage()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(
        children: [
          // Custom Green Header
          Container(
            padding: const EdgeInsets.only(top: 65, left: 20, right: 20, bottom: 27),
            decoration: const BoxDecoration(
              color: Color(0xFF7CB342), // Green header
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            child: Row(
              children: [
                // Back Button
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const UserDashboard()),
                  ),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: const Icon(
                      Icons.chevron_left,
                      color: Colors.black87,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                
                const Text(
                  'My Account',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),

          // Menu Items
          Expanded(
            child: Column(
              children: [
                const SizedBox(height: 20),

                // Personal Details
                _buildExpandableItem(
                  title: 'Personal Details',
                  isExpanded: _isPersonalDetailsExpanded,
                  onTap: () {
                    setState(() {
                      _isPersonalDetailsExpanded = !_isPersonalDetailsExpanded;
                    });
                  },
                  expandedContent: _buildPersonalDetailsContent(),
                ),

                // Password & Security
                _buildExpandableItem(
                  title: 'Password & Security',
                  isExpanded: _isPasswordSecurityExpanded,
                  onTap: () {
                    setState(() {
                      _isPasswordSecurityExpanded =
                          !_isPasswordSecurityExpanded;
                    });
                  },
                  expandedContent: _buildPasswordSecurityContent(),
                ),
                // Logout
                _buildLogoutItem(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandableItem({
    required String title,
    required bool isExpanded,
    required VoidCallback onTap,
    required Widget expandedContent,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: Colors.black87,
                  ),
                ),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.black54,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, thickness: 1, color: Color(0xFFE0E0E0)),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: expandedContent,
          crossFadeState: isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }
 // Personal Details
  Widget _buildPersonalDetailsContent() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF9F9F9),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailRow('Full Name:', ''),
          const SizedBox(height: 12),
          _buildDetailRow('Email:', ''),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {},
              child: const Text(
                'Edit',
                style: TextStyle(color: Color(0xFF4CAF50)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
// Password & Security
  Widget _buildPasswordSecurityContent() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF9F9F9),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSecurityOption(
            Icons.lock_outline, 'Change Password'),
          const SizedBox(height: 12),
          _buildSecurityOption(
            Icons.shield_outlined, 'Two-Factor Authentication'),
        ],
      ),
    );
  }

  Widget _buildSecurityOption(IconData icon, String label) {
    return GestureDetector(
      onTap: () {},
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF4CAF50)),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
          const Spacer(),
          const Icon(Icons.arrow_back_ios_new, 
          size: 18, 
          color: Colors.black38),
        ],
      ),
    );
  }

  Widget _buildLogoutItem() {
    return Column(
      children: [
        InkWell(
          onTap: _handleLogout,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Logout',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: Colors.black87,
                  ),
                ),
                const Icon(
                  Icons.logout,
                  color: Colors.black54,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, thickness: 1, color: Color(0xFFE0E0E0)),
      ],
    );
  }
}
