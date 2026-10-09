import 'package:flutter/material.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/widgets/app_bottom_nav.dart';
import 'package:flutter_application_harbest_1/widgets/app_button.dart';
import 'package:flutter_application_harbest_1/widgets/app_card.dart';
import 'package:flutter_application_harbest_1/widgets/status_widgets.dart';

// Re-exported so any file that imported AppBottomNav from here keeps working.
export 'package:flutter_application_harbest_1/widgets/app_bottom_nav.dart';
import 'package:flutter_application_harbest_1/pages/user_account.dart';
import 'package:flutter_application_harbest_1/analytics/ai_analytics.dart';
import 'package:flutter_application_harbest_1/plant_profile/profile.dart';
import 'package:flutter_application_harbest_1/Insights/Insights_recommendation.dart';
import 'package:flutter_application_harbest_1/notification/alerts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_harbest_1/widgets/plant_image.dart';

import 'dart:async';

// Plain widget now, not its own MaterialApp — app initialization (Firebase,
// Supabase) and the single root MaterialApp now live in main.dart. This
// class is kept (rather than replacing every call site with
// MainNavigation) so existing Navigator.push(...)/pushAndRemoveUntil(...)
// calls elsewhere in the app don't need to change.
class UserDashboard extends StatelessWidget {
  const UserDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return const MainNavigation();
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;

  // No longer const — DashboardScreen now needs a callback.
  late final List<Widget> _pages = [
    DashboardScreen(
      onNavigateToProfile: () => setState(() => _selectedIndex = 2),
    ),
    const AiAnalytics(),
    const PlantProfilePage(),
    const InsightsRecommendation(),
    const AlertsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SENSOR DEFINITIONS (used by the Sensor Overview cards)
// ─────────────────────────────────────────────

class SensorDef {
  final String key;
  final String label;
  final String unit;
  final IconData icon;
  final double min;
  final double max;
  final double tolerance; // deviation from range at which score hits 0
  final String optimalText;
  final int decimals;

  const SensorDef({
    required this.key,
    required this.label,
    required this.unit,
    required this.icon,
    required this.min,
    required this.max,
    required this.tolerance,
    required this.optimalText,
    this.decimals = 1,
  });
}

// Compact 3x3 order and labels for the Sensor Overview cards.
const List<SensorDef> kSensors = [
  // Arkansas Cooperative Extension Service mustard greens fact sheet
  // (FSA-6072): pH 6.0–7.0.
  SensorDef(
    key: 'pH', label: 'Soil pH', unit: '', icon: AppIcons.soilPh,
    min: 6.0, max: 7.0, tolerance: 1.5, optimalText: '6.0 – 7.0',
  ),
  SensorDef(
    key: 'moisture', label: 'Moisture', unit: '%', icon: AppIcons.moisture,
    min: 60, max: 80, tolerance: 30, optimalText: '60% – 80%', decimals: 0,
  ),
  SensorDef(
    key: 'temperature', label: 'Temp', unit: '°C', icon: AppIcons.temperature,
    min: 10, max: 24, tolerance: 14, optimalText: '10°C – 24°C',
  ),
  SensorDef(
    key: 'humidity', label: 'Humidity', unit: '%', icon: AppIcons.humidity,
    min: 40, max: 70, tolerance: 25, optimalText: '40% – 70%', decimals: 0,
  ),
  // NOAA NWS heat index chart: "Caution" band begins at 27°C.
  SensorDef(
    key: 'heat_index', label: 'Heat Index', unit: '°C', icon: AppIcons.heatIndex,
    min: 0, max: 27, tolerance: 12, optimalText: 'Below 27°C',
  ),
  SensorDef(
    key: 'EC', label: 'EC', unit: '', icon: AppIcons.conductivity,
    min: 1.0, max: 2.5, tolerance: 1.0, optimalText: '1.0 – 2.5 mS/cm',
    decimals: 2,
  ),
  // UW–Madison Extension garden soil-test ideal ranges (N, P, K).
  SensorDef(
    key: 'nitrogen', label: 'Nitrogen', unit: '', icon: AppIcons.nitrogen,
    min: 5.8, max: 11.6, tolerance: 6.0, optimalText: '5.8 – 11.6 ppm',
  ),
  SensorDef(
    key: 'phosphorus', label: 'Phosphorus', unit: '', icon: AppIcons.phosphorus,
    min: 16, max: 21, tolerance: 10, optimalText: '16 – 21 ppm',
  ),
  SensorDef(
    key: 'potassium', label: 'Potassium', unit: '', icon: AppIcons.potassium,
    min: 161, max: 201, tolerance: 80, optimalText: '161 – 201 ppm',
    decimals: 0,
  ),
];

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onNavigateToProfile;

  const DashboardScreen({super.key, this.onNavigateToProfile});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  static const int _historyLength = 10;

  final String _uid = FirebaseAuth.instance.currentUser!.uid;
  final _supabase = Supabase.instance.client;

  Map<String, dynamic> _sensorData = {};
  // Oldest → newest. Feeds the mini charts in the Sensor Overview cards.
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;
  String? _error;

  late final RealtimeChannel _sensorChannel;

  // Full name from the same Firestore record the My Account page edits
  // (users/{uid}.fullName). Listening to snapshots means the greeting
  // updates right after the name is changed there.
  String _fullName = '';
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _nameSub;
  Timer? _refreshTimer;

  // Rebuilds the screen on a fixed interval purely so the "time ago" text
  // keeps counting up, independent of whether new sensor data arrives.
  Timer? _relativeTimeTicker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenToUserName();
    _fetchSensorData();
    _subscribeToSensor();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _fetchSensorData(),
    );
    _relativeTimeTicker = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  // Refresh the "time ago" text immediately when the app comes back from
  // the background (timers can be paused/throttled while backgrounded).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
      _fetchSensorData();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _relativeTimeTicker?.cancel();
    _nameSub?.cancel();
    _supabase.removeChannel(_sensorChannel);
    super.dispose();
  }

  // Fetches the latest N rows: the newest is the current reading, the
  // rest feed the mini charts.
  Future<void> _fetchSensorData() async {
    try {
      final response = await _supabase
          .from('sensor_readings')
          .select()
          .order('id', ascending: false)
          .limit(_historyLength);

      debugPrint("Raw response: $response");
      if (!mounted) return;

      final rows = List<Map<String, dynamic>>.from(
        (response as List).map((e) => Map<String, dynamic>.from(e)),
      );

      if (rows.isEmpty) {
        setState(() {
          _error = "No sensor data found. Start your Raspberry Pi!";
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _sensorData = rows.first;
        _history = rows.reversed.toList();
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "No sensor data found. Start your Raspberry Pi!";
        _isLoading = false;
      });
      debugPrint("Supabase fetch error: $e");
    }
  }

  void _subscribeToSensor() {
    _sensorChannel = _supabase
        .channel('sensor_readings_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'sensor_readings',
          callback: (payload) {
            debugPrint("Supabase live update: ${payload.newRecord}");
            if (!mounted) return;
            final row = Map<String, dynamic>.from(payload.newRecord);
            setState(() {
              _sensorData = row;
              _history = [..._history, row];
              if (_history.length > _historyLength) {
                _history = _history.sublist(_history.length - _historyLength);
              }
              _error = null;
            });
          },
        )
        .subscribe((status, [error]) {
          debugPrint("Realtime status: $status");
          if (error != null) debugPrint("Realtime error: $error");
        });
  }

  // ── LAST READING TIMESTAMP ──
  // Shows the `timestamp` (timestamptz) column exactly as it's stored
  // in the database — no timezone conversion applied. .toUtc() here
  // just reads back the raw stored field values unmodified (since the
  // column's offset is +00), so this always matches what you see in
  // the Supabase table editor.
  DateTime? _lastReadingDateTime() {
    final raw = _sensorData['timestamp'];
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toUtc();
  }

  String _formatLastReading() {
    final dt = _lastReadingDateTime();
    if (dt == null) return 'No reading yet';

    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final day = weekdays[dt.weekday - 1];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';

    return '$day, ${dt.month}/${dt.day}/${dt.year} • $hour:$minute $ampm';
  }

  // Human-friendly "time ago" version of the same timestamp, e.g.
  // "Just now", "5 minutes ago", "3 hours ago", "2 days ago".
  //
  // Uses its own helper so the "Last reading" text above stays untouched.
  // The stored clock fields (e.g. 12:03) are already the real local time
  // but labeled +00, so we rebuild them as a LOCAL DateTime before
  // comparing against DateTime.now().
  DateTime? _lastReadingAsLocal() {
    final utc = _lastReadingDateTime();
    if (utc == null) return null;
    return DateTime(utc.year, utc.month, utc.day, utc.hour, utc.minute,
        utc.second);
  }

  String _formatRelativeReading() {
    final dt = _lastReadingAsLocal();
    if (dt == null) return '';

    final diff = DateTime.now().difference(dt);

    if (diff.isNegative || diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return '$m minute${m == 1 ? '' : 's'} ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return '$h hour${h == 1 ? '' : 's'} ago';
    }
    final d = diff.inDays;
    return '$d day${d == 1 ? '' : 's'} ago';
  }

  // ── HEADER GREETING ──
  // "Good Morning" (before 12:00), "Good Afternoon" (12:00–17:59),
  // "Good Evening" (18:00 onward), based on the device's local time.
  // The 30s ticker above rebuilds the screen, so this stays current.
  String _greetingForNow() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 18) return 'Good Afternoon';
    return 'Good Evening';
  }

  void _listenToUserName() {
    _nameSub = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .snapshots()
        .listen((doc) {
      final name = (doc.data()?['fullName'] as String?)?.trim() ?? '';
      if (mounted && name != _fullName) setState(() => _fullName = name);
    }, onError: (e) => debugPrint('Name listener error: $e'));
  }

  // First name for the greeting: first word of the Firestore fullName,
  // then Firebase's display name, then the part of the email before "@".
  String _userFirstName() {
    String firstWord(String v) => v.trim().split(RegExp(r'\s+')).first;

    if (_fullName.isNotEmpty) return firstWord(_fullName);

    final user = FirebaseAuth.instance.currentUser;
    final display = user?.displayName?.trim() ?? '';
    if (display.isNotEmpty) return firstWord(display);

    final email = user?.email ?? '';
    if (email.contains('@')) {
      final local = email.split('@').first;
      if (local.isNotEmpty) {
        return local[0].toUpperCase() + local.substring(1);
      }
    }
    return 'there';
  }

  Widget _buildCropImageCard() {
    final imageUrl = _sensorData['image_url'] as String?;
    final plantName = _sensorData['plant_name'] ?? 'Mustard Green';

    return Center(
      child: GestureDetector(
        onTap: () {
          widget.onNavigateToProfile?.call();
        },
        child: AppCard(
          radius: 20,
          outlineColor: AppColors.darkGreen,
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlantImage(imageUrl: imageUrl, size: 160),
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    plantName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                      color: AppColors.green,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      AppIcons.forward,
                      color: Colors.white,
                      size: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // OVERALL HEALTH SCORE
  // Computed from every live sensor reading + crop_health, rather than
  // a separate stored score field.

  double? _parseNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  // Scores a single sensor reading against its optimal range: 100
  // inside the range, tapering down the further outside it falls,
  // reaching 0 once the deviation reaches `tolerance` (a per-sensor
  // buffer, not just the raw width of the optimal band — this keeps
  // narrow-range sensors like pH from being scored unfairly harshly).
  double? _rangeScore(dynamic raw, double min, double max, double tolerance) {
    final value = _parseNum(raw);
    if (value == null) return null;
    if (value >= min && value <= max) return 100.0;
    final deviation = value < min ? (min - value) : (value - max);
    if (deviation >= tolerance) return 0.0;
    return 100.0 * (1 - (deviation / tolerance));
  }

  // Optimal: inside the range. Caution: outside it, but less than halfway
  // to the tolerance limit (score >= 50). Critical: beyond that.
  HealthLevel _statusFromScore(double score) {
    if (score >= 100) return HealthLevel.optimal;
    if (score >= 50) return HealthLevel.caution;
    return HealthLevel.critical;
  }

  // Every sensor tracked on the dashboard, its optimal range, how far
  // outside that range it can drift before scoring 0, and how much it
  // should count toward the overall score.

  // moisture 25%,
  // pH 20%, NPK (combined) 20%, temperature 15%, humidity 10%,
  // heat index 5%. Weights don't need to sum to 100 — the scoring
  // below renormalizes by whatever weights are present, so only the
  // ratios between them matter.
  static const List<Map<String, dynamic>> _sensorScoreConfig = [
    {'key': 'pH', 'min': 6.0, 'max': 7.0, 'tolerance': 1.5, 'weight': 0.20},
    {'key': 'moisture', 'min': 60.0, 'max': 80.0, 'tolerance': 30.0, 'weight': 0.25},
    {'key': 'temperature', 'min': 10.0, 'max': 24.0, 'tolerance': 14.0, 'weight': 0.15},
    {'key': 'humidity', 'min': 40.0, 'max': 70.0, 'tolerance': 25.0, 'weight': 0.10},
    {'key': 'heat_index', 'min': 0.0, 'max': 27.0, 'tolerance': 12.0, 'weight': 0.05},
  ];

  // Nitrogen, phosphorus and potassium are folded into one combined
  // "NPK" factor (weighted 20% overall, see _npkWeight below) rather
  // than scored individually — the three are averaged together first,
  // so no single nutrient dominates the composite score.
  static const List<Map<String, dynamic>> _npkScoreConfig = [
    {'key': 'nitrogen', 'min': 5.8, 'max': 11.6, 'tolerance': 6.0},
    {'key': 'phosphorus', 'min': 16.0, 'max': 21.0, 'tolerance': 10.0},
    {'key': 'potassium', 'min': 161.0, 'max': 201.0, 'tolerance': 80.0},
  ];
  static const double _npkWeight = 0.20;

  // crop_health may come through as a numeric score (0-100) or as one
  // of the status strings the Pi reports: "Optimal", "Critical",
  // "Temp warning", "Humidity warning".
  double? _cropHealthScore() {
    final raw = _sensorData['crop_health'];
    if (raw == null) return null;

    final asNum = _parseNum(raw);
    if (asNum != null) return asNum.clamp(0.0, 100.0);

    final status = raw.toString().toLowerCase().trim();
    if (status.contains('optimal')) {
      return 95.0;
    }
    if (status.contains('critical')) {
      return 15.0;
    }
    if (status.contains('temp') && status.contains('warning')) {
      return 55.0;
    }
    if (status.contains('humidity') && status.contains('warning')) {
      return 55.0;
    }
    if (status.contains('warning')) {
      // Catch-all for any other "<thing> warning" status the Pi sends.
      return 55.0;
    }
    return null; // Unrecognized status text — skip it.
  }

  double _computeOverallHealthScore() {
    // Weighted average across every factor that currently has data.
    // Weights of missing factors are dropped and the rest
    // renormalized, so one offline sensor doesn't silently zero out
    // the whole score.
    double weightedSum = 0.0;
    double weightTotal = 0.0;

    for (final cfg in _sensorScoreConfig) {
      final score = _rangeScore(
        _sensorData[cfg['key']],
        cfg['min'] as double,
        cfg['max'] as double,
        cfg['tolerance'] as double,
      );
      if (score != null) {
        final weight = cfg['weight'] as double;
        weightedSum += score * weight;
        weightTotal += weight;
      }
    }

    // Average the three NPK readings into one combined score, then
    // fold that in as a single weighted factor.
    final npkScores = _npkScoreConfig
        .map((cfg) => _rangeScore(
              _sensorData[cfg['key']],
              cfg['min'] as double,
              cfg['max'] as double,
              cfg['tolerance'] as double,
            ))
        .whereType<double>()
        .toList();
    if (npkScores.isNotEmpty) {
      final npkAverage = npkScores.reduce((a, b) => a + b) / npkScores.length;
      weightedSum += npkAverage * _npkWeight;
      weightTotal += _npkWeight;
    }

    final double? sensorScore =
        weightTotal == 0 ? null : weightedSum / weightTotal;

    final double? cropScore = _cropHealthScore();

    if (sensorScore != null && cropScore != null) {
      // The sensor score already aggregates every live reading, so it
      // carries more weight than the single crop-health status.
      return (sensorScore * 0.6) + (cropScore * 0.4);
    }
    if (sensorScore != null) return sensorScore;
    if (cropScore != null) return cropScore;
    return 0.0;
  }

  // Overall health score (same weighted formula as before) shown as a
  // ring gauge, next to an "Active alerts" card.
  Widget _buildTopInsightCards() {
    final bool hasData = _sensorData.isNotEmpty;
    final double score = hasData ? _computeOverallHealthScore().clamp(0, 100) : 0;

    final String statusText;
    final Color statusColor;
    if (!hasData) {
      statusText = 'No data';
      statusColor = Colors.grey;
    } else if (score >= 75) {
      statusText = 'Healthy';
      statusColor = AppColors.healthy;
    } else if (score >= 45) {
      statusText = 'Caution';
      statusColor = AppColors.caution;
    } else {
      statusText = 'Critical';
      statusColor = AppColors.critical;
    }

    final alerts = _computeAlertSummary();

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Crop Health (overall score ring) ──
          Expanded(
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              outlineColor: AppColors.emphasisOutline,
              child: Row(
                children: [
                  AppHealthRing(
                    progress: score / 100,
                    color: statusColor,
                    child: Text(
                      hasData ? '${score.toStringAsFixed(0)}%' : '--',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Crop Health',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // ── Active alerts ──
          Expanded(
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              outlineColor: AppColors.emphasisOutline,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Active alerts',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasData ? '${alerts.total}' : '--',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (hasData) _alertPill(alerts.total, alerts.critical),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Small rounded tag under the alert count: red for critical sensors,
  // amber when there are only cautions, green when everything is optimal.
  Widget _alertPill(int total, int critical) {
    final String text;
    final Color color;
    if (critical > 0) {
      text = '$critical CRITICAL';
      color = AppColors.critical;
    } else if (total > 0) {
      text = '$total CAUTION';
      color = AppColors.caution;
    } else {
      text = 'ALL CLEAR';
      color = AppColors.optimal;
    }

    return AppStatusPill(text: text, color: color);
  }

  // Active alerts = sensors currently outside their optimal range, using
  // the same per-sensor status as the Sensor Overview cards. "critical"
  // counts the ones in the Critical band.
  ({int total, int critical}) _computeAlertSummary() {
    int total = 0;
    int critical = 0;
    for (final def in kSensors) {
      final score =
          _rangeScore(_sensorData[def.key], def.min, def.max, def.tolerance);
      if (score == null) continue;
      final st = _statusFromScore(score);
      if (st == HealthLevel.optimal) continue;
      total++;
      if (st == HealthLevel.critical) critical++;
    }
    return (total: total, critical: critical);
  }

  // ── SENSOR OVERVIEW GRID (mini charts + range status bars) ──
  Widget _buildSensorGrid() {
    if (_isLoading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(AppIcons.offline, size: 52, color: Colors.grey),
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 20),
              AppButton(
                label: 'Retry',
                icon: AppIcons.refresh,
                onPressed: () {
                  setState(() => _isLoading = true);
                  _fetchSensorData();
                },
              ),
            ],
          ),
        ),
      );
    }

    return GridView.count(
      padding: EdgeInsets.zero, // removes the hidden top inset (dead space)
      crossAxisCount: 3,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.7,
      children: kSensors.map((def) {
        final score = _rangeScore(
            _sensorData[def.key], def.min, def.max, def.tolerance);
        return SensorMiniCard(
          def: def,
          value: _parseNum(_sensorData[def.key]),
          score: score,
          status: score == null ? null : _statusFromScore(score),
          series: _history
              .map((r) => _parseNum(r[def.key]))
              .whereType<double>()
              .toList(),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final relative = _formatRelativeReading();

    // The whole page (green header included) lives inside one scroll
    // view, so the header scrolls away with the content. Standard
    // pull-to-refresh: drag down from the top, the spinner follows your
    // finger and drops in just below the status bar.
    return RefreshIndicator(
      color: AppColors.green,
      backgroundColor: Colors.white,
      edgeOffset: MediaQuery.of(context).padding.top,
      displacement: 40,
      onRefresh: _fetchSensorData,
      child: SingleChildScrollView(
        // Always scrollable so pull-to-refresh also works when the
        // content fits on screen.
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // GREEN HEADER, top part: app title + account icon, greeting.
            Container(
              color: AppColors.green,
              padding: const EdgeInsets.only(
                top: 60,
                left: 20,
                right: 20,
                bottom: 14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(AppIcons.plant,
                          color: Colors.white, size: 26),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'HarBest: Dashboard',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.deepGreen,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const UserAccount()),
                          );
                        },
                        behavior: HitTestBehavior.opaque,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            AppIcons.account,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Small gap so the greeting sits right under the title.
                  const SizedBox(height: 2),
                  Text(
                    '${_greetingForNow()}, ${_userFirstName()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.darkGreen,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    "Let's grow your crop!",
                    style: TextStyle(
                      color: AppColors.darkGreen,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            // GREEN HEADER, lower part: the green band ends at the vertical
            // middle of the plant picture. Measured from the card's top:
            // 1.5px border + 14px padding + half of the 160px image.
            Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 1.5 + 14 + 80,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppColors.green,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(50),
                        bottomRight: Radius.circular(50),
                      ),
                    ),
                  ),
                ),
                _buildCropImageCard(),
              ],
            ),

            // PAGE CONTENT (20px side margins)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopInsightCards(),
                  const SizedBox(height: 25),
                  const Text(
                    'Sensor Overview',
                    style: AppText.sectionTitle,
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Your crop sensor readings',
                    style: AppText.subtitle,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Last reading: ${_formatLastReading()}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  if (relative.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        relative,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black45,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  _buildSensorGrid(),
                  const SizedBox(height: 15),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SENSOR MINI CARD: value, mini chart, range % bar, status label
// ─────────────────────────────────────────────
class SensorMiniCard extends StatelessWidget {
  final SensorDef def;
  final double? value;
  final double? score; // 0–100 closeness to the optimal range
  final HealthLevel? status;
  final List<double> series;

  const SensorMiniCard({
    super.key,
    required this.def,
    required this.value,
    required this.score,
    required this.status,
    required this.series,
  });

  @override
  Widget build(BuildContext context) {
    final color = status?.color ?? Colors.grey;
    final valueText = value == null
        ? '--'
        : '${value!.toStringAsFixed(def.decimals)}${def.unit}';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  def.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
              ),
              Icon(def.icon, size: 15, color: AppColors.green),
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valueText,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 4),
          // Mini chart
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: double.infinity,
                child: CustomPaint(
                  painter: _SparklinePainter(
                    values: series,
                    color: color,
                    optimalMin: def.min,
                    optimalMax: def.max,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Percentage bar
          AppProgressBar(value: (score ?? 0) / 100, color: color, height: 5),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                status?.label ?? 'No data',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                score == null ? '' : '${score!.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // Optimal range (shrinks to fit on narrow cards)
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'Optimal: ${def.optimalText}',
              maxLines: 1,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                color: Colors.black45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Tiny line chart with a soft fill and a faint band marking the sensor's
// optimal range.
class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double optimalMin;
  final double optimalMax;

  _SparklinePainter({
    required this.values,
    required this.color,
    required this.optimalMin,
    required this.optimalMax,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = color.withOpacity(0.06),
    );

    if (values.isEmpty) return;

    // Include the optimal band in the y-scale so it's always visible.
    double lo = values.reduce((a, b) => a < b ? a : b);
    double hi = values.reduce((a, b) => a > b ? a : b);
    lo = lo < optimalMin ? lo : optimalMin;
    hi = hi > optimalMax ? hi : optimalMax;
    if (hi - lo < 1e-9) {
      hi += 1;
      lo -= 1;
    }
    const pad = 3.0;
    double yOf(double v) =>
        size.height - pad - ((v - lo) / (hi - lo)) * (size.height - pad * 2);

    // Optimal band
    canvas.drawRect(
      Rect.fromLTRB(0, yOf(optimalMax), size.width, yOf(optimalMin)),
      Paint()..color = AppColors.optimal.withOpacity(0.12),
    );

    if (values.length < 2) {
      canvas.drawCircle(
          Offset(size.width / 2, yOf(values.first)), 2.5, Paint()..color = color);
      return;
    }

    final dx = size.width / (values.length - 1);
    final line = Path()..moveTo(0, yOf(values.first));
    for (var i = 1; i < values.length; i++) {
      line.lineTo(dx * i, yOf(values[i]));
    }

    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withOpacity(0.15));

    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawCircle(
      Offset(size.width, yOf(values.last)),
      2.6,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.values != values || old.color != color;
}