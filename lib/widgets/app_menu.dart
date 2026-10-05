import 'package:flutter/cupertino.dart' show CupertinoSwitch, CupertinoTheme, CupertinoThemeData;
import 'package:flutter/material.dart';
import '../theme/app_style.dart';

/// Small grey heading above a group ("ACCOUNT", "SUPPORT").
class AppSectionLabel extends StatelessWidget {
  final String text;
  const AppSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 22, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: AppText.caption.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// White rounded card holding a list of rows, with a thin line between them.
class AppMenuGroup extends StatelessWidget {
  final List<Widget> children;
  const AppMenuGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(const Divider(
          height: 1,
          thickness: 1,
          indent: 64,
          color: AppColors.divider,
        ));
      }
      rows.add(children[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}

/// Rounded square with an icon in it, green (or red when [destructive]).
class AppIconTile extends StatelessWidget {
  final IconData icon;
  final bool destructive;
  const AppIconTile(this.icon, {super.key, this.destructive = false});

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.destructive : AppColors.green;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: destructive ? color : AppColors.darkGreen),
    );
  }
}

/// One tappable row: icon tile, title (+ optional small subtitle) and a
/// trailing widget (chevron by default).
class AppMenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final bool showChevron;

  const AppMenuTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            AppIconTile(icon, destructive: destructive),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppText.body.copyWith(
                      color: destructive
                          ? AppColors.destructive
                          : AppColors.textPrimary,
                    ),
                  ),
                  if (subtitle != null)
                    Text(subtitle!, style: AppText.caption),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (showChevron)
              const Icon(
                AppIcons.forward,
                size: 18,
                color: AppColors.textTertiary,
              ),
          ],
        ),
      ),
    );
  }
}

/// A row that opens and closes a panel of [child] under it (chevron turns).
/// The panel sits on a light grey background.
class AppExpandableTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool expanded;
  final VoidCallback onTap;
  final Widget child;

  const AppExpandableTile({
    super.key,
    required this.icon,
    required this.title,
    required this.expanded,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppMenuTile(
          icon: icon,
          title: title,
          onTap: onTap,
          trailing: AnimatedRotation(
            turns: expanded ? 0.25 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(
              AppIcons.forward,
              size: 18,
              color: AppColors.textTertiary,
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Container(
            width: double.infinity,
            color: AppColors.rowBackground,
            padding: const EdgeInsets.fromLTRB(64, 14, 16, 14),
            child: child,
          ),
          crossFadeState: expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }
}

/// The on / off switch used in settings (iOS style, brand green when on).
class AppToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const AppToggle({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return CupertinoTheme(
      data: const CupertinoThemeData(primaryColor: AppColors.green),
      child: CupertinoSwitch(value: value, onChanged: onChanged),
    );
  }
}