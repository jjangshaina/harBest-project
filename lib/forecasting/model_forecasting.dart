import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_application_harbest_1/theme/app_style.dart';

import 'package:flutter_application_harbest_1/services/crop_services.dart';
import 'package:flutter_application_harbest_1/services/forecast_service.dart';

import 'package:flutter_application_harbest_1/widgets/app_card.dart';
import 'package:flutter_application_harbest_1/widgets/app_empty_state.dart';
import 'package:flutter_application_harbest_1/widgets/app_header.dart';
import 'package:flutter_application_harbest_1/widgets/app_snackbar.dart';
import 'package:flutter_application_harbest_1/widgets/sensor_chip_selector.dart';
import 'package:flutter_application_harbest_1/widgets/status_widgets.dart';

import 'package:flutter_application_harbest_1/pages/user_dashboard.dart'
    show SensorDef, kSensors;

// ═════════════════════════════════════════════════════════════════════════
// 1. CONSTANTS & STYLES
// ═════════════════════════════════════════════════════════════════════════

const _forecastColor = Color(0xFFD9822B);

/// App sensor key -> variable name used by the forecast pipeline.
/// Sensors not listed (heat index) have no forecast yet.
const _varNames = {
  'moisture': 'moisture_pct',
  'pH': 'pH',
  'temperature': 'temperature',
  'humidity': 'humidity',
  'EC': 'EC',
  'nitrogen': 'nitrogen',
  'phosphorus': 'phosphorus',
  'potassium': 'potassium',
};

const _axisStyle = TextStyle(fontSize: 10, color: AppColors.textSecondary);
const _noTitles = AxisTitles(sideTitles: SideTitles(showTitles: false));

// ═════════════════════════════════════════════════════════════════════════
// 2. FORECAST DATA — parsed chart lines
// ═════════════════════════════════════════════════════════════════════════

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
      FlSpot(
        (f['horizon_min'] as num).toDouble() / 60.0,
        (f[key] as num).toDouble() * k,
      ),
  ];
  return _Forecast(actual, line('value'), line('upper'), line('lower'));
}

// ═════════════════════════════════════════════════════════════════════════
// 3. HELPERS — formatting and status labels
// ═════════════════════════════════════════════════════════════════════════

String _horizonText(num minutes) {
  if (minutes < 60) return '${minutes.round()} min';
  if (minutes < 1440) return '${(minutes / 60).round()} h';
  return '${(minutes / 1440).round()} days';
}

String _clock(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'PM' : 'AM'}';
}

// Bottom-axis label: "Now", "-30m", "+6h", "+2.5d".
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

// ═════════════════════════════════════════════════════════════════════════
// 4. FORECASTING PAGE
// ═════════════════════════════════════════════════════════════════════════

class AiForecasting extends StatefulWidget {
  const AiForecasting({super.key});

  @override
  State<AiForecasting> createState() => _AiForecastingState();
}

class _AiForecastingState extends State<AiForecasting>
    with OfflineNotice<AiForecasting> {
  // ─────────────────────────── STATE ───────────────────────────

  // Device whose forecast is on screen.
  String? _loadedDevice;

  String _sensorKey = kSensors.first.key;
  Map<String, dynamic>? _run;
  bool _loading = true;
  String? _error;
  Object? _latestTimestamp; // newest sensor_readings.timestamp

  // Re-reads the newest reading every 30s; this also keeps "Updated x mins
  // ago" counting up.
  Timer? _timer;

  // ─────────────────────────── LIFECYCLE ───────────────────────────

  @override
  void initState() {
    super.initState();
    CropService.instance.addListener(_load);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _load(), // forecast + "Updated ... ago", without a spinner
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    CropService.instance.removeListener(_load);
    super.dispose();
  }

  // ─────────────────────────── NO INTERNET (OfflineNotice) ───────────────────────────

  @override
  int get tabIndex => 3;

  @override
  bool get hasLastData => _run != null;

  @override
  void onBackOnline() => _load();

  // ─────────────────────────── DATA: FORECAST ───────────────────────────

  Future<void> _refresh() => _load(userAction: true);

  /// Loads the newest forecast. Runs on start, on crop changes, on
  /// pull-to-refresh ([userAction]) and when the connection comes back.
  /// The forecast already on screen stays there while this runs, and stays
  /// if it fails for lack of internet.
  Future<void> _load({bool userAction = false}) async {
    if (!mounted || !CropService.instance.loaded) return;
    if (userAction && CropService.instance.offline) {
      await CropService.instance.load(); // retry a failed crop list
      if (!mounted) return;
    }
    final id = CropService.instance.selected?.deviceId;
    final firstLoad = id != _loadedDevice;
    if (firstLoad) {
      // Another crop: never show the previous crop's forecast.
      _run = null;
      _latestTimestamp = null;
    }
    _loadedDevice = id;
    setState(() {
      // Spinner only for a crop's first load, never for the 30 s refresh,
      // and never without a device.
      _loading = firstLoad && _run == null && id != null;
      _error = null;
    });
    _fetchLatestReading();
    if (id == null) {
      if (CropService.instance.offline) {
        markConnection(false, userAction: userAction);
      }
      return;
    }
    try {
      final run = await ForecastService.latest(id).timeout(kRequestTimeout);
      if (!mounted || id != _loadedDevice) return;
      markConnection(true);
      LastData.save('forecast_$id', run);
      setState(() {
        _run = run;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Forecast load error: $e');
      if (!mounted || id != _loadedDevice) return;
      final noInternet = isConnectionError(e);
      // No internet and nothing on screen yet: use the forecast saved on
      // the phone.
      if (noInternet && _run == null) {
        final saved = await LastData.read('forecast_$id');
        if (!mounted || id != _loadedDevice) return;
        if (saved is Map) _run = Map<String, dynamic>.from(saved);
      }
      setState(() {
        if (_run == null && !noInternet) {
          _error = 'Could not load the forecast. Pull down to retry.';
        }
        _loading = false;
      });
      if (noInternet) markConnection(false, userAction: userAction);
    }
  }

  // ─────────────────────────── DATA: LATEST READING ───────────────────────────

  // Newest sensor reading for the selected crop (drives "Updated ...").
  Future<void> _fetchLatestReading() async {
    final id = CropService.instance.selected?.deviceId;
    if (id == null) {
      if (mounted) setState(() => _latestTimestamp = null);
      return;
    }
    try {
      final rows = await Supabase.instance.client
          .from('sensor_readings')
          .select('timestamp')
          .eq('device_id', id)
          .order('timestamp', ascending: false)
          .limit(1)
          .timeout(kRequestTimeout);
      if (!mounted || CropService.instance.selected?.deviceId != id) return;
      markConnection(true);
      final ts = rows.isEmpty ? null : rows.first['timestamp'];
      LastData.save('latest_reading_$id', ts);
      setState(() => _latestTimestamp = ts);
    } catch (e) {
      debugPrint('Latest reading fetch error: $e');
      if (!mounted || !isConnectionError(e)) return;
      // Opened offline: "Updated ... ago" from the time saved on the phone.
      if (_latestTimestamp == null) {
        final saved = await LastData.read('latest_reading_$id');
        if (!mounted || CropService.instance.selected?.deviceId != id) return;
        if (saved != null) setState(() => _latestTimestamp = saved);
      }
      // Runs every 30 s, so this is also what notices a lost connection.
      markConnection(false);
    }
  }

  // "Updated 5 mins ago", from the newest reading's timestamp. The stored
  // clock fields are already local time, so they are rebuilt as a local
  // DateTime before comparing with now (same as the Plant Profile page).
  String _updatedText() {
    final raw = _latestTimestamp;
    if (raw == null) return '';
    final utc = DateTime.tryParse(raw.toString())?.toUtc();
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

  // ─────────────────────────── SELECTED SENSOR ───────────────────────────

  SensorDef get _def => kSensors.firstWhere(
    (d) => d.key == _sensorKey,
    orElse: () => kSensors.first,
  );

  // The selected sensor's forecast from the current run, or null.
  Map<String, dynamic>? get _variable {
    final name = _varNames[_sensorKey];
    final vars = _run?['variables'];
    if (name == null || vars is! Map || vars[name] is! Map) return null;
    return Map<String, dynamic>.from(vars[name] as Map);
  }

  // ═══════════════════════════ UI (top of screen → bottom) ═══════════════════════════

  @override
  Widget build(BuildContext context) {
    final updated = _updatedText();
    return Column(
      children: [
        AppHeader(
          title: 'AI Forecasting',
          subtitle: updated.isEmpty ? null : updated,
        ),
        Expanded(child: _body()),
      ],
    );
  }

  // Every state below can be pulled down to refresh.
  Widget _body() {
    if (CropService.instance.loaded && CropService.instance.selected == null) {
      return AppRefreshable(
        onRefresh: _refresh,
        child: CropService.instance.offline
            ? const AppOfflineState()
            : const AppNoCropState(),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_run == null) {
      return AppRefreshable(
        onRefresh: _refresh,
        child: offline
            ? const AppOfflineState()
            : _error != null
                ? Center(
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: AppText.subtitle,
                    ),
                  )
                : const AppEmptyState(
                    icon: Icons.show_chart,
                    title: 'No forecast has been generated yet',
                    message:
                        'A forecast appears once your device has sent new readings.',
                  ),
      );
    }

    final def = _def;
    final v = _variable;
    final k = _sensorKey == 'EC' ? 0.001 : 1.0; // µS/cm -> mS/cm

    return _scrollable([
      // 1. Sensor selector
      SensorChipSelector(
        selectedKey: _sensorKey,
        onChanged: (key) => setState(() => _sensorKey = key),
      ),
      const SizedBox(height: AppSpace.cardGap),

      // 2. Run notices
      if (_run!['status'] == 'experimental') ...[
        _banner('Experimental: ${_run!['note']}', AppColors.info),
        const SizedBox(height: AppSpace.gap),
      ],
      if (_run!['stale'] == true) ...[
        _banner(
          'Waiting for new sensor data. The forecast is based on older readings.',
          AppColors.caution,
        ),
        const SizedBox(height: AppSpace.gap),
      ],

      // 3. Forecast for the selected sensor
      if (v == null)
        _buildNotAvailableCard(def)
      else
        ..._buildForecast(v, def, k),
    ]);
  }

  // ── NO FORECAST FOR THIS SENSOR ──

  Widget _buildNotAvailableCard(SensorDef def) => SizedBox(
    width: double.infinity,
    child: AppCard(
      padding: const EdgeInsets.all(20),
      child: Text(
        'A forecast for ${def.label} is not available yet.',
        style: AppText.subtitle,
      ),
    ),
  );

  // ── FORECAST: outlook chart, info cards, suggested action, footer ──

  List<Widget> _buildForecast(Map<String, dynamic> v, SensorDef def, double k) {
    final status = v['status'] as String;
    final last = (v['forecast'] as List).last;
    final horizon = _horizonText(last['horizon_min'] as num);
    final predicted = (last['value'] as num).toDouble() * k;
    final leaves = v['leaves_optimal_at'] as String?;
    final leaveText = leaves != null
        ? _clock(DateTime.parse(leaves).toLocal())
        : (status == 'out_of_range' ? 'Now' : 'Stays in range');

    return [
      _buildOutlookCard(v, def, k, horizon),
      const SizedBox(height: AppSpace.gap),
      Row(
        children: [
          _infoCard(
            'Predicted in $horizon',
            '${predicted.toStringAsFixed(def.decimals)}${def.unit}',
            badge: AppStatusPill(
              text: _statusLabel(status),
              color: _statusColor(status),
            ),
          ),
          const SizedBox(width: AppSpace.gap),
          _infoCard('Leaves optimal range', leaveText),
        ],
      ),
      const SizedBox(height: AppSpace.gap),
      _buildSuggestedAction(v['suggested_action'] as String),
      const SizedBox(height: AppSpace.gap),
      Text(v['footer'] as String, style: AppText.caption),
    ];
  }

  Widget _buildOutlookCard(
    Map<String, dynamic> v,
    SensorDef def,
    double k,
    String horizon,
  ) {
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${def.label} outlook', style: AppText.cardTitle),
            const SizedBox(height: 2),
            Text(
              'Next $horizon, predicted from your last readings',
              style: AppText.subtitle,
            ),
            const SizedBox(height: 12),
            SizedBox(height: 200, child: _buildChart(v, def, k)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _legendItem(AppColors.healthy, 'Actual'),
                _legendItem(_forecastColor, 'Forecast'),
                _legendItem(
                  _forecastColor.withValues(alpha: 0.25),
                  'Confidence range',
                  box: true,
                ),
                if (v['optimal'] != null)
                  _legendItem(
                    AppColors.optimal.withValues(alpha: 0.2),
                    'Optimal',
                    box: true,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(Map<String, dynamic> v, SensorDef def, double k) {
    final f = _parse(v, k);
    final opt = v['optimal'] as List?;
    final optLo = opt == null ? null : (opt[0] as num).toDouble() * k;
    final optHi = opt == null ? null : (opt[1] as num).toDouble() * k;

    var minX = f.actual.first.x;
    final maxX = f.predicted.last.x;
    if (minX >= 0) minX = -(maxX / 2);

    final ys = <double>[
      for (final s in [f.actual, f.predicted, f.upper, f.lower])
        ...s.map((p) => p.y),
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

    // Invisible lines for the confidence band's upper and lower edges.
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
                    color: AppColors.optimal.withValues(alpha: 0.12),
                  ),
                ],
        ),
        // Dashed "now" line.
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
          topTitles: _noTitles,
          rightTitles: _noTitles,
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: yStep,
              getTitlesWidget: (y, _) =>
                  Text(y.toStringAsFixed(def.decimals), style: _axisStyle),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: (maxX - minX) / 4,
              getTitlesWidget: (x, _) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_axisLabel(x), style: _axisStyle),
              ),
            ),
          ),
        ),
        betweenBarsData: [
          BetweenBarsData(
            fromIndex: 2,
            toIndex: 3,
            color: _forecastColor.withValues(alpha: 0.22),
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

  Widget _buildSuggestedAction(String text) => SizedBox(
    width: double.infinity,
    child: AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Suggested action', style: AppText.label),
          const SizedBox(height: 6),
          Text(text, style: AppText.body.copyWith(fontSize: 14)),
        ],
      ),
    ),
  );

  // ── BUILDING BLOCKS ──

  // Pull-to-refresh list that holds the page content.
  Widget _scrollable(List<Widget> children) => RefreshIndicator(
    color: AppColors.green,
    onRefresh: _refresh,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpace.page),
      children: children,
    ),
  );

  Widget _banner(String text, Color color) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppRadius.field),
    ),
    child: Text(text, style: AppText.body.copyWith(fontSize: 13, height: 1.4)),
  );

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

  Widget _legendItem(Color c, String label, {bool box = false}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: box ? 12 : 16, height: box ? 12 : 3, color: c),
      const SizedBox(width: 4),
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
    ],
  );
}