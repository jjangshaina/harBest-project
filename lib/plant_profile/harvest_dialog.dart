// HarBest - "Harvesting Time" dialog
//
// File layout (each section only uses what comes before it):
//   1. HarvestDialog widget
//   2. State: fields -> lifecycle -> actions -> small pieces -> build
//   3. showHarvestDialog() - the entry point other pages call

import 'package:flutter/material.dart';
import 'package:flutter_application_harbest_1/pages/add_crop.dart';
import 'package:flutter_application_harbest_1/plant_profile/harvest_service.dart';
import 'package:flutter_application_harbest_1/services/crop_services.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/widgets/app_button.dart';
import 'package:flutter_application_harbest_1/widgets/app_snackbar.dart';

// ================================================================ 1. widget

/// "Harvesting Time" pop-up: days grown, average health and alerts of the
/// harvesting stage, a tip taken from the forecast, and three choices:
/// mark as harvested, remind me tomorrow, or start a new crop.
class HarvestDialog extends StatefulWidget {
  const HarvestDialog({super.key, required this.crop});
  final Crop crop;

  @override
  State<HarvestDialog> createState() => _HarvestDialogState();
}

// ================================================================ 2. state

class _HarvestDialogState extends State<HarvestDialog> {
  // ── Fields ──

  HarvestInfo? _info; // null while the numbers load
  bool _busy = false;
  bool? _helpful; // answer to "Was this tip helpful?"; kept on this screen only

  // ── Lifecycle ──

  @override
  void initState() {
    super.initState();
    // HarvestService.load never throws, so no error handling is needed here.
    HarvestService.load(widget.crop).then((info) {
      if (mounted) setState(() => _info = info);
    });
  }

  // ── Actions ──

  Future<void> _markHarvested() async {
    // Grab these before any await: the dialog may be gone afterwards.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final name = widget.crop.name;
    setState(() => _busy = true);
    try {
      await HarvestService.markHarvested(widget.crop);
      await CropService.instance.load();
      if (mounted) navigator.pop();
      AppSnack.showOn(messenger, '$name was marked as harvested.', type: AppSnackType.success);
    } catch (e) {
      debugPrint('Mark harvested error: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      AppSnack.show(
        context,
        'Could not mark the crop as harvested. Please try again.',
        type: AppSnackType.error,
      );
    }
  }

  Future<void> _remindTomorrow() async {
    final navigator = Navigator.of(context);
    await HarvestService.remindTomorrow(widget.crop);
    if (mounted) navigator.pop();
  }

  // The old crop is marked harvested and the new one is inserted together,
  // when the user saves on the Add crop page.
  void _startNewCrop() {
    final navigator = Navigator.of(context);
    final crop = widget.crop;
    navigator
      ..pop()
      ..push(MaterialPageRoute(
        builder: (_) => AddCropPage(
          deviceId: crop.deviceId,
          replacingCropId: crop.id,
          initialName: HarvestService.nextCropName(crop.name),
        ),
      ));
  }

  // ── Small pieces ──

  static const _statValueStyle = TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800);
  static const _statLabelStyle = TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700);

  /// Full-width rounded box used for the stats and the tip.
  Widget _panel({required Color color, required EdgeInsets padding, required Widget child}) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
        child: child,
      );

  /// One number + caption in the stats row.
  Widget _stat(String value, String label) => Expanded(
        child: Column(children: [
          Text(value, style: _statValueStyle),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, style: _statLabelStyle),
        ]),
      );

  /// "Yes" / "No" pill for the tip feedback.
  Widget _thumb({required bool up}) {
    final selected = _helpful == up;
    final fg = selected ? Colors.white : AppColors.textPrimary;
    return GestureDetector(
      onTap: () => setState(() => _helpful = up),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.darkGreen : Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(up ? AppIcons.thumbUp : AppIcons.thumbDown, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(up ? 'Yes' : 'No', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
        ]),
      ),
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    // -- values shown in the dialog ('...' while loading, '--' when unavailable)
    final crop = widget.crop;
    final info = _info;
    final healthText = info == null
        ? '...'
        : (info.avgHealth == null ? '--' : '${info.avgHealth!.round()}%');
    final alertsText = info == null
        ? '...'
        : (info.alerts == null ? '--' : '${info.alerts}');

    // -- layout, top to bottom: header, stats, tip, buttons
    return Dialog(
      backgroundColor: AppColors.card,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.dialog)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            const Center(child: Icon(AppIcons.harvest, size: 38, color: AppColors.textPrimary)),
            const SizedBox(height: 14),
            Center(
              child: Text(
                'Harvesting Time',
                textAlign: TextAlign.center,
                style: AppText.sectionTitle.copyWith(fontSize: 26, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '${crop.name} has reached the end of its harvest window.',
              style: AppText.body.copyWith(fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 14),

            // Stats: Days grown / Avg. Health / Alerts
            _panel(
              color: AppColors.disabledEnd,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _stat('${HarvestService.daysGrown(crop)}', 'Days grown'),
                _stat(healthText, 'Avg. Health'),
                _stat(alertsText, 'Alerts'),
              ]),
            ),
            const SizedBox(height: 12),

            // Tip from the forecast + feedback
            _panel(
              color: AppColors.green.withValues(alpha: 0.55),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(AppIcons.tip, size: 18, color: AppColors.textPrimary),
                const SizedBox(height: 6),
                Text(
                  info?.tip ?? 'Loading a suggestion from the forecast...',
                  style: AppText.body.copyWith(fontSize: 12.5, height: 1.35),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: Text(
                      _helpful == null ? 'Was this tip helpful?' : 'Thanks for the feedback.',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  _thumb(up: true),
                  const SizedBox(width: 6),
                  _thumb(up: false),
                ]),
              ]),
            ),
            const SizedBox(height: 16),

            // Buttons: primary, secondary, text link
            AppButton(
              label: 'Mark as Harvested',
              expanded: true,
              loading: _busy,
              onPressed: _markHarvested,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _busy ? null : _remindTomorrow,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.textPrimary, width: 1.5),
                  minimumSize: const Size(0, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
                  textStyle: AppText.button,
                ),
                child: const Text('Remind me tomorrow'),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: GestureDetector(
                onTap: _busy ? null : _startNewCrop,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  child: Text(
                    'Start new crop',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================ 3. entry point

/// Opens the harvest reminder over the current page.
Future<void> showHarvestDialog(BuildContext context, Crop crop) {
  return showDialog<void>(
    context: context,
    builder: (_) => HarvestDialog(crop: crop),
  );
}