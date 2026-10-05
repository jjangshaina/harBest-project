import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_style.dart';

/// Slim capsule progress bar: light track, rounded fill that animates when
/// the value changes. [value] is 0–1.
class AppProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  final double height;

  const AppProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 5,
  });

  @override
  Widget build(BuildContext context) {
    // Built from FractionallySizedBox (not LayoutBuilder) so the bar can sit
    // inside IntrinsicHeight, which the Plant Profile timeline uses.
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: ColoredBox(
          color: AppColors.track,
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedFractionallySizedBox(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
              widthFactor: value.clamp(0.0, 1.0),
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small rounded tag with a colored dot, e.g. "● 8 CRITICAL".
class AppStatusPill extends StatelessWidget {
  final String text;
  final Color color;

  const AppStatusPill({super.key, required this.text, required this.color});

  /// Pill for a health level: "CRITICAL", "CAUTION" or "OPTIMAL".
  factory AppStatusPill.level(HealthLevel level, {String? text}) =>
      AppStatusPill(
        text: text ?? level.label.toUpperCase(),
        color: level.color,
      );

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              text,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Circular gauge with [child] in the middle (usually a percentage).
class AppHealthRing extends StatelessWidget {
  final double progress; // 0–1
  final Color color;
  final double size;
  final Widget? child;

  const AppHealthRing({
    super.key,
    required this.progress,
    required this.color,
    this.size = 62,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(progress: progress, color: color),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final arcRect = (Offset.zero & size).deflate(stroke / 2);

    canvas.drawArc(
      arcRect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = AppColors.track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    final sweep = math.pi * 2 * progress.clamp(0.0, 1.0);
    if (sweep > 0) {
      canvas.drawArc(
        arcRect,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color;
}