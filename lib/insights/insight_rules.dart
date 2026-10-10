import 'package:flutter_application_harbest_1/pages/user_dashboard.dart'
    show SensorDef, kSensors;
import 'package:flutter_application_harbest_1/theme/app_style.dart';

// ─────────────────────────────────────────────────────────────────────────
// Turns the latest sensor_readings row into a list of recommendations.
// Ranges and tolerances come from kSensors (user_dashboard.dart), so the
// Insights page always agrees with the Sensor Overview cards.
// Later, ML-generated insights from the backend can be added next to these.
// ─────────────────────────────────────────────────────────────────────────

/// A recommendation with a score below this counts as a "priority"
/// (clearly outside its range). Change it here to tune the Priorities count.
const double kPriorityBelowScore = 75;

enum InsightCategory { water, nutrient, growth }

extension InsightCategoryX on InsightCategory {
  String get label => switch (this) {
        InsightCategory.water => 'Water',
        InsightCategory.nutrient => 'Nutrient',
        InsightCategory.growth => 'Growth',
      };
}

class _Advice {
  final String name;
  final InsightCategory category;
  final String unit; // shown after the value, e.g. ' ppm'
  final String low;
  final String high;

  const _Advice({
    required this.name,
    required this.category,
    required this.unit,
    required this.low,
    required this.high,
  });
}

// Wording for each sensor. Phrased as suggestions, with no exact doses.
// Climate sensors (temperature, humidity, heat index) sit under "Growth".
const Map<String, _Advice> _advice = {
  'moisture': _Advice(
    name: 'Soil moisture',
    category: InsightCategory.water,
    unit: '%',
    low: 'Consider watering soon.',
    high: 'Soil is very wet. Hold off watering and check that it drains well.',
  ),
  'pH': _Advice(
    name: 'Soil pH',
    category: InsightCategory.nutrient,
    unit: '',
    low: 'Soil is on the acidic side. Consider a pH-raising amendment, then recheck.',
    high: 'Soil is on the alkaline side. Consider a pH-lowering amendment, then recheck.',
  ),
  'EC': _Advice(
    name: 'Soil EC',
    category: InsightCategory.nutrient,
    unit: ' mS/cm',
    low: 'Nutrient concentration looks low. Consider a balanced feed.',
    high: 'Nutrient or salt level is high. Ease off fertilizer and consider flushing with plain water.',
  ),
  'nitrogen': _Advice(
    name: 'Nitrogen',
    category: InsightCategory.nutrient,
    unit: ' ppm',
    low: 'Consider a light nitrogen feed to support leaf growth.',
    high: 'Nitrogen is high. Hold off nitrogen fertilizer for now.',
  ),
  'phosphorus': _Advice(
    name: 'Phosphorus',
    category: InsightCategory.nutrient,
    unit: ' ppm',
    low: 'Consider a phosphorus source to support root development.',
    high: 'Hold off phosphorus fertilizer. Too much can block other nutrients.',
  ),
  'potassium': _Advice(
    name: 'Potassium',
    category: InsightCategory.nutrient,
    unit: ' ppm',
    low: 'Consider a potassium source to support overall plant health.',
    high: 'Hold off potassium fertilizer for now.',
  ),
  'temperature': _Advice(
    name: 'Temperature',
    category: InsightCategory.growth,
    unit: '°C',
    low: 'It is cool for the crop. Consider covering it or moving it somewhere warmer.',
    high: 'Running warm for mustard greens. Consider shade or more ventilation to reduce bolting risk.',
  ),
  'humidity': _Advice(
    name: 'Humidity',
    category: InsightCategory.growth,
    unit: '%',
    low: 'Air is dry. Consider light misting and shelter from drying wind.',
    high: 'Air is very humid, which can encourage fungal disease. Improve airflow around the plants.',
  ),
  'heat_index': _Advice(
    name: 'Heat index',
    category: InsightCategory.growth,
    unit: '°C',
    low: 'Heat index is lower than usual. Keep an eye on it.',
    high: 'It feels hotter than the crop likes. Consider shade and water in the cooler part of the day.',
  ),
};

class Recommendation {
  final SensorDef def;
  final InsightCategory category;
  final HealthLevel level;
  final double score; // 0–100, lower = further outside the optimal range
  final double value;
  final bool isLow;
  final String title;
  final String message;
  final String subtitle;

  const Recommendation({
    required this.def,
    required this.category,
    required this.level,
    required this.score,
    required this.value,
    required this.isLow,
    required this.title,
    required this.message,
    required this.subtitle,
  });

  String get key => def.key;
}

double? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

// Same scoring as the Dashboard: 100 inside the range, tapering to 0 once
// the value is `tolerance` away from it.
double _scoreFor(double value, SensorDef def) {
  if (value >= def.min && value <= def.max) return 100;
  final deviation = value < def.min ? def.min - value : value - def.max;
  if (deviation >= def.tolerance) return 0;
  return 100 * (1 - deviation / def.tolerance);
}

HealthLevel _levelFor(double score) {
  if (score >= 100) return HealthLevel.optimal;
  if (score >= 50) return HealthLevel.caution;
  return HealthLevel.critical;
}

// Compares the older and newer half of the recent readings to say whether a
// sensor is getting worse or recovering. Returns '' when there is no clear
// movement or not enough history.
String _trendNote(
  SensorDef def,
  _Advice advice,
  List<Map<String, dynamic>> history,
  bool isLow,
) {
  final series =
      history.map((r) => _num(r[def.key])).whereType<double>().toList();
  if (series.length < 6) return '';

  final half = series.length ~/ 2;
  double avg(Iterable<double> v) => v.reduce((a, b) => a + b) / v.length;
  final delta =
      avg(series.skip(series.length - half)) - avg(series.take(half));
  final threshold = (def.max - def.min) * 0.03;

  final worsening = isLow ? delta < -threshold : delta > threshold;
  final improving = isLow ? delta > threshold : delta < -threshold;
  if (worsening) {
    return ' ${advice.name} has been ${isLow ? 'falling' : 'rising'} recently.';
  }
  if (improving) return ' ${advice.name} is moving back toward its range.';
  return '';
}

/// Builds one recommendation per sensor that is outside its optimal range,
/// most urgent (lowest score) first. [history] is oldest → newest.
List<Recommendation> buildRecommendations(
  Map<String, dynamic> reading,
  List<Map<String, dynamic>> history,
) {
  final out = <Recommendation>[];

  for (final def in kSensors) {
    final advice = _advice[def.key];
    final value = _num(reading[def.key]);
    if (advice == null || value == null) continue;

    final score = _scoreFor(value, def);
    final level = _levelFor(score);
    if (level == HealthLevel.optimal) continue;

    final isLow = value < def.min;
    out.add(Recommendation(
      def: def,
      category: advice.category,
      level: level,
      score: score,
      value: value,
      isLow: isLow,
      title: '${advice.name} is ${isLow ? 'low' : 'high'}',
      message: '${isLow ? advice.low : advice.high}'
          '${_trendNote(def, advice, history, isLow)}',
      subtitle: '${value.toStringAsFixed(def.decimals)}${advice.unit} now · '
          'target ${def.optimalText}',
    ));
  }

  out.sort((a, b) => a.score.compareTo(b.score));
  return out;
}