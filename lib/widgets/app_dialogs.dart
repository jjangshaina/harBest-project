import 'package:flutter/material.dart';
import '../theme/app_style.dart';

/// Standard pop-up dialogs, so every confirmation looks the same.
class AppDialog {
  AppDialog._();

  /// Yes/no question. Returns true only if the user taps the confirm button.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'OK',
    String cancelLabel = 'Cancel',
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              cancelLabel,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              confirmLabel,
              style: TextStyle(
                color:
                    destructive ? AppColors.destructive : AppColors.green,
              ),
            ),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// Asks for one line of text. Returns the trimmed text, or null if the
  /// user cancelled. Empty input is ignored (the Save button does nothing).
  static Future<String?> textInput(
    BuildContext context, {
    required String title,
    String initialValue = '',
    String? hint,
    String confirmLabel = 'Save',
    bool obscure = false,
    bool destructive = false,
  }) {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: obscure,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isNotEmpty) Navigator.of(ctx).pop(trimmed);
            },
            child: Text(
              confirmLabel,
              style: TextStyle(
                color: destructive ? AppColors.destructive : AppColors.green,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Simple message with one OK button.
  static Future<void> info(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'OK',
              style: TextStyle(color: AppColors.green),
            ),
          ),
        ],
      ),
    );
  }
}