import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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

const _axisStyle = TextStyle(fontSize: 10, color: AppColors.textSecondary);
const _mutedStyle = TextStyle(color: AppColors.textTertiary, fontSize: 13);
const _tooltipStyle = TextStyle(color: Colors.white, fontSize: 12);
const _noTitles = AxisTitles(sideTitles: SideTitles(showTitles: false));
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
];

String _short(String name) => _shortNames[name.toLowerCase()] ?? name;

double? _toNum(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');

String _md(DateTime d, [bool year = false]) =>
    '${_months[d.month - 1]} ${d.day}${year ? ', ${d.year}' : ''}';

// "May 5 – 20, 2026", "May 5 – Jul 3, 2026" or "Dec 28, 2025 – Jan 3, 2026".
String _fmtRange(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 'no dates';
  if (a == null || b == null) return _md((a ?? b)!, true);
  if (a.year != b.year) return '${_md(a, true)} – ${_md(b, true)}';
  if (a.month != b.month) return '${_md(a)} – ${_md(b, true)}';
  return a.day == b.day ? _md(a, true) : '${_md(a)} – ${b.day}, ${a.year}';
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
  return s >= 50 ? AppColors.caution : AppColors.critical;
}

String _axisFmt(double value, double range) =>
    value.toStringAsFixed(range >= 20 ? 0 : (range >= 5 ? 1 : 2));

String _dateLabel(DateTime? d, int index) =>
    d == null ? '${index + 1}' : '${d.month}/${d.day}';

// ── Shared chart pieces ──

FlGridData _grid(double interval, {bool zeroLine = false}) => FlGridData(
  show: true,
  drawVerticalLine: false,
  horizontalInterval: interval,
  getDrawingHorizontalLine: (v) => FlLine(
    color: zeroLine && v == 0 ? AppColors.textTertiary : AppColors.track,
    strokeWidth: 1,
  ),
);

Widget _tick(String text) => Text(
  text,
  textAlign: TextAlign.center,
  style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
);

FlTitlesData _titles({
  required double leftSize,
  required double interval,
  required String Function(double) leftLabel,
  required double bottomSize,
  required Widget? Function(int) bottom,
  double? bottomInterval,
}) => FlTitlesData(
  topTitles: _noTitles,
  rightTitles: _noTitles,
  leftTitles: AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      reservedSize: leftSize,
      interval: interval,
      getTitlesWidget: (v, _) => Text(leftLabel(v), style: _axisStyle),
    ),
  ),
  bottomTitles: AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      reservedSize: bottomSize,
      interval: bottomInterval,
      getTitlesWidget: (v, _) {
        final w = v == v.roundToDouble() ? bottom(v.toInt()) : null;
        return w == null
            ? const SizedBox.shrink()
            : Padding(padding: const EdgeInsets.only(top: 6), child: w);
      },
    ),
  ),
);

Widget _barChart({
  double minY = 0,
  required double maxY,
  required double interval,
  required List<double> values,
  required List<Color> colors,
  required double barWidth,
  required double leftSize,
  required String Function(double) leftLabel,
  required double bottomSize,
  required Widget? Function(int) bottom,
  required String Function(int) tip,
  bool zeroLine = false,
}) => BarChart(
  BarChartData(
    minY: minY,
    maxY: maxY,
    alignment: BarChartAlignment.spaceAround,
    gridData: _grid(interval, zeroLine: zeroLine),
    borderData: FlBorderData(show: false),
    titlesData: _titles(
      leftSize: leftSize,
      interval: interval,
      leftLabel: leftLabel,
      bottomSize: bottomSize,
      bottom: (i) => i < 0 || i >= values.length ? null : bottom(i),
    ),
    barTouchData: BarTouchData(
      touchTooltipData: BarTouchTooltipData(
        getTooltipColor: (_) => AppColors.textPrimary,
        getTooltipItem: (g, gi, rod, ri) =>
            BarTooltipItem(tip(gi), _tooltipStyle),
      ),
    ),
    barGroups: [
      for (int i = 0; i < values.length; i++)
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: values[i],
              color: colors[i],
              width: barWidth,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
    ],
  ),
);

class _CorrPair {
  final String a, b;
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

/// Loading / error / data triple for one fetched series.
class _Series<T> {
  bool loading = true;
  String? error;
  List<T> data = [];
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
  List<_CorrPair> _allCorrelations = []; // every unique pair, strongest first
  Map<String, Map<String, double>> _breakdown = {}; // metric -> health -> avg

  // ── Daily rolling / weekly average state ──
  final _daily = _Series<_DailyPt>();
  final _weekly = _Series<_WeeklyPt>();
  String _statKey = 'moisture'; // sensor driving every analytics card

  // Sensor chip row scrolling + minimap position (start, size as 0..1).
  final _chipScroll = ScrollController();
  final _chipKeys = List.generate(kSensors.length, (_) => GlobalKey());
  final _mini = ValueNotifier<(double, double)>((0.0, 1.0));

  // Page scroll: drives the "back to top" button.
  final _pageScroll = ScrollController();
  bool _showTop = false;
  // How close (in pixels) to the bottom before the button appears.
  static const double _showTopWithin = 400;

  // Overall period covered by the data (earliest / latest reading).
  DateTime? _covStart, _covEnd;

  @override
  void initState() {
    super.initState();
    _pageScroll.addListener(_onPageScroll);
    CropService.instance.addListener(_onCropChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onCropChanged());
  }

  @override
  void dispose() {
    CropService.instance.removeListener(_onCropChanged);
    _pageScroll.dispose();
    _chipScroll.dispose();
    _mini.dispose();
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

  Future<void> _refreshAll() => Future.wait([
    _fetchEda(showSpinner: false),
    _fetchCoverage(),
    _fetchDaily(showSpinner: false),
    _fetchWeekly(showSpinner: false),
  ]);

  String? get _deviceId => CropService.instance.selected?.deviceId;

  // ───────────────────────── DATA ─────────────────────────

  Future<void> _fetchEda({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _edaLoading = true;
        _edaError = null;
      });
    }
    final id = _deviceId;
    try {
      final pairs = <_CorrPair>[];
      final grouped = <String, Map<String, double>>{};
      if (id != null) {
        final corr = await _supabase.rpc(
          'device_correlations',
          params: {'p_device': id},
        );
        final breakdown = await _supabase.rpc(
          'device_target_breakdown',
          params: {'p_device': id},
        );

        // Drop self-pairs and mirrored duplicates; the card filters by sensor.
        final seen = <String>{};
        for (final row in List<Map<String, dynamic>>.from(corr as List)) {
          final a = '${row['col_a']}', b = '${row['col_b']}';
          final v = _toNum(row['correlation']);
          if (v == null || a == b || !seen.add(([a, b]..sort()).join('|'))) {
            continue;
          }
          pairs.add(_CorrPair(a, b, v));
        }
        pairs.sort((x, y) => y.value.abs().compareTo(x.value.abs()));

        for (final row in List<Map<String, dynamic>>.from(breakdown as List)) {
          final v = _toNum(row['avg_value']);
          if (v == null) continue;
          final byHealth = grouped.putIfAbsent('${row['metric']}', () => {});
          byHealth['${row['crop_health']}'] = v;
        }
      }
      if (!mounted) return;
      setState(() {
        _allCorrelations = pairs;
        _breakdown = grouped;
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

  // Earliest and latest reading for this device (the overall coverage).
  Future<void> _fetchCoverage() async {
    final id = _deviceId;
    try {
      Future<DateTime?> edge(bool asc) async {
        final r = await _supabase
            .from('sensor_readings')
            .select('timestamp')
            .eq('device_id', id!)
            .order('timestamp', ascending: asc)
            .limit(1);
        return r.isEmpty
            ? null
            : DateTime.tryParse('${r.first['timestamp']}')?.toUtc();
      }

      final start = id == null ? null : await edge(true);
      final end = id == null ? null : await edge(false);
      if (!mounted) return;
      setState(() {
        _covStart = start;
        _covEnd = end;
      });
    } catch (e) {
      debugPrint('Coverage fetch error: $e');
    }
  }

  /// Fetches the newest [keep] rows of [rpc] for the selected sensor into [s]
  /// (oldest → newest).
  Future<void> _fetchSeries<T extends Object>(
    _Series<T> s,
    String rpc,
    String orderCol,
    int keep,
    T? Function(Map<String, dynamic>) parse,
    String errMsg,
    bool showSpinner,
  ) async {
    final key = _statKey;
    if (showSpinner) {
      setState(() {
        s.loading = true;
        s.error = null;
      });
    }
    final id = _deviceId;
    try {
      var rows = <T>[];
      if (id != null) {
        final res = await _supabase
            .rpc(rpc, params: {'p_device': id})
            .ilike('sensor', key)
            .order(orderCol, ascending: false)
            .limit(keep);
        rows = (res as List)
            .map((e) => parse(Map<String, dynamic>.from(e as Map)))
            .nonNulls
            .toList()
            .reversed
            .toList();
      }
      if (!mounted || key != _statKey) return; // sensor changed meanwhile
      setState(() {
        s.data = rows;
        s.loading = false;
        s.error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        s.error = errMsg;
        s.loading = false;
      });
      debugPrint('$rpc fetch error: $e');
    }
  }

  Future<void> _fetchDaily({bool showSpinner = true}) => _fetchSeries(
    _daily,
    'device_daily_rolling',
    'day',
    _dailyKeep,
    (r) => _DailyPt(
      DateTime.tryParse('${r['day']}'),
      _toNum(r['daily_mean']),
      _toNum(r['rolling_7d_mean']),
    ),
    'Could not load daily rolling data.',
    showSpinner,
  );

  Future<void> _fetchWeekly({bool showSpinner = true}) => _fetchSeries(
    _weekly,
    'device_weekly_avg',
    'week_end',
    _weeklyKeep,
    (r) {
      final mean = _toNum(r['weekly_mean']);
      return mean == null
          ? null
          : _WeeklyPt(
              DateTime.tryParse('${r['week_end']}'),
              mean,
              _toNum(r['n_readings'])?.toInt(),
            );
    },
    'Could not load weekly average data.',
    showSpinner,
  );

  // Changing the sensor re-drives every card: daily + weekly refetch, while
  // correlations and the health breakdown are filtered from loaded data.
  void _selectSensor(String key) {
    if (key == _statKey) return;
    setState(() => _statKey = key);
    _fetchDaily();
    _fetchWeekly();
  }

  bool _isSelected(String name) => name.toLowerCase() == _statKey.toLowerCase();

  // All correlation pairs that involve the selected sensor, strongest first.
  List<_CorrPair> get _sensorCorrelations => [
    for (final p in _allCorrelations)
      if (_isSelected(p.a) || _isSelected(p.b)) p,
  ];

  // Health-breakdown data for the selected sensor (case-insensitive match).
  Map<String, double>? get _sensorBreakdown {
    for (final e in _breakdown.entries) {
      if (_isSelected(e.key)) return e.value;
    }
    return null;
  }

  SensorDef get _selectedDef {
    final d = kSensors.firstWhere(
      (d) => d.key == _statKey,
      orElse: () => kSensors.first,
    );
    if (d.key != 'EC') return d;
    // The analytics functions return raw µS/cm, so show EC in µS/cm here.
    final lo = d.min * 1000, hi = d.max * 1000;
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
    double height = 200,
    List<Widget> footer = const [],
    String? caption,
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
            const SizedBox(height: 6),
            ...footer,
            if (caption != null) Text(caption, style: AppText.caption),
          ],
        ),
      ),
    );
  }

  Widget _emptyBody(String message) => Center(
    child: Text(message, textAlign: TextAlign.center, style: _mutedStyle),
  );

  Widget _errorBody(String message, VoidCallback onRetry) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(AppIcons.offline, size: 36, color: AppColors.textTertiary),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center, style: _mutedStyle),
        const SizedBox(height: 10),
        AppButton(label: 'Retry', icon: AppIcons.refresh, onPressed: onRetry),
      ],
    ),
  );

  // Spinner or error body while a chart isn't ready; null when it is.
  Widget? _notReady(bool loading, String? error, VoidCallback retry) => loading
      ? const Center(child: CircularProgressIndicator())
      : error != null
      ? _errorBody(error, retry)
      : null;

  Widget _legendDot(Color color, String label) => Row(
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

  // ───────────────────────── COVERAGE BANNER ─────────────────────────

  Widget _buildCoverageBanner() {
    final hasDates = _covStart != null || _covEnd != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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

  // ───────────────────────── SENSOR SELECTOR ─────────────────────────

  // Keeps the minimap thumb in sync with the chip row.
  bool _onChipScroll(Notification n) {
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

  // Slim track + thumb under the chips. Tap or drag it to move through chips.
  Widget _buildChipMinimap() {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        void jump(double dx) {
          if (!_chipScroll.hasClients) return;
          final thumbW = w * _mini.value.$2;
          final frac = w <= thumbW
              ? 0.0
              : ((dx - thumbW / 2) / (w - thumbW)).clamp(0.0, 1.0);
          _chipScroll.jumpTo(frac * _chipScroll.position.maxScrollExtent);
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

  // One sensor picker for the whole page: scrolling filter chips plus a
  // minimap slider. Tapping a chip centres it; the minimap follows.
  Widget _buildSensorSelector() {
    return Column(
      children: [
        SizedBox(
          height: 40,
          child: NotificationListener<Notification>(
            onNotification: _onChipScroll,
            child: ListView.separated(
              controller: _chipScroll,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: kSensors.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final d = kSensors[i];
                final selected = d.key == _statKey;
                return FilterChip(
                  key: _chipKeys[i],
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
                    _selectSensor(d.key);
                    final ctx = _chipKeys[i].currentContext;
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
        _buildChipMinimap(),
      ],
    );
  }

  // ───────────────────────── CARD: Weekly average ─────────────────────────

  Widget _buildWeeklyCard() {
    final def = _selectedDef;
    final pts = _weekly.data;
    return _card(
      title: 'Weekly Average',
      subtitle: pts.isEmpty
          ? def.label
          : '${def.label} · weeks ending '
                '${_fmtRange(pts.first.weekEnd, pts.last.weekEnd)}',
      body: _buildWeeklyChart(def),
      caption:
          'Each bar is one week\'s average, labelled by the week-end date. '
          'Tap a bar to see how many readings it is based on. '
          'Recent weeks may be partial.',
    );
  }

  Widget _buildWeeklyChart(SensorDef def) {
    if (_notReady(_weekly.loading, _weekly.error, _fetchWeekly) case final w?) {
      return w;
    }
    final pts = _weekly.data;
    if (pts.isEmpty) {
      return _emptyBody('No ${def.label} data yet for this crop.');
    }

    final maxVal = pts.map((p) => p.mean).reduce((a, b) => a > b ? a : b);
    final maxY = maxVal <= 0 ? 1.0 : maxVal * 1.2;
    return _barChart(
      maxY: maxY,
      interval: maxY / 4,
      values: [for (final p in pts) p.mean],
      colors: List.filled(pts.length, AppColors.healthy),
      barWidth: pts.length > 8 ? 16 : 22,
      leftSize: 40,
      leftLabel: (v) => _axisFmt(v, maxY),
      bottomSize: 24,
      bottom: (i) => _tick(_dateLabel(pts[i].weekEnd, i)),
      tip: (i) =>
          'Week ending ${_dateLabel(pts[i].weekEnd, i)}\n'
          '${pts[i].mean.toStringAsFixed(def.decimals)}${def.unit}\n'
          '${pts[i].n ?? '--'} readings',
    );
  }

  // ───────────────────────── CARD: Target breakdown ─────────────────────────

  Widget _buildBreakdownCard() => _card(
    title: 'Readings by Crop Health',
    subtitle: '${_selectedDef.label} · average value for each health status',
    height: 190,
    body: _buildBreakdownChart(),
    caption:
        'Shows what each sensor typically reads when the crop is in each '
        'status, so you can see which readings go with healthy vs. '
        'stressed conditions.',
  );

  Widget _buildBreakdownChart() {
    if (_notReady(_edaLoading, _edaError, _fetchEda) case final w?) return w;
    final data = _sensorBreakdown;
    if (data == null || data.isEmpty) {
      return _emptyBody(
        'No ${_selectedDef.label} breakdown data yet for this crop',
      );
    }

    // Healthiest status first (Optimal → Warning → Critical).
    final labels = data.keys.toList()
      ..sort((a, b) {
        final c = (_scoreForCropHealth(b) ?? -1).compareTo(
          _scoreForCropHealth(a) ?? -1,
        );
        return c != 0 ? c : a.compareTo(b);
      });
    final maxVal = labels.map((l) => data[l]!).reduce((a, b) => a > b ? a : b);
    final maxY = maxVal <= 0 ? 1.0 : maxVal * 1.2;

    return _barChart(
      maxY: maxY,
      interval: maxY / 4,
      values: [for (final l in labels) data[l]!],
      colors: [for (final l in labels) _colorForCropHealth(l)],
      barWidth: 28,
      leftSize: 40,
      leftLabel: (v) => v.toStringAsFixed(v.abs() >= 100 ? 0 : 1),
      bottomSize: 34,
      bottom: (i) => _tick(labels[i].replaceFirst(' ', '\n')),
      tip: (i) => '${labels[i]}\n${data[labels[i]]!.toStringAsFixed(2)}',
    );
  }

  // ───────────────────────── CARD: Correlations ─────────────────────────

  Widget _buildCorrelationCard() => _card(
    title: 'Sensor Correlations',
    subtitle: '${_selectedDef.label} compared with the other sensors',
    body: _buildCorrelationChart(),
    footer: [
      Row(
        children: [
          _legendDot(AppColors.healthy, 'Move together (+)'),
          _legendDot(AppColors.critical, 'Move opposite (−)'),
        ],
      ),
      const SizedBox(height: 4),
    ],
    caption:
        'Every pair involving this sensor, strongest first. Values near ±1 '
        'mean a strong relationship; near 0 means little or none. '
        'Tap a bar for details.',
  );

  Widget _buildCorrelationChart() {
    if (_notReady(_edaLoading, _edaError, _fetchEda) case final w?) return w;
    final corr = _sensorCorrelations;
    if (corr.isEmpty) {
      return _emptyBody(
        'No correlation data yet for ${_selectedDef.label} on this crop.',
      );
    }
    return _barChart(
      minY: -1,
      maxY: 1,
      interval: 0.5,
      zeroLine: true,
      values: [for (final p in corr) p.value],
      colors: [
        for (final p in corr)
          p.value >= 0 ? AppColors.healthy : AppColors.critical,
      ],
      barWidth: 22,
      leftSize: 32,
      leftLabel: (v) => v.toStringAsFixed(1),
      bottomSize: 34,
      bottom: (i) => _tick('${_short(corr[i].a)}\n${_short(corr[i].b)}'),
      tip: (i) =>
          '${corr[i].a} ↔ ${corr[i].b}\n${corr[i].value.toStringAsFixed(2)}',
    );
  }

  // ───────────────────── CARD: Daily rolling average ─────────────────────

  Widget _buildDailyCard() {
    final def = _selectedDef;
    final pts = _daily.data;
    return _card(
      title: 'Daily Rolling Average',
      subtitle: pts.isEmpty
          ? def.label
          : '${def.label} · ${_fmtRange(pts.first.day, pts.last.day)}',
      body: _buildDailyChart(def),
      footer: [
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
      ],
      caption:
          'The rolling mean smooths out day-to-day noise so you can see '
          'whether a sensor is drifting. The green band appears only '
          'when the optimal range overlaps the data.',
    );
  }

  Widget _buildDailyChart(SensorDef def) {
    if (_notReady(_daily.loading, _daily.error, _fetchDaily) case final w?) {
      return w;
    }
    final pts = _daily.data;
    final all = <double>[
      for (final p in pts) ...[
        if (p.daily != null) p.daily!,
        if (p.rolling != null) p.rolling!,
      ],
    ];
    if (pts.length < 2 || all.isEmpty) {
      return _emptyBody('No ${def.label} data yet for this crop');
    }

    var lo = all.reduce((a, b) => a < b ? a : b);
    var hi = all.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 1e-9) {
      hi += 1;
      lo -= 1;
    }
    final pad = (hi - lo) * 0.1;
    final minY = lo - pad, maxY = hi + pad;
    final range = maxY - minY;
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
        gridData: _grid(range / 4),
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
        titlesData: _titles(
          leftSize: 40,
          interval: range / 4,
          leftLabel: (v) => _axisFmt(v, range),
          bottomSize: 24,
          bottomInterval: (pts.length / 5).ceilToDouble().clamp(1.0, 1000.0),
          bottom: (i) => i < 0 || i >= pts.length
              ? null
              : _tick(_dateLabel(pts[i].day, i)),
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
                  _tooltipStyle,
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

  // ───────────────────────── BACK TO TOP ─────────────────────────

  // Show the button only when the user is near the bottom of the page.
  void _onPageScroll() {
    if (!_pageScroll.hasClients) return;
    final p = _pageScroll.position;
    final near =
        p.maxScrollExtent > 0 && p.pixels >= p.maxScrollExtent - _showTopWithin;
    if (near != _showTop) setState(() => _showTop = near);
  }

  void _scrollToTop() {
    if (!_pageScroll.hasClients) return;
    _pageScroll.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildBackToTop() {
    return Positioned(
      right: AppSpace.page,
      bottom: AppSpace.page,
      child: IgnorePointer(
        ignoring: !_showTop,
        child: AnimatedSlide(
          offset: _showTop ? Offset.zero : const Offset(0, 0.6),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: _showTop ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            child: GestureDetector(
              onTap: _scrollToTop,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.green,
                  shape: BoxShape.circle,
                  boxShadow: AppShadows.card,
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(AppIcons.up, size: 16, color: AppColors.onGreen),
                    Text(
                      'top',
                      style: TextStyle(
                        fontSize: 9,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────── PAGE ─────────────────────────

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: AppSpace.cardGap);
    return Column(
      children: [
        const AppHeader(title: 'AI Analytics'),
        // Scrollable body (pull down to refresh) with the floating
        // back-to-top button drawn above it.
        Expanded(
          child: Stack(
            children: [
              RefreshIndicator(
                color: AppColors.green,
                onRefresh: _refreshAll,
                child: SingleChildScrollView(
                  controller: _pageScroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(AppSpace.page),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCoverageBanner(),
                      gap,
                      _buildSensorSelector(),
                      gap,
                      _buildWeeklyCard(),
                      gap,
                      _buildBreakdownCard(),
                      gap,
                      _buildCorrelationCard(),
                      gap,
                      _buildDailyCard(), // Daily Rolling Average is the last graph
                      gap,
                    ],
                  ),
                ),
              ),
              _buildBackToTop(),
            ],
          ),
        ),
      ],
    );
  }
}