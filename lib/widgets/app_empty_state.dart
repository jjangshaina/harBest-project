import 'package:flutter/material.dart';
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