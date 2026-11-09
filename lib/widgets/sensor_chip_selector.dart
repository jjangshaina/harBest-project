import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/pages/user_dashboard.dart'
    show kSensors;

/// Scrolling row of sensor filter chips with a minimap slider underneath.
/// Tapping a chip selects it and centres it; the minimap follows the row,
/// and tapping or dragging the minimap scrolls the chips.
///
/// Shared by the Analytics and AI Forecasting pages.
class SensorChipSelector extends StatefulWidget {
  final String selectedKey;
  final ValueChanged<String> onChanged;

  const SensorChipSelector({
    super.key,
    required this.selectedKey,
    required this.onChanged,
  });

  @override
  State<SensorChipSelector> createState() => _SensorChipSelectorState();
}

class _SensorChipSelectorState extends State<SensorChipSelector> {
  final _scroll = ScrollController();
  final _keys = List.generate(kSensors.length, (_) => GlobalKey());
  // Minimap thumb position: (start, size), both as 0..1 of the track.
  final _mini = ValueNotifier<(double, double)>((0.0, 1.0));

  @override
  void dispose() {
    _scroll.dispose();
    _mini.dispose();
    super.dispose();
  }

  // Keeps the minimap thumb in sync with the chip row.
  bool _onScroll(Notification n) {
    final m = n is ScrollNotification
        ? n.metrics
        : n is ScrollMetricsNotification
        ? n.metrics
        : null;
    if (m == null || m.viewportDimension <= 0) return false;
    final total = m.maxScrollExtent + m.viewportDimension;
    final size = (m.viewportDimension / total).clamp(0.05, 1.0);
    final start = m.maxScrollExtent <= 0
        ? 0.0
        : (m.pixels / m.maxScrollExtent).clamp(0.0, 1.0) * (1 - size);
    final next = (start, size);
    // ScrollMetricsNotification can fire mid-layout, where changing a
    // listened-to value triggers "Build scheduled during frame".
    final phase = WidgetsBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      _mini.value = next;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mini.value = next;
      });
    }
    return false;
  }

  void _select(int i) {
    widget.onChanged(kSensors[i].key);
    final ctx = _keys[i].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 40,
          child: NotificationListener<Notification>(
            onNotification: _onScroll,
            child: ListView.separated(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: kSensors.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => _buildChip(i),
            ),
          ),
        ),
        const SizedBox(height: 2),
        _buildMinimap(),
      ],
    );
  }

  Widget _buildChip(int i) {
    final d = kSensors[i];
    final selected = d.key == widget.selectedKey;
    return FilterChip(
      key: _keys[i],
      label: Text(
        d.label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? Colors.white : AppColors.textPrimary,
        ),
      ),
      selected: selected,
      showCheckmark: false,
      selectedColor: AppColors.green,
      backgroundColor: Colors.white,
      side: BorderSide(color: selected ? AppColors.green : AppColors.track),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      onSelected: (_) => _select(i),
    );
  }

  // Slim track + thumb under the chips. Tap or drag it to move through chips.
  Widget _buildMinimap() {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        void jump(double dx) {
          if (!_scroll.hasClients) return;
          final thumbW = w * _mini.value.$2;
          final frac = w <= thumbW
              ? 0.0
              : ((dx - thumbW / 2) / (w - thumbW)).clamp(0.0, 1.0);
          _scroll.jumpTo(frac * _scroll.position.maxScrollExtent);
        }

        Widget bar(double width, Color color) => Container(
          height: 4,
          width: width,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => jump(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => jump(d.localPosition.dx),
          child: SizedBox(
            height: 14,
            child: Center(
              child: ValueListenableBuilder<(double, double)>(
                valueListenable: _mini,
                builder: (_, v, _) => Stack(
                  children: [
                    bar(w, Colors.grey.shade300),
                    Positioned(
                      left: v.$1 * w,
                      child: bar(v.$2 * w, Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}