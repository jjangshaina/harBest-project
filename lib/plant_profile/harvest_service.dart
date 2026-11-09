// HarBest - harvest reminder logic
//
// File layout (each section only uses what comes before it):
//   1. HarvestInfo           - the numbers the dialog shows
//   2. HarvestService
//      a. Settings           - stage, timeouts, labels, session memory
//      b. Small helpers      - dates, formatting, ranking
//      c. When to prompt     - daysGrown, isDue, shouldPrompt
//      d. Remind me tomorrow - snooze memory
//      e. Numbers and tip    - forecast tip, then load()
//      f. Harvested status   - markHarvested, nextCropName

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_harbest_1/plant_profile/profile.dart'
    show GrowthStage, kGrowthStages;
import 'package:flutter_application_harbest_1/services/crop_services.dart';
import 'package:flutter_application_harbest_1/services/forecast_service.dart';

// ================================================================ 1. data

/// What the harvest dialog shows besides the day count.
class HarvestInfo {
  const HarvestInfo({this.avgHealth, this.alerts, required this.tip});

  /// Average crop-health score (0-100) of the readings in the harvesting
  /// stage. Null when no reading in that stage could be scored.
  final double? avgHealth;

  /// Alerts raised during the harvesting stage. Null when it could not load.
  final int? alerts;

  /// Suggestion taken from the Forecast page.
  final String tip;
}

// ================================================================ 2. service

/// Everything behind the harvest reminder: when it is due, the numbers in it,
/// the tip, the "remind me tomorrow" memory, and saving the harvested status.
class HarvestService {
  HarvestService._();

  // ── a. Settings ──

  /// The reminder follows the LAST stage of the growth timeline
  /// (kGrowthStages in profile.dart), so editing the days there moves it too.
  /// It is due on the last day of that stage (the end of the harvest window).
  /// To remind at the START of the harvest stage instead, use stage.minDay
  /// in [isDue].
  static GrowthStage get stage => kGrowthStages.last;

  static const Duration _timeout = Duration(seconds: 10);
  static const Duration _saveTimeout = Duration(seconds: 15);

  // Forecast variable name -> label shown in the tip.
  static const Map<String, String> _varLabels = {
    'moisture_pct': 'Moisture',
    'pH': 'Soil pH',
    'temperature': 'Temperature',
    'humidity': 'Humidity',
    'EC': 'EC',
  };

  static const String _fallbackTip =
      'Harvest now for the best leaf quality. Open the Forecast tab to see '
      'how conditions are expected to change.';

  /// Trailing number in a crop name, e.g. "Mustard no.1" -> "1".
  static final RegExp _trailingNumber = RegExp(r'^(.*?)(\d+)\s*$');

  /// Crops already prompted during this app launch, so the dialog shows once
  /// per time the app is opened.
  static final Set<String> _promptedThisSession = {};

  static SupabaseClient get _db => Supabase.instance.client;

  // ── b. Small helpers ──

  /// Planting date at midnight, or null when there is none.
  static DateTime? _planted(Crop c) {
    final p = c.plantingDate;
    return p == null ? null : DateTime(p.year, p.month, p.day);
  }

  static int _daysSince(DateTime planted) {
    final d = DateTime.now().difference(planted).inDays;
    return d < 0 ? 0 : d;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _ymd(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
  static String _remindKey(Crop c) => 'harvest_remind_${c.id}';

  /// The Pi stores local clock time labeled as UTC, so the reading window
  /// keeps the same clock fields. Alerts hold real instants.
  static String _fakeUtc(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second).toIso8601String();

  static int _rank(String? status) => switch (status) {
        'out_of_range' => 2,
        'caution' => 1,
        'optimal' => 0,
        _ => -1,
      };

  // ── c. When to prompt ──

  /// Days since the planting date (0 when there is none).
  static int daysGrown(Crop c) {
    final p = _planted(c);
    return p == null ? 0 : _daysSince(p);
  }

  /// True once the crop reaches the last day of the last growth stage.
  static bool isDue(Crop c) {
    final p = _planted(c);
    return p != null && _daysSince(p) >= stage.maxDay;
  }

  /// Only the owner is asked (admins monitoring a crop cannot change it), only
  /// when it is due, and only once per app launch.
  static bool shouldPrompt(Crop c) {
    final me = FirebaseAuth.instance.currentUser?.uid;
    return me != null &&
        c.ownerUid == me &&
        isDue(c) &&
        !_promptedThisSession.contains(c.id);
  }

  static void markPrompted(Crop c) => _promptedThisSession.add(c.id);

  // ── d. Remind me tomorrow ──

  /// True while a "remind me tomorrow" answer is still in effect.
  static Future<bool> isSnoozed(Crop c) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final until = prefs.getString(_remindKey(c));
      if (until == null) return false;
      // Dates are yyyy-MM-dd, so comparing the text compares the days.
      return _ymd(DateTime.now()).compareTo(until) < 0;
    } catch (_) {
      return false;
    }
  }

  static Future<void> remindTomorrow(Crop c) async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_remindKey(c), _ymd(tomorrow));
  }

  // ── e. Numbers and tip ──

  /// The suggested action of the forecast variable in the worst shape, from
  /// the same run the Forecast page shows. Never throws.
  static Future<String> _forecastTip(Crop c) async {
    try {
      final run = await ForecastService.latest(c.deviceId).timeout(_timeout);
      final vars = run?['variables'];
      if (vars is! Map) return _fallbackTip;

      // First variable with the highest rank wins.
      MapEntry<dynamic, Map>? worst;
      var worstRank = -1;
      for (final e in vars.entries) {
        final v = e.value;
        if (v is! Map) continue;
        final r = _rank(v['status'] as String?);
        if (r > worstRank) {
          worstRank = r;
          worst = MapEntry(e.key, v);
        }
      }
      if (worst == null) return _fallbackTip;

      final action = (worst.value['suggested_action'] as String?)?.trim();
      if (action == null || action.isEmpty) return _fallbackTip;
      final name = '${worst.key}';
      return '${_varLabels[name] ?? name}: $action';
    } catch (e) {
      debugPrint('Forecast tip error: $e');
      return _fallbackTip;
    }
  }

  /// Loads the stage numbers and the forecast tip. Never throws: anything
  /// that cannot be loaded comes back as null and the dialog shows "--".
  static Future<HarvestInfo> load(Crop c) async {
    // Start the tip now so it loads at the same time as the stage summary.
    final tip = _forecastTip(c);

    double? health;
    int? alerts;

    final planted = _planted(c);
    if (planted != null) {
      final from = planted.add(Duration(days: stage.minDay));
      var to = planted.add(Duration(days: stage.maxDay));
      final now = DateTime.now();
      if (to.isAfter(now)) to = now;

      try {
        final res = await _db.rpc(
          'stage_summary',
          params: {
            'p_device': c.deviceId,
            'p_readings_from': _fakeUtc(from),
            'p_readings_to': _fakeUtc(to),
            'p_alerts_from': from.toUtc().toIso8601String(),
            'p_alerts_to': to.toUtc().toIso8601String(),
          },
        ).timeout(_timeout);
        final rows = res as List;
        if (rows.isNotEmpty) {
          final r = rows.first as Map;
          health = (r['avg_health'] as num?)?.toDouble();
          alerts = (r['alert_count'] as num?)?.toInt();
        }
      } catch (e) {
        debugPrint('stage_summary error: $e');
      }
    }

    return HarvestInfo(avgHealth: health, alerts: alerts, tip: await tip);
  }

  // ── f. Harvested status ──

  /// Marks the crop as harvested and records when. Throws when the database
  /// refuses (for example when the user does not own the crop).
  static Future<void> markHarvested(Crop c) async {
    final updated = await _db
        .from('crops')
        .update({
          'status': 'harvested',
          'harvested_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('crop_id', c.id)
        .select()
        .timeout(_saveTimeout);
    if ((updated as List).isEmpty) {
      throw Exception('No rows updated');
    }
  }

  /// Suggests the next crop name: "Mustard no.1" -> "Mustard no.2",
  /// "Mustard Green" -> "Mustard Green 2".
  static String nextCropName(String name) {
    final trimmed = name.trim();
    final m = _trailingNumber.firstMatch(trimmed);
    final n = m == null ? null : int.tryParse(m.group(2)!);
    if (m == null || n == null) return '$trimmed 2';
    return '${m.group(1)}${n + 1}';
  }
}