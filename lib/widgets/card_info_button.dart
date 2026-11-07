import 'package:flutter/material.dart';
import '../theme/app_style.dart';
import 'app_dialogs.dart';

/// Small "i" button for the top-right of a card. Tapping it shows [text].
class CardInfoButton extends StatelessWidget {
  final String title;
  final String text;
  const CardInfoButton({super.key, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'About this chart',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      visualDensity: VisualDensity.compact,
      icon: const Icon(AppIcons.infoOutline,
          size: 22, color: AppColors.textSecondary),
      onPressed: () => AppDialog.info(context, title: title, message: text),
    );
  }
}