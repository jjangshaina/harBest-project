import 'package:flutter/material.dart';
import '../theme/app_style.dart';

enum AppSnackType { success, error, info }

/// One way to show a message at the bottom of the screen.
///   AppSnack.show(context, 'Saved', type: AppSnackType.success);
class AppSnack {
  AppSnack._();

  static void show(
    BuildContext context,
    String message, {
    AppSnackType type = AppSnackType.info,
  }) => showOn(ScaffoldMessenger.of(context), message, type: type);

  /// Same message, but through a messenger you already hold (used for
  /// push notifications that arrive while the app is open).
  static void showOn(
    ScaffoldMessengerState messenger,
    String message, {
    AppSnackType type = AppSnackType.info,
  }) {
    final IconData icon = switch (type) {
      AppSnackType.success => AppIcons.success,
      AppSnackType.error => AppIcons.error,
      AppSnackType.info => AppIcons.info,
    };
    final Color color = switch (type) {
      AppSnackType.success => AppColors.optimal,
      AppSnackType.error => AppColors.critical,
      AppSnackType.info => const Color(0xFF3A3A3C),
    };

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: color,
          content: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
  }
}