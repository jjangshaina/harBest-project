import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_harbest_1/widgets/plant_image.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/widgets/app_header.dart';
import 'package:flutter_application_harbest_1/widgets/app_card.dart';
import 'package:flutter_application_harbest_1/widgets/status_widgets.dart';

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
  GrowthStage(name: 'Germination', minDay: 0, maxDay: 7, icon: AppIcons.growthGermination),
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

/// The five sensor-backed ranges plus an NPK note, specific to one growth
/// stage. Needs differ across the growth cycle — e.g. germination wants
/// consistently wet soil to trigger sprouting, while vegetative growth
/// wants more moderate moisture and peak nitrogen. These are general
/// horticultural targets for mustard greens; treat them as a reasonable
/// starting point to refine against your own results over time.
class StageConditions {
  final _RangeSpec pH;
  final _RangeSpec soilMoisture;
  final _RangeSpec temperature;
  final _RangeSpec humidity;
  final _RangeSpec heatIndex;
  final String npkGuidance;

  const StageConditions({
    required this.pH,
    required this.soilMoisture,
    required this.temperature,
    required this.humidity,
    required this.heatIndex,
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

  /// Which stage tile (if any) is expanded to show its optimal conditions.
  /// Accordion-style: tapping a different stage switches to it; tapping
  /// the same one again collapses it. Every stage can be expanded, not
  /// just the current one — each shows its own stage-specific targets.
  int? _expandedStageIndex;

  // Mustard greens are a cool-season crop — sustained heat pushes them to
  // bolt earlier than the day-based estimate would suggest. Threshold is in
  // Celsius, matching the temperature column in sensor_readings.
  static const double _boltingRiskTempC = 27.0;
  static const int _recentReadingsWindow = 5;

  // Fixed widths for the conditions-panel table columns, so the value and
  // status pill line up across rows regardless of how long each factor's
  // name or label text happens to be.
  static const double _kValueColumnWidth = 62;
  static const double _kStatusPillWidth = 66;

  @override
  void initState() {
    super.initState();
    _fetchAll();
  }

  Future<void> _fetchAll() async {
    try {
      // plant_info holds one row per plant: name, image, and planting date.
      // There's a single shared device during development, so just grab
      // the one row.
      final plantInfoResponse = await _supabase
          .from('plant_info')
          .select()
          .limit(1)
          .maybeSingle();

      final plantInfo = plantInfoResponse != null
          ? Map<String, dynamic>.from(plantInfoResponse)
          : <String, dynamic>{};

      final deviceId = plantInfo['device_id'] as String?;

      // sensor_readings is telemetry, not plant profile data — pull the
      // recent window for this device, ordered by the real timestamp
      // column (not id, which only reflects insert order).
      var readingsQuery = _supabase.from('sensor_readings').select();
      if (deviceId != null) {
        readingsQuery = readingsQuery.eq('device_id', deviceId);
      }
      final readingsResponse = await readingsQuery
          .order('timestamp', ascending: false)
          .limit(_recentReadingsWindow);

      if (!mounted) return;

      final rows = (readingsResponse as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();

      setState(() {
        _plantInfo = plantInfo;
        _recentReadings = rows;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      debugPrint("PlantProfilePage fetch error: $e");
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

  /// Average temperature across the recent sensor_readings window.
  /// Expects a numeric 'temperature' field (Celsius). Returns null if no
  /// readings or the field is missing/non-numeric.
  double? _getAverageRecentTemperature() {
    final temps = _recentReadings
        .map((row) => row['temperature'])
        .whereType<num>()
        .map((t) => (t as num).toDouble())
        .toList();
    if (temps.isEmpty) return null;
    return temps.reduce((a, b) => a + b) / temps.length;
  }

  /// Flags elevated bolting risk when recent average temperature is above
  /// mustard greens' preferred range, and the plant isn't already in
  /// (or past) the Bolting stage. Bolting is heat/day-length triggered, so
  /// this can fire earlier than the day-based estimate would predict.
  bool _isBoltingRiskElevated(int estimatedStageIndex) {
    final avgTemp = _getAverageRecentTemperature();
    if (avgTemp == null) return false;
    final boltingStageIndex = kGrowthStages.length - 1;
    if (estimatedStageIndex >= boltingStageIndex) return false;
    return avgTemp >= _boltingRiskTempC;
  }

  // --- Growth conditions (pH, moisture, temp, humidity, heat index, NPK) ---

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

  /// Builds the six-factor breakdown for one specific stage, checked
  /// against that stage's own ideal ranges (not a single global set) —
  /// germination and bolting want different soil moisture and temperature,
  /// for instance. Uses the latest reading for instantaneous values, plus
  /// the recent-average temperature for consistency with the bolting-risk
  /// check above.
  List<_ConditionFactor> _buildConditionFactorsForStage(String stageName) {
    final ranges = kStageConditions[stageName]!;
    final latest = _latestReading;
    final avgTemp = _getAverageRecentTemperature();

    double? asDouble(dynamic v) => v is num ? v.toDouble() : null;

    final ph = asDouble(latest?['pH']);
    final soilMoisture = asDouble(latest?['moisture']);
    final humidity = asDouble(latest?['humidity']);
    final heatIndex = asDouble(latest?['heat_index']);
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
        displayValue: avgTemp != null ? '${avgTemp.toStringAsFixed(1)}°C' : '—',
        status: avgTemp != null
            ? _statusForValue(ranges.temperature, avgTemp)
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

  Widget _buildCropImageCard() {
    final imageUrl = _latestReading?['image_url'] as String?;

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
          ],
        ),
      ),
    );
  }

  /// Growth Stage Timeline card: germination -> seedling -> vegetative
  /// -> harvest -> bolting, with the current stage highlighted based on
  /// days elapsed since planting_date.
  Widget _buildGrowthTimelineCard() {
    final daysSincePlanting = _getDaysSincePlanting();
    final hasPlantingDate = daysSincePlanting != null;
    final estimatedStageIndex = hasPlantingDate
        ? _getCurrentStageIndex(daysSincePlanting)
        : -1;

    final currentStageIndex = estimatedStageIndex;

    final avgTemp = _getAverageRecentTemperature();
    final boltingRisk =
        hasPlantingDate && _isBoltingRiskElevated(estimatedStageIndex);

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
                  const Icon(AppIcons.timeline, color: AppColors.green, size: 20),
                  const SizedBox(width: 8),
                  Text('Growth Stage Timeline', style: AppText.cardTitle),
                ],
              ),
              const SizedBox(height: 4),
              if (hasPlantingDate)
                Text('Day $daysSincePlanting of growth', style: AppText.subtitle)
              else
                Text(
                  'Planting date not set — add one to track progress.',
                  style: AppText.subtitle.copyWith(
                    color: AppColors.textTertiary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              if (avgTemp != null) ...[
                const SizedBox(height: 2),
                Text(
                  'Avg. recent temp: ${avgTemp.toStringAsFixed(1)}°C '
                  '(last ${_recentReadings.length} readings)',
                  style: AppText.caption.copyWith(fontSize: 12),
                ),
              ],
              if (boltingRisk) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.caution.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.caution.withOpacity(0.5),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        AppIcons.warning,
                        color: AppColors.caution,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Elevated bolting risk — recent temperatures are running warm for '
                          'mustard greens. Bolting may happen sooner than the day-based estimate — '
                          'check the plant to see how it\'s actually doing.',
                          textAlign: TextAlign.justify,
                          style: AppText.caption.copyWith(
                            fontSize: 12,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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

        final Color circleColor = isCurrent
            ? AppColors.green
            : (isPast ? AppColors.green.withOpacity(0.45) : AppColors.track);
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
                  child: Icon(
                    stage.icon,
                    size: 18,
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
  /// stage's own target ranges. Shown when its timeline row is tapped —
  /// works the same way whether it's the current stage or not, so a
  /// grower can preview what a future stage will expect, or look back at
  /// what an earlier one wanted.
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
    return Column(
      children: [
        const AppHeader(title: 'Plant Profile'),

        // Body
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpace.page),
                  child: Column(
                    children: [
                      _buildCropImageCard(),
                      _buildGrowthTimelineCard(),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}