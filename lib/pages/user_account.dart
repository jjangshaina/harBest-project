import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_application_harbest_1/widgets/app_content.dart';
import 'package:flutter_application_harbest_1/widgets/info_page.dart';
import 'package:flutter_application_harbest_1/widgets/app_card.dart';
import 'package:flutter_application_harbest_1/widgets/app_menu.dart';
import 'package:flutter_application_harbest_1/widgets/status_widgets.dart';
import 'package:flutter_application_harbest_1/pages/home_page.dart';
import 'package:flutter_application_harbest_1/security/change_password.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/widgets/app_dialogs.dart';
import 'package:flutter_application_harbest_1/widgets/app_header.dart';
import 'package:flutter_application_harbest_1/widgets/app_snackbar.dart';

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
  bool _isHelpExpanded = false;
  bool _isTermsExpanded = false;

  bool _isVerified = false; // email verified in Firebase Auth

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
      // Refresh the user from Firebase so "verified" is up to date.
      try {
        await user.reload();
      } catch (_) {}

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
        _isVerified =
            FirebaseAuth.instance.currentUser?.emailVerified ?? false;
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
      AppSnack.show(
        context,
        'Failed to load account details: $e',
        type: AppSnackType.error,
      );
    }
  }

  Future<void> _promptForMissingName() async {
    final shouldAddName = await AppDialog.confirm(
      context,
      title: 'Add your full name',
      message: "We don't have a name on file for your account yet. "
          "Would you like to add one now?",
      confirmLabel: 'Add Name',
      cancelLabel: 'Later',
    );

    if (shouldAddName) {
      if (!mounted) return;
      // Reuse the same edit flow used for the "Edit" button
      _handleEditFullName();
    }
  }

  Future<void> _handleEditFullName() async {
    final newName = await AppDialog.textInput(
      context,
      title: 'Edit Full Name',
      initialValue: _fullName,
      hint: 'Enter your full name',
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

      AppSnack.show(
        context,
        'Full name updated successfully',
        type: AppSnackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(
        context,
        'Failed to update name: $e',
        type: AppSnackType.error,
      );
    }
  }

  // ── Help & Support ─────────────────────────────────────────────────────

  Future<void> _launch(Uri uri) async {
    try {
      final ok = await launchUrl(uri);
      if (!ok && mounted) {
        AppSnack.show(
          context,
          "Couldn't open that on this phone.",
          type: AppSnackType.error,
        );
      }
    } catch (_) {
      if (!mounted) return;
      AppSnack.show(
        context,
        "Couldn't open that on this phone.",
        type: AppSnackType.error,
      );
    }
  }

  void _openContact({required String value, required bool isPhone, String? subject}) {
    if (value.trim().isEmpty) {
      AppSnack.show(context, "This contact hasn't been set up yet.");
      return;
    }
    final v = value.trim();
    if (isPhone) {
      _launch(Uri(scheme: 'tel', path: v));
    } else {
      _launch(Uri.parse(
        'mailto:$v${subject == null ? '' : '?subject=${Uri.encodeComponent(subject)}'}',
      ));
    }
  }

  void _openInfo(String title, List<InfoSection> sections) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InfoPage(title: title, sections: sections),
      ),
    );
  }

  // ── Logout / Delete ────────────────────────────────────────────────────

  Future<void> _handleLogout() async {
    final confirmed = await AppDialog.confirm(
      context,
      title: 'Logout',
      message: 'Are you sure you want to logout?',
      confirmLabel: 'Logout',
      destructive: true,
    );

    if (confirmed) {
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

  Future<void> _handleDeleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;

    final confirmed = await AppDialog.confirm(
      context,
      title: 'Delete account',
      message: 'This permanently deletes your account and your saved '
          'details. This cannot be undone.',
      confirmLabel: 'Continue',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final password = await AppDialog.textInput(
      context,
      title: 'Confirm your password',
      hint: 'Password',
      confirmLabel: 'Delete',
      obscure: true,
      destructive: true,
    );
    if (password == null || !mounted) return;

    try {
      // Firebase needs a recent sign-in before deleting an account.
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: user.email!, password: password),
      );

      // Remove the user's record, then the account.
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .delete();
      await user.delete();

      if (!mounted) return;
      AppSnack.show(
        context,
        'Your account has been deleted.',
        type: AppSnackType.success,
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomePage()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final message = switch (e.code) {
        'wrong-password' ||
        'invalid-credential' => 'Incorrect password. Your account was not deleted.',
        'too-many-requests' => 'Too many attempts. Please try again later.',
        'network-request-failed' => 'Network error. Check your connection.',
        'requires-recent-login' =>
          'Please log out and log back in, then try again.',
        _ => e.message ?? 'Failed to delete your account.',
      };
      AppSnack.show(context, message, type: AppSnackType.error);
    } catch (e) {
      if (!mounted) return;
      AppSnack.show(
        context,
        'Failed to delete your account: $e',
        type: AppSnackType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const AppHeader(title: 'My Account', showBack: true),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _buildUserCard(),

                const AppSectionLabel('Account'),
                AppMenuGroup(
                  children: [
                    AppExpandableTile(
                      icon: AppIcons.profile,
                      title: 'Personal Details',
                      expanded: _isPersonalDetailsExpanded,
                      onTap: () => setState(() {
                        _isPersonalDetailsExpanded =
                            !_isPersonalDetailsExpanded;
                      }),
                      child: _buildPersonalDetailsContent(),
                    ),
                    AppExpandableTile(
                      icon: AppIcons.security,
                      title: 'Password & Security',
                      expanded: _isPasswordSecurityExpanded,
                      onTap: () => setState(() {
                        _isPasswordSecurityExpanded =
                            !_isPasswordSecurityExpanded;
                      }),
                      child: _buildPasswordSecurityContent(),
                    ),
                  ],
                ),

                const AppSectionLabel('Support'),
                AppMenuGroup(
                  children: [
                    AppExpandableTile(
                      icon: AppIcons.help,
                      title: 'Help & Support',
                      expanded: _isHelpExpanded,
                      onTap: () => setState(() {
                        _isHelpExpanded = !_isHelpExpanded;
                      }),
                      child: _buildHelpContent(),
                    ),
                    AppExpandableTile(
                      icon: AppIcons.terms,
                      title: 'Terms & Privacy',
                      expanded: _isTermsExpanded,
                      onTap: () => setState(() {
                        _isTermsExpanded = !_isTermsExpanded;
                      }),
                      child: _buildOptionRow(
                        icon: AppIcons.terms,
                        label: 'Terms & Conditions',
                        onTap: () =>
                            _openInfo('Terms & Conditions', kTermsSections),
                      ),
                    ),
                    AppMenuTile(
                      icon: AppIcons.aboutUs,
                      title: 'About Us',
                      onTap: () => _openInfo('About Us', kAboutSections),
                    ),
                  ],
                ),

                const SizedBox(height: 17),
                AppMenuGroup(
                  children: [
                    AppMenuTile(
                      icon: AppIcons.logout,
                      title: 'Logout',
                      onTap: _handleLogout,
                    ),
                  ],
                ),
                const SizedBox(height: 17),
                AppMenuGroup(
                  children: [
                    AppMenuTile(
                      icon: AppIcons.delete,
                      title: 'Delete Account',
                      destructive: true,
                      showChevron: false,
                      onTap: _handleDeleteAccount,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Name + email card at the top of the page.
  Widget _buildUserCard() {
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _fullName.isNotEmpty ? _fullName : (_isLoadingUser ? '' : 'Your Name'),
              style: AppText.cardTitle,
            ),
            const SizedBox(height: 2),
            Text(_email, style: AppText.subtitle),
          ],
        ),
      ),
    );
  }

  // Personal Details
  Widget _buildPersonalDetailsContent() {
    if (_isLoadingUser) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDetailRow(
          'Full Name:',
          Text(
            _fullName.isNotEmpty ? _fullName : 'Not set',
            style: AppText.body.copyWith(fontSize: 13),
          ),
        ),
        const SizedBox(height: 14),
        _buildDetailRow(
          'Email:',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_email, style: AppText.body.copyWith(fontSize: 13)),
              const SizedBox(height: 6),
              AppStatusPill(
                text: _isVerified ? 'Verified' : 'Not verified',
                color: _isVerified ? AppColors.optimal : AppColors.critical,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _handleEditFullName,
            child: const Text(
              'Edit',
              style: TextStyle(color: AppColors.green, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, Widget value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(label, style: AppText.label.copyWith(fontSize: 13)),
        ),
        const SizedBox(width: 8),
        Expanded(child: value),
      ],
    );
  }

  // Password & Security
  Widget _buildPasswordSecurityContent() {
    return Column(
      children: [
        _buildOptionRow(
          icon: AppIcons.lock,
          label: 'Change Password',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ChangePassword()),
            );
          },
        ),
        const SizedBox(height: 14),
        _buildOptionRow(
          icon: AppIcons.twoFactor,
          label: 'Two-Factor Authentication',
          onTap: () => AppDialog.info(
            context,
            title: 'Two-Factor Authentication',
            message: 'Two-factor authentication is coming soon.',
          ),
        ),
      ],
    );
  }

  // Help & Support
  Widget _buildHelpContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Contact Us or Send Feedback', style: AppText.label.copyWith(color: AppColors.darkGreen)),
        const SizedBox(height: 10),
        _buildContactRow(
          icon: AppIcons.mail,
          label: 'Email:',
          value: kSupportEmail,
          onTap: () => _openContact(
            value: kSupportEmail,
            isPhone: false,
            subject: 'HarBest support',
          ),
        ),
        const SizedBox(height: 12),
        _buildContactRow(
          icon: AppIcons.phone,
          label: 'Call us:',
          value: kSupportPhone,
          onTap: () => _openContact(value: kSupportPhone, isPhone: true),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _buildContactRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final isBlank = value.trim().isEmpty;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.green),
          const SizedBox(width: 10),
          Text(label, style: AppText.body.copyWith(fontSize: 14)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isBlank ? 'Not set yet' : value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: AppText.subtitle.copyWith(
                color: isBlank ? AppColors.textTertiary : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.green),
          const SizedBox(width: 10),
          Text(label, style: AppText.body.copyWith(fontSize: 14)),
          const Spacer(),
          const Icon(AppIcons.forward, size: 18, color: AppColors.textTertiary),
        ],
      ),
    );
  }
}