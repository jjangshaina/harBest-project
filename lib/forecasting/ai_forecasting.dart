import 'dart:math' as math;
import 'package:flutter/cupertino.dart' show CupertinoSlidingSegmentedControl;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/widgets/app_card.dart';
import 'package:flutter_application_harbest_1/widgets/app_header.dart';
import 'package:flutter_application_harbest_1/pages/user_dashboard.dart'
    show SensorDef, kSensors;

const _forecastColor = Color(0xFFD9822B);

/// Forecast horizons: label, subtitle text, and hours of history shown
/// before "Now". The future side is always twice the history side.
const _ranges = [
  (label: '24 hours', text: '24 hours', pastHours: 12),
  (label: '3 days', text: '3 days', pastHours: 36),
  (label: '7 days', text: '7 days', pastHours: 84),
];

/// What the chart needs for one sensor + horizon.
/// TODO(backend): replace [_mockForecast] with the real forecasting result.
class _Forecast {
  final List<FlSpot> actual; // x = hours relative to now (≤ 0)
  final List<FlSpot> predicted; // x = hours relative to now (≥ 0)
  final List<FlSpot> upper; // confidence band, same x as [predicted]
  final List<FlSpot> lower;
  const _Forecast(this.actual, this.predicted, this.upper, this.lower);
}

// Placeholder data shaped like the design: the sensor drifts down out of its
// optimal range and the confidence band widens with time.
_Forecast _mockForecast(SensorDef def, int range) {
  final past = _ranges[range].pastHours.toDouble();
  final future = past * 2;
  final span = def.max - def.min;
  const n = 12;

  final actual = <FlSpot>[
    for (int i = 0; i <= n; i++)
      FlSpot(
        -past + past * i / n,
        def.min +
            span *
                (0.6 -
                    0.55 * i / n +
                    0.03 * math.sin(i * 1.7) * (1 - i / n)),
      ),
  ];
  final now = actual.last.y;
  final predicted = <FlSpot>[
    for (int j = 0; j <= n; j++)
      FlSpot(future * j / n, now - 0.65 * span * j / n),
  ];
  return _Forecast(
    actual,
    predicted,
    [for (int j = 0; j <= n; j++) FlSpot(predicted[j].x, predicted[j].y + 0.3 * span * j / n)],
    [for (int j = 0; j <= n; j++) FlSpot(predicted[j].x, predicted[j].y - 0.3 * span * j / n)],
  );
}

class AiForecasting extends StatefulWidget {
  const AiForecasting({super.key});

  @override
  State<AiForecasting> createState() => _AiForecastingState();
}

class _AiForecastingState extends State<AiForecasting> {
  String _sensorKey = kSensors.first.key;
  int _range = 0;

  SensorDef get _def => kSensors.firstWhere(
    (d) => d.key == _sensorKey,
    orElse: () => kSensors.first,
  );

  // "-12h", "+36h", "+3.5d" ...
  String _hoursLabel(double h) {
    if (h == 0) return 'Now';
    final a = h.abs();
    final text = a < 48
        ? '${a.round()}h'
        : '${(a / 24).toStringAsFixed(a % 24 == 0 ? 0 : 1)}d';
    return '${h < 0 ? '-' : '+'}$text';
  }

  // ───────────────────────── UI pieces ─────────────────────────

  Widget _rangePicker() => SizedBox(
    width: double.infinity,
    child: CupertinoSlidingSegmentedControl<int>(
      groupValue: _range,
      thumbColor: Colors.white,
      backgroundColor: const Color(0xFFE3E3F0),
      children: {
        for (int i = 0; i < _ranges.length; i++)
          i: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              _ranges[i].label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: i == _range ? FontWeight.w700 : FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
      },
      onValueChanged: (v) => setState(() => _range = v ?? 0),
    ),
  );

  Widget _legendItem(Widget swatch, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      swatch,
      const SizedBox(width: 4),
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
    ],
  );

  Widget _line(Color c, {bool dashed = false}) => SizedBox(
    width: 16,
    height: 3,
    child: dashed
        ? Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (int i = 0; i < 3; i++)
                Container(width: 4, height: 3, color: c),
            ],
          )
        : ColoredBox(color: c),
  );

  Widget _box(Color c) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
  );

  Widget _legend(SensorDef def) => Wrap(
    spacing: 14,
    runSpacing: 6,
    children: [
      _legendItem(_line(AppColors.healthy), 'Actual'),
      _legendItem(_line(_forecastColor, dashed: true), 'Forecast'),
      _legendItem(_box(_forecastColor.withOpacity(0.25)), 'Confidence range'),
      _legendItem(
        _box(AppColors.optimal.withOpacity(0.2)),
        'Optimal ${def.optimalText}',
      ),
    ],
  );

  // ───────────────────────── Chart ─────────────────────────

  Widget _chart(SensorDef def) {
    final f = _mockForecast(def, _range);
    final past = _ranges[_range].pastHours.toDouble();
    final span = def.max - def.min;
    final minY = def.min - span, maxY = def.max;

    // Invisible bars carry the confidence band fill.
    LineChartBarData edge(List<FlSpot> s) => LineChartBarData(
      spots: s,
      color: Colors.transparent,
      barWidth: 0,
      dotData: const FlDotData(show: false),
    );

    return LineChart(
      LineChartData(
        minX: -past,
        maxX: past * 2,
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: span,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.track, strokeWidth: 1),
        ),
        rangeAnnotations: RangeAnnotations(
          horizontalRangeAnnotations: [
            HorizontalRangeAnnotation(
              y1: def.min,
              y2: def.max,
              color: AppColors.optimal.withOpacity(0.12),
            ),
          ],
        ),
        extraLinesData: ExtraLinesData(
          verticalLines: [
            VerticalLine(
              x: 0,
              color: AppColors.textTertiary,
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
          ],
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: span,
              getTitlesWidget: (v, _) => Text(
                '${v.toStringAsFixed(def.decimals)}${def.unit}',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: past,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _hoursLabel(v),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
        betweenBarsData: [
          BetweenBarsData(
            fromIndex: 2,
            toIndex: 3,
            color: _forecastColor.withOpacity(0.22),
          ),
        ],
        lineBarsData: [
          // 0: actual readings
          LineChartBarData(
            spots: f.actual,
            isCurved: true,
            color: AppColors.healthy,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
          ),
          // 1: forecast (dashed) with a red dot where it starts
          LineChartBarData(
            spots: f.predicted,
            color: _forecastColor,
            barWidth: 2.5,
            dashArray: [6, 4],
            dotData: FlDotData(
              show: true,
              checkToShowDot: (s, _) => s.x == f.predicted.first.x,
              getDotPainter: (a, b, c, d) => FlDotCirclePainter(
                radius: 4,
                color: AppColors.critical,
                strokeWidth: 2,
                strokeColor: Colors.white,
              ),
            ),
          ),
          // 2 + 3: confidence band edges
          edge(f.upper),
          edge(f.lower),
        ],
      ),
    );
  }

  // ───────────────────────── Page ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final def = _def;
    return Column(
      children: [
        const AppHeader(title: 'AI Forecasting'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SensorChipSelector(
                  selectedKey: _sensorKey,
                  onChanged: (k) => setState(() => _sensorKey = k),
                ),
                const SizedBox(height: AppSpace.cardGap),
                _rangePicker(),
                const SizedBox(height: AppSpace.cardGap),
                SizedBox(
                  width: double.infinity,
                  child: AppCard(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${def.label} outlook', style: AppText.cardTitle),
                        const SizedBox(height: 2),
                        Text(
                          'Next ${_ranges[_range].text}, predicted from your '
                          'last readings',
                          style: AppText.subtitle,
                        ),
                        const SizedBox(height: 12),
                        SizedBox(height: 200, child: _chart(def)),
                        const SizedBox(height: 10),
                        _legend(def),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Scrolling row of sensor filter chips with a minimap slider underneath.
/// Tapping a chip centres it; the minimap follows the scroll and can be
/// tapped or dragged to move through the chips.
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
  // Minimap thumb (start, size) as fractions of the track.
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
    final size = (m.viewportDimension / (m.maxScrollExtent + m.viewportDimension))
        .clamp(0.05, 1.0);
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

  Widget _minimap() {
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
              itemBuilder: (context, i) {
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
                  side: BorderSide(
                    color: selected ? AppColors.green : AppColors.track,
                  ),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  onSelected: (_) {
                    widget.onChanged(d.key);
                    final ctx = _keys[i].currentContext;
                    if (ctx != null) {
                      Scrollable.ensureVisible(
                        ctx,
                        alignment: 0.5,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                      );
                    }
                  },
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 2),
        _minimap(),
      ],
    );
  }
}