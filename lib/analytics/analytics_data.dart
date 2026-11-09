import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_application_harbest_1/theme/app_style.dart';

import 'package:flutter_application_harbest_1/services/crop_services.dart';

import 'package:flutter_application_harbest_1/widgets/app_button.dart';
import 'package:flutter_application_harbest_1/widgets/app_card.dart';
import 'package:flutter_application_harbest_1/widgets/app_header.dart';
import 'package:flutter_application_harbest_1/widgets/app_snackbar.dart';
import 'package:flutter_application_harbest_1/widgets/sensor_chip_selector.dart';

import 'package:flutter_application_harbest_1/pages/user_dashboard.dart'
    show SensorDef, kSensors;

// ── SCHEMA ──
// eda_correlations     : col_a (text), col_b (text), correlation (float8)
// eda_target_breakdown : crop_health (text), metric (text), avg_value (float8)
// sensor_daily_rolling : day, sensor, daily_mean, rolling_7d_mean
// sensor_weekly_avg    : week_end, sensor, weekly_mean, n_readings

// ═════════════════════════════════════════════════════════════════════════
// 1. CONSTANTS & STYLES
// ═════════════════════════════════════════════════════════════════════════

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

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
];

const _axisStyle = TextStyle(fontSize: 10, color: AppColors.textSecondary);
const _mutedStyle = TextStyle(color: AppColors.textTertiary, fontSize: 13);
const _tooltipStyle = TextStyle(color: Colors.white, fontSize: 12);
const _noTitles = AxisTitles(sideTitles: SideTitles(showTitles: false));

// ═════════════════════════════════════════════════════════════════════════
// 2. HELPERS — parsing, formatting, crop-health scoring
// ═════════════════════════════════════════════════════════════════════════

double? _toNum(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');

String _short(String name) => _shortNames[name.toLowerCase()] ?? name;

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

String _dateLabel(DateTime? d, int index) =>
    d == null ? '${index + 1}' : '${d.month}/${d.day}';

String _axisFmt(double value, double range) =>
    value.toStringAsFixed(range >= 20 ? 0 : (range >= 5 ? 1 : 2));

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

// Color for a score from [_scoreForCropHealth].
Color _colorForHealthScore(double? s) {
  if (s == null) return AppColors.textTertiary;
  if (s >= 90) return AppColors.healthy;
  return s >= 50 ? AppColors.caution : AppColors.critical;
}

// ═════════════════════════════════════════════════════════════════════════
// 3. SHARED CHART PIECES
// ═════════════════════════════════════════════════════════════════════════

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

// ═════════════════════════════════════════════════════════════════════════
// 4. DATA MODELS
// ═════════════════════════════════════════════════════════════════════════

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

// ═════════════════════════════════════════════════════════════════════════
// 5. ANALYTICS PAGE
// ═════════════════════════════════════════════════════════════════════════

class AiAnalytics extends StatefulWidget {
  const AiAnalytics({super.key});

  @override
  State<AiAnalytics> createState() => _AiAnalyticsState();
}

class _AiAnalyticsState extends State<AiAnalytics>
    with OfflineNotice<AiAnalytics> {
  // ─────────────────────────── CONSTANTS ───────────────────────────

  // How close (in pixels) to the bottom before "back to top" appears.
  static const double _showTopWithin = 400;

  // ─────────────────────────── SERVICES ───────────────────────────

  final _supabase = Supabase.instance.client;

  String? get _deviceId => CropService.instance.selected?.deviceId;

  // ─────────────────────────── STATE ───────────────────────────

  // Device whose charts are on screen; a crop-list update for the same
  // device keeps them instead of reloading everything with spinners.
  String? _loadedDevice;
  String? _loadedCrop;
  bool _started = false;

  // Overall period covered by the data (earliest / latest reading).
  DateTime? _covStart, _covEnd;

  // EDA cards (correlations + health breakdown).
  bool _edaLoading = true;
  String? _edaError;
  List<_CorrPair> _allCorrelations = []; // every unique pair, strongest first
  Map<String, Map<String, double>> _breakdown = {}; // metric -> health -> avg

  // Daily rolling / weekly average series.
  final _daily = _Series<_DailyPt>();
  final _weekly = _Series<_WeeklyPt>();
  String _statKey = 'moisture'; // sensor driving every analytics card

  // Page scroll: drives the "back to top" button.
  final _pageScroll = ScrollController();
  bool _showTop = false;

  // Re-reads the newest reading every 30s; this also keeps "Updated x mins
  // ago" counting up.
  Timer? _timer;

  // ─────────────────────────── LIFECYCLE ───────────────────────────

  @override
  void initState() {
    super.initState();
    _pageScroll.addListener(_onPageScroll);
    CropService.instance.addListener(_onCropChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onCropChanged());
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _fetchCoverage(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    CropService.instance.removeListener(_onCropChanged);
    _pageScroll.dispose();
    super.dispose();
  }

  // ─────────────────────────── NO INTERNET (OfflineNotice) ───────────────────────────

  @override
  int get tabIndex => 1;

  @override
  bool get hasLastData =>
      _covEnd != null ||
      _allCorrelations.isNotEmpty ||
      _breakdown.isNotEmpty ||
      _daily.data.isNotEmpty ||
      _weekly.data.isNotEmpty;

  // Reload everything when the internet comes back or the app reopens.
  @override
  void onBackOnline() {
    _fetchCoverage();
    _fetchEda(showSpinner: false);
    _fetchDaily(showSpinner: false);
    _fetchWeekly(showSpinner: false);
  }

  // ─────────────────────────── CROP SELECTION & REFRESH ───────────────────────────

  // Runs when crops finish loading or the user picks another crop.
  void _onCropChanged() {
    if (!mounted || !CropService.instance.loaded) return;
    final id = _deviceId;
    final cropId = CropService.instance.selected?.id;
    if (_started && id == _loadedDevice && cropId == _loadedCrop) {
      setState(() {}); // same crop: keep the charts on screen
      return;
    }
    _started = true;
    _loadedDevice = id;
    _loadedCrop = cropId;
    // Another device: drop the old charts so they are never shown for it.
    setState(() {
      _allCorrelations = [];
      _breakdown = {};
      _daily.data = [];
      _weekly.data = [];
      _covStart = null;
      _covEnd = null;
    });
    _fetchEda();
    _fetchCoverage();
    _fetchDaily();
    _fetchWeekly();
  }

  // Pull-to-refresh. Also retries the crop list if it could not load.
  Future<void> _refreshAll() async {
    if (CropService.instance.offline) {
      await CropService.instance.load();
      if (!mounted) return;
      if (CropService.instance.offline && _deviceId == null) {
        markConnection(false, userAction: true);
        return;
      }
    }
    await Future.wait([
      _fetchEda(showSpinner: false, userAction: true),
      _fetchCoverage(userAction: true),
      _fetchDaily(showSpinner: false, userAction: true),
      _fetchWeekly(showSpinner: false, userAction: true),
    ]);
  }

  /// After a failed request: no internet keeps the last data on screen (with
  /// the notice and snackbar); the error message only replaces a chart that
  /// has nothing to show. Returns the message to show, or null.
  String? _failed(
    Object e,
    String message, {
    required bool hasData,
    required bool userAction,
  }) {
    if (isConnectionError(e)) {
      markConnection(false, userAction: userAction);
      return hasData ? null : message;
    }
    return message;
  }

  // ─────────────────────────── DATA: COVERAGE ───────────────────────────

  // Earliest and latest reading for this device (the overall coverage).
  Future<void> _fetchCoverage({bool userAction = false}) async {
    final id = _deviceId;
    try {
      Future<DateTime?> edge(String deviceId, bool asc) async {
        final r = await _supabase
            .from('sensor_readings')
            .select('timestamp')
            .eq('device_id', deviceId)
            .order('timestamp', ascending: asc)
            .limit(1)
            .timeout(kRequestTimeout);
        return r.isEmpty
            ? null
            : DateTime.tryParse('${r.first['timestamp']}')?.toUtc();
      }

      // Both ends are requested together.
      final edges = id == null
          ? const <DateTime?>[null, null]
          : await Future.wait([edge(id, true), edge(id, false)]);
      final start = edges[0], end = edges[1];
      if (!mounted || id != _deviceId) return;
      // A newer reading than the one shown: the charts are out of date.
      final newer = _covEnd != null && end != null && end.isAfter(_covEnd!);
      if (id != null) {
        markConnection(true);
        LastData.save('analytics_coverage_$id', [
          start?.toIso8601String(),
          end?.toIso8601String(),
        ]);
      }
      setState(() {
        _covStart = start;
        _covEnd = end;
      });
      if (newer) {
        _fetchEda(showSpinner: false);
        _fetchDaily(showSpinner: false);
        _fetchWeekly(showSpinner: false);
      }
    } catch (e) {
      debugPrint('Coverage fetch error: $e');
      if (!mounted || id != _deviceId || !isConnectionError(e)) return;
      // Opened offline: the saved dates also drive "Updated ... ago".
      if (id != null && _covEnd == null) {
        final saved = await LastData.read('analytics_coverage_$id');
        if (!mounted || id != _deviceId) return;
        if (saved is List && saved.length == 2) {
          setState(() {
            _covStart = DateTime.tryParse('${saved[0]}')?.toUtc();
            _covEnd = DateTime.tryParse('${saved[1]}')?.toUtc();
          });
        }
      }
      // Runs every 30 s, so this is also what notices a lost connection.
      markConnection(false, userAction: userAction);
    }
  }

  // "Updated 5 mins ago", from the newest reading's timestamp. The stored
  // clock fields are already local time, so they are rebuilt as a local
  // DateTime before comparing with now (same as the Plant Profile page).
  String _updatedText() {
    final utc = _covEnd; // always stored as UTC
    if (utc == null) return '';
    final dt = DateTime(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
      utc.second,
    );
    final diff = DateTime.now().difference(dt);

    if (diff.isNegative || diff.inSeconds < 60) return 'Updated just now';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return 'Updated $m min${m == 1 ? '' : 's'} ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return 'Updated $h hr${h == 1 ? '' : 's'} ago';
    }
    final d = diff.inDays;
    return 'Updated $d day${d == 1 ? '' : 's'} ago';
  }

  // ─────────────────────────── DATA: CORRELATIONS & BREAKDOWN ───────────────────────────

  Future<void> _fetchEda({
    bool showSpinner = true,
    bool userAction = false,
  }) async {
    if (showSpinner) {
      setState(() {
        _edaLoading = true;
        _edaError = null;
      });
    }
    final id = _deviceId;
    try {
      var corr = <dynamic>[], breakdown = <dynamic>[];
      if (id != null) {
        // Both are requested together.
        final params = {'p_device': id};
        final results = await Future.wait([
          _supabase
              .rpc('device_correlations', params: params)
              .timeout(kRequestTimeout),
          _supabase
              .rpc('device_target_breakdown', params: params)
              .timeout(kRequestTimeout),
        ]);
        corr = results[0] as List;
        breakdown = results[1] as List;
        LastData.save('analytics_eda_$id', {
          'corr': corr,
          'breakdown': breakdown,
        });
      }
      if (!mounted || id != _deviceId) return;
      if (id != null) markConnection(true);
      _applyEda(corr, breakdown);
    } catch (e) {
      debugPrint('EDA fetch error: $e');
      if (!mounted || id != _deviceId) return;
      // No internet and nothing on screen yet: use the copy saved on the
      // phone.
      if (id != null &&
          _allCorrelations.isEmpty &&
          _breakdown.isEmpty &&
          isConnectionError(e)) {
        final saved = await LastData.read('analytics_eda_$id');
        if (!mounted || id != _deviceId) return;
        if (saved is Map) {
          try {
            _applyEda(
              (saved['corr'] as List?) ?? const [],
              (saved['breakdown'] as List?) ?? const [],
            );
          } catch (e) {
            debugPrint('Saved analysis unreadable: $e');
          }
        }
      }
      final error = _failed(
        e,
        'Could not load analysis data.',
        hasData: _allCorrelations.isNotEmpty || _breakdown.isNotEmpty,
        userAction: userAction,
      );
      setState(() {
        _edaError = error;
        _edaLoading = false;
      });
    }
  }

  /// Turns the raw correlation and breakdown rows (from the server or the
  /// saved copy) into the two charts' data.
  void _applyEda(List corr, List breakdown) {
    final pairs = <_CorrPair>[];
    final grouped = <String, Map<String, double>>{};

    // Drop self-pairs and mirrored duplicates; the card filters by sensor.
    final seen = <String>{};
    for (final raw in corr) {
      final row = Map<String, dynamic>.from(raw as Map);
      final a = '${row['col_a']}', b = '${row['col_b']}';
      final v = _toNum(row['correlation']);
      if (v == null || a == b || !seen.add(([a, b]..sort()).join('|'))) {
        continue;
      }
      pairs.add(_CorrPair(a, b, v));
    }
    pairs.sort((x, y) => y.value.abs().compareTo(x.value.abs()));

    for (final raw in breakdown) {
      final row = Map<String, dynamic>.from(raw as Map);
      final v = _toNum(row['avg_value']);
      if (v == null) continue;
      final byHealth = grouped.putIfAbsent('${row['metric']}', () => {});
      byHealth['${row['crop_health']}'] = v;
    }

    setState(() {
      _allCorrelations = pairs;
      _breakdown = grouped;
      _edaLoading = false;
      _edaError = null;
    });
  }

  // ─────────────────────────── DATA: DAILY & WEEKLY SERIES ───────────────────────────

  Future<void> _fetchDaily({
    bool showSpinner = true,
    bool userAction = false,
  }) => _fetchSeries(
    _daily,
    rpc: 'device_daily_rolling',
    orderCol: 'day',
    keep: _dailyKeep,
    parse: (r) => _DailyPt(
      DateTime.tryParse('${r['day']}'),
      _toNum(r['daily_mean']),
      _toNum(r['rolling_7d_mean']),
    ),
    errMsg: 'Could not load daily rolling data.',
    showSpinner: showSpinner,
    userAction: userAction,
  );

  Future<void> _fetchWeekly({
    bool showSpinner = true,
    bool userAction = false,
  }) => _fetchSeries(
    _weekly,
    rpc: 'device_weekly_avg',
    orderCol: 'week_end',
    keep: _weeklyKeep,
    parse: (r) {
      final mean = _toNum(r['weekly_mean']);
      return mean == null
          ? null
          : _WeeklyPt(
              DateTime.tryParse('${r['week_end']}'),
              mean,
              _toNum(r['n_readings'])?.toInt(),
            );
    },
    errMsg: 'Could not load weekly average data.',
    showSpinner: showSpinner,
    userAction: userAction,
  );

  /// Fetches the newest [keep] rows of [rpc] for the selected sensor into [s]
  /// (oldest → newest).
  Future<void> _fetchSeries<T extends Object>(
    _Series<T> s, {
    required String rpc,
    required String orderCol,
    required int keep,
    required T? Function(Map<String, dynamic>) parse,
    required String errMsg,
    required bool showSpinner,
    required bool userAction,
  }) async {
    final key = _statKey;
    if (showSpinner) {
      setState(() {
        s.loading = true;
        s.error = null;
      });
    }
    final id = _deviceId;
    final savedKey = 'analytics_${rpc}_${id}_$key';
    List<T> toRows(List raw) => raw
        .map((e) => parse(Map<String, dynamic>.from(e as Map)))
        .nonNulls
        .toList()
        .reversed
        .toList();
    try {
      var rows = <T>[];
      if (id != null) {
        final res = await _supabase
            .rpc(rpc, params: {'p_device': id})
            .ilike('sensor', key)
            .order(orderCol, ascending: false)
            .limit(keep)
            .timeout(kRequestTimeout);
        rows = toRows(res as List);
        LastData.save(savedKey, res);
      }
      // Sensor or crop changed meanwhile.
      if (!mounted || key != _statKey || id != _deviceId) return;
      if (id != null) markConnection(true);
      setState(() {
        s.data = rows;
        s.loading = false;
        s.error = null;
      });
    } catch (e) {
      debugPrint('$rpc fetch error: $e');
      if (!mounted || key != _statKey || id != _deviceId) return;
      // No internet and nothing on screen yet: use the copy saved on the
      // phone for this sensor.
      if (id != null && s.data.isEmpty && isConnectionError(e)) {
        final saved = await LastData.read(savedKey);
        if (!mounted || key != _statKey || id != _deviceId) return;
        if (saved is List) {
          try {
            s.data = toRows(saved);
          } catch (e) {
            debugPrint('Saved $rpc data unreadable: $e');
          }
        }
      }
      final error = _failed(
        e,
        errMsg,
        hasData: s.data.isNotEmpty,
        userAction: userAction,
      );
      setState(() {
        s.error = error;
        s.loading = false;
      });
    }
  }

  // ─────────────────────────── SELECTED SENSOR ───────────────────────────

  // Changing the sensor re-drives every card: daily + weekly refetch, while
  // correlations and the health breakdown are filtered from loaded data.
  void _selectSensor(String key) {
    if (key == _statKey) return;
    setState(() {
      _statKey = key;
      _daily.data = [];
      _weekly.data = [];
    });
    _fetchDaily();
    _fetchWeekly();
  }

  bool _isSelected(String name) => name.toLowerCase() == _statKey.toLowerCase();

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

  // ─────────────────────────── PAGE SCROLL ───────────────────────────

  // Show the "back to top" button only when the user is near the bottom.
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

  // ═══════════════════════════ UI (top of screen → bottom) ═══════════════════════════

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: AppSpace.cardGap);
    final updated = _updatedText();
    final def = _selectedDef;
    return Column(
      children: [
        AppHeader(
          title: 'Analytics',
          subtitle: updated.isEmpty ? null : updated,
        ),
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
                      SensorChipSelector(
                        selectedKey: _statKey,
                        onChanged: _selectSensor,
                      ),
                      gap,
                      _buildWeeklyCard(def),
                      gap,
                      _buildBreakdownCard(def),
                      gap,
                      _buildCorrelationCard(def),
                      gap,
                      _buildDailyCard(def), // Daily Rolling Average is the last graph
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

  // ── 1. COVERAGE BANNER ──

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
              color: Colors.white.withValues(alpha: 0.18),
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

  // ── 2. SENSOR SELECTOR: shared SensorChipSelector (see build) ──

  // ── 3. WEEKLY AVERAGE ──

  Widget _buildWeeklyCard(SensorDef def) {
    final pts = _weekly.data;
    return _card(
      title: 'Weekly Average',
      subtitle: pts.isEmpty
          ? def.label
          : '${def.label} · weeks ending '
                '${_fmtRange(pts.first.weekEnd, pts.last.weekEnd)}',
      body: _buildWeeklyChart(def),
      info:
          'Each bar is one week\'s average, labelled by the week-end date. '
          'Tap a bar to see how many readings it is based on. '
          'Recent weeks may be partial.',
    );
  }

  Widget _buildWeeklyChart(SensorDef def) {
    if (_notReady(
          _weekly.loading,
          _weekly.error,
          () => _fetchWeekly(userAction: true),
        )
        case final w?) {
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

  // ── 4. READINGS BY CROP HEALTH ──

  Widget _buildBreakdownCard(SensorDef def) => _card(
    title: 'Readings by Crop Health',
    subtitle: '${def.label} · average value for each health status',
    height: 190,
    body: _buildBreakdownChart(def),
    info:
        'Shows what each sensor typically reads when the crop is in each '
        'status, so you can see which readings go with healthy vs. '
        'stressed conditions.',
  );

  Widget _buildBreakdownChart(SensorDef def) {
    if (_notReady(_edaLoading, _edaError, () => _fetchEda(userAction: true))
        case final w?) {
      return w;
    }
    final data = _sensorBreakdown;
    if (data == null || data.isEmpty) {
      return _emptyBody('No ${def.label} breakdown data yet for this crop');
    }

    // Score each status once (used for both the order and the colors).
    final health = {for (final l in data.keys) l: _scoreForCropHealth(l)};

    // Healthiest status first (Optimal → Warning → Critical).
    final labels = data.keys.toList()
      ..sort((a, b) {
        final c = (health[b] ?? -1).compareTo(health[a] ?? -1);
        return c != 0 ? c : a.compareTo(b);
      });
    final maxVal = data.values.reduce((a, b) => a > b ? a : b);
    final maxY = maxVal <= 0 ? 1.0 : maxVal * 1.2;

    return _barChart(
      maxY: maxY,
      interval: maxY / 4,
      values: [for (final l in labels) data[l]!],
      colors: [for (final l in labels) _colorForHealthScore(health[l])],
      barWidth: 28,
      leftSize: 40,
      leftLabel: (v) => v.toStringAsFixed(v.abs() >= 100 ? 0 : 1),
      bottomSize: 34,
      bottom: (i) => _tick(labels[i].replaceFirst(' ', '\n')),
      tip: (i) => '${labels[i]}\n${data[labels[i]]!.toStringAsFixed(2)}',
    );
  }

  // ── 5. SENSOR CORRELATIONS ──

  Widget _buildCorrelationCard(SensorDef def) => _card(
    title: 'Sensor Correlations',
    subtitle: '${def.label} compared with the other sensors',
    body: _buildCorrelationChart(def),
    footer: [
      Row(
        children: [
          _legendDot(AppColors.healthy, 'Move together (+)'),
          _legendDot(AppColors.critical, 'Move opposite (−)'),
        ],
      ),
      const SizedBox(height: 4),
    ],
    info:
        'Every pair involving this sensor, strongest first. Values near ±1 '
        'mean a strong relationship; near 0 means little or none. '
        'Tap a bar for details.',
  );

  Widget _buildCorrelationChart(SensorDef def) {
    if (_notReady(_edaLoading, _edaError, () => _fetchEda(userAction: true))
        case final w?) {
      return w;
    }
    final corr = _sensorCorrelations;
    if (corr.isEmpty) {
      return _emptyBody(
        'No correlation data yet for ${def.label} on this crop.',
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

  // ── 6. DAILY ROLLING AVERAGE ──

  Widget _buildDailyCard(SensorDef def) {
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
              AppColors.optimal.withValues(alpha: 0.35),
              'Optimal: ${def.optimalText}',
            ),
          ],
        ),
        const SizedBox(height: 2),
      ],
      info:
          'The rolling mean smooths out day-to-day noise so you can see '
          'whether a sensor is drifting. The green band appears only '
          'when the optimal range overlaps the data.',
    );
  }

  Widget _buildDailyChart(SensorDef def) {
    if (_notReady(
          _daily.loading,
          _daily.error,
          () => _fetchDaily(userAction: true),
        )
        case final w?) {
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
        if (pick(pts[i]) case final v?) FlSpot(i.toDouble(), v),
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
                    color: AppColors.optimal.withValues(alpha: 0.15),
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
            color: AppColors.info.withValues(alpha: 0.7),
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
              color: AppColors.healthy.withValues(alpha: 0.10),
            ),
          ),
        ],
      ),
    );
  }

  // ── 7. BACK TO TOP (floats above the page) ──

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

  // ── CARD BUILDING BLOCKS (used by every chart card above) ──

  /// A chart card. [info] is the explanation of what the chart shows; it is
  /// not printed on the card but shown while the (i) button at the top right
  /// is held.
  Widget _card({
    required String title,
    required String subtitle,
    required Widget body,
    double height = 200,
    List<Widget> footer = const [],
    String? info,
  }) {
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppText.cardTitle),
                      const SizedBox(height: 2),
                      Text(subtitle, style: AppText.subtitle),
                    ],
                  ),
                ),
                if (info != null) ...[
                  const SizedBox(width: 8),
                  _InfoButton(message: info),
                ],
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(height: height, child: body),
            const SizedBox(height: 6),
            ...footer,
          ],
        ),
      ),
    );
  }

  // Spinner or error body while a chart isn't ready; null when it is.
  Widget? _notReady(bool loading, String? error, VoidCallback retry) => loading
      ? const Center(child: CircularProgressIndicator())
      : error != null
      ? _errorBody(error, retry)
      : null;

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

  Widget _emptyBody(String message) => Center(
    child: Text(message, textAlign: TextAlign.center, style: _mutedStyle),
  );

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
}

// ═════════════════════════════════════════════════════════════════════════
// 6. INFO BUTTON — small (i) for the top-right of a chart card. Press and
//    hold it to show [message] in a bubble under the icon; the bubble
//    disappears as soon as the finger is lifted.
// ═════════════════════════════════════════════════════════════════════════

class _InfoButton extends StatefulWidget {
  final String message;
  const _InfoButton({required this.message});

  @override
  State<_InfoButton> createState() => _InfoButtonState();
}

class _InfoButtonState extends State<_InfoButton> {
  final _link = LayerLink(); // anchors the bubble to the icon
  OverlayEntry? _entry;

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  void _show() {
    if (_entry != null) return;
    final width = MediaQuery.of(context).size.width;
    _entry = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        top: 0,
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 6),
          child: IgnorePointer(
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: width - 80),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.textPrimary,
                    borderRadius: BorderRadius.circular(AppRadius.field),
                    boxShadow: AppShadows.card,
                  ),
                  child: Text(
                    widget.message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_entry!);
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      // Raw pointer events: shows while the finger is down, hides on release.
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _show(),
        onPointerUp: (_) => _hide(),
        onPointerCancel: (_) => _hide(),
        child: const Padding(
          padding: EdgeInsets.all(4),
          child: Icon(AppIcons.info, size: 20, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}