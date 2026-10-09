import 'package:flutter/material.dart';
import '../theme/app_style.dart';

/// The standard green header used by every page except the Dashboard
/// (which has its own greeting header). Change it here and all pages follow.
///
/// Optional [backgroundAsset] puts a picture behind the header, tinted green
/// so the white title stays readable.
class AppHeader extends StatelessWidget {
  final String title;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? trailing;
  final String? backgroundAsset;

  const AppHeader({
    super.key,
    required this.title,
    this.showBack = false,
    this.onBack,
    this.trailing,
    this.backgroundAsset,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.only(
        top: 60,
        left: AppSpace.page,
        right: AppSpace.page,
        bottom: 24,
      ),
      child: Row(
        children: [
          if (showBack) ...[
            GestureDetector(
              onTap: onBack ?? () => Navigator.of(context).maybePop(),
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  AppIcons.back,
                  color: AppColors.textPrimary,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.headerTitle,
            ),
          ),
          ?trailing,
        ],
      ),
    );

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: AppColors.green,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(AppRadius.header),
          bottomRight: Radius.circular(AppRadius.header),
        ),
      ),
      child: Stack(
        children: [
          if (backgroundAsset != null)
            Positioned.fill(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    backgroundAsset!,
                    fit: BoxFit.cover,
                    // Falls back to plain green if the picture can't load.
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: AppColors.green),
                  ),
                  ColoredBox(color: AppColors.green.withOpacity(0.55)),
                ],
              ),
            ),
          row,
        ],
      ),
    );
  }
}