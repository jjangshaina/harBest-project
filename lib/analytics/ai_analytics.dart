import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/widgets/app_header.dart';
import 'package:flutter_application_harbest_1/widgets/app_button.dart';
import 'package:flutter_application_harbest_1/widgets/app_card.dart';
import 'package:flutter_application_harbest_1/services/crop_services.dart';
import 'package:flutter_application_harbest_1/pages/user_dashboard.dart'
    show SensorDef, kSensors;

// ── SCHEMA ──
// eda_correlations     : col_a (text), col_b (text), correlation (float8)
// eda_target_breakdown : crop_health (text), metric (text), avg_value (float8)
// sensor_daily_rolling : day, sensor, daily_mean, rolling_7d_mean
// sensor_weekly_avg    : week_end, sensor, weekly_mean, n_readings

const int _dailyKeep = 30; // newest N days to chart
const int _weeklyKeep = 12; // newest N weeks to chart

// Short axis labels for the correlation chart (full names shown in tooltip).
const Map<String, String> _shortNames = {
  'temperature': 'Temp',
  'humidity': 'Hum',
  'heat_index': 'HI',
  'nitrogen': 'N',
  'phosphorus': 'P',
  'potassium': 'K',
  'ph': 'pH',
  'ec': 'EC',
  'moisture': 'Moist',
};

String _short(String name) => _shortNames[name.toLowerCase()] ?? name;

double? _toNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

// "May 5 – 20, 2026", "May 5 – Jul 3, 2026" or "Dec 28, 2025 – Jan 3, 2026".
String _fmtRange(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 'no dates';
  if (a == null || b == null) {
    final d = (a ?? b)!;
    return '${_months[d.month - 1]} ${d.day}, ${d.year}';
  }
  if (a.year != b.year) {
    return '${_months[a.month - 1]} ${a.day}, ${a.year} – '
        '${_months[b.month - 1]} ${b.day}, ${b.year}';
  }
  if (a.month == b.month) {
    return a.day == b.day
        ? '${_months[a.month - 1]} ${a.day}, ${a.year}'
        : '${_months[a.month - 1]} ${a.day} – ${b.day}, ${a.year}';
  }
  return '${_months[a.month - 1]} ${a.day} – '
      '${_months[b.month - 1]} ${b.day}, ${a.year}';
}

// `crop_health` is TEXT, generated per-sensor. Scoring is pattern-based so
// new "X Warning" labels score correctly without another edit.
double? _scoreForCropHealth(String rawLabel) {
  final label = rawLabel.trim().toLowerCase();
  if (label.contains('unknown')) return null; // failed reading, excluded
  if (label.contains('optimal')) return 100;
  if (label.contains('critical')) return 15;
  if (label.contains('warning')) return 50;
  debugPrint('Unrecognized crop_health label, scored as 90: "$rawLabel"');
  return 90;
}

Color _colorForCropHealth(String label) {
  final s = _scoreForCropHealth(label);
  if (s == null) return AppColors.textTertiary;
  if (s >= 90) return AppColors.healthy;
  if (s >= 50) return AppColors.caution;
  return AppColors.critical;
}

class _CorrPair {
  final String a;
  final String b;
  final double value;
  const _CorrPair(this.a, this.b, this.value);
}

/// One row of sensor_daily_rolling for the selected sensor.
class _DailyPt {
  final DateTime? day;
  final double? daily; // daily_mean
  final double? rolling; // rolling_7d_mean
  const _DailyPt(this.day, this.daily, this.rolling);
}

/// One row of sensor_weekly_avg for the selected sensor.
class _WeeklyPt {
  final DateTime? weekEnd;
  final double mean; // weekly_mean
  final int? n; // n_readings
  const _WeeklyPt(this.weekEnd, this.mean, this.n);
}

class AiAnalytics extends StatefulWidget {
  const AiAnalytics({super.key});

  @override
  State<AiAnalytics> createState() => _AiAnalyticsState();
}

class _AiAnalyticsState extends State<AiAnalytics> {
  final _supabase = Supabase.instance.client;

  // ── EDA cards state ──
  bool _edaLoading = true;
  String? _edaError;
  List<_CorrPair> _topCorrelations = [];
  // metric -> (crop_health -> avg_value)
  Map<String, Map<String, double>> _breakdown = {};
  String? _selectedMetric;

  // ── Daily rolling / weekly average state ──
  bool _dailyLoading = true;
  String? _dailyError;
  List<_DailyPt> _daily = [];

  bool _weeklyLoading = true;
  String? _weeklyError;
  List<_WeeklyPt> _weekly = [];

  String _statKey = 'moisture'; // sensor shown in the two new charts

  // Overall period covered by the data (earliest / latest day).
  DateTime? _covStart;
  DateTime? _covEnd;

  @override
  void initState() {
    super.initState();
    CropService.instance.addListener(_onCropChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onCropChanged());
  }

  @override
  void dispose() {
    CropService.instance.removeListener(_onCropChanged);
    super.dispose();
  }

  // Runs when crops finish loading or the user picks another crop.
  void _onCropChanged() {
    if (!mounted || !CropService.instance.loaded) return;
    _fetchEda();
    _fetchCoverage();
    _fetchDaily();
    _fetchWeekly();
  }

  String? get _deviceId => CropService.instance.selected?.deviceId;
  // ───────────────────────── DATA: EDA tables ─────────────────────────

  Future<void> _fetchEda({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _edaLoading = true;
        _edaError = null;
      });
    }

    final deviceId = _deviceId;
    if (deviceId == null) {
      if (!mounted) return;
      setState(() {
        _topCorrelations = [];
        _breakdown = {};
        _selectedMetric = null;
        _edaLoading = false;
        _edaError = null;
      });
      return;
    }

    try {
      final corrRes = await _supabase.rpc(
        'device_correlations',
        params: {'p_device': deviceId},
      );
      final breakdownRes = await _supabase.rpc(
        'device_target_breakdown',
        params: {'p_device': deviceId},
      );

      // Correlations: drop self-pairs and mirrored duplicates, keep the 6
      // strongest by absolute value.
      final seen = <String>{};
      final pairs = <_CorrPair>[];
      for (final row in List<Map<String, dynamic>>.from(corrRes as List)) {
        final a = '${row['col_a']}';
        final b = '${row['col_b']}';
        final v = (row['correlation'] as num?)?.toDouble();
        if (v == null || a == b) continue;
        final key = ([a, b]..sort()).join('|');
        if (!seen.add(key)) continue;
        pairs.add(_CorrPair(a, b, v));
      }
      pairs.sort((x, y) => y.value.abs().compareTo(x.value.abs()));
      final top = pairs.take(6).toList();

      // Breakdown: group by metric.
      final grouped = <String, Map<String, double>>{};
      for (final row in List<Map<String, dynamic>>.from(breakdownRes as List)) {
        final metric = '${row['metric']}';
        final health = '${row['crop_health']}';
        final v = (row['avg_value'] as num?)?.toDouble();
        if (v == null) continue;
        grouped.putIfAbsent(metric, () => {})[health] = v;
      }

      if (!mounted) return;
      setState(() {
        _topCorrelations = top;
        _breakdown = grouped;
        if (_selectedMetric == null || !grouped.containsKey(_selectedMetric)) {
          _selectedMetric = grouped.isEmpty ? null : grouped.keys.first;
        }
        _edaLoading = false;
        _edaError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _edaError = 'Could not load analysis data.';
        _edaLoading = false;
      });
      debugPrint('EDA fetch error: $e');
    }
  }

  // Earliest and latest day in sensor_daily_rolling (the overall coverage).
  Future<void> _fetchCoverage() async {
    final deviceId = _deviceId;
    if (deviceId == null) {
      if (!mounted) return;
      setState(() {
        _covStart = null;
        _covEnd = null;
      });
      return;
    }
    try {
      final first = await _supabase
          .from('sensor_readings')
          .select('timestamp')
          .eq('device_id', deviceId)
          .order('timestamp', ascending: true)
          .limit(1);
      final last = await _supabase
          .from('sensor_readings')
          .select('timestamp')
          .eq('device_id', deviceId)
          .order('timestamp', ascending: false)
          .limit(1);

      DateTime? parse(dynamic res) {
        final list = res as List;
        return list.isEmpty
            ? null
            : DateTime.tryParse('${list.first['timestamp']}')?.toUtc();
      }

      if (!mounted) return;
      setState(() {
        _covStart = parse(first);
        _covEnd = parse(last);
      });
    } catch (e) {
      debugPrint('Coverage fetch error: $e');
    }
  }

  // ───────────────────── DATA: daily rolling / weekly avg ─────────────────────

  Future<void> _fetchDaily({bool showSpinner = true}) async {
    final key = _statKey;
    if (showSpinner) {
      setState(() {
        _dailyLoading = true;
        _dailyError = null;
      });
    }

    final deviceId = _deviceId;
    if (deviceId == null) {
      if (!mounted) return;
      setState(() {
        _daily = [];
        _dailyLoading = false;
        _dailyError = null;
      });
      return;
    }

    try {
      final res = await _supabase
          .rpc('device_daily_rolling', params: {'p_device': deviceId})
          .ilike('sensor', key)
          .order('day', ascending: false)
          .limit(_dailyKeep);

      final pts = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map(
            (r) => _DailyPt(
              DateTime.tryParse('${r['day']}'),
              _toNum(r['daily_mean']),
              _toNum(r['rolling_7d_mean']),
            ),
          )
          .toList()
          .reversed
          .toList(); // oldest → newest

      if (!mounted || key != _statKey) return; // sensor changed meanwhile
      setState(() {
        _daily = pts;
        _dailyLoading = false;
        _dailyError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dailyError = 'Could not load daily rolling data.';
        _dailyLoading = false;
      });
      debugPrint('Daily rolling fetch error: $e');
    }
  }

  Future<void> _fetchWeekly({bool showSpinner = true}) async {
    final key = _statKey;
    if (showSpinner) {
      setState(() {
        _weeklyLoading = true;
        _weeklyError = null;
      });
    }

    final deviceId = _deviceId;
    if (deviceId == null) {
      if (!mounted) return;
      setState(() {
        _weekly = [];
        _weeklyLoading = false;
        _weeklyError = null;
      });
      return;
    }

    try {
      final res = await _supabase
          .rpc('device_weekly_avg', params: {'p_device': deviceId})
          .ilike('sensor', key)
          .order('week_end', ascending: false)
          .limit(_weeklyKeep);


      final pts = <_WeeklyPt>[];
      for (final e in (res as List)) {
        final r = Map<String, dynamic>.from(e as Map);
        final mean = _toNum(r['weekly_mean']);
        if (mean == null) continue;
        pts.add(
          _WeeklyPt(
            DateTime.tryParse('${r['week_end']}'),
            mean,
            _toNum(r['n_readings'])?.toInt(),
          ),
        );
      }
      final ordered = pts.reversed.toList(); // oldest → newest

      if (!mounted || key != _statKey) return;
      setState(() {
        _weekly = ordered;
        _weeklyLoading = false;
        _weeklyError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _weeklyError = 'Could not load weekly average data.';
        _weeklyLoading = false;
      });
      debugPrint('Weekly avg fetch error: $e');
    }
  }

  void _selectSensor(String key) {
    if (key == _statKey) return;
    setState(() => _statKey = key);
    _fetchDaily();
    _fetchWeekly();
  }

  SensorDef get _selectedDef {
  final d = kSensors.firstWhere(
    (d) => d.key == _statKey,
    orElse: () => kSensors.first,
  );
  if (d.key != 'EC') return d;
  // The analytics functions return raw µS/cm, so show EC in µS/cm here.
  final lo = d.min * 1000;
  final hi = d.max * 1000;
  return SensorDef(
    key: d.key,
    label: d.label,
    unit: ' µS/cm',
    icon: d.icon,
    min: lo,
    max: hi,
    tolerance: d.tolerance * 1000,
    optimalText: '${lo.toStringAsFixed(0)} – ${hi.toStringAsFixed(0)} µS/cm',
    decimals: 0,
  );
}

  // ───────────────────────── SHARED UI ─────────────────────────

  Widget _card({
    required String title,
    required String subtitle,
    required Widget body,
    double height = 180,
    Widget? footer,
  }) {
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppText.cardTitle),
            const SizedBox(height: 2),
            Text(subtitle, style: AppText.subtitle),
            const SizedBox(height: 12),
            SizedBox(height: height, child: body),
            if (footer != null) ...[const SizedBox(height: 6), footer],
          ],
        ),
      ),
    );
  }

  Widget _errorBody(String message, VoidCallback onRetry) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(AppIcons.offline, size: 36, color: AppColors.textTertiary),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
          ),
          const SizedBox(height: 10),
          AppButton(label: 'Retry', icon: AppIcons.refresh, onPressed: onRetry),
        ],
      ),
    );
  }

  Widget _emptyBody(String message) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 3, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
        ),
        const SizedBox(width: 12),
      ],
    );
  }

  // Sensor picker shared by the daily rolling and weekly average cards.
  Widget _sensorChips() {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kSensors.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final def = kSensors[i];
          final selected = def.key == _statKey;
          return ChoiceChip(
            label: Text(
              def.label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
            ),
            selected: selected,
            selectedColor: AppColors.green,
            showCheckmark: false,
            onSelected: (_) => _selectSensor(def.key),
          );
        },
      ),
    );
  }

  String _axisFmt(double value, double range) {
    if (range >= 20) return value.toStringAsFixed(0);
    if (range >= 5) return value.toStringAsFixed(1);
    return value.toStringAsFixed(2);
  }

  String _dateLabel(DateTime? d, int index) =>
      d == null ? '${index + 1}' : '${d.month}/${d.day}';

  // ───────────────────────── COVERAGE BANNER ─────────────────────────

  Widget _buildCoverageBanner() {
    final hasDates = _covStart != null || _covEnd != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.darkGreen,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(AppIcons.timeline, size: 24, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Analytics Coverage',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasDates ? _fmtRange(_covStart, _covEnd) : '--No data yet--',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── CARD 1: Correlations ─────────────────────────

  Widget _buildCorrelationCard() {
    return _card(
      title: 'Sensor Correlations',
      subtitle: 'Strongest relationships between sensor readings',
      height: 200,
      body: _buildCorrelationChart(),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _legendDot(AppColors.healthy, 'Move together (+)'),
              _legendDot(AppColors.critical, 'Move opposite (−)'),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Top 6 pairs by strength. Values near ±1 mean a strong '
            'relationship; near 0 means little or none. Tap a bar for details.',
            style: AppText.caption,
          ),
        ],
      ),
    );  
  }

  Widget _buildCorrelationChart() {
    if (_edaLoading) return const Center(child: CircularProgressIndicator());
    if (_edaError != null) return _errorBody(_edaError!, _fetchEda);
    if (_topCorrelations.isEmpty) {
      return _emptyBody(
        'No correlation data yet for this crop.',
      );
    }

    final groups = <BarChartGroupData>[
      for (int i = 0; i < _topCorrelations.length; i++)
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: _topCorrelations[i].value,
              color: _topCorrelations[i].value >= 0
                  ? AppColors.healthy
                  : AppColors.critical,
              width: 22,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
    ];

    return BarChart(
      BarChartData(
        minY: -1,
        maxY: 1,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 0.5,
          getDrawingHorizontalLine: (value) => FlLine(
            color: value == 0 ? AppColors.textTertiary : AppColors.track,
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
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
              reservedSize: 32,
              interval: 0.5,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(1),
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
              reservedSize: 34,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= _topCorrelations.length) {
                  return const SizedBox.shrink();
                }
                final p = _topCorrelations[i];
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${_short(p.a)}\n${_short(p.b)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppColors.textSecondary,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (group) => AppColors.textPrimary,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final p = _topCorrelations[groupIndex];
              return BarTooltipItem(
                '${p.a} ↔ ${p.b}\n${p.value.toStringAsFixed(2)}',
                const TextStyle(color: Colors.white, fontSize: 12),
              );
            },
          ),
        ),
        barGroups: groups,
      ),
    );
  }

  // ───────────────────────── CARD 2: Target breakdown ─────────────────────────

  Widget _buildBreakdownCard() {
    final metrics = _breakdown.keys.toList();

    return SizedBox(
      width: double.infinity,
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Readings by Crop Health', style: AppText.cardTitle),
            const SizedBox(height: 2),
            const Text(
              'Average sensor value for each health status',
              style: AppText.subtitle,
            ),
            const SizedBox(height: 10),
            if (metrics.isNotEmpty)
              SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: metrics.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final m = metrics[i];
                    final selected = m == _selectedMetric;
                    return ChoiceChip(
                      label: Text(
                        m.replaceAll('_', ' '),
                        style: TextStyle(
                          fontSize: 12,
                          color: selected
                              ? Colors.white
                              : AppColors.textPrimary,
                        ),
                      ),
                      selected: selected,
                      selectedColor: AppColors.green,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _selectedMetric = m),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(height: 190, child: _buildBreakdownChart()),
            const SizedBox(height: 6),
            const Text(
              'Shows what each sensor typically reads when the crop is in each '
              'status, so you can see which readings go with healthy vs. '
              'stressed conditions.',
              style: AppText.caption,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreakdownChart() {
    if (_edaLoading) return const Center(child: CircularProgressIndicator());
    if (_edaError != null) return _errorBody(_edaError!, _fetchEda);

    final data = _selectedMetric == null ? null : _breakdown[_selectedMetric];
    if (data == null || data.isEmpty) {
      return _emptyBody(
        'No breakdown data yet for this crop',
      );
    }

    // Healthiest status first (Optimal → Warning → Critical).
    final labels = data.keys.toList()
      ..sort((a, b) {
        final sa = _scoreForCropHealth(a) ?? -1;
        final sb = _scoreForCropHealth(b) ?? -1;
        final c = sb.compareTo(sa);
        return c != 0 ? c : a.compareTo(b);
      });

    final maxVal = labels.map((l) => data[l]!).reduce((a, b) => a > b ? a : b);
    final maxY = maxVal <= 0 ? 1.0 : maxVal * 1.2;

    final groups = <BarChartGroupData>[
      for (int i = 0; i < labels.length; i++)
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: data[labels[i]]!,
              color: _colorForCropHealth(labels[i]),
              width: 28,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
    ];

    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (value) =>
              const FlLine(color: AppColors.track, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
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
              reservedSize: 40,
              interval: maxY / 4,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(value.abs() >= 100 ? 0 : 1),
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
              reservedSize: 34,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= labels.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    labels[i].replaceFirst(' ', '\n'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppColors.textSecondary,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (group) => AppColors.textPrimary,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${labels[groupIndex]}\n${rod.toY.toStringAsFixed(2)}',
                const TextStyle(color: Colors.white, fontSize: 12),
              );
            },
          ),
        ),
        barGroups: groups,
      ),
    );
  }

  // ───────────────────────── CARD 3: Daily rolling average ─────────────────────────

  Widget _buildDailyCard() {
    final def = _selectedDef;
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Daily Rolling Average', style: AppText.cardTitle),
            const SizedBox(height: 2),
            Text(
              _daily.isEmpty
                  ? def.label
                  : '${def.label} · ${_fmtRange(_daily.first.day, _daily.last.day)}',
              style: AppText.subtitle,
            ),
            const SizedBox(height: 10),
            _sensorChips(),
            const SizedBox(height: 12),
            SizedBox(height: 200, child: _buildDailyChart(def)),
            const SizedBox(height: 6),
            Wrap(
              children: [
                _legendDot(AppColors.healthy, '7-day rolling mean'),
                _legendDot(AppColors.info, 'Daily mean'),
                _legendDot(
                  AppColors.optimal.withOpacity(0.35),
                  'Optimal: ${def.optimalText}',
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              'The rolling mean smooths out day-to-day noise so you can see '
              'whether a sensor is drifting. The green band appears only '
              'when the optimal range overlaps the data.',
              style: AppText.caption,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyChart(SensorDef def) {
    if (_dailyLoading) return const Center(child: CircularProgressIndicator());
    if (_dailyError != null) return _errorBody(_dailyError!, _fetchDaily);

    final pts = _daily;
    final all = <double>[
      for (final p in pts) ...[
        if (p.daily != null) p.daily!,
        if (p.rolling != null) p.rolling!,
      ],
    ];
    if (pts.length < 2 || all.isEmpty) {
      return _emptyBody(
        'No ${def.label} data yet for this crop',
      );
    }

    double lo = all.reduce((a, b) => a < b ? a : b);
    double hi = all.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 1e-9) {
      hi += 1;
      lo -= 1;
    }
    final pad = (hi - lo) * 0.1;
    final minY = lo - pad;
    final maxY = hi + pad;
    final range = maxY - minY;
    final xInterval = (pts.length / 5).ceilToDouble().clamp(1.0, 1000.0);
    final showBand = def.max >= minY && def.min <= maxY;

    List<FlSpot> spots(double? Function(_DailyPt) pick) => [
      for (int i = 0; i < pts.length; i++)
        if (pick(pts[i]) != null) FlSpot(i.toDouble(), pick(pts[i])!),
    ];

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        minX: 0,
        maxX: (pts.length - 1).toDouble(),
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: range / 4,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.track, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        rangeAnnotations: RangeAnnotations(
          horizontalRangeAnnotations: showBand
              ? [
                  HorizontalRangeAnnotation(
                    y1: def.min < minY ? minY : def.min,
                    y2: def.max > maxY ? maxY : def.max,
                    color: AppColors.optimal.withOpacity(0.15),
                  ),
                ]
              : const [],
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
              reservedSize: 40,
              interval: range / 4,
              getTitlesWidget: (value, meta) => Text(
                _axisFmt(value, range),
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
              interval: xInterval,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (value != i.toDouble() || i < 0 || i >= pts.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _dateLabel(pts[i].day, i),
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppColors.textSecondary,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.textPrimary,
            getTooltipItems: (touched) {
              if (touched.isEmpty) return [];
              final i = touched.first.x.toInt().clamp(0, pts.length - 1);
              final p = pts[i];
              String f(double? v) =>
                  v == null ? '--' : v.toStringAsFixed(def.decimals);
              return [
                LineTooltipItem(
                  '${_dateLabel(p.day, i)}\n'
                  'Rolling: ${f(p.rolling)}${def.unit}\n'
                  'Daily: ${f(p.daily)}${def.unit}',
                  const TextStyle(color: Colors.white, fontSize: 12),
                ),
                // Other touched bars get an empty tooltip so only one shows.
                for (int k = 1; k < touched.length; k++)
                  const LineTooltipItem('', TextStyle(fontSize: 0)),
              ];
            },
          ),
        ),
        lineBarsData: [
          // Daily mean (thin, behind)
          LineChartBarData(
            spots: spots((p) => p.daily),
            isCurved: false,
            color: AppColors.info.withOpacity(0.7),
            barWidth: 1.5,
            dotData: const FlDotData(show: true),
          ),
          // 7-day rolling mean (main line)
          LineChartBarData(
            spots: spots((p) => p.rolling),
            isCurved: true,
            preventCurveOverShooting: true,
            color: AppColors.healthy,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.healthy.withOpacity(0.10),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── CARD 4: Weekly average ─────────────────────────

  Widget _buildWeeklyCard() {
    final def = _selectedDef;
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Weekly Average', style: AppText.cardTitle),
            const SizedBox(height: 2),
            Text(
              _weekly.isEmpty
                  ? def.label
                  : '${def.label} · weeks ending '
                        '${_fmtRange(_weekly.first.weekEnd, _weekly.last.weekEnd)}',
              style: AppText.subtitle,
            ),
            const SizedBox(height: 10),
            _sensorChips(),
            const SizedBox(height: 12),
            SizedBox(height: 200, child: _buildWeeklyChart(def)),
            const SizedBox(height: 6),
            const Text(
              'Each bar is one week\'s average, labelled by the week-end '
              'date. Tap a bar to see how many readings it is based on. '
              'Recent weeks may be partial.',
              style: AppText.caption,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyChart(SensorDef def) {
    if (_weeklyLoading) return const Center(child: CircularProgressIndicator());
    if (_weeklyError != null) return _errorBody(_weeklyError!, _fetchWeekly);

    final pts = _weekly;
    if (pts.isEmpty) {
      return _emptyBody(
        'No ${def.label} data yet for this crop.',
      );
    }

    final maxVal = pts.map((p) => p.mean).reduce((a, b) => a > b ? a : b);
    final maxY = maxVal <= 0 ? 1.0 : maxVal * 1.2;

    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.track, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
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
              reservedSize: 40,
              interval: maxY / 4,
              getTitlesWidget: (value, meta) => Text(
                _axisFmt(value, maxY),
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
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= pts.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _dateLabel(pts[i].weekEnd, i),
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppColors.textSecondary,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.textPrimary,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final p = pts[groupIndex];
              return BarTooltipItem(
                'Week ending ${_dateLabel(p.weekEnd, groupIndex)}\n'
                '${p.mean.toStringAsFixed(def.decimals)}${def.unit}\n'
                '${p.n ?? '--'} readings',
                const TextStyle(color: Colors.white, fontSize: 12),
              );
            },
          ),
        ),
        barGroups: [
          for (int i = 0; i < pts.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: pts[i].mean,
                  width: pts.length > 8 ? 16 : 22,
                  borderRadius: BorderRadius.circular(4),
                  color: AppColors.healthy,
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ───────────────────────── PAGE ─────────────────────────

  Future<void> _refreshAll() => Future.wait([
    _fetchEda(showSpinner: false),
    _fetchCoverage(),
    _fetchDaily(showSpinner: false),
    _fetchWeekly(showSpinner: false),
  ]);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AppHeader(title: 'AI Analytics'),

        // Scrollable body (pull down to refresh)
        Expanded(
          child: RefreshIndicator(
            color: AppColors.green,
            onRefresh: _refreshAll,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpace.page),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCoverageBanner(),
                  const SizedBox(height: AppSpace.cardGap),
                  _buildDailyCard(),
                  const SizedBox(height: AppSpace.cardGap),
                  _buildWeeklyCard(),
                  const SizedBox(height: AppSpace.cardGap),
                  _buildBreakdownCard(),
                  const SizedBox(height: AppSpace.cardGap),
                  _buildCorrelationCard(),
                  const SizedBox(height: AppSpace.cardGap),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
