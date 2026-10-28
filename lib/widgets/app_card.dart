import 'package:flutter/material.dart';
import '../theme/app_style.dart';

/// The standard white rounded card. By default it has a soft shadow; pass
/// [outlineColor] for an outlined (emphasised) card instead.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? outlineColor;
  final double radius;
  final Color? color;
  final bool flat; // true = no shadow

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.onTap,
    this.outlineColor,
    this.radius = AppRadius.card,
    this.color,
    this.flat = false,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.card,
        borderRadius: BorderRadius.circular(radius),
         boxShadow: (outlineColor == null && !flat) ? AppShadows.card : null,
        border: outlineColor == null
            ? null
            : Border.all(color: outlineColor!, width: 1.5),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: card,
    );
  }
}
