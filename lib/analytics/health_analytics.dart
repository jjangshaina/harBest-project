// Place at: lib/analytics/health_analytics.dart
//
// Three cards for the Analytics page, computed from sensor_readings:
//   1. Time in Range       - share of readings Optimal / Caution / Critical per sensor
//   2. Crop Health Timeline - daily share of Optimal / Warning / Critical crop_health
//   3. Top Stress Factors  - which sensors were out of range while health was not Optimal
//
// Uses the same ranges as the dashboard (kSensors) and the same scoring
// (100 = optimal, >= 50 = caution, below = critical), so numbers agree.
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/widgets/app_button.dart';
import 'package:flutter_application_harbest_1/widgets/app_card.dart';
import 'package:flutter_application_harbest_1/pages/user_dashboard.dart'
    show SensorDef, kSensors, normalizeReading;

class _RangeShare {
  final SensorDef def;
  final double optimal, caution, critical; // fractions, sum = 1
  const _RangeShare(this.def, this.optimal, this.caution, this.critical);
}

class _DayShare {
  final DateTime day;
  final double optimal, warning, critical; // percent, sum = 100
  const _DayShare(this.day, this.optimal, this.warning, this.critical);
}

class _Stress {
  final SensorDef def;
  final double percent; // of non-optimal readings
  const _Stress(this.def, this.percent);
}

class HealthAnalytics extends StatefulWidget {
  final String? deviceId;
  const HealthAnalytics({super.key, required this.deviceId});

  @override
  State<HealthAnalytics> createState() => HealthAnalyticsState();
}

class HealthAnalyticsState extends State<HealthAnalytics> {
  static const int _days = 7;
  static const int _pageSize =
      1000; // Supabase returns at most 1000 rows per request
  static const int _maxPages = 8;
  static const String _cols =
      'timestamp,temperature,humidity,heat_index,crop_health,'
      'nitrogen,phosphorus,potassium,pH,EC,moisture';

  final _db = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  int _readingCount = 0;
  int _stressReadings = 0;
  List<_RangeShare> _ranges = [];
  List<_DayShare> _daily = [];
  List<_Stress> _stress = [];

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void didUpdateWidget(covariant HealthAnalytics old) {
    super.didUpdateWidget(old);
    if (old.deviceId != widget.deviceId) reload();
  }

  // ───────────────────────── DATA ─────────────────────────

  Future<void> reload() async {
    final id = widget.deviceId;
    if (id == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _readingCount = 0;
        _ranges = [];
        _daily = [];
        _stress = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final since = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: _days))
          .toIso8601String();
      final rows = <Map<String, dynamic>>[];
      for (var page = 0; page < _maxPages; page++) {
        final res = await _db
            .from('sensor_readings')
            .select(_cols)
            .eq('device_id', id)
            .gte('timestamp', since)
            .order('timestamp', ascending: false)
            .range(page * _pageSize, page * _pageSize + _pageSize - 1);
        final list = (res as List)
            .map((e) => normalizeReading(Map<String, dynamic>.from(e as Map)))
            .toList();
        rows.addAll(list);
        if (list.length < _pageSize) break;
      }
      if (!mounted || id != widget.deviceId) return;
      _compute(rows);
      setState(() => _loading = false);
    } catch (e) {
      debugPrint('HealthAnalytics error: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Could not load health analytics.';
        _loading = false;
      });
    }
  }

  double? _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');

  // Same scoring as the dashboard: 100 inside range, 0 at `tolerance` away.
  double? _score(dynamic raw, SensorDef d) {
    final v = _num(raw);
    if (v == null) return null;
    if (v >= d.min && v <= d.max) return 100;
    final dev = v < d.min ? d.min - v : v - d.max;
    return dev >= d.tolerance ? 0 : 100 * (1 - dev / d.tolerance);
  }

  // 'optimal' | 'warning' | 'critical' | null (unknown / failed reading)
  String? _bucket(dynamic raw) {
    final s = '$raw'.toLowerCase();
    if (raw == null || s.contains('unknown')) return null;
    if (s.contains('optimal')) return 'optimal';
    if (s.contains('critical')) return 'critical';
    if (s.contains('warning')) return 'warning';
    return null;
  }

  void _compute(List<Map<String, dynamic>> rows) {
    _readingCount = rows.length;

    // 1. Time in range, per sensor (worst first).
    final ranges = <_RangeShare>[];
    for (final d in kSensors) {
      int o = 0, w = 0, c = 0;
      for (final r in rows) {
        final s = _score(r[d.key], d);
        if (s == null) continue;
        if (s >= 100) {
          o++;
        } else if (s >= 50) {
          w++;
        } else {
          c++;
        }
      }
      final n = o + w + c;
      if (n > 0) ranges.add(_RangeShare(d, o / n, w / n, c / n));
    }
    ranges.sort((a, b) => a.optimal.compareTo(b.optimal));

    // 2 + 3. Daily crop-health shares and stress-factor counts.
    final byDay = <DateTime, List<int>>{}; // [optimal, warning, critical]
    final stressCount = <String, int>{};
    var stressRows = 0;
    for (final r in rows) {
      final b = _bucket(r['crop_health']);
      if (b == null) continue;
      final t = DateTime.tryParse('${r['timestamp']}')?.toUtc();
      if (t != null) {
        final day = DateTime(t.year, t.month, t.day);
        byDay.putIfAbsent(day, () => [0, 0, 0])[b == 'optimal'
            ? 0
            : (b == 'warning' ? 1 : 2)]++;
      }
      if (b != 'optimal') {
        stressRows++;
        for (final d in kSensors) {
          final s = _score(r[d.key], d);
          if (s != null && s < 100) {
            stressCount[d.key] = (stressCount[d.key] ?? 0) + 1;
          }
        }
      }
    }

    final days = byDay.keys.toList()..sort();
    final daily = <_DayShare>[
      for (final d in days)
        () {
          final a = byDay[d]!;
          final n = a[0] + a[1] + a[2];
          return _DayShare(d, 100 * a[0] / n, 100 * a[1] / n, 100 * a[2] / n);
        }(),
    ];

    final stress = <_Stress>[
      if (stressRows > 0)
        for (final d in kSensors)
          if ((stressCount[d.key] ?? 0) > 0)
            _Stress(d, 100 * stressCount[d.key]! / stressRows),
    ]..sort((a, b) => b.percent.compareTo(a.percent));

    _ranges = ranges;
    _daily = daily;
    _stress = stress.take(5).toList();
    _stressReadings = stressRows;
  }

  // ───────────────────────── UI HELPERS ─────────────────────────

  Widget _card({
    required String title,
    required String subtitle,
    required Widget body,
    String? caption,
  }) {
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppText.cardTitle),
            const SizedBox(height: 2),
            Text(subtitle, style: AppText.subtitle),
            const SizedBox(height: 12),
            body,
            if (caption != null) ...[
              const SizedBox(height: 8),
              Text(caption, style: AppText.caption),
            ],
          ],
        ),
      ),
    );
  }

  Widget _message(String text, {VoidCallback? onRetry}) => SizedBox(
    height: 120,
    child: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 10),
            AppButton(
              label: 'Retry',
              icon: AppIcons.refresh,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    ),
  );

  /// Spinner / error / empty body, or null when there is data to draw.
  Widget? _notReady(bool hasData, String emptyText) {
    if (_loading) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) return _message(_error!, onRetry: reload);
    if (!hasData) return _message(emptyText);
    return null;
  }

  Widget _legendDot(Color c, String label) => Padding(
    padding: const EdgeInsets.only(right: 12),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
        ),
      ],
    ),
  );

  // ───────────────────────── CARD 1: TIME IN RANGE ─────────────────────────

  Widget _segment(double fraction, Color color) {
    final flex = (fraction * 1000).round();
    if (flex <= 0) return const SizedBox.shrink();
    return Expanded(
      flex: flex,
      child: ColoredBox(color: color),
    );
  }

  Widget _rangeRow(_RangeShare r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                r.def.label,
                style: AppText.body.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${(r.optimal * 100).round()}% optimal',
                style: AppText.caption.copyWith(fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  _segment(r.optimal, AppColors.optimal),
                  _segment(r.caution, AppColors.caution),
                  _segment(r.critical, AppColors.critical),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeInRange() {
    final body =
        _notReady(_ranges.isNotEmpty, 'No readings in the last $_days days.') ??
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in _ranges) _rangeRow(r),
            Wrap(
              children: [
                _legendDot(AppColors.optimal, 'Optimal'),
                _legendDot(AppColors.caution, 'Caution'),
                _legendDot(AppColors.critical, 'Critical'),
              ],
            ),
          ],
        );
    return _card(
      title: 'Time in Range',
      subtitle: 'Last $_days days · $_readingCount readings',
      body: body,
      caption:
          'Share of readings inside, near, or far outside each sensor\'s '
          'optimal range. Worst sensors are listed first.',
    );
  }

  // ───────────────────────── CARD 2: CROP HEALTH TIMELINE ─────────────────────────

  Widget _buildHealthTimeline() {
    final body =
        _notReady(
          _daily.isNotEmpty,
          'No crop health data in the last $_days days.',
        ) ??
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 170, child: _timelineChart()),
            const SizedBox(height: 8),
            Wrap(
              children: [
                _legendDot(AppColors.optimal, 'Optimal'),
                _legendDot(AppColors.caution, 'Warning'),
                _legendDot(AppColors.critical, 'Critical'),
              ],
            ),
          ],
        );
    return _card(
      title: 'Crop Health Timeline',
      subtitle: 'Daily share of readings by status',
      body: body,
      caption:
          'Each bar is one day. Tap a bar for the exact percentages. '
          'Readings with an unknown status are left out.',
    );
  }

  Widget _timelineChart() {
    const tick = TextStyle(fontSize: 9, color: AppColors.textSecondary);
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: 100,
        alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.track, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: 25,
              getTitlesWidget: (v, _) => Text('${v.toInt()}%', style: tick),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= _daily.length) return const SizedBox.shrink();
                final d = _daily[i].day;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${d.month}/${d.day}', style: tick),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.textPrimary,
            getTooltipItem: (g, gi, rod, ri) {
              final d = _daily[gi];
              return BarTooltipItem(
                '${d.day.month}/${d.day.day}\n'
                'Optimal ${d.optimal.round()}%\n'
                'Warning ${d.warning.round()}%\n'
                'Critical ${d.critical.round()}%',
                const TextStyle(color: Colors.white, fontSize: 12),
              );
            },
          ),
        ),
        barGroups: [
          for (int i = 0; i < _daily.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: 100,
                  width: _daily.length > 8 ? 14 : 22,
                  borderRadius: BorderRadius.circular(4),
                  rodStackItems: [
                    BarChartRodStackItem(
                      0,
                      _daily[i].optimal,
                      AppColors.optimal,
                    ),
                    BarChartRodStackItem(
                      _daily[i].optimal,
                      _daily[i].optimal + _daily[i].warning,
                      AppColors.caution,
                    ),
                    BarChartRodStackItem(
                      _daily[i].optimal + _daily[i].warning,
                      100,
                      AppColors.critical,
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ───────────────────────── CARD 3: TOP STRESS FACTORS ─────────────────────────

  Widget _stressRow(_Stress s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                s.def.label,
                style: AppText.body.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${s.percent.round()}%',
                style: AppText.caption.copyWith(fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: ColoredBox(color: AppColors.track),
                  ),
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: (s.percent / 100).clamp(0.0, 1.0),
                      child: const ColoredBox(color: AppColors.critical),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStressFactors() {
    final emptyText = _stressReadings == 0 && !_loading && _error == null
        ? 'No Warning or Critical readings in the last $_days days.'
        : 'Not enough data yet.';
    final body =
        _notReady(_stress.isNotEmpty, emptyText) ??
        Column(children: [for (final s in _stress) _stressRow(s)]);
    return _card(
      title: 'Top Stress Factors',
      subtitle:
          '$_stressReadings Warning / Critical readings · last $_days days',
      body: body,
      caption:
          'Of the readings where crop health was not Optimal, the share '
          'in which each sensor was outside its optimal range. Several '
          'sensors can be out of range in the same reading.',
    );
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: AppSpace.cardGap);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTimeInRange(),
        gap,
        _buildHealthTimeline(),
        gap,
        _buildStressFactors(),
      ],
    );
  }
}
