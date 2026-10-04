import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_harbest_1/pages/home_page.dart';
import 'package:flutter_application_harbest_1/security/change_password.dart';

// Plain widget now, not its own MaterialApp — relies on the single root
// MaterialApp defined in main.dart.
class UserAccount extends StatelessWidget {
  const UserAccount({super.key});

  @override
  Widget build(BuildContext context) {
    return const AccountScreen();
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

  // Holds the user's current full name and email for display
  String _fullName = '';
  String _email = '';
  bool _isLoadingUser = true;
  bool _hasPromptedForName = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      setState(() => _isLoadingUser = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      var data = doc.data();

      if (!doc.exists) {
        // Orphaned account (e.g. from a signup that failed partway
        // through before this fix, or a user created outside the normal
        // signup flow). Self-heal by writing a baseline record now, so
        // the rest of the app has consistent data to rely on going
        // forward. fullName is intentionally left unset here — the
        // existing "add your name" prompt below will ask for it.
        final defaults = <String, dynamic>{
          'email': user.email ?? '',
          'createdAt': FieldValue.serverTimestamp(),
          'focus_crop': 'Mustard Green',
          'isVerified': user.emailVerified,
        };
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set(defaults, SetOptions(merge: true));
        data = defaults;
      }

      setState(() {
        _fullName = (data?['fullName'] as String?) ?? '';
        // Firestore mirrors the email saved at signup, but Auth's email
        // is the source of truth in case it was ever changed
        _email = user.email ?? (data?['email'] as String?) ?? '';
        _isLoadingUser = false;
      });

      // Defensive sync: users who stay auto-logged-in across app restarts
      // (via Firebase Auth's own persisted session) skip the login screen
      // entirely, so that's not guaranteed to catch every case. Keep
      // Firestore's isVerified aligned with the real Auth status here too.
      final storedIsVerified = data?['isVerified'] as bool?;
      if (storedIsVerified != user.emailVerified) {
        FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({'isVerified': user.emailVerified}, SetOptions(merge: true))
            .catchError((_) {
          // Non-critical background sync; ignore failures here.
        });
      }

      // Older accounts created before the fullName field existed won't
      // have it set. Gently prompt them to add it, once per screen visit.
      if (_fullName.isEmpty && !_hasPromptedForName) {
        _hasPromptedForName = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _promptForMissingName();
        });
      }
    } catch (e) {
      setState(() => _isLoadingUser = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load account details: $e')),
      );
    }
  }

  Future<void> _promptForMissingName() async {
    final shouldAddName = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add your full name'),
          content: const Text(
            "We don't have a name on file for your account yet. "
            "Would you like to add one now?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Later',
                style: TextStyle(color: Color.fromARGB(137, 48, 47, 47)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(
                'Add Name',
                style: TextStyle(color: Color(0xFF4CAF50)),
              ),
            ),
          ],
        );
      },
    );

    if (shouldAddName == true) {
      if (!mounted) return;
      // Reuse the same edit flow used for the "Edit" button
      _handleEditFullName();
    }
  }

  Future<void> _handleEditFullName() async {
    final controller = TextEditingController(text: _fullName);

    final newName = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Edit Full Name'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Enter your full name',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color.fromARGB(137, 48, 47, 47)),
              ),
            ),
            TextButton(
              onPressed: () {
                final trimmed = controller.text.trim();
                if (trimmed.isNotEmpty) {
                  Navigator.of(context).pop(trimmed);
                }
              },
              child: const Text(
                'Save',
                style: TextStyle(color: Color(0xFF4CAF50)),
              ),
            ),
          ],
        );
      },
    );

    if (newName == null || newName == _fullName) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({'fullName': newName}, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _fullName = newName;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Full name updated successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update name: $e')),
      );
    }
  }

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
      // Sign out of Firebase. AuthGate in main.dart reacts to this via
      // authStateChanges() and routes back to the Welcome screen on its
      // own — no separate local "logged in" flag to clear.
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      // Navigate to Harbest welcome screen and remove all previous routes to prevent back navigation
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
          Container(
            padding: const EdgeInsets.only(top: 65, left: 20, right: 20, bottom: 27),
            decoration: const BoxDecoration(
              color: Color(0xFF7CB342), 
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            child: Row(
              children: [
                // Back Button
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
                  'My Account',
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
          if (_isLoadingUser)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            _buildDetailRow(
              'Full Name:',
              _fullName.isNotEmpty ? _fullName : 'Not set',
            ),
            const SizedBox(height: 15),
            _buildDetailRow('Email:', _email),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _handleEditFullName,
                child: const Text(
                  'Edit',
                  style: TextStyle(color: Color(0xFF4CAF50)),
                ),
              ),
            ),
          ],
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
            icon: Icons.lock_outline,
            label: 'Change Password',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ChangePassword(),
                ),
              );
            },
          ),
          const SizedBox(height: 15),
          _buildSecurityOption(
            icon: Icons.shield_outlined,
            label: 'Two-Factor Authentication',
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
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
          const Icon(Icons.arrow_forward_ios,
              size: 18, color: Colors.black38),
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