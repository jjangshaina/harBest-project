import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_harbest_1/widgets/plant_image.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/widgets/app_button.dart';
import 'package:flutter_application_harbest_1/widgets/app_card.dart';
import 'package:flutter_application_harbest_1/plant_profile/insight_rules.dart';
import 'package:flutter_application_harbest_1/widgets/app_snackbar.dart';
import 'package:flutter_application_harbest_1/widgets/status_widgets.dart';
import 'package:flutter_application_harbest_1/services/crop_services.dart';
import 'package:flutter_application_harbest_1/widgets/app_empty_state.dart';
import 'package:flutter_application_harbest_1/pages/user_dashboard.dart'
    show normalizeReading;

/// Represents one stage in the plant's growth cycle.
/// [name] is the short label under each step; [title] is the descriptive
/// heading shown in the press-and-hold card.
class GrowthStage {
  final String name;
  final String title;
  final int minDay;
  final int maxDay;
  final IconData icon;

  const GrowthStage({
    required this.name,
    required this.title,
    required this.minDay,
    required this.maxDay,
    required this.icon,
  });
}

const List<GrowthStage> kGrowthStages = [
  GrowthStage(
    name: 'Germination',
    title: 'Seed Germination',
    minDay: 0,
    maxDay: 7,
    icon: AppIcons.growthGermination,
  ),
  GrowthStage(
    name: 'Seedling',
    title: 'Seedling Development',
    minDay: 7,
    maxDay: 14,
    icon: AppIcons.growthSeedling,
  ),
  GrowthStage(
    name: 'Vegetative',
    title: 'Rapid Leaf Growth',
    minDay: 14,
    maxDay: 30,
    icon: AppIcons.growthVegetative,
  ),
  GrowthStage(
    name: 'Harvesting',
    title: 'Mature Harvest',
    minDay: 30,
    maxDay: 50,
    icon: AppIcons.growthHarvest,
  ),
];

/// Three-band range used to classify a raw sensor value against what's
/// ideal for mustard greens.
class _RangeSpec {
  final double optimalMin;
  final double optimalMax;
  final double acceptableMin;
  final double acceptableMax;

  const _RangeSpec({
    required this.optimalMin,
    required this.optimalMax,
    required this.acceptableMin,
    required this.acceptableMax,
  });
}

enum _FactorStatus { optimal, caution, critical, unknown }

extension on _FactorStatus {
  Color get color {
    switch (this) {
      case _FactorStatus.optimal:
        return AppColors.optimal;
      case _FactorStatus.caution:
        return AppColors.caution;
      case _FactorStatus.critical:
        return AppColors.critical;
      case _FactorStatus.unknown:
        return AppColors.textTertiary;
    }
  }

  String get label {
    switch (this) {
      case _FactorStatus.optimal:
        return 'Optimal';
      case _FactorStatus.caution:
        return 'Caution';
      case _FactorStatus.critical:
        return 'Critical';
      case _FactorStatus.unknown:
        return 'No data';
    }
  }
}

/// One row in the "Growth conditions" breakdown.
class _ConditionFactor {
  final String name;
  final String displayValue;
  final _FactorStatus status;
  final IconData? icon;

  const _ConditionFactor({
    required this.name,
    required this.displayValue,
    required this.status,
    this.icon,
  });
}

/// The six sensor-backed ranges plus an NPK note, specific to one growth
/// stage. Needs differ across the growth cycle — e.g. germination wants
/// consistently wet soil to trigger sprouting, while vegetative growth
/// wants more moderate moisture and peak nitrogen. These are general
/// horticultural targets for mustard greens; treat them as a reasonable
/// starting point to refine against your own results over time.
///
/// [ec] is in mS/cm (the same unit the dashboard shows).
class StageConditions {
  final _RangeSpec pH;
  final _RangeSpec soilMoisture;
  final _RangeSpec temperature;
  final _RangeSpec humidity;
  final _RangeSpec heatIndex;
  final _RangeSpec ec;
  final String npkGuidance;

  const StageConditions({
    required this.pH,
    required this.soilMoisture,
    required this.temperature,
    required this.humidity,
    required this.heatIndex,
    required this.ec,
    required this.npkGuidance,
  });
}

final Map<String, StageConditions> kStageConditions = {
  'Germination': const StageConditions(
    pH: _RangeSpec(
      optimalMin: 6.0,
      optimalMax: 7.0,
      acceptableMin: 5.5,
      acceptableMax: 7.5,
    ),
    soilMoisture: _RangeSpec(
      optimalMin: 65,
      optimalMax: 80,
      acceptableMin: 55,
      acceptableMax: 85,
    ),
    temperature: _RangeSpec(
      optimalMin: 20,
      optimalMax: 25,
      acceptableMin: 15,
      acceptableMax: 27,
    ),
    humidity: _RangeSpec(
      optimalMin: 60,
      optimalMax: 80,
      acceptableMin: 50,
      acceptableMax: 90,
    ),
    heatIndex: _RangeSpec(
      optimalMin: 20,
      optimalMax: 25,
      acceptableMin: 15,
      acceptableMax: 27,
    ),
    ec: _RangeSpec(
      optimalMin: 0.8,
      optimalMax: 1.5,
      acceptableMin: 0.5,
      acceptableMax: 2.0,
    ),
    npkGuidance:
        'Minimal feeding needed — the seed itself supplies early nutrients.',
  ),
  'Seedling': const StageConditions(
    pH: _RangeSpec(
      optimalMin: 6.0,
      optimalMax: 7.0,
      acceptableMin: 5.5,
      acceptableMax: 7.5,
    ),
    soilMoisture: _RangeSpec(
      optimalMin: 55,
      optimalMax: 70,
      acceptableMin: 45,
      acceptableMax: 75,
    ),
    temperature: _RangeSpec(
      optimalMin: 18,
      optimalMax: 22,
      acceptableMin: 12,
      acceptableMax: 26,
    ),
    humidity: _RangeSpec(
      optimalMin: 55,
      optimalMax: 75,
      acceptableMin: 45,
      acceptableMax: 85,
    ),
    heatIndex: _RangeSpec(
      optimalMin: 18,
      optimalMax: 22,
      acceptableMin: 12,
      acceptableMax: 26,
    ),
    ec: _RangeSpec(
      optimalMin: 1.0,
      optimalMax: 1.8,
      acceptableMin: 0.7,
      acceptableMax: 2.2,
    ),
    npkGuidance: 'Begin light nitrogen feeding to support early leaf growth.',
  ),
  'Vegetative': const StageConditions(
    pH: _RangeSpec(
      optimalMin: 6.0,
      optimalMax: 7.0,
      acceptableMin: 5.5,
      acceptableMax: 7.5,
    ),
    soilMoisture: _RangeSpec(
      optimalMin: 40,
      optimalMax: 60,
      acceptableMin: 30,
      acceptableMax: 70,
    ),
    temperature: _RangeSpec(
      optimalMin: 15,
      optimalMax: 20,
      acceptableMin: 10,
      acceptableMax: 25,
    ),
    humidity: _RangeSpec(
      optimalMin: 50,
      optimalMax: 70,
      acceptableMin: 40,
      acceptableMax: 80,
    ),
    heatIndex: _RangeSpec(
      optimalMin: 15,
      optimalMax: 20,
      acceptableMin: 10,
      acceptableMax: 27,
    ),
    ec: _RangeSpec(
      optimalMin: 1.2,
      optimalMax: 2.4,
      acceptableMin: 0.8,
      acceptableMax: 3.0,
    ),
    npkGuidance:
        'Highest nitrogen demand of the whole cycle — this drives leaf growth.',
  ),
  'Harvesting': const StageConditions(
    pH: _RangeSpec(
      optimalMin: 6.0,
      optimalMax: 7.0,
      acceptableMin: 5.5,
      acceptableMax: 7.5,
    ),
    soilMoisture: _RangeSpec(
      optimalMin: 40,
      optimalMax: 60,
      acceptableMin: 30,
      acceptableMax: 70,
    ),
    temperature: _RangeSpec(
      optimalMin: 15,
      optimalMax: 20,
      acceptableMin: 10,
      acceptableMax: 25,
    ),
    humidity: _RangeSpec(
      optimalMin: 50,
      optimalMax: 70,
      acceptableMin: 40,
      acceptableMax: 80,
    ),
    heatIndex: _RangeSpec(
      optimalMin: 15,
      optimalMax: 20,
      acceptableMin: 10,
      acceptableMax: 27,
    ),
    ec: _RangeSpec(
      optimalMin: 1.2,
      optimalMax: 2.4,
      acceptableMin: 0.8,
      acceptableMax: 3.0,
    ),
    npkGuidance:
        'Maintain balanced NPK; ease off heavy nitrogen as leaves mature.',
  ),
  'Bolting': const StageConditions(
    pH: _RangeSpec(
      optimalMin: 6.0,
      optimalMax: 7.0,
      acceptableMin: 5.5,
      acceptableMax: 7.5,
    ),
    soilMoisture: _RangeSpec(
      optimalMin: 35,
      optimalMax: 55,
      acceptableMin: 25,
      acceptableMax: 65,
    ),
    temperature: _RangeSpec(
      optimalMin: 12,
      optimalMax: 18,
      acceptableMin: 8,
      acceptableMax: 22,
    ),
    humidity: _RangeSpec(
      optimalMin: 45,
      optimalMax: 65,
      acceptableMin: 35,
      acceptableMax: 75,
    ),
    heatIndex: _RangeSpec(
      optimalMin: 12,
      optimalMax: 18,
      acceptableMin: 8,
      acceptableMax: 25,
    ),
    ec: _RangeSpec(
      optimalMin: 1.0,
      optimalMax: 2.0,
      acceptableMin: 0.7,
      acceptableMax: 2.5,
    ),
    npkGuidance:
        'Reduce fertilizing — the plant is shifting energy into flowering.',
  ),
};

// A recommendation the user marked done / dismissed. It stays hidden until
// [until] passes, the sensor returns to range, or it gets worse.
class _Hidden {
  final DateTime until;
  final int level; // HealthLevel.index when it was hidden
  const _Hidden(this.until, this.level);
}

class PlantProfilePage extends StatefulWidget {
  const PlantProfilePage({super.key});

  @override
  State<PlantProfilePage> createState() => _PlantProfilePageState();
}

class _PlantProfilePageState extends State<PlantProfilePage> {
  static const String _hiddenPrefsKey = 'insights_hidden_v1';
  static const Duration _snoozeFor = Duration(hours: 6);

  final _supabase = Supabase.instance.client;

  Map<String, dynamic> _plantInfo = {};
  List<Map<String, dynamic>> _recentReadings = []; // newest → oldest
  List<Recommendation> _recs = [];
  final Map<String, _Hidden> _hidden = {};
  InsightCategory? _filter; // null = All
  String? _readingsError;
  bool _isLoading = true;
  bool _isSavingDate = false;
  Timer? _timer;

  /// Stage whose optimal conditions are shown under the tracker while its
  /// step is held down. [_peekVisible] turns off on release; the index is
  /// kept so the section can collapse smoothly.
  int? _peekIndex;
  bool _peekVisible = false;
  final LayerLink _timelineLink = LayerLink(); // anchors the stage card
  Timer? _peekTimer;
  Offset _peekDownPos = Offset.zero;

  // Newest readings kept. The latest one drives the conditions; the whole
  // window feeds the trend notes in the recommendations.
  static const int _recentReadingsWindow = 20;

  @override
  void initState() {
    super.initState();
    CropService.instance.addListener(_onCropChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadHidden();
      _onCropChanged();
    });
    // Re-reads the sensors every 30s; this also keeps "Updated x mins ago"
    // counting up.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _fetchAll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _peekTimer?.cancel();
    CropService.instance.removeListener(_onCropChanged);
    super.dispose();
  }

  void _onCropChanged() {
    if (!mounted || !CropService.instance.loaded) return;
    setState(() {
      _isLoading = true;
      _recentReadings = [];
      _recs = [];
      _readingsError = null;
    });
    _fetchAll();
  }

  Future<void> _fetchAll({bool silent = true}) async {
    final crop = CropService.instance.selected;
    if (crop == null) {
      if (!mounted) return;
      setState(() {
        _plantInfo = {};
        _recentReadings = [];
        _recs = [];
        _readingsError = null;
        _isLoading = false;
      });
      return;
    }
    try {
      final readingsResponse = await _supabase
          .from('sensor_readings')
          .select()
          .eq('device_id', crop.deviceId)
          .order('timestamp', ascending: false)
          .limit(_recentReadingsWindow);

      // Ignore the result if the user switched crop while this was loading.
      if (!mounted || CropService.instance.selected?.deviceId != crop.deviceId) {
        return;
      }

      // normalizeReading converts EC from µS/cm (Pi) to mS/cm (app).
      final rows = (readingsResponse as List)
          .map((row) => normalizeReading(Map<String, dynamic>.from(row as Map)))
          .toList();
      final recs = rows.isEmpty
          ? <Recommendation>[]
          : buildRecommendations(rows.first, rows.reversed.toList());

      // Forget hidden items whose sensor is back in range, so a new problem
      // later is not silently hidden.
      final before = _hidden.length;
      _hidden.removeWhere((k, _) => !recs.any((r) => r.key == k));

      setState(() {
        _plantInfo = {
          'device_id': crop.deviceId,
          'plant_name': crop.name,
          'planting_date': crop.plantingDate?.toIso8601String(),
        };
        _recentReadings = rows;
        _recs = recs;
        _readingsError =
            rows.isEmpty ? 'No sensor data found for this crop yet.' : null;
        _isLoading = false;
      });
      if (_hidden.length != before) _saveHidden();
    } catch (e) {
      debugPrint("PlantProfilePage fetch error: $e");
      if (!mounted) return;
      setState(() {
        if (_recentReadings.isEmpty) {
          _readingsError = 'Could not load sensor data. Check your connection.';
        }
        _isLoading = false;
      });
      if (!silent && _recentReadings.isNotEmpty) {
        AppSnack.show(
          context,
          'Could not refresh. Showing the last data.',
          type: AppSnackType.error,
        );
      }
    }
  }

  // --- Recommendations: hide / snooze ---------------------------------------

  Future<void> _loadHidden() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_hiddenPrefsKey);
      if (raw == null) return;
      final now = DateTime.now();
      (jsonDecode(raw) as Map<String, dynamic>).forEach((key, value) {
        final m = value as Map<String, dynamic>;
        final until = DateTime.fromMillisecondsSinceEpoch(m['until'] as int);
        if (until.isAfter(now)) _hidden[key] = _Hidden(until, m['level'] as int);
      });
    } catch (_) {
      // Unreadable saved state: start fresh.
    }
  }

  Future<void> _saveHidden() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _hiddenPrefsKey,
        jsonEncode({
          for (final e in _hidden.entries)
            e.key: {
              'until': e.value.until.millisecondsSinceEpoch,
              'level': e.value.level,
            },
        }),
      );
    } catch (_) {}
  }

  bool _isOpen(Recommendation r) {
    final h = _hidden[r.key];
    if (h == null || DateTime.now().isAfter(h.until)) return true;
    return r.level.index > h.level; // got worse since it was hidden
  }

  Future<void> _hide(Recommendation r, {required bool done}) async {
    setState(() {
      _hidden[r.key] = _Hidden(DateTime.now().add(_snoozeFor), r.level.index);
    });
    await _saveHidden();
    if (!mounted) return;
    AppSnack.show(
      context,
      done
          ? 'Marked as done. We will keep checking this sensor.'
          : 'Dismissed. It will return if things get worse.',
      type: done ? AppSnackType.success : AppSnackType.info,
    );
  }

  // "Updated 5 mins ago", from the newest reading's timestamp. The stored
  // clock fields are already local time, so they are rebuilt as a local
  // DateTime before comparing with now.
  String _updatedText() {
    final raw = _latestReading?['timestamp'];
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

  // --- Planting date (add / edit) -------------------------------------------

  String _two(int n) => n.toString().padLeft(2, '0');
  String _fmtDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

  /// Opens the small pop-up, then saves whatever date the user confirmed.
  Future<void> _openPlantingDateDialog() async {
    if (_isSavingDate) return;
    final crop = CropService.instance.selected;
    if (crop == null) return;

    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => _PlantingDateDialog(current: crop.plantingDate),
    );
    if (picked == null || !mounted) return;

    setState(() => _isSavingDate = true);
    try {
      // .select() returns the updated rows, so an empty result means the
      // database refused the change (e.g. not the owner of this crop).
      final updated = await _supabase
          .from('crops')
          .update({'planting_date': _fmtDate(picked)})
          .eq('crop_id', crop.id)
          .select();
      if ((updated as List).isEmpty) {
        throw Exception('No rows updated');
      }

      // Reload crops; this notifies the listener above, which refreshes
      // the day count, current stage and conditions panel.
      await CropService.instance.load();

      if (!mounted) return;
      AppSnack.show(
        context,
        'Planting date updated.',
        type: AppSnackType.success,
      );
    } catch (e) {
      debugPrint('Update planting date error: $e');
      if (!mounted) return;
      AppSnack.show(
        context,
        'Could not update the planting date. Please try again.',
        type: AppSnackType.error,
      );
    } finally {
      if (mounted) setState(() => _isSavingDate = false);
    }
  }

  // --- Growth stage helpers -------------------------------------------------

  /// Reads the planting date from plant_info. Supabase returns `date`
  /// columns as 'YYYY-MM-DD' strings. Returns null if missing/invalid.
  DateTime? _getPlantingDate() {
    final raw = _plantInfo['planting_date'];
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String) {
      return DateTime.tryParse(raw);
    }
    return null;
  }

  int? _getDaysSincePlanting() {
    final plantingDate = _getPlantingDate();
    if (plantingDate == null) return null;
    final now = DateTime.now();
    final diff = now.difference(plantingDate).inDays;
    return diff < 0 ? 0 : diff;
  }

  /// Returns the index into kGrowthStages for the current day count.
  /// Clamps to the last stage if past the final range.
  int _getCurrentStageIndex(int daysSincePlanting) {
    for (int i = 0; i < kGrowthStages.length; i++) {
      final stage = kGrowthStages[i];
      final isLast = i == kGrowthStages.length - 1;
      if (daysSincePlanting >= stage.minDay &&
          (daysSincePlanting < stage.maxDay || isLast)) {
        return i;
      }
    }
    return kGrowthStages.length - 1;
  }

  // --- Growth conditions (pH, moisture, temp, humidity, heat index, EC, NPK) --

  Map<String, dynamic>? get _latestReading =>
      _recentReadings.isNotEmpty ? _recentReadings.first : null;

  _FactorStatus _statusForValue(_RangeSpec range, double value) {
    if (value >= range.optimalMin && value <= range.optimalMax) {
      return _FactorStatus.optimal;
    }
    if (value >= range.acceptableMin && value <= range.acceptableMax) {
      return _FactorStatus.caution;
    }
    return _FactorStatus.critical;
  }

  /// The device already classifies NPK status per reading in `nutrient_rec`
  /// (e.g. "Nutrient levels optimal", "Nitrogen low (0 mg/kg) - apply
  /// nitrogen"). Rather than re-deriving thresholds against raw sensor
  /// units, this parses that verdict directly so it never disagrees with
  /// what the device itself reported.
  _FactorStatus _statusFromNutrientRec(String? nutrientRec) {
    if (nutrientRec == null) return _FactorStatus.unknown;
    final text = nutrientRec.toLowerCase();
    if (text.contains('unavailable')) return _FactorStatus.unknown;
    if (text.contains('optimal')) return _FactorStatus.optimal;
    if (text.contains('low') ||
        text.contains('high') ||
        text.contains('apply')) {
      return _FactorStatus.caution;
    }
    return _FactorStatus.unknown;
  }

  /// Builds the seven-factor breakdown for one specific stage, checked
  /// against that stage's own ideal ranges (not a single global set) —
  /// germination and bolting want different soil moisture and temperature,
  /// for instance. Uses the latest reading for every instantaneous value.
  List<_ConditionFactor> _buildConditionFactorsForStage(String stageName) {
    final ranges = kStageConditions[stageName]!;
    final latest = _latestReading;

    double? asDouble(dynamic v) => v is num ? v.toDouble() : null;

    final ph = asDouble(latest?['pH']);
    final soilMoisture = asDouble(latest?['moisture']);
    final temperature = asDouble(latest?['temperature']);
    final humidity = asDouble(latest?['humidity']);
    final heatIndex = asDouble(latest?['heat_index']);
    final ec = asDouble(latest?['EC']);
    final nutrientRec = latest?['nutrient_rec'] as String?;

    return [
      _ConditionFactor(
        name: 'Soil pH',
        icon: AppIcons.soilPh,
        displayValue: ph != null ? ph.toStringAsFixed(1) : '—',
        status: ph != null
            ? _statusForValue(ranges.pH, ph)
            : _FactorStatus.unknown,
      ),
      _ConditionFactor(
        name: 'Soil moisture',
        displayValue: soilMoisture != null
            ? '${soilMoisture.toStringAsFixed(0)}%'
            : '—',
        status: soilMoisture != null
            ? _statusForValue(ranges.soilMoisture, soilMoisture)
            : _FactorStatus.unknown,
      ),
      _ConditionFactor(
        name: 'Temperature',
        displayValue: temperature != null
            ? '${temperature.toStringAsFixed(1)}°C'
            : '—',
        status: temperature != null
            ? _statusForValue(ranges.temperature, temperature)
            : _FactorStatus.unknown,
      ),
      _ConditionFactor(
        name: 'Humidity',
        displayValue: humidity != null
            ? '${humidity.toStringAsFixed(0)}%'
            : '—',
        status: humidity != null
            ? _statusForValue(ranges.humidity, humidity)
            : _FactorStatus.unknown,
      ),
      _ConditionFactor(
        name: 'Heat index',
        displayValue: heatIndex != null
            ? '${heatIndex.toStringAsFixed(1)}°C'
            : '—',
        status: heatIndex != null
            ? _statusForValue(ranges.heatIndex, heatIndex)
            : _FactorStatus.unknown,
      ),
      _ConditionFactor(
        name: 'EC',
        displayValue: ec != null ? ec.toStringAsFixed(2) : '—',
        status: ec != null
            ? _statusForValue(ranges.ec, ec)
            : _FactorStatus.unknown,
      ),
      _ConditionFactor(
        name: 'N-P-K',
        displayValue: nutrientRec ?? 'No data',
        status: _statusFromNutrientRec(nutrientRec),
      ),
    ];
  }

  /// Composite score: optimal = 2 points, caution = 1, critical = 0,
  /// unknown factors are excluded from both the numerator and denominator
  /// so missing sensors don't drag the score down unfairly.
  int? _growthConditionsScore(List<_ConditionFactor> factors) {
    final known = factors
        .where((f) => f.status != _FactorStatus.unknown)
        .toList();
    if (known.isEmpty) return null;
    final points = known.fold<int>(0, (sum, f) {
      switch (f.status) {
        case _FactorStatus.optimal:
          return sum + 2;
        case _FactorStatus.caution:
          return sum + 1;
        case _FactorStatus.critical:
        case _FactorStatus.unknown:
          return sum;
      }
    });
    return ((points / (known.length * 2)) * 100).round();
  }

  // --- UI ---------------------------------------------------------------

  /// Plain title + "Updated ..." line at the top (no green header).
  Widget _buildTitleBlock() {
    final updated = _updatedText();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpace.page,
        MediaQuery.of(context).padding.top + 16,
        AppSpace.page,
        8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Plant Profile',
            style: AppText.sectionTitle.copyWith(color: AppColors.darkGreen),
          ),
          if (updated.isNotEmpty) Text(updated, style: AppText.subtitle),
        ],
      ),
    );
  }

  /// Plant photo card. The day-of-growth text sits right under the photo.
  Widget _buildCropImageCard() {
    final imageUrl =
        CropService.instance.selected?.imageUrl ??
        _latestReading?['image_url'] as String?;
    final days = _getDaysSincePlanting();

    return Center(
      child: AppCard(
        radius: 20,
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PlantImage(
              imageUrl: imageUrl,
              borderRadius: 5,
              size: 200,
              enableZoom: true,
            ),
            const SizedBox(height: 12),
            if (days != null)
              Text(
                'Day $days of growth',
                style: AppText.body.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              Text(
                'Planting date not set — tap + to add one.',
                textAlign: TextAlign.center,
                style: AppText.subtitle.copyWith(
                  color: AppColors.textTertiary,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static const Duration _peekHoldDelay = Duration(milliseconds: 350);
  static const double _peekMoveSlop = 12;

  void _showPeek(int index) {
    setState(() {
      _peekIndex = index;
      _peekVisible = true;
    });
  }

  void _hidePeek() {
    if (!_peekVisible) return;
    setState(() => _peekVisible = false);
  }

  // The stage steps use raw pointer events instead of a long-press gesture,
  // so the hold never takes over the touch: once the card is showing, the
  // user can keep the finger down and still scroll the page to see all of it.
  void _onStagePointerDown(int index, Offset position) {
    _peekTimer?.cancel();
    _peekDownPos = position;
    _peekTimer = Timer(_peekHoldDelay, () {
      _peekTimer = null;
      if (mounted) _showPeek(index);
    });
  }

  // Moving before the hold registers means the user is just scrolling.
  void _onStagePointerMove(Offset position) {
    final t = _peekTimer;
    if (t != null && (position - _peekDownPos).distance > _peekMoveSlop) {
      t.cancel();
      _peekTimer = null;
    }
  }

  void _onStagePointerEnd() {
    _peekTimer?.cancel();
    _peekTimer = null;
    _hidePeek();
  }

  /// Card with the dark green outline AND the soft shadow used by the cards
  /// on the other pages (AppCard gives one or the other, so the shadow sits
  /// on a wrapper).
  Widget _outlinedShadowCard({
    required Widget child,
    Color color = AppColors.darkGreen,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.card,
      ),
      child: AppCard(outlineColor: color, padding: padding, child: child),
    );
  }

  /// Growth Stage Timeline card: a horizontal progress tracker (germination
  /// -> seedling -> vegetative -> harvesting). Finished stages show a check
  /// mark. Press and hold any stage and a card with its optimal conditions
  /// lays over the cards right below this one, pointing at that stage; let
  /// go and it closes again.
  Widget _buildGrowthTimelineCard() {
    final days = _getDaysSincePlanting();
    final currentIndex = days != null ? _getCurrentStageIndex(days) : -1;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: CompositedTransformTarget(
        link: _timelineLink,
        child: SizedBox(
        width: double.infinity,
        child: _outlinedShadowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    AppIcons.timeline,
                    color: AppColors.green,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text('Growth Stage Timeline', style: AppText.cardTitle),
                ],
              ),
              const SizedBox(height: 20),
              _buildGrowthStepper(currentIndex),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildGrowthStepper(int currentIndex) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(kGrowthStages.length, (i) {
        final stage = kGrowthStages[i];
        final isCurrent = i == currentIndex;
        final isPast = i < currentIndex;
        final isFirst = i == 0;
        final isLast = i == kGrowthStages.length - 1;

        final Color circleColor = isPast
            ? AppColors.darkGreen
            : (isCurrent ? AppColors.green : AppColors.track);
        final Color textColor = isCurrent
            ? AppColors.darkGreen
            : (isPast ? AppColors.textPrimary : AppColors.textTertiary);

        // Connector half-line on one side of the circle.
        Widget line(bool visible, bool active) => Expanded(
          child: Container(
            height: 2,
            color: !visible
                ? Colors.transparent
                : (active ? AppColors.darkGreen : AppColors.track),
          ),
        );

        return Expanded(
          child: Listener(
            // Hold to view, release to close; scrolling still works.
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) => _onStagePointerDown(i, e.position),
            onPointerMove: (e) => _onStagePointerMove(e.position),
            onPointerUp: (_) => _onStagePointerEnd(),
            onPointerCancel: (_) => _onStagePointerEnd(),
            child: Column(
              children: [
                Row(
                  children: [
                    line(!isFirst, i <= currentIndex),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: circleColor,
                        shape: BoxShape.circle,
                        border: isCurrent
                            ? Border.all(color: AppColors.darkGreen, width: 2)
                            : null,
                      ),
                      // Finished stages show a check mark instead of the
                      // stage icon.
                      child: Icon(
                        isPast ? AppIcons.done : stage.icon,
                        size: isPast ? 20 : 18,
                        color: isCurrent || isPast
                            ? AppColors.onGreen
                            : AppColors.textTertiary,
                      ),
                    ),
                    line(!isLast, i < currentIndex),
                  ],
                ),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    stage.name,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Day ${stage.minDay}–${stage.maxDay}',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: textColor.withOpacity(0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  /// The held stage's card. It lays over the cards under the timeline card
  /// (so nothing is pushed down or expanded) and scrolls together with the
  /// page.
  Widget _buildStageDetailsOverlay(int? daysSincePlanting) {
    final index = _peekIndex;
    if (index == null) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: _timelineLink,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
        child: IgnorePointer(
          child: AnimatedOpacity(
            opacity: _peekVisible ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: _buildStageDetails(index, daysSincePlanting),
          ),
        ),
      ),
    );
  }

  /// Slim progress bar with a dark track, as in the design.
  Widget _stageBar(double value) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        width: double.infinity,
        height: 6,
        child: Stack(
          children: [
            const Positioned.fill(
              child: ColoredBox(color: AppColors.emphasisOutline),
            ),
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value.clamp(0.0, 1.0),
                child: const ColoredBox(color: AppColors.green),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The held stage's title, day range and optimal conditions, in a gray
  /// bordered card with a small pointer aimed at that stage in the tracker.
  Widget _buildStageDetails(int index, int? daysSincePlanting) {
    final stage = kGrowthStages[index];
    final isCurrent = daysSincePlanting != null &&
        _getCurrentStageIndex(daysSincePlanting) == index;

    return LayoutBuilder(
      builder: (context, constraints) {
        // The tracker splits the timeline card's inner width (14 padding +
        // 1.5 border each side) into equal columns; aim at the held one.
        const edge = 14 + 1.5;
        final columnWidth =
            (constraints.maxWidth - edge * 2) / kGrowthStages.length;
        final pointerX = edge + columnWidth * (index + 0.5);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _outlinedShadowCard(
                // Gray border (matches the design).
                color: AppColors.disabledStart,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${stage.title} (${stage.name})',
                      style: AppText.body.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Day ${stage.minDay}–${stage.maxDay}',
                      style: AppText.caption.copyWith(fontSize: 12),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(height: 8),
                      _stageBar(
                        (daysSincePlanting - stage.minDay) /
                            (stage.maxDay - stage.minDay),
                      ),
                    ],
                    const SizedBox(height: 14),
                    _buildStageConditionsPanel(stage.name),
                  ],
                ),
              ),
            ),
            Positioned(
              left: pointerX - 11,
              top: 0,
              child: CustomPaint(
                size: const Size(22, 11.5),
                painter: const _PointerPainter(
                  fill: AppColors.card,
                  border: AppColors.disabledStart,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _statusDot(_FactorStatus status) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: status.color, shape: BoxShape.circle),
  );

  BoxDecoration get _chipDecoration => BoxDecoration(
    color: AppColors.authField,
    borderRadius: BorderRadius.circular(AppRadius.field),
  );

  /// One factor as a rounded tag: status dot and name on the left, value on
  /// the right, so names and values line up down each column.
  Widget _conditionChip(_ConditionFactor factor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: _chipDecoration,
      child: Row(
        children: [
          _statusDot(factor.status),
          const SizedBox(width: 6),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                factor.name,
                maxLines: 1,
                style: AppText.label.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            factor.displayValue,
            maxLines: 1,
            style: AppText.label.copyWith(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// N-P-K gets a full-width tag: its value is a sentence from nutrient_rec.
  Widget _npkChip(_ConditionFactor factor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: _chipDecoration,
      child: Row(
        children: [
          _statusDot(factor.status),
          const SizedBox(width: 6),
          Text(
            factor.name,
            style: AppText.label.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              factor.displayValue,
              style: AppText.label.copyWith(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Optimal-conditions breakdown for one stage, checked against that
  /// stage's own target ranges: a two-column grid of tags, then N-P-K.
  Widget _buildStageConditionsPanel(String stageName) {
    final factors = _buildConditionFactorsForStage(stageName);
    final score = _growthConditionsScore(factors);
    final optimalCount = factors
        .where((f) => f.status == _FactorStatus.optimal)
        .length;
    final knownCount = factors
        .where((f) => f.status != _FactorStatus.unknown)
        .length;

    final npk = factors.firstWhere((f) => f.name == 'N-P-K');
    final grid = factors.where((f) => f.name != 'N-P-K').toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.track,
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'OPTIMAL CONDITIONS',
                  style: AppText.label.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (score != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.green.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$score%',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.darkGreen,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            knownCount > 0
                ? '$optimalCount out of $knownCount tracked factors optimal right now'
                : 'No sensor data available yet',
            style: AppText.caption.copyWith(fontSize: 11.5),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < grid.length; i += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(child: _conditionChip(grid[i])),
                  const SizedBox(width: 8),
                  Expanded(
                    child: i + 1 < grid.length
                        ? _conditionChip(grid[i + 1])
                        : const SizedBox(),
                  ),
                ],
              ),
            ),
          _npkChip(npk),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(AppIcons.tip, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  kStageConditions[stageName]!.npkGuidance,
                  style: AppText.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Insights & Recommendations (moved here from the Insights page) ──

  /// "Insights & Recommendation" card: title and the Actions / Priorities /
  /// Critical counts. The recommendations themselves are separate cards below.
  Widget _buildInsightsCard() {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: SizedBox(
        width: double.infinity,
        child: _outlinedShadowCard(
          color: AppColors.disabledStart,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'INSIGHTS & RECOMMENDATION',
                style: AppText.label.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              if (_recentReadings.isEmpty)
                _buildNoReadings()
              else
                _buildSummaryStrip(_recs.where(_isOpen).toList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoReadings() {
    return Column(
      children: [
        Center(
          child: Text(
            _readingsError ?? 'No sensor data found for this crop yet.',
            textAlign: TextAlign.center,
            style: AppText.subtitle,
          ),
        ),
        const SizedBox(height: 12),
        AppButton(
          label: 'Retry',
          icon: AppIcons.refresh,
          onPressed: () => _fetchAll(silent: false),
        ),
      ],
    );
  }

  Widget _buildSummaryStrip(List<Recommendation> open) {
    final critical = open.where((r) => r.level == HealthLevel.critical).length;
    final priorities = open.where((r) => r.score < kPriorityBelowScore).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.track,
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      child: Row(
        children: [
          _stat('Actions', '${open.length}'),
          _stat('Priorities', '$priorities'),
          _stat('Critical', '$critical'),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: AppText.cardTitle),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppText.body.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// Filter chips and the recommendation cards. They sit on the page itself,
  /// not inside the insights card. All priorities come first, the rest after.
  Widget _buildRecommendations() {
    if (_recentReadings.isEmpty) return const SizedBox.shrink();

    final open = _recs.where(_isOpen).toList(); // most urgent first
    if (open.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: AppSpace.cardGap),
        child: SizedBox(
          width: double.infinity,
          height: 240,
          child: AppEmptyState(
            icon: AppIcons.success,
            title: 'All clear',
            message:
                'All your sensors are in their optimal range. Nothing needs your attention right now.',
          ),
        ),
      );
    }

    bool inFilter(Recommendation r) => _filter == null || r.category == _filter;
    final priorities = open
        .where((r) => r.score < kPriorityBelowScore && inFilter(r))
        .toList();
    final others = open
        .where((r) => r.score >= kPriorityBelowScore && inFilter(r))
        .toList();

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpace.cardGap),
          _buildFilterChips(),
          const SizedBox(height: AppSpace.cardGap),
          if (priorities.isEmpty && others.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.section),
              child: Center(
                child: Text(
                  'No ${_filter!.label.toLowerCase()} recommendations right now.',
                  style: AppText.subtitle,
                ),
              ),
            )
          else ...[
            for (final r in priorities) _buildRecCard(r, priority: true),
            for (final r in others) _buildRecCard(r),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    const options = <InsightCategory?>[
      null,
      InsightCategory.water,
      InsightCategory.nutrient,
      InsightCategory.growth,
    ];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final option = options[i];
          final selected = option == _filter;
          return ChoiceChip(
            label: Text(
              option?.label ?? 'All',
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            selected: selected,
            showCheckmark: false,
            selectedColor: AppColors.green,
            backgroundColor: AppColors.green.withOpacity(0.25),
            side: BorderSide.none,
            shape: const StadiumBorder(),
            onSelected: (_) => setState(() => _filter = option),
          );
        },
      ),
    );
  }

  Widget _messageBox(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.green.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      child: Text(
        message,
        style: AppText.body.copyWith(fontSize: 14, height: 1.4),
      ),
    );
  }

  Widget _pillButton(
    String label, {
    required bool filled,
    required VoidCallback onTap,
  }) {
    final color = filled ? AppColors.green : AppColors.destructive;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.button),
    );
    const size = Size(0, 38);
    const padding = EdgeInsets.symmetric(horizontal: 22);
    final text = AppText.button.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w700,
    );
    return filled
        ? ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              elevation: 0,
              minimumSize: size,
              padding: padding,
              shape: shape,
              textStyle: text,
            ),
            child: Text(label),
          )
        : OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              side: BorderSide(color: color, width: 1.5),
              minimumSize: size,
              padding: padding,
              shape: shape,
              textStyle: text,
            ),
            child: Text(label),
          );
  }

  /// One recommendation, in its own card outlined in its status color.
  /// Priority cards carry the "TOP PRIORITY" label. Every card keeps its
  /// status tag, score bar and advice sentence.
  Widget _buildRecCard(Recommendation r, {bool priority = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.cardGap),
      child: SizedBox(
        width: double.infinity,
        child: _outlinedShadowCard(
          color: r.level.color,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (priority) ...[
                Row(
                  children: [
                    Text(
                      'TOP PRIORITY',
                      style: AppText.label.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    AppStatusPill.level(r.level),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Icon(r.def.icon, size: 22, color: r.level.color),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.title,
                          style: AppText.body.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          r.subtitle,
                          style: AppText.caption.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  // Priority cards show the tag next to their label instead.
                  if (!priority) ...[
                    const SizedBox(width: 8),
                    AppStatusPill.level(r.level),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              AppProgressBar(
                value: r.score / 100,
                color: r.level.color,
                height: 6,
              ),
              const SizedBox(height: 12),
              _messageBox(r.message),
              const SizedBox(height: 14),
              // Buttons line up under the title text (icon 22 + gap 14).
              Padding(
                padding: const EdgeInsets.only(left: 36),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _pillButton(
                      'Mark as done',
                      filled: true,
                      onTap: () => _hide(r, done: true),
                    ),
                    _pillButton(
                      'Dismiss',
                      filled: false,
                      onTap: () => _hide(r, done: false),
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

  @override
  Widget build(BuildContext context) {
    final hasCrop = CropService.instance.selected != null;
    final showEmpty = CropService.instance.loaded && !hasCrop;

    // Stack so the round "+" button can float over the bottom-right corner
    // of the page, above the bottom navigation bar.
    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          children: [
            _buildTitleBlock(),

            // Body
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : showEmpty
                      ? const AppEmptyState(
                          icon: AppIcons.plant,
                          title: 'No crop yet',
                          message: 'No crop is linked to your account yet.',
                        )
                      : RefreshIndicator(
                          color: AppColors.green,
                          onRefresh: () => _fetchAll(silent: false),
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            // Extra bottom space so the floating button never
                            // covers the last card.
                            padding: const EdgeInsets.fromLTRB(
                              AppSpace.page,
                              AppSpace.gap,
                              AppSpace.page,
                              96,
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              fit: StackFit.passthrough,
                              children: [
                                Column(
                                  children: [
                                    _buildCropImageCard(),
                                    _buildGrowthTimelineCard(),
                                    _buildInsightsCard(),
                                    _buildRecommendations(),
                                  ],
                                ),
                                // Last child = drawn on top of the cards.
                                _buildStageDetailsOverlay(
                                  _getDaysSincePlanting(),
                                ),
                              ],
                            ),
                          ),
                        ),
            ),
          ],
        ),

        if (hasCrop && !_isLoading)
          Positioned(
            right: AppSpace.page,
            bottom: AppSpace.page,
            child: FloatingActionButton(
              heroTag: null,
              tooltip: 'Add or edit planting date',
              backgroundColor: AppColors.darkGreen,
              foregroundColor: AppColors.onGreen,
              elevation: 3,
              shape: const CircleBorder(),
              onPressed: _openPlantingDateDialog,
              child: const Icon(AppIcons.add),
            ),
          ),
      ],
    );
  }
}

// Small triangle on top of the stage details card, pointing up at the held
// stage. Filled like the card, with the border drawn on its two slanted sides.
class _PointerPainter extends CustomPainter {
  final Color fill;
  final Color border;
  const _PointerPainter({required this.fill, required this.border});

  @override
  void paint(Canvas canvas, Size size) {
    final triangle = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(triangle, Paint()..color = fill);

    final edges = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height);
    canvas.drawPath(
      edges,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _PointerPainter old) =>
      old.fill != fill || old.border != border;
}

// ─────────────────────────────────────────────────────────────────────────
// PLANTING DATE POP-UP
// A small dialog (not a new page): a date field that opens the calendar,
// plus Cancel / Save. Pops with the chosen DateTime on Save, null on Cancel.
// ─────────────────────────────────────────────────────────────────────────
class _PlantingDateDialog extends StatefulWidget {
  /// The crop's current planting date, or null when none is set yet.
  final DateTime? current;
  const _PlantingDateDialog({this.current});

  @override
  State<_PlantingDateDialog> createState() => _PlantingDateDialogState();
}

class _PlantingDateDialogState extends State<_PlantingDateDialog> {
  late final DateTime _today;
  late DateTime _picked;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _today = DateTime(n.year, n.month, n.day);
    final c = widget.current;
    _picked = c == null ? _today : DateTime(c.year, c.month, c.day);
    if (_picked.isAfter(_today)) _picked = _today;
  }

  String _two(int n) => n.toString().padLeft(2, '0');
  String _fmt(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

  Future<void> _pickDate() async {
    // Same window as the Add Crop page (up to 120 days back), but never
    // later than the currently saved date so editing an older crop works.
    final earliest = _today.subtract(const Duration(days: 120));
    final first = _picked.isBefore(earliest) ? _picked : earliest;

    final result = await showDatePicker(
      context: context,
      initialDate: _picked,
      firstDate: first,
      lastDate: _today,
    );
    if (result != null) setState(() => _picked = result);
  }

  Widget _button(String label, Color bg, Color fg, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 0,
        minimumSize: const Size(0, 46),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: AppText.button,
      ),
      child: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.current == null
                  ? 'Add new planting date'
                  : 'Edit planting date',
              style: AppText.body.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _pickDate,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: AppColors.fieldLight,
                  borderRadius: BorderRadius.circular(AppRadius.field),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(_fmt(_picked), style: AppText.body)),
                    const Icon(
                      AppIcons.timeline,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _button(
                    'Cancel',
                    AppColors.authField,
                    AppColors.textPrimary,
                    () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _button(
                    'Save',
                    AppColors.darkGreen,
                    AppColors.onGreen,
                    () => Navigator.of(context).pop(_picked),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}