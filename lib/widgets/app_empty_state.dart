import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_harbest_1/pages/add_crop.dart';
import 'package:flutter_application_harbest_1/pages/claim_device.dart';
import 'package:flutter_application_harbest_1/services/crop_services.dart';
import 'package:flutter_application_harbest_1/widgets/app_button.dart';
import '../theme/app_style.dart';

/// Centered "nothing here yet" message: big faded icon, title, short text.
/// Use it on any page or section that has no content to show.
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.black26),
            const SizedBox(height: AppSpace.cardGap),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: AppText.subtitle),
          ],
        ),
      ),
    );
  }
}

/// Shown on a tab when the signed-in account has no crop yet.
///
/// Only the dashboard passes [showButton] = true. It shows the
/// "Add your device" button, which opens the claim-device screen, or the
/// add-crop screen when the user already claimed a device but never saved a
/// crop. Every other tab shows a message that points to the Home tab.
class AppNoCropState extends StatelessWidget {
  final bool showButton;
  const AppNoCropState({super.key, this.showButton = false});

  Future<void> _start(BuildContext context) async {
    String? pending;
    try {
      final rows =
          await Supabase.instance.client.from('devices').select('device_id');
      final used = CropService.instance.crops.map((c) => c.deviceId).toSet();
      for (final r in rows as List) {
        final id = r['device_id'] as String;
        if (!used.contains(id)) {
          pending = id;
          break;
        }
      }
    } catch (_) {}
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => pending == null
            ? const ClaimDevicePage()
            : AddCropPage(deviceId: pending),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.plant, size: 56, color: Colors.black26),
            const SizedBox(height: AppSpace.cardGap),
            Text(
              showButton ? 'Add your device' : 'No crop yet',
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              showButton
                  ? 'Link your HarBest device to start monitoring your crop. '
                      'You will need the code that came with it.'
                  : 'Add your device on the Home tab to start monitoring '
                      'your crop.',
              textAlign: TextAlign.center,
              style: AppText.subtitle,
            ),
            if (showButton) ...[
              const SizedBox(height: 20),
              AppButton(
                label: 'Add your device',
                onPressed: () => _start(context),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// NO INTERNET
// ─────────────────────────────────────────────────────────────────────────

/// Whole-page message when there is no internet and nothing to show yet.
class AppOfflineState extends StatelessWidget {
  const AppOfflineState({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppEmptyState(
      icon: AppIcons.offline,
      title: 'No internet connection',
      message:
          'Check your Wi-Fi or mobile data, then pull down to try again.',
    );
  }
}

/// Lets the user pull down to refresh even when [child] does not scroll on
/// its own (empty states, error messages). [child] fills the page height,
/// so centered messages stay centered.
class AppRefreshable extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget child;

  const AppRefreshable({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.green,
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: child,
          ),
        ),
      ),
    );
  }
}