import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/widgets/app_header.dart';
import 'package:flutter_application_harbest_1/widgets/app_button.dart';
import 'package:flutter_application_harbest_1/widgets/app_card.dart';


// ── SCHEMA ──
// eda_correlations     : col_a (text), col_b (text), correlation (float8)
// eda_target_breakdown : crop_health (text), metric (text), avg_value (float8)

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

class AiAnalytics extends StatefulWidget {
  const AiAnalytics({super.key});

  @override
  State<AiAnalytics> createState() =>
      _AiAnalyticsState();
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

  @override
  void initState() {
    super.initState();
    _fetchEda();
  }

  // ───────────────────────── DATA: EDA tables ─────────────────────────

  Future<void> _fetchEda({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _edaLoading = true;
        _edaError = null;
      });
    }

    try {
      final corrRes = await _supabase
          .from('eda_correlations')
          .select('col_a, col_b, correlation');
      final breakdownRes = await _supabase
          .from('eda_target_breakdown')
          .select('crop_health, metric, avg_value');

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
      for (final row
          in List<Map<String, dynamic>>.from(breakdownRes as List)) {
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
            if (footer != null) ...[
              const SizedBox(height: 6),
              footer,
            ],
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
            style: const TextStyle(
                color: AppColors.textTertiary, fontSize: 13),
          ),
          const SizedBox(height: 10),
          AppButton(
            label: 'Retry',
            icon: AppIcons.refresh,
            onPressed: onRetry,
          ),
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
        Text(label,
            style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        const SizedBox(width: 12),
      ],
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
          Row(children: [
            _legendDot(AppColors.healthy, 'Move together (+)'),
            _legendDot(AppColors.critical, 'Move opposite (−)'),
          ]),
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
          'No correlation data found.\nIf the table has rows, check that a '
          'SELECT policy (RLS) exists for eda_correlations.');
    }

    final groups = <BarChartGroupData>[
      for (int i = 0; i < _topCorrelations.length; i++)
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: _topCorrelations[i].value,
              color: _topCorrelations[i].value >= 0 ? AppColors.healthy : AppColors.critical,
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
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: 0.5,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(1),
                style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
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
                    style:
                        const TextStyle(fontSize: 9, color: AppColors.textSecondary),
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
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final m = metrics[i];
                  final selected = m == _selectedMetric;
                  return ChoiceChip(
                    label: Text(
                      m.replaceAll('_', ' '),
                      style: TextStyle(
                        fontSize: 12,
                        color: selected ? Colors.white : AppColors.textPrimary,
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
          'No breakdown data found.\nIf the table has rows, check that a '
          'SELECT policy (RLS) exists for eda_target_breakdown.');
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
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: maxY / 4,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(value.abs() >= 100 ? 0 : 1),
                style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
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
                    style:
                        const TextStyle(fontSize: 9, color: AppColors.textSecondary),
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

  // ───────────────────────── PAGE ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AppHeader(title: 'AI Analytics'),

        // Scrollable body (pull down to refresh)
        Expanded(
          child: RefreshIndicator(
            color: AppColors.green,
            onRefresh: () => _fetchEda(showSpinner: false),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpace.page),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCorrelationCard(),
                  const SizedBox(height: AppSpace.cardGap),
                  _buildBreakdownCard(),
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