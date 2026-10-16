import 'package:flutter/material.dart';
import '../theme/app_style.dart';
import 'app_button.dart' show AppBackButton;

/// The standard green header used by every page except the Dashboard
/// (which has its own greeting header). Change it here and all pages follow.
///
/// Optional [backgroundAsset] puts a picture behind the header, tinted green
/// so the white title stays readable.
///
/// Optional [subtitle] shows a small line under the title
/// (e.g. "Updated 5 mins ago").
class AppHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? trailing;
  final String? backgroundAsset;

  const AppHeader({
    super.key,
    required this.title,
    this.subtitle,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.headerTitle,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.headerSubtitle,
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
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
                    errorBuilder: (_, __, ___) =>
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

// ─────────────────────────────────────────────────────────────────────────
// AUTH PAGES: green header + white card (Log in, Create account, Reset password)
// ─────────────────────────────────────────────────────────────────────────

/// Dark-green header (back button, brand, title, subtitle) with a white
/// rounded card below it. Used by the Log in and Create account pages.
class AuthScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  /// Space between the back button and the "HarBest" heading. A bigger
  /// value moves the heading AND the white card further down the screen.
  final double topGap;

  /// Centers the "HarBest" / title / subtitle text (left-aligned by default).
  final bool centerHeader;

  /// Shows the small green "HarBest" text above the title.
  final bool showBrand;

  /// Space between the subtitle and the top of the white card.
  final double cardGap;

  /// Alignment of the subtitle. Null = follow [centerHeader].
  final TextAlign? subtitleAlign;

  /// Font size of the subtitle.
  final double subtitleSize;

  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.topGap = 24,
    this.centerHeader = false,
    this.showBrand = true,
    this.cardGap = 24,
    this.subtitleAlign,
    this.subtitleSize = 13,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.authBackground,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 20, top: 12),
                      child: AppBackButton(),
                    ),
                    SizedBox(height: topGap),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: SizedBox(
                        width: double.infinity,
                        child: Column(
                        crossAxisAlignment: centerHeader
                            ? CrossAxisAlignment.center
                            : CrossAxisAlignment.start,
                        children: [
                          if (showBrand) ...[
                          Text(
                            'HarBest',
                            textAlign:
                                centerHeader ? TextAlign.center : TextAlign.start,
                            style: const TextStyle(
                              color: AppColors.brandOnDark,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          ],
                          Text(
                            title,
                            textAlign:
                                centerHeader ? TextAlign.center : TextAlign.start,
                            style: AppText.authTitle,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            subtitle,
                            textAlign: subtitleAlign ??
                                (centerHeader
                                    ? TextAlign.center
                                    : TextAlign.start),
                            style: AppText.authSubtitle.copyWith(
                              fontSize: subtitleSize,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                      ),
                    ),
                    SizedBox(height: cardGap),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(28),
                            topRight: Radius.circular(28),
                          ),
                        ),
                        padding: EdgeInsets.fromLTRB(
                          24,
                          24,
                          24,
                          24 + MediaQuery.of(context).padding.bottom,
                        ),
                        child: child,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}