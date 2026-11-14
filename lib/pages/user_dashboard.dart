import 'dart:async';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/services/crop_services.dart';
import 'package:flutter_application_harbest_1/services/device_status.dart';
import 'package:flutter_application_harbest_1/services/supabase_claim.dart';
import 'package:flutter_application_harbest_1/widgets/app_bottom_nav.dart';
import 'package:flutter_application_harbest_1/widgets/app_button.dart';
import 'package:flutter_application_harbest_1/widgets/app_card.dart';
import 'package:flutter_application_harbest_1/widgets/app_empty_state.dart';
import 'package:flutter_application_harbest_1/widgets/app_snackbar.dart';
import 'package:flutter_application_harbest_1/widgets/device_status_widgets.dart';
import 'package:flutter_application_harbest_1/widgets/plant_image.dart';
import 'package:flutter_application_harbest_1/widgets/status_widgets.dart';
import 'package:flutter_application_harbest_1/pages/add_crop.dart';
import 'package:flutter_application_harbest_1/pages/user_account.dart';
import 'package:flutter_application_harbest_1/analytics/analytics_data.dart';
import 'package:flutter_application_harbest_1/plant_profile/profile.dart';
import 'package:flutter_application_harbest_1/plant_profile/harvest_dialog.dart';
import 'package:flutter_application_harbest_1/plant_profile/harvest_service.dart';
import 'package:flutter_application_harbest_1/forecasting/model_forecasting.dart';
import 'package:flutter_application_harbest_1/notification/alerts.dart';

// ═════════════════════════════════════════════════════════════════════════
// 1. APP SHELL — entry widget and bottom navigation
// ═════════════════════════════════════════════════════════════════════════

// App initialization (Firebase, Supabase) and the root MaterialApp live in
// main.dart. This wrapper is kept so existing Navigator.push(...) /
// pushAndRemoveUntil(...) calls elsewhere in the app don't need to change.
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

  late final List<Widget> _pages = [
    DashboardScreen(onNavigateToProfile: () => _goTo(2)),
    const AiAnalytics(),
    const PlantProfilePage(),
    const AiForecasting(),
    const AlertsPage(),
  ];

  @override
  void initState() {
    super.initState();
    currentTab.value = 0;
    () async {
      await ensureSupabaseClaim();
      await CropService.instance.load();
    }();
  }

  // Also tells the pages which tab is on screen (for the "no internet"
  // snackbar).
  void _goTo(int index) {
    setState(() => _selectedIndex = index);
    currentTab.value = index;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _selectedIndex,
        onTap: _goTo,
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// 2. SENSOR DEFINITIONS — ranges used by the cards and the health score
// ═════════════════════════════════════════════════════════════════════════

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
    key: 'pH',
    label: 'Soil pH',
    unit: '',
    icon: AppIcons.soilPh,
    min: 6.0,
    max: 7.5,
    tolerance: 1.5,
    optimalText: '6.0 – 7.5',
  ),
  SensorDef(
    key: 'moisture',
    label: 'Moisture',
    unit: '%',
    icon: AppIcons.moisture,
    min: 60,
    max: 80,
    tolerance: 30,
    optimalText: '60% – 80%',
    decimals: 0,
  ),
  SensorDef(
    key: 'temperature',
    label: 'Temp',
    unit: '°C',
    icon: AppIcons.temperature,
    min: 15,
    max: 25,
    tolerance: 10,
    optimalText: '15°C – 24°C',
  ),
  SensorDef(
    key: 'humidity',
    label: 'Humidity',
    unit: '%',
    icon: AppIcons.humidity,
    min: 60,
    max: 80,
    tolerance: 25,
    optimalText: '60% – 80%',
    decimals: 0,
  ),
  // NOAA NWS heat index chart: "Caution" band begins at 27°C.
  SensorDef(
    key: 'heat_index',
    label: 'Heat Index',
    unit: '°C',
    icon: AppIcons.heatIndex,
    min: 0,
    max: 27,
    tolerance: 12,
    optimalText: 'Below 27°C',
  ),
  // Hartatie et al. 2025 (pakcoy mustard, hydroponic): EC 0.8–2.4 mS/cm
  // tested, best growth at 2.0. NOTE: this is a nutrient-solution range;
  // an in-soil probe reads bulk EC, which runs well below solution EC.
  SensorDef(
    key: 'EC',
    label: 'EC',
    unit: ' mS/cm',
    icon: AppIcons.conductivity,
    min: 1.2,
    max: 2.4,
    tolerance: 1.0,
    optimalText: '1.2 – 2.4 mS/cm',
    decimals: 2,
  ),
  // UW–Madison Extension garden soil-test ideal ranges (N, P, K).
  SensorDef(
    key: 'nitrogen',
    label: 'Nitrogen',
    unit: '',
    icon: AppIcons.nitrogen,
    min: 30,
    max: 3000,
    tolerance: 30,
    optimalText: '30+ mg/kg',
    decimals: 0,
  ),
  SensorDef(
    key: 'phosphorus',
    label: 'Phosphorus',
    unit: '',
    icon: AppIcons.phosphorus,
    min: 20,
    max: 3000,
    tolerance: 20,
    optimalText: '20+ mg/kg',
    decimals: 0,
  ),
  SensorDef(
    key: 'potassium',
    label: 'Potassium',
    unit: '',
    icon: AppIcons.potassium,
    min: 20,
    max: 3000,
    tolerance: 20,
    optimalText: '20+ mg/kg',
    decimals: 0,
  ),
];

/// The Pi stores EC in µS/cm; the app shows it in mS/cm.
Map<String, dynamic> normalizeReading(Map<String, dynamic> row) {
  final ec = row['EC'];
  final v = ec is num ? ec.toDouble() : double.tryParse('$ec');
  if (v == null) return row;
  return {...row, 'EC': v / 1000};
}

// ═════════════════════════════════════════════════════════════════════════
// 3. DASHBOARD SCREEN
// ═════════════════════════════════════════════════════════════════════════

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onNavigateToProfile;

  const DashboardScreen({super.key, this.onNavigateToProfile});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with OfflineNotice<DashboardScreen> {
  // ─────────────────────────── CONSTANTS ───────────────────────────

  static const int _historyLength = 10;

  // Put your picture at this path and list it under `assets:` in pubspec.yaml.
  static const String _headerImage = 'assets/urban_garden.jpg';

  // The crop card sits in a fixed-height slot so the picture can end at the
  // vertical middle of the plant photo (14px card padding + half of 160px).
  static const double _cropCardHeight = 230;
  static const double _headerOverlap = 14 + 80;

  // White text with a soft shadow so it stays readable on any picture.
  static const List<Shadow> _onPhotoShadow = [
    Shadow(
      color: Color.fromARGB(255, 13, 61, 13),
      blurRadius: 10,
      offset: Offset(1, 1),
    ),
  ];

  // Shared by the harvest banner and the "Last reading" banner.
  static final BoxDecoration _bannerDecoration = BoxDecoration(
    color: AppColors.green.withValues(alpha: 0.35),
    borderRadius: BorderRadius.circular(AppRadius.field),
  );

  // Overall health weights (sum to 100%): moisture 25%, pH 20%,
  // NPK (combined) 20%, temperature 15%, humidity 10%, heat index 5%,
  // EC 5%. Weights are renormalized by whatever is present, so a missing
  // sensor never drags the score down. Ranges come from [kSensors].
  //
  // EC is scored on both sides of its range: too low means too few
  // dissolved nutrients, too high means salt stress (FAO/Maas & Grattan
  // rate leafy brassicas "moderately sensitive" to salinity). Its weight is
  // kept small because low-cost NPK probes estimate N, P and K from the
  // same conductivity reading, so EC is already partly counted via NPK.
  static const Map<String, double> _scoreWeights = {
    'pH': 0.20,
    'moisture': 0.25,
    'temperature': 0.15,
    'humidity': 0.10,
    'heat_index': 0.05,
    'EC': 0.05,
  };

  // Nitrogen, phosphorus and potassium are averaged into one "NPK" factor.
  static const Set<String> _npkKeys = {'nitrogen', 'phosphorus', 'potassium'};
  static const double _npkWeight = 0.20;

  // ─────────────────────────── SERVICES ───────────────────────────

  final String _uid = FirebaseAuth.instance.currentUser!.uid;
  final _supabase = Supabase.instance.client;

  // ─────────────────────────── STATE ───────────────────────────

  // Which crop/device is on screen.
  String? _deviceId;
  String? _cropId;
  bool _initialized = false;
  String? _freeDeviceId; // a device of yours with no active crop

  // Sensor readings.
  Map<String, dynamic> _sensorData = {};
  // Oldest → newest. Feeds the mini charts in the Sensor Overview cards.
  List<Map<String, dynamic>> _history = [];
  String? _error;

  // Latest heartbeat row from `device_status` (null until the Pi runs the
  // updated script; the status then falls back to the last reading time).
  DeviceStatus? _deviceStatus;
  // Feeds the status pill's details sheet so it updates while open.
  final ValueNotifier<DeviceStatusView> _statusView = ValueNotifier(
    const DeviceStatusView(),
  );

  // Realtime channels.
  RealtimeChannel? _sensorChannel;
  RealtimeChannel? _statusChannel;

  // Full name from the same Firestore record the My Account page edits
  // (users/{uid}.fullName). Listening to snapshots means the greeting
  // updates right after the name is changed there.
  String _fullName = '';
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _nameSub;

  // Timers.
  Timer? _refreshTimer;
  // Rebuilds the screen on a fixed interval purely so the "time ago" text
  // keeps counting up, independent of whether new sensor data arrives.
  Timer? _relativeTimeTicker;

  // ─────────────────────────── LIFECYCLE ───────────────────────────

  @override
  void initState() {
    super.initState();
    _listenToUserName();
    CropService.instance.addListener(_onCropChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onCropChanged());
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refreshAll(),
    );
    _relativeTimeTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() {});
      _syncStatusView(); // Online → Delayed → Offline as time passes
    });
  }

  @override
  void dispose() {
    CropService.instance.removeListener(_onCropChanged);
    _refreshTimer?.cancel();
    _relativeTimeTicker?.cancel();
    _nameSub?.cancel();
    unawaited(_closeLiveUpdates());
    _statusView.dispose();
    super.dispose();
  }

  // ─────────────────────────── NO INTERNET (OfflineNotice) ───────────────────────────

  @override
  int get tabIndex => 0;

  @override
  bool get hasLastData => _sensorData.isNotEmpty;

  @override
  void onBackOnline() {
    _reconnectLiveUpdates();
    _refreshAll();
  }

  // ─────────────────────────── CROP SELECTION ───────────────────────────

  // Runs when the user's crops finish loading, or they pick another crop.
  void _onCropChanged() {
    if (!mounted) return;
    final svc = CropService.instance;
    if (!svc.loaded) return;
    final id = svc.selected?.deviceId;

    _checkHarvest();
    _loadFreeDevice();
    // Crop list could not load (e.g. offline at start-up): say so now.
    if (svc.offline) markConnection(false);
    final cropId = svc.selected?.id;
    if (_initialized && id == _deviceId) {
      if (cropId != _cropId) {
        // Another crop on the same device: start from a clean screen.
        _cropId = cropId;
        setState(() {
          _sensorData = {};
          _history = [];
          _error = null;
        });
        _fetchSensorData();
        _fetchDeviceStatus();
      } else {
        setState(() {}); // same crop, just refresh name/image
      }
      _syncStatusView();
      return;
    }
    _initialized = true;
    _cropId = cropId;
    _deviceId = id;
    unawaited(_closeLiveUpdates());
    setState(() {
      _sensorData = {};
      _history = [];
      _error = null;
      _deviceStatus = null;
    });
    _syncStatusView();
    if (id != null) {
      _fetchSensorData();
      _subscribeToSensor(id);
      _fetchDeviceStatus();
      _subscribeToDeviceStatus(id);
    }
  }

  Future<void> _loadFreeDevice() async {
    try {
      final rows = await _supabase.from('devices').select('device_id');
      final used = CropService.instance.crops.map((c) => c.deviceId).toSet();
      String? free;
      for (final r in rows as List) {
        final id = r['device_id'] as String;
        if (!used.contains(id)) {
          free = id;
          break;
        }
      }
      if (mounted) setState(() => _freeDeviceId = free);
    } catch (_) {}
  }

  // Harvest reminder: once per app open, never when snoozed to a later day.
  Future<void> _checkHarvest() async {
    final crop = CropService.instance.selected;
    if (crop == null || !HarvestService.shouldPrompt(crop)) return;
    HarvestService.markPrompted(crop);
    if (await HarvestService.isSnoozed(crop)) return;
    if (!mounted) return;
    showHarvestDialog(context, crop);
  }

  // ─────────────────────────── REFRESH ───────────────────────────

  // Pull-to-refresh passes [userAction] so it always answers with a
  // snackbar when there is no internet. If the crop list itself could not
  // load (offline at start-up), it is retried first.
  Future<void> _refreshAll({bool userAction = false}) async {
    if (CropService.instance.offline) {
      await CropService.instance.load();
      if (!mounted) return;
      if (CropService.instance.offline && _deviceId == null) {
        markConnection(false, userAction: userAction);
        return;
      }
    }
    await Future.wait([
      _fetchSensorData(userAction: userAction),
      _fetchDeviceStatus(),
    ]);
  }

  // ─────────────────────────── SENSOR READINGS ───────────────────────────

  static List<Map<String, dynamic>> _normalizeRows(List raw) => [
    for (final e in raw) normalizeReading(Map<String, dynamic>.from(e)),
  ];

  // Shows rows that are ordered newest → oldest.
  void _showRows(List<Map<String, dynamic>> rows) {
    setState(() {
      _sensorData = rows.first;
      _history = rows.reversed.toList();
      _error = null;
    });
    _syncStatusView();
  }

  Future<void> _fetchSensorData({bool userAction = false}) async {
    final deviceId = _deviceId;
    if (deviceId == null) return;
    try {
      final response = await _supabase
          .from('sensor_readings')
          .select()
          .eq('device_id', deviceId)
          .order('timestamp', ascending: false)
          .limit(_historyLength)
          .timeout(kRequestTimeout);

      if (!mounted || deviceId != _deviceId) return; // crop switched meanwhile

      markConnection(true);
      LastData.save('dashboard_readings_$deviceId', response);

      final rows = _normalizeRows(response as List);
      if (rows.isEmpty) {
        setState(() {
          _sensorData = {};
          _history = [];
          _error = "No sensor data found for this crop yet.";
        });
        return;
      }
      _showRows(rows);
    } catch (e) {
      debugPrint("Supabase fetch error: $e");
      if (!mounted || deviceId != _deviceId) return;
      final connectionError = isConnectionError(e);
      // No internet and nothing on screen yet (e.g. the app was opened
      // offline): show the readings saved on the phone.
      if (_sensorData.isEmpty && connectionError) {
        await _showSavedReadings(deviceId);
        if (!mounted || deviceId != _deviceId) return;
      }
      // The last readings stay on screen; only the message changes.
      if (_sensorData.isEmpty) {
        setState(() {
          _error = "Couldn't load sensor data. Check your connection.";
        });
      }
      if (connectionError) {
        markConnection(false, userAction: userAction);
      }
    }
  }

  Future<void> _showSavedReadings(String deviceId) async {
    final saved = await LastData.read('dashboard_readings_$deviceId');
    if (!mounted || deviceId != _deviceId || _sensorData.isNotEmpty) return;
    if (saved is! List || saved.isEmpty) return;
    try {
      _showRows(_normalizeRows(saved));
    } catch (e) {
      debugPrint('Saved readings unreadable: $e');
    }
  }

  void _subscribeToSensor(String deviceId) {
    _sensorChannel = _supabase
        .channel('sensor_readings_$deviceId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'sensor_readings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'device_id',
            value: deviceId,
          ),
          callback: (payload) {
            if (!mounted) return;
            final row = normalizeReading(
              Map<String, dynamic>.from(payload.newRecord),
            );
            setState(() {
              _sensorData = row;
              _history = [..._history, row];
              if (_history.length > _historyLength) {
                _history = _history.sublist(_history.length - _historyLength);
              }
              _error = null;
            });
            _syncStatusView();
          },
        )
        .subscribe();
  }

  // ─────────────────────────── DEVICE STATUS ───────────────────────────

  Future<void> _fetchDeviceStatus() async {
    final deviceId = _deviceId;
    if (deviceId == null) return;
    try {
      final row = await _supabase
          .from('device_status')
          .select()
          .eq('device_id', deviceId)
          .maybeSingle()
          .timeout(kRequestTimeout);
      if (!mounted || deviceId != _deviceId) return;
      setState(() {
        _deviceStatus = row == null ? null : DeviceStatus.fromMap(row);
      });
      _syncStatusView();
    } catch (e) {
      // Table not created yet, or offline: keep the reading-based fallback.
      debugPrint('device_status fetch error: $e');
    }
  }

  void _subscribeToDeviceStatus(String deviceId) {
    _statusChannel = _supabase
        .channel('device_status_$deviceId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'device_status',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'device_id',
            value: deviceId,
          ),
          callback: (payload) {
            if (!mounted || deviceId != _deviceId) return;
            final row = payload.newRecord;
            if (row.isEmpty) return;
            setState(() {
              _deviceStatus = DeviceStatus.fromMap(
                Map<String, dynamic>.from(row),
              );
            });
            _syncStatusView();
          },
        )
        .subscribe();
  }

  DeviceStatusView _currentStatusView() => DeviceStatusView(
    deviceId: _deviceId,
    cropName: CropService.instance.selected?.name,
    status: _deviceStatus,
    lastReading: _lastReadingAsLocal(),
  );

  void _syncStatusView() {
    if (mounted) _statusView.value = _currentStatusView();
  }

  // ─────────────────────────── LIVE UPDATES ───────────────────────────

  // Live updates can drop while offline; open them again for this device.
  Future<void> _reconnectLiveUpdates() async {
    final id = _deviceId;
    if (id == null) return;
    await _closeLiveUpdates();
    if (!mounted || id != _deviceId) return;
    _subscribeToSensor(id);
    _subscribeToDeviceStatus(id);
  }

  // Removes both realtime channels (if open) and clears the references.
  Future<void> _closeLiveUpdates() async {
    final sensor = _sensorChannel, status = _statusChannel;
    _sensorChannel = null;
    _statusChannel = null;
    await Future.wait([
      if (sensor != null) _supabase.removeChannel(sensor),
      if (status != null) _supabase.removeChannel(status),
    ]);
  }

  // ─────────────────────────── USER NAME & GREETING ───────────────────────────

  void _listenToUserName() {
    _nameSub = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .snapshots()
        .listen((doc) {
          final data = doc.data();
          final name =
              ((data?['name'] ?? data?['fullName']) as String?)?.trim() ?? '';
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

  // "Good Morning" (before 12:00), "Good Afternoon" (12:00–17:59),
  // "Good Evening" (18:00 onward), based on the device's local time.
  String _greetingForNow() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 18) return 'Good Afternoon';
    return 'Good Evening';
  }

  // ─────────────────────────── LAST READING TIMESTAMP ───────────────────────────

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

  // The stored clock fields (e.g. 12:03) are already the real local time
  // but labeled +00, so we rebuild them as a LOCAL DateTime before
  // comparing against DateTime.now().
  DateTime? _lastReadingAsLocal() {
    final utc = _lastReadingDateTime();
    if (utc == null) return null;
    return DateTime(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
      utc.second,
    );
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

  // Human-friendly "time ago", e.g. "Just now", "5 minutes ago",
  // "3 hours ago", "2 days ago".
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

  // ─────────────────────────── SCORING ───────────────────────────
  // Every sensor is scored once per build (see [_sensorScores]); the health
  // ring, the alert count and the sensor cards all read from that map.

  double? _parseNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  // Scores a single sensor reading against its optimal range: 100
  // inside the range, tapering down the further outside it falls,
  // reaching 0 once the deviation reaches `tolerance`.
  double? _rangeScore(SensorDef def) {
    final value = _parseNum(_sensorData[def.key]);
    if (value == null) return null;
    if (value >= def.min && value <= def.max) return 100.0;
    final deviation = value < def.min ? def.min - value : value - def.max;
    if (deviation >= def.tolerance) return 0.0;
    return 100.0 * (1 - deviation / def.tolerance);
  }

  /// Score per sensor key, in [kSensors] order (null = no reading).
  Map<String, double?> _sensorScores() => {
    for (final def in kSensors) def.key: _rangeScore(def),
  };

  // Optimal: inside the range. Caution: outside it, but less than halfway
  // to the tolerance limit (score >= 50). Critical: beyond that.
  HealthLevel _statusFromScore(double score) {
    if (score >= 100) return HealthLevel.optimal;
    if (score >= 50) return HealthLevel.caution;
    return HealthLevel.critical;
  }

  // crop_health may come through as a numeric score (0-100) or as one
  // of the status strings the Pi reports.
  double? _cropHealthScore() {
    final raw = _sensorData['crop_health'];
    if (raw == null) return null;

    final asNum = _parseNum(raw);
    if (asNum != null) return asNum.clamp(0.0, 100.0);

    final status = raw.toString().toLowerCase().trim();
    if (status.contains('optimal')) return 95.0;
    if (status.contains('critical')) return 15.0;
    if (status.contains('warning')) return 55.0;
    return null; // Unrecognized status text — skip it.
  }

  double _computeOverallHealthScore(Map<String, double?> scores) {
    double weightedSum = 0.0;
    double weightTotal = 0.0;
    double npkSum = 0.0;
    int npkCount = 0;

    for (final MapEntry(:key, value: score) in scores.entries) {
      if (score == null) continue;
      final weight = _scoreWeights[key];
      if (weight != null) {
        weightedSum += score * weight;
        weightTotal += weight;
      } else if (_npkKeys.contains(key)) {
        npkSum += score;
        npkCount++;
      }
    }

    if (npkCount > 0) {
      weightedSum += (npkSum / npkCount) * _npkWeight;
      weightTotal += _npkWeight;
    }

    final double? sensorScore = weightTotal == 0
        ? null
        : weightedSum / weightTotal;

    final double? cropScore = _cropHealthScore();

    if (sensorScore != null && cropScore != null) {
      return (sensorScore * 0.6) + (cropScore * 0.4);
    }
    return sensorScore ?? cropScore ?? 0.0;
  }

  // Active alerts = sensors currently outside their optimal range.
  ({int total, int critical}) _computeAlertSummary(
    Map<String, double?> scores,
  ) {
    int total = 0;
    int critical = 0;
    for (final score in scores.values) {
      if (score == null) continue;
      final st = _statusFromScore(score);
      if (st == HealthLevel.optimal) continue;
      total++;
      if (st == HealthLevel.critical) critical++;
    }
    return (total: total, critical: critical);
  }

  // ─────────────────────────── SHEETS ───────────────────────────

  void _openDeviceStatus() {
    _syncStatusView();
    showDeviceStatusSheet(context, _statusView);
  }

  void _openCropSwitcher() {
    final svc = CropService.instance;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.dialog),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text('Switch crop', style: AppText.cardTitle),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in svc.crops)
                      ListTile(
                        leading: const Icon(
                          AppIcons.plant,
                          color: AppColors.green,
                        ),
                        title: Text(c.name, style: AppText.body),
                        subtitle: Text(
                          c.deviceId,
                          style: AppText.caption.copyWith(fontSize: 12),
                        ),
                        trailing: svc.selected?.id == c.id
                            ? const Icon(AppIcons.check, color: AppColors.green)
                            : null,
                        onTap: () {
                          svc.select(c);
                          Navigator.pop(ctx);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════ UI (top of screen → bottom) ═══════════════════════════

  @override
  Widget build(BuildContext context) {
    final relative = _formatRelativeReading();
    final scores = _sensorScores();

    return RefreshIndicator(
      color: AppColors.green,
      backgroundColor: Colors.white,
      edgeOffset: MediaQuery.of(context).padding.top,
      displacement: 40,
      onRefresh: () => _refreshAll(userAction: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        // Gray page so the white cards stand out.
        child: ColoredBox(
          color: AppColors.background,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // PICTURE HEADER + crop card
              _buildHeader(),

              // PAGE CONTENT (20px side margins)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ..._buildHarvestBanner(),
                    _buildTopInsightCards(scores),
                    const SizedBox(height: 25),
                    _buildSensorOverviewTitle(),
                    const SizedBox(height: 12),
                    _buildLastReadingBanner(relative),
                    const SizedBox(height: 14),
                    _buildSensorGrid(scores),
                    const SizedBox(height: 15),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 1. HEADER: picture behind, texts + crop switcher + crop card in front ──

  /// The picture ends at the middle of the plant photo (see [_headerOverlap]).
  Widget _buildHeader() {
    final showSwitcher = CropService.instance.crops.length > 1;

    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          bottom: _cropCardHeight - _headerOverlap,
          child: _buildHeaderPicture(),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeaderTexts(),
            if (showSwitcher) _buildCropSwitcherButton(),
            SizedBox(height: _cropCardHeight, child: _buildCropImageCard()),
          ],
        ),
      ],
    );
  }

  /// Picture + dark fade behind the header text, from the top of the screen
  /// down to the middle of the plant photo, with rounded bottom corners.
  Widget _buildHeaderPicture() {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(50),
        bottomRight: Radius.circular(50),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            _headerImage,
            fit: BoxFit.cover,
            // Plain green if the picture is missing, so the page still works.
            errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.green),
          ),
          // Darkens the top where the text sits, fades out toward the bottom.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.55),
                  Colors.black.withValues(alpha: 0.28),
                  Colors.black.withValues(alpha: 0.05),
                ],
                stops: const [0, 0.55, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderTexts() {
    return Padding(
      padding: const EdgeInsets.only(top: 60, left: 20, right: 20, bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'HarBest: Dashboard',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                    shadows: _onPhotoShadow,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const UserAccount()),
                  );
                },
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    AppIcons.account,
                    color: Colors.white,
                    size: 35,
                    shadows: _onPhotoShadow,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${_greetingForNow()}, ${_userFirstName()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            "Let's grow your crop!",
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              shadows: _onPhotoShadow,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCropSwitcherButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 14),
      child: Center(
        child: GestureDetector(
          onTap: _openCropSwitcher,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(
                    CropService.instance.selected?.name ?? 'Choose crop',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  AppIcons.expand,
                  size: 16,
                  color: AppColors.textPrimary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCropImageCard() {
    final crop = CropService.instance.selected;
    final imageUrl = crop?.imageUrl ?? _sensorData['image_url'] as String?;
    final plantName = crop?.name ?? 'No crop yet';

    return Center(
      child: GestureDetector(
        onTap: crop == null ? null : () => widget.onNavigateToProfile?.call(),
        child: AppCard(
          radius: 20,
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              crop == null
                  ? Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        color: AppColors.track,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        AppIcons.plant,
                        size: 56,
                        color: AppColors.textTertiary,
                      ),
                    )
                  : PlantImage(imageUrl: imageUrl, size: 160),
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
                  if (crop != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: AppColors.darkGreen,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        AppIcons.forward,
                        color: Colors.white,
                        size: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 2. HARVEST BANNER ──

  // Stays on the dashboard while the crop is due, so the dialog can be
  // reopened after it was closed.
  List<Widget> _buildHarvestBanner() {
    final crop = CropService.instance.selected;
    if (crop == null ||
        crop.ownerUid != FirebaseAuth.instance.currentUser?.uid ||
        !HarvestService.isDue(crop)) {
      return const [];
    }
    return [
      GestureDetector(
        onTap: () => showHarvestDialog(context, crop),
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: _bannerDecoration,
          child: Row(
            children: [
              const Icon(AppIcons.harvest, color: AppColors.textPrimary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${crop.name} is ready to harvest',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Text(
                      'Tap to review and harvest',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                AppIcons.forward,
                size: 16,
                color: AppColors.textPrimary,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  // ── 3. CROP CONDITION + ACTIVE ALERTS ──

  // Overall health ring + "Active alerts" card. Gray, no border.
  Widget _buildTopInsightCards(Map<String, double?> scores) {
    final bool hasData = _sensorData.isNotEmpty;
    final double score = hasData
        ? _computeOverallHealthScore(scores).clamp(0, 100)
        : 0;

    final String statusText;
    final Color statusColor;
    if (!hasData) {
      statusText = 'No data';
      statusColor = Colors.grey;
    } else if (score >= 75) {
      statusText = 'Good';
      statusColor = AppColors.healthy;
    } else if (score >= 45) {
      statusText = 'Caution';
      statusColor = AppColors.caution;
    } else {
      statusText = 'Critical';
      statusColor = AppColors.critical;
    }

    final alerts = _computeAlertSummary(scores);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Crop Condition (overall score ring) ──
          Expanded(
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
                            'Crop Condition',
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

  // Small rounded tag under the alert count.
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

  // ── 4. SENSOR OVERVIEW: title, last reading, grid ──

  /// Icon tile + title + device status pill.
  Widget _buildSensorOverviewTitle() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.darkGreen,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(AppIcons.sensors, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sensor Overview', style: AppText.sectionTitle),
              SizedBox(height: 2),
            ],
          ),
        ),
        // Battery: small icon + "73%" beside the status pill. Only shown
        // once the Pi has reported a battery level. Tap -> volts / state.
        if (_deviceId != null && (_deviceStatus?.hasBattery ?? false)) ...[
          BatteryBadge(
            status: _deviceStatus!,
            connection: _currentStatusView().connection,
          ),
          const SizedBox(width: 8),
        ],
        if (_deviceId != null)
          DeviceStatusPill(
            connection: _currentStatusView().connection,
            onTap: _openDeviceStatus,
          ),
      ],
    );
  }

  /// Light-green banner: bold "Last reading" line, "x ago" under it.
  Widget _buildLastReadingBanner(String relative) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: _bannerDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Last reading: ${_formatLastReading()}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (relative.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              relative,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSensorGrid(Map<String, double?> scores) {
    final svc = CropService.instance;
    if (svc.loaded && svc.selected == null) {
      if (!svc.offline && _freeDeviceId != null) {
        return _buildStartNewCrop(_freeDeviceId!);
      }
      return SizedBox(
        height: 280,
        child: svc.offline
            ? const AppOfflineState()
            : const AppNoCropState(showButton: true),
      );
    }

    if (_error != null &&
        _sensorData.isEmpty &&
        _error!.startsWith('No sensor data')) {
      final online = _currentStatusView().connection == DeviceConnection.online;
      return SizedBox(
        height: 200,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(AppIcons.plant, size: 52, color: Colors.grey),
                const SizedBox(height: 10),
                Text(
                  online
                      ? 'Your device is online.\nWaiting for the first reading.'
                      : 'Waiting for the first reading.\nMake sure your device is switched on and connected.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GridView.count(
      padding: EdgeInsets.zero,
      crossAxisCount: 3,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.7,
      children: [
        for (final def in kSensors)
          SensorMiniCard(
            def: def,
            value: _parseNum(_sensorData[def.key]),
            score: scores[def.key],
            status: scores[def.key] == null
                ? null
                : _statusFromScore(scores[def.key]!),
            series: _history
                .map((r) => _parseNum(r[def.key]))
                .whereType<double>()
                .toList(),
          ),
      ],
    );
  }

  // Shown in place of the grid when a device of yours has no active crop.
  Widget _buildStartNewCrop(String deviceId) {
    return SizedBox(
      height: 280,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(AppIcons.plant, size: 56, color: Colors.black26),
              const SizedBox(height: AppSpace.cardGap),
              Text(
                'Your device is ready for a new crop.',
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              AppButton(
                label: 'Start a new crop',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddCropPage(deviceId: deviceId),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// 4. SENSOR MINI CARD — label, value, mini chart, range % bar, status label
//    Gray card, no border, no shadow.
// ═════════════════════════════════════════════════════════════════════════

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
              Icon(def.icon, size: 15, color: AppColors.darkGreen),
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valueText,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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

// ═════════════════════════════════════════════════════════════════════════
// 5. SPARKLINE PAINTER — tiny line chart with a soft fill and a faint band
//    marking the sensor's optimal range
// ═════════════════════════════════════════════════════════════════════════

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double optimalMin;
  final double optimalMax;

  const _SparklinePainter({
    required this.values,
    required this.color,
    required this.optimalMin,
    required this.optimalMax,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // White plate behind the chart so it reads clearly on the gray card.
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = color.withValues(alpha: 0.06),
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
      Paint()..color = AppColors.optimal.withValues(alpha: 0.12),
    );

    if (values.length < 2) {
      canvas.drawCircle(
        Offset(size.width / 2, yOf(values.first)),
        2.5,
        Paint()..color = color,
      );
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
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.15));

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

  // The series list is rebuilt on every build, so compare contents rather
  // than identity; otherwise every sparkline repaints on every rebuild.
  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.color != color ||
      old.optimalMin != optimalMin ||
      old.optimalMax != optimalMax ||
      !listEquals(old.values, values);
}