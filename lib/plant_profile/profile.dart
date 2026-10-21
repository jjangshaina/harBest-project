import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_harbest_1/widgets/plant_image.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/widgets/app_header.dart';
import 'package:flutter_application_harbest_1/widgets/app_card.dart';
import 'package:flutter_application_harbest_1/widgets/app_snackbar.dart';
import 'package:flutter_application_harbest_1/widgets/status_widgets.dart';
import 'package:flutter_application_harbest_1/services/crop_services.dart';
import 'package:flutter_application_harbest_1/widgets/app_empty_state.dart';
import 'package:flutter_application_harbest_1/pages/user_dashboard.dart'
    show normalizeReading;

/// Represents one stage in the plant's growth cycle.
class GrowthStage {
  final String name;
  final int minDay;
  final int maxDay;
  final IconData icon;

  const GrowthStage({
    required this.name,
    required this.minDay,
    required this.maxDay,
    required this.icon,
  });
}

const List<GrowthStage> kGrowthStages = [
  GrowthStage(
    name: 'Germination',
    minDay: 0,
    maxDay: 7,
    icon: AppIcons.growthGermination,
  ),
  GrowthStage(
    name: 'Seedling',
    minDay: 7,
    maxDay: 14,
    icon: AppIcons.growthSeedling,
  ),
  GrowthStage(
    name: 'Vegetative',
    minDay: 14,
    maxDay: 30,
    icon: AppIcons.growthVegetative,
  ),
  GrowthStage(
    name: 'Harvest',
    minDay: 30,
    maxDay: 50,
    icon: AppIcons.growthHarvest,
  ),
  GrowthStage(
    name: 'Bolting',
    minDay: 50,
    maxDay: 75,
    icon: AppIcons.growthBolting,
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
  'Harvest': const StageConditions(
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

class PlantProfilePage extends StatefulWidget {
  const PlantProfilePage({super.key});

  @override
  State<PlantProfilePage> createState() => _PlantProfilePageState();
}

class _PlantProfilePageState extends State<PlantProfilePage> {
  final _supabase = Supabase.instance.client;

  Map<String, dynamic> _plantInfo = {};
  List<Map<String, dynamic>> _recentReadings = [];
  bool _isLoading = true;
  bool _isSavingDate = false;

  /// Which stage tile (if any) is expanded to show its optimal conditions.
  /// Accordion-style: tapping a different stage switches to it; tapping
  /// the same one again collapses it.
  int? _expandedStageIndex;

  static const int _recentReadingsWindow = 5;

  // Fixed widths for the conditions-panel table columns, so the value and
  // status pill line up across rows regardless of how long each factor's
  // name or label text happens to be.
  static const double _kValueColumnWidth = 62;
  static const double _kStatusPillWidth = 66;

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

  void _onCropChanged() {
    if (!mounted || !CropService.instance.loaded) return;
    setState(() => _isLoading = true);
    _fetchAll();
  }

  Future<void> _fetchAll() async {
    final crop = CropService.instance.selected;
    if (crop == null) {
      if (!mounted) return;
      setState(() {
        _plantInfo = {};
        _recentReadings = [];
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

      if (!mounted) return;
      setState(() {
        _plantInfo = {
          'device_id': crop.deviceId,
          'plant_name': crop.name,
          'planting_date': crop.plantingDate?.toIso8601String(),
        };
        // normalizeReading converts EC from µS/cm (Pi) to mS/cm (app).
        _recentReadings = (readingsResponse as List)
            .map((row) => normalizeReading(Map<String, dynamic>.from(row as Map)))
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      debugPrint("PlantProfilePage fetch error: $e");
    }
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

  /// Plant photo card. The day-of-growth text sits right under the photo.
  Widget _buildCropImageCard() {
    final imageUrl =
        CropService.instance.selected?.imageUrl ??
        _latestReading?['image_url'] as String?;
    final days = _getDaysSincePlanting();

    return Center(
      child: AppCard(
        radius: 20,
        outlineColor: AppColors.darkGreen,
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

  /// Growth Stage Timeline card: germination -> seedling -> vegetative
  /// -> harvest -> bolting, with the current stage highlighted based on
  /// days elapsed since planting_date. Finished stages get a check mark.
  Widget _buildGrowthTimelineCard() {
    final daysSincePlanting = _getDaysSincePlanting();
    final hasPlantingDate = daysSincePlanting != null;
    final currentStageIndex = hasPlantingDate
        ? _getCurrentStageIndex(daysSincePlanting)
        : -1;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: SizedBox(
        width: double.infinity,
        child: AppCard(
          padding: const EdgeInsets.all(14),
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
              _buildGrowthTimeline(currentStageIndex, daysSincePlanting),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrowthTimeline(int currentStageIndex, int? daysSincePlanting) {
    return Column(
      children: List.generate(kGrowthStages.length, (index) {
        final stage = kGrowthStages[index];
        final isCurrent = index == currentStageIndex;
        final isPast = index < currentStageIndex;
        final isLast = index == kGrowthStages.length - 1;

        final Color circleColor = isCurrent || isPast
            ? AppColors.green
            : AppColors.track;
        final Color textColor = isCurrent
            ? AppColors.darkGreen
            : (isPast ? AppColors.textPrimary : AppColors.textTertiary);

        // A Stack (not IntrinsicHeight) so the connector line can stretch
        // to the row's height without any intrinsic-size measuring.
        return Stack(
          children: [
            if (!isLast)
              Positioned(
                left: 17,
                top: 36,
                bottom: 0,
                width: 2,
                child: ColoredBox(
                  color: isPast
                      ? AppColors.green.withOpacity(0.45)
                      : AppColors.track,
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: isCurrent
                      ? () {
                          setState(() {
                            _expandedStageIndex = _expandedStageIndex == index
                                ? null
                                : index;
                          });
                        }
                      : null,
                  child: Container(
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
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stage.name,
                          style: AppText.body.copyWith(
                            fontWeight: isCurrent
                                ? FontWeight.bold
                                : FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Day ${stage.minDay}–${stage.maxDay}',
                          style: TextStyle(
                            fontSize: 12,
                            color: textColor.withOpacity(0.7),
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(height: 8),
                          AppProgressBar(
                            value:
                                ((daysSincePlanting! - stage.minDay) /
                                        (stage.maxDay - stage.minDay))
                                    .clamp(0.0, 1.0),
                            color: AppColors.green,
                            height: 6,
                          ),
                          if (_expandedStageIndex == index) ...[
                            const SizedBox(height: 10),
                            _buildStageConditionsPanel(stage.name),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      }),
    );
  }

  /// One factor's status tag, same look as every other status pill in the app.
  Widget _statusPill(_FactorStatus status) => SizedBox(
    width: _kStatusPillWidth,
    child: Center(
      child: AppStatusPill(text: status.label, color: status.color),
    ),
  );

  Widget _statusDot(_FactorStatus status) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: status.color, shape: BoxShape.circle),
  );

  /// Optimal-conditions breakdown for one stage, checked against that
  /// stage's own target ranges. Shown when its timeline row is tapped.
  Widget _buildStageConditionsPanel(String stageName) {
    final factors = _buildConditionFactorsForStage(stageName);
    final score = _growthConditionsScore(factors);
    final optimalCount = factors
        .where((f) => f.status == _FactorStatus.optimal)
        .length;
    final knownCount = factors
        .where((f) => f.status != _FactorStatus.unknown)
        .length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.rowBackground,
        borderRadius: BorderRadius.circular(AppRadius.button),
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
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkGreen,
                  ),
                ),
              ),
              if (score != null)
                AppStatusPill(text: '$score%', color: AppColors.optimal),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            knownCount > 0
                ? '$optimalCount out of $knownCount tracked factors optimal right now'
                : 'No sensor data available yet',
            style: AppText.caption.copyWith(fontSize: 11.5),
          ),
          const SizedBox(height: 10),
          ...factors.map((factor) {
            final isLongValue = factor.name == 'N-P-K';
            final nameStyle = AppText.label.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            );
            final valueStyle = AppText.caption.copyWith(
              fontSize: 11.5,
              color: AppColors.textSecondary,
            );

            if (isLongValue) {
              // NPK's value is a full sentence from nutrient_rec (e.g.
              // "Nitrogen low (0 mg/kg) - apply nitrogen fertilizer"), not
              // a short number+unit like the other factors — give it its
              // own line to wrap into instead of squeezing it into a row.
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _statusDot(factor.status),
                        const SizedBox(width: 8),
                        Expanded(child: Text(factor.name, style: nameStyle)),
                        const SizedBox(width: 8),
                        _statusPill(factor.status),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Text(factor.displayValue, style: valueStyle),
                    ),
                  ],
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  _statusDot(factor.status),
                  const SizedBox(width: 8),
                  Expanded(child: Text(factor.name, style: nameStyle)),
                  SizedBox(
                    width: _kValueColumnWidth,
                    child: Text(
                      factor.displayValue,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: valueStyle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _statusPill(factor.status),
                ],
              ),
            );
          }),
          const SizedBox(height: 2),
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
            const AppHeader(title: 'Plant Profile'),

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
                      : SingleChildScrollView(
                          // Extra bottom space so the floating button never
                          // covers the last card.
                          padding: const EdgeInsets.fromLTRB(
                            AppSpace.page,
                            AppSpace.page,
                            AppSpace.page,
                            96,
                          ),
                          child: Column(
                            children: [
                              _buildCropImageCard(),
                              _buildGrowthTimelineCard(),
                            ],
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