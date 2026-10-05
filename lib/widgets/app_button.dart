import 'package:flutter/material.dart';
import '../theme/app_style.dart';

enum AppButtonStyle { primary, destructive, outline }

/// The standard button. Use this instead of ElevatedButton / TextButton
/// directly so every button in the app looks and behaves the same.
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonStyle style;
  final bool expanded; // stretch to full width
  final bool loading; // show a spinner and ignore taps

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = AppButtonStyle.primary,
    this.expanded = false,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color base = style == AppButtonStyle.destructive
        ? AppColors.destructive
        : AppColors.green;

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.button),
    );
    final VoidCallback? tap = loading ? null : onPressed;
    final Widget text = loading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: style == AppButtonStyle.outline ? base : Colors.white,
            ),
          )
        : Text(label);
    final bool showIcon = icon != null && !loading;
    const minSize = Size(0, 46);

    final Widget button;
    if (style == AppButtonStyle.outline) {
      final s = OutlinedButton.styleFrom(
        foregroundColor: base,
        side: BorderSide(color: base, width: 1.5),
        minimumSize: minSize,
        shape: shape,
        textStyle: AppText.button,
      );
      button = !showIcon
          ? OutlinedButton(onPressed: tap, style: s, child: text)
          : OutlinedButton.icon(
              onPressed: tap,
              style: s,
              icon: Icon(icon, size: 18),
              label: Text(label),
            );
    } else {
      final s = ElevatedButton.styleFrom(
        backgroundColor: base,
        disabledBackgroundColor: base.withOpacity(0.6),
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: minSize,
        shape: shape,
        textStyle: AppText.button,
      );
      button = !showIcon
          ? ElevatedButton(onPressed: tap, style: s, child: text)
          : ElevatedButton.icon(
              onPressed: tap,
              style: s,
              icon: Icon(icon, size: 18),
              label: Text(label),
            );
    }

    return expanded
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}

/// The big rounded gradient button on the sign-in / sign-up screens.
/// [active] only changes the look (green when the form is ready, grey when
/// not); it is still tappable so the screen can show what is missing.
/// Pass a null [onPressed] to disable it (e.g. while [loading]).
class AppPillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool active;
  final bool loading;

  const AppPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.active = true,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 55,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: active
              ? const [AppColors.authAccent, AppColors.authAccentDark]
              : const [AppColors.disabledStart, AppColors.disabledEnd],
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                label,
                style: const TextStyle(fontSize: 18, color: Colors.white),
              ),
      ),
    );
  }
}

/// Small white round back button for screens without the green header.
class AppBackButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const AppBackButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 20,
      backgroundColor: Colors.white.withOpacity(0.9),
      child: IconButton(
        icon: const Icon(AppIcons.back, color: Colors.black, size: 18),
        onPressed: onPressed ?? () => Navigator.pop(context),
      ),
    );
  }
}

/// The two big buttons on the welcome screen: a green gradient one
/// ([primary] true) and a light grey one ([primary] false).
class AppLandingButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool primary;

  const AppLandingButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = true,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(15);
    if (!primary) {
      return ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.authField,
          foregroundColor: Colors.black,
          minimumSize: const Size(0, 60),
          shape: RoundedRectangleBorder(borderRadius: radius),
          elevation: 4,
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      );
    }
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.authAccent, AppColors.authAccentDark],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}