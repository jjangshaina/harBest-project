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
import 'package:flutter_application_harbest_1/services/crop_services.dart';

// Relies on the single root MaterialApp defined in main.dart.
class UserAccount extends StatelessWidget {
  const UserAccount({super.key});

  @override
  Widget build(BuildContext context) => const AccountScreen();
}

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  static final _detailLabelStyle = AppText.label.copyWith(fontSize: 13);
  static final _detailValueStyle = AppText.body.copyWith(fontSize: 13);

  // ── State ──

  // Holds the user's current full name and email for display
  String _name = '';
  String _email = '';
  bool _isVerified = false; // email verified in Firebase Auth
  bool _isLoadingUser = true;

  bool _isPersonalDetailsExpanded = false;
  bool _isHelpExpanded = false;

  // ── Lifecycle ──

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  // ── Load user data ──

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      setState(() => _isLoadingUser = false);
      return;
    }

    
    final displayName = user.displayName?.trim() ?? '';
    final hasAuthName = displayName.isNotEmpty;
    final authName = hasAuthName ? displayName : _emailPrefix(user.email);
    setState(() {
      _name = authName;
      _email = user.email ?? '';
    });

    try {
      // Refresh the user from Firebase so "verified" is up to date.
      try {
        await user.reload().timeout(kRequestTimeout);
      } catch (_) {}

      final docRef = _userDoc(user.uid);
      final doc = await docRef.get().timeout(kRequestTimeout);

      final Map<String, dynamic> data;
      if (doc.exists) {
        data = doc.data()!;
      } else {
        // Orphaned account (e.g. a sign-up whose profile save failed). Self-
        // heal by writing a baseline record in the background, with the name
        // taken from the login account.
        data = {
          'email': user.email ?? '',
          'createdAt': FieldValue.serverTimestamp(),
          'focus_crop': 'Mustard Green',
          'isVerified': user.emailVerified,
          if (hasAuthName) 'fullName': authName,
        };
        _saveInBackground(docRef, data);
      }

      // Sign-up and the dashboard use "fullName"; "name" is the older field
      // name this page used to read, kept as a fallback.
      final stored =
          ((data['fullName'] as String?) ?? (data['name'] as String?) ?? '')
              .trim();

      if (!mounted) return;
      setState(() {
        _name = stored.isNotEmpty ? stored : authName;
        // Firestore mirrors the email saved at signup, but Auth's email
        // is the source of truth in case it was ever changed
        _email = user.email ?? (data['email'] as String?) ?? '';
        _isLoadingUser = false;
        _isVerified =
            FirebaseAuth.instance.currentUser?.emailVerified ?? false;
      });

      if (doc.exists) {
        final updates = <String, dynamic>{
          // The profile has no name but the login account does: copy it over
          // quietly so the dashboard greeting and this page agree.
          if (stored.isEmpty && hasAuthName) 'fullName': authName,
          // Defensive sync: users who stay auto-logged-in across app restarts
          // (via Firebase Auth's own persisted session) skip the login screen
          // entirely, so that's not guaranteed to catch every case. Keep
          // Firestore's isVerified aligned with the real Auth status here too.
          if ((data['isVerified'] as bool?) != user.emailVerified)
            'isVerified': user.emailVerified,
        };
        if (updates.isNotEmpty) _saveInBackground(docRef, updates);
      }
    } catch (e) {
      debugPrint('Account load error: $e');
      if (!mounted) return;
      setState(() => _isLoadingUser = false);
      // The name is already shown from the login account, so a slow or
      // missing connection is not worth an error message.
      if (isConnectionError(e)) return;
      AppSnack.show(
        context,
        'Failed to load account details. Please try again.',
        type: AppSnackType.error,
      );
    }
  }

  // The part of the email before the "@", or '' if there is none.
  static String _emailPrefix(String? email) {
    final at = email?.indexOf('@') ?? -1;
    return at < 0 ? '' : email!.substring(0, at);
  }

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid);

  // Fire-and-forget merge write; failures are non-critical and ignored.
  void _saveInBackground(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> fields,
  ) {
    ref.set(fields, SetOptions(merge: true)).catchError((_) {});
  }

  // ── Account ──

  Future<void> _handleEditFullName() async {
    final newName = await AppDialog.textInput(
      context,
      title: 'Edit Name',
      initialValue: _name,
      hint: 'Enter your name',
    );

    if (newName == null || newName == _name) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await _userDoc(user.uid)
          .set({'fullName': newName, 'name': newName}, SetOptions(merge: true));
      // Keep the login account's name in step (best effort).
      user.updateDisplayName(newName).catchError((_) {});

      if (!mounted) return;
      setState(() => _name = newName);

      AppSnack.show(
        context,
        'Name updated successfully',
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

  // ── Help & Support ──

  void _openContact({
    required String value,
    required bool isPhone,
    String? subject,
  }) {
    final v = value.trim();
    if (v.isEmpty) {
      AppSnack.show(context, "This contact hasn't been set up yet.");
      return;
    }
    if (isPhone) {
      _launch(Uri(scheme: 'tel', path: v));
    } else {
      _launch(Uri.parse(
        'mailto:$v${subject == null ? '' : '?subject=${Uri.encodeComponent(subject)}'}',
      ));
    }
  }

  Future<void> _launch(Uri uri) async {
    bool ok;
    try {
      ok = await launchUrl(uri);
    } catch (_) {
      ok = false;
    }
    if (!ok && mounted) {
      AppSnack.show(
        context,
        "Couldn't open that on this phone.",
        type: AppSnackType.error,
      );
    }
  }

  void _openInfo(
    String title,
    List<InfoSection> sections, {
    bool collapsible = false,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InfoPage(
          title: title,
          sections: sections,
          collapsible: collapsible,
        ),
      ),
    );
  }

  // ── Logout / Delete ──

  Future<void> _handleLogout() async {
    final confirmed = await AppDialog.confirm(
      context,
      title: 'Logout',
      message: 'Are you sure you want to logout?',
      confirmLabel: 'Logout',
      destructive: true,
    );
    if (!confirmed) return;

    // Sign out of Firebase. AuthGate in main.dart reacts to this via
    // authStateChanges() and routes back to the Welcome screen on its
    // own — no separate local "logged in" flag to clear.
    await FirebaseAuth.instance.signOut();
    CropService.instance.clear();
    if (!mounted) return;
    _goToWelcome();
  }

  Future<void> _handleDeleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;
    if (user == null || email == null) return;

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
        EmailAuthProvider.credential(email: email, password: password),
      );

      // Remove the user's record, then the account.
      await _userDoc(user.uid).delete();
      await user.delete();

      if (!mounted) return;
      AppSnack.show(
        context,
        'Your account has been deleted.',
        type: AppSnackType.success,
      );
      _goToWelcome();
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

  // Go to the Harbest welcome screen and remove all previous routes to
  // prevent back navigation.
  void _goToWelcome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomePage()),
      (route) => false,
    );
  }

  // ── UI ──

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
                      onTap: () => setState(() =>
                          _isPersonalDetailsExpanded =
                              !_isPersonalDetailsExpanded),
                      child: _buildPersonalDetailsContent(),
                    ),
                    AppMenuTile(
                      icon: AppIcons.security,
                      title: 'Password',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ChangePassword(),
                        ),
                      ),
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
                      onTap: () =>
                          setState(() => _isHelpExpanded = !_isHelpExpanded),
                      child: _buildHelpContent(),
                    ),
                    AppMenuTile(
                      icon: AppIcons.aboutUs,
                      title: 'About Us',
                      onTap: () => _openInfo(
                        'About Us',
                        kAboutSections,
                        collapsible: true,
                      ),
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
              _name.isNotEmpty ? _name : (_isLoadingUser ? '' : 'Your Name'),
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
          'Name:',
          Text(_name.isNotEmpty ? _name : 'Not set', style: _detailValueStyle),
        ),
        const SizedBox(height: 14),
        _buildDetailRow(
          'Email:',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_email, style: _detailValueStyle),
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
          child: Text(label, style: _detailLabelStyle),
        ),
        const SizedBox(width: 8),
        Expanded(child: value),
      ],
    );
  }

  // Help & Support
  Widget _buildHelpContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Send Feedback or Contact Us',
          style: AppText.label.copyWith(color: AppColors.darkGreen),
        ),
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
                color:
                    isBlank ? AppColors.textTertiary : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}