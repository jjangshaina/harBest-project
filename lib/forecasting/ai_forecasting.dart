// UNTESTED: written without a Flutter compiler. Replaces the mock-data version.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/widgets/app_card.dart';
import 'package:flutter_application_harbest_1/widgets/app_header.dart';
import 'package:flutter_application_harbest_1/widgets/status_widgets.dart';
import 'package:flutter_application_harbest_1/services/crop_services.dart';
import 'package:flutter_application_harbest_1/services/forecast_service.dart';
import 'package:flutter_application_harbest_1/pages/user_dashboard.dart'
    show SensorDef, kSensors;

const _forecastColor = Color(0xFFD9822B);

/// App sensor key -> variable name used by the forecast pipeline.
/// Sensors not listed (heat index, N, P, K) have no forecast yet.
const _varNames = {
  'moisture': 'moisture_pct',
  'pH': 'pH',
  'temperature': 'temperature',
  'humidity': 'humidity',
  'EC': 'EC',
};

class _Forecast {
  final List<FlSpot> actual, predicted, upper, lower; // x = hours from now
  const _Forecast(this.actual, this.predicted, this.upper, this.lower);
}

/// [k] converts pipeline units to app units (EC: µS/cm -> mS/cm).
_Forecast _parse(Map<String, dynamic> v, double k) {
  final origin = DateTime.parse(v['current']['time'] as String);
  double hrs(String t) => DateTime.parse(t).difference(origin).inMinutes / 60.0;
  final now = (v['current']['value'] as num).toDouble() * k;

  final actual = <FlSpot>[
    for (final p in (v['history'] as List))
      FlSpot(hrs(p['t'] as String), (p['v'] as num).toDouble() * k),
  ];
  if (actual.isEmpty) actual.add(FlSpot(0, now));

  final fc = v['forecast'] as List;
  List<FlSpot> line(String key) => [
    FlSpot(0, now),
    for (final f in fc)
      FlSpot((f['horizon_min'] as num).toDouble() / 60.0,
          (f[key] as num).toDouble() * k),
  ];
  return _Forecast(actual, line('value'), line('upper'), line('lower'));
}

String _horizonText(num minutes) {
  if (minutes < 60) return '${minutes.round()} min';
  if (minutes < 1440) return '${(minutes / 60).round()} h';
  return '${(minutes / 1440).round()} days';
}

String _clock(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'PM' : 'AM'}';
}

class AiForecasting extends StatefulWidget {
  const AiForecasting({super.key});

  @override
  State<AiForecasting> createState() => _AiForecastingState();
}

class _AiForecastingState extends State<AiForecasting> {
  String _sensorKey = kSensors.first.key;
  Map<String, dynamic>? _run;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    CropService.instance.addListener(_load);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    CropService.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted || !CropService.instance.loaded) return;
    final id = CropService.instance.selected?.deviceId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final run = id == null ? null : await ForecastService.latest(id);
      if (!mounted) return;
      setState(() {
        _run = run;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Forecast load error: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the forecast. Pull down to retry.';
        _loading = false;
      });
    }
  }

  SensorDef get _def => kSensors.firstWhere(
    (d) => d.key == _sensorKey,
    orElse: () => kSensors.first,
  );

  Map<String, dynamic>? get _variable {
    final name = _varNames[_sensorKey];
    final vars = _run?['variables'];
    if (name == null || vars is! Map || vars[name] is! Map) return null;
    return Map<String, dynamic>.from(vars[name] as Map);
  }

  // ───────────────────────── helpers ─────────────────────────

  Color _statusColor(String s) => switch (s) {
    'optimal' => AppColors.optimal,
    'caution' => AppColors.caution,
    'out_of_range' => AppColors.critical,
    _ => AppColors.textTertiary,
  };

  String _statusLabel(String s) => switch (s) {
    'optimal' => 'OPTIMAL',
    'caution' => 'CAUTION',
    'out_of_range' => 'OUT OF RANGE',
    _ => 'NO RANGE SET',
  };

  Widget _banner(String text, Color color) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(AppRadius.field),
    ),
    child: Text(text, style: AppText.body.copyWith(fontSize: 13, height: 1.4)),
  );

  String _axisLabel(double h) {
    if (h.abs() < 0.01) return 'Now';
    final a = h.abs();
    final text = a < 1
        ? '${(a * 60).round()}m'
        : a < 48
        ? '${a.toStringAsFixed(a % 1 == 0 ? 0 : 1)}h'
        : '${(a / 24).toStringAsFixed(1)}d';
    return '${h < 0 ? '-' : '+'}$text';
  }

  // ───────────────────────── chart ─────────────────────────

  Widget _chart(Map<String, dynamic> v, SensorDef def, double k) {
    final f = _parse(v, k);
    final opt = v['optimal'] as List?;
    final optLo = opt == null ? null : (opt[0] as num).toDouble() * k;
    final optHi = opt == null ? null : (opt[1] as num).toDouble() * k;

    var minX = f.actual.first.x;
    final maxX = f.predicted.last.x;
    if (minX >= 0) minX = -(maxX / 2);

    final ys = <double>[
      for (final s in [f.actual, f.predicted, f.upper, f.lower]) ...s.map((p) => p.y),
      ?optLo,
      ?optHi,
    ];
    var lo = ys.reduce((a, b) => a < b ? a : b);
    var hi = ys.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 1e-9) {
      hi += 1;
      lo -= 1;
    }
    final pad = (hi - lo) * 0.1;
    final minY = lo - pad, maxY = hi + pad;
    final yStep = (maxY - minY) / 4;

    LineChartBarData edge(List<FlSpot> s) => LineChartBarData(
      spots: s,
      color: Colors.transparent,
      barWidth: 0,
      dotData: const FlDotData(show: false),
    );

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: yStep,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.track, strokeWidth: 1),
        ),
        rangeAnnotations: RangeAnnotations(
          horizontalRangeAnnotations: optLo == null
              ? const []
              : [
                  HorizontalRangeAnnotation(
                    y1: optLo,
                    y2: optHi!,
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
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: yStep,
              getTitlesWidget: (y, _) => Text(
                y.toStringAsFixed(def.decimals),
                style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: (maxX - minX) / 4,
              getTitlesWidget: (x, _) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _axisLabel(x),
                  style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
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
          LineChartBarData(
            spots: f.actual,
            isCurved: true,
            color: AppColors.healthy,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: f.predicted,
            color: _forecastColor,
            barWidth: 2.5,
            dashArray: [6, 4],
            dotData: FlDotData(
              show: true,
              checkToShowDot: (s, _) => s.x == 0,
              getDotPainter: (a, b, c, d) => FlDotCirclePainter(
                radius: 4,
                color: AppColors.critical,
                strokeWidth: 2,
                strokeColor: Colors.white,
              ),
            ),
          ),
          edge(f.upper), // index 2
          edge(f.lower), // index 3
        ],
      ),
    );
  }

  Widget _legendItem(Color c, String label, {bool box = false}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: box ? 12 : 16, height: box ? 12 : 3, color: c),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
    ],
  );

  // ───────────────────────── cards ─────────────────────────

  Widget _infoCard(String title, String value, {Widget? badge}) => Expanded(
    child: AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.caption.copyWith(fontSize: 12)),
          const SizedBox(height: 6),
          Text(value, style: AppText.cardTitle),
          if (badge != null) ...[const SizedBox(height: 6), badge],
        ],
      ),
    ),
  );

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!, style: AppText.subtitle));
    if (_run == null) {
      return const Center(
        child: Text('No forecast has been generated yet.', style: AppText.subtitle),
      );
    }
    final def = _def;
    final v = _variable;
    final k = _sensorKey == 'EC' ? 0.001 : 1.0; // µS/cm -> mS/cm

    final children = <Widget>[
      SensorChipSelector(
        selectedKey: _sensorKey,
        onChanged: (key) => setState(() => _sensorKey = key),
      ),
      const SizedBox(height: AppSpace.cardGap),
    ];

    if (_run!['status'] == 'experimental') {
      children.addAll([
        _banner('Experimental: ${_run!['note']}', AppColors.info),
        const SizedBox(height: AppSpace.gap),
      ]);
    }
    if (_run!['stale'] == true) {
      children.addAll([
        _banner('Waiting for new sensor data. The forecast is based on older readings.',
            AppColors.caution),
        const SizedBox(height: AppSpace.gap),
      ]);
    }

    if (v == null) {
      children.add(
        SizedBox(
          width: double.infinity,
          child: AppCard(
            padding: const EdgeInsets.all(20),
            child: Text('A forecast for ${def.label} is not available yet.',
                style: AppText.subtitle),
          ),
        ),
      );
      return ListView(padding: const EdgeInsets.all(AppSpace.page), children: children);
    }

    final status = v['status'] as String;
    final fc = v['forecast'] as List;
    final last = fc.last;
    final leaves = v['leaves_optimal_at'] as String?;
    final leaveText = leaves != null
        ? _clock(DateTime.parse(leaves).toLocal())
        : (status == 'out_of_range' ? 'Now' : 'Stays in range');

    children.addAll([
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
                'Next ${_horizonText((last['horizon_min'] as num))}, predicted from your last readings',
                style: AppText.subtitle,
              ),
              const SizedBox(height: 12),
              SizedBox(height: 200, child: _chart(v, def, k)),
              const SizedBox(height: 10),
              Wrap(spacing: 14, runSpacing: 6, children: [
                _legendItem(AppColors.healthy, 'Actual'),
                _legendItem(_forecastColor, 'Forecast'),
                _legendItem(_forecastColor.withOpacity(0.25), 'Confidence range', box: true),
                if (v['optimal'] != null)
                  _legendItem(AppColors.optimal.withOpacity(0.2), 'Optimal', box: true),
              ]),
            ],
          ),
        ),
      ),
      const SizedBox(height: AppSpace.gap),
      Row(children: [
        _infoCard(
          'Predicted in ${_horizonText(last['horizon_min'] as num)}',
          '${((last['value'] as num).toDouble() * k).toStringAsFixed(def.decimals)}${def.unit}',
          badge: AppStatusPill(text: _statusLabel(status), color: _statusColor(status)),
        ),
        const SizedBox(width: AppSpace.gap),
        _infoCard('Leaves optimal range', leaveText),
      ]),
      const SizedBox(height: AppSpace.gap),
      SizedBox(
        width: double.infinity,
        child: AppCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Suggested action', style: AppText.label),
              const SizedBox(height: 6),
              Text(v['suggested_action'] as String, style: AppText.body.copyWith(fontSize: 14)),
            ],
          ),
        ),
      ),
      const SizedBox(height: AppSpace.gap),
      Text(v['footer'] as String, style: AppText.caption),
    ]);

    return RefreshIndicator(
      color: AppColors.green,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpace.page),
        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AppHeader(title: 'AI Forecasting'),
        Expanded(child: _body()),
      ],
    );
  }
}

/// Scrolling row of sensor filter chips with a minimap slider underneath.
/// (Unchanged from the original file.)
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
  final _mini = ValueNotifier<(double, double)>((0.0, 1.0));

  @override
  void dispose() {
    _scroll.dispose();
    _mini.dispose();
    super.dispose();
  }

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
    final phase = WidgetsBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle || phase == SchedulerPhase.postFrameCallbacks) {
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
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
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
                    Positioned(left: v.$1 * w, child: bar(v.$2 * w, Colors.grey.shade600)),
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
                  side: BorderSide(color: selected ? AppColors.green : AppColors.track),
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
