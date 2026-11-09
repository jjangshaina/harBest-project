// HarBest - puts Gemini's advice into the Plant Profile's own recommendation
// cards. Put this file in lib/plant_profile/.
//
// Each Gemini action is matched to a sensor (moisture, pH, temperature ...):
//   * if the page already has a card for that sensor ("Soil moisture is high"),
//     that card keeps its title, numbers and bar, but its advice becomes
//     Gemini's action and it gets the "AI" chip;
//   * otherwise the action gets its own new card (e.g. pests, shade).
// Every card keeps Mark as done / Dismiss and works with the filter chips.

import 'package:flutter/material.dart';

import 'package:flutter_application_harbest_1/pages/user_dashboard.dart'
    show SensorDef, kSensors;
import 'package:flutter_application_harbest_1/plant_profile/insight_rules.dart';
import 'package:flutter_application_harbest_1/services/ai_insights_service.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';

/// A recommendation card whose advice came from Gemini.
class AiRecItem extends Recommendation {
  const AiRecItem({
    required super.def,
    required super.category,
    required super.level,
    required super.score,
    required super.value,
    required super.isLow,
    required super.title,
    required super.message,
    required super.subtitle,
    required this.id,
  });

  /// Used for Mark as done / Dismiss. Cards that replace a sensor card keep
  /// that sensor's key, so hiding works exactly like before.
  final String id;

  @override
  String get key => id;
}

// ------------------------------------------------------------ matching

// Checked in order: the first match wins ("heat index" before "temperature").
final List<(String, RegExp)> _sensorWords = [
  ('heat_index', RegExp(r'heat index', caseSensitive: false)),
  ('pH', RegExp(r'\bph\b|lime|acidi|alkalin|sulfur|sulphur', caseSensitive: false)),
  ('EC', RegExp(r'\bec\b|salin|conductiv|\bsalt', caseSensitive: false)),
  ('nitrogen', RegExp(r'nitrogen|urea', caseSensitive: false)),
  ('phosphorus', RegExp(r'phosph', caseSensitive: false)),
  ('potassium', RegExp(r'potass|potash', caseSensitive: false)),
  ('moisture', RegExp(r'moist|water|irrigat|drain|wet|dry soil', caseSensitive: false)),
  ('humidity', RegExp(r'humid|mist', caseSensitive: false)),
  ('temperature', RegExp(r'temperat|°c|heat|hot|shade|cool', caseSensitive: false)),
];

const Map<String, String> _categorySensor = {
  'irrigation': 'moisture',
  'soil_ph': 'pH',
  'fertilizer': 'nitrogen',
  'climate': 'temperature',
};

String? _sensorFor(AiAction a) {
  for (final text in [a.title, a.reason]) {
    for (final (key, re) in _sensorWords) {
      if (re.hasMatch(text)) return key;
    }
  }
  return _categorySensor[a.category];
}

SensorDef? _defFor(String key) {
  for (final d in kSensors) {
    if (d.key == key) return d;
  }
  return null;
}

// Cards for advice that is not about one sensor (pests, disease, sensors).
SensorDef _otherDef(String category) => SensorDef(
      key: 'ai_$category',
      label: switch (category) {
        'pest' => 'Pests',
        'disease' => 'Disease',
        'sensor' => 'Sensors',
        _ => 'Crop care',
      },
      unit: '',
      icon: switch (category) {
        'pest' => Icons.bug_report,
        'disease' => Icons.healing,
        'sensor' => Icons.sensors_off,
        _ => AppIcons.info,
      },
      min: 0,
      max: 1,
      tolerance: 1,
      optimalText: '',
    );

InsightCategory _categoryOf(AiAction a) => switch (a.filter) {
      AiFilter.water => InsightCategory.water,
      AiFilter.nutrient => InsightCategory.nutrient,
      AiFilter.growth => InsightCategory.growth,
    };

HealthLevel _levelOf(AiAction a) =>
    a.priority == 'high' ? HealthLevel.critical : HealthLevel.caution;

// Below kPriorityBelowScore (75) = shown as TOP PRIORITY.
double _scoreOf(AiAction a) => switch (a.priority) {
      'high' => 20,
      'medium' => 60,
      _ => 85,
    };

double? _num(dynamic v) =>
    v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

String _sentence(String s) {
  final t = s.trim();
  if (t.isEmpty) return t;
  return RegExp(r'[.!?]$').hasMatch(t) ? t : '$t.';
}

// ------------------------------------------------------------ merge

/// Rule-based cards [rules] + Gemini's latest advice [ai] -> one list,
/// most urgent first. [reading] is the newest sensor reading.
/// When [ai] is null, old (>3 h) or not from Gemini, [rules] come back unchanged.
List<Recommendation> mergeAiActions(
  List<Recommendation> rules,
  AiRecommendation? ai,
  Map<String, dynamic>? reading,
) {
  if (ai == null || !ai.isAi || !ai.isFresh() || ai.actions.isEmpty) return rules;

  final out = [...rules];
  final replaced = <String>{};

  for (final a in ai.actions) {
    if (a.title.trim().isEmpty) continue;
    final sensor = _sensorFor(a);

    // 1) Give an existing sensor card Gemini's advice.
    final i = sensor == null || replaced.contains(sensor)
        ? -1
        : out.indexWhere((r) => r is! AiRecItem && r.def.key == sensor);
    if (i >= 0) {
      final r = out[i];
      out[i] = AiRecItem(
        def: r.def,
        category: r.category,
        level: r.level,
        score: r.score,
        value: r.value,
        isLow: r.isLow,
        title: r.title,
        message: _sentence(a.title),
        subtitle: r.subtitle,
        id: r.key,
      );
      replaced.add(sensor!);
      continue;
    }

    // 2) No card for it yet -> a new card of its own.
    final def = (sensor == null ? null : _defFor(sensor)) ?? _otherDef(a.category);
    final double? raw = _num(reading?[def.key]);
    final hasValue = raw != null && def.optimalText.isNotEmpty;
    final value = raw ?? 0;
    out.add(AiRecItem(
      def: def,
      category: _categoryOf(a),
      level: _levelOf(a),
      score: _scoreOf(a),
      value: value,
      isLow: hasValue && value < def.min,
      title: _sentence(a.title).replaceAll(RegExp(r'\.$'), ''),
      message: _sentence(a.reason.isNotEmpty ? a.reason : a.title),
      subtitle: [
        if (hasValue)
          '${value.toStringAsFixed(def.decimals)}${def.unit} now · target ${def.optimalText}',
        if (a.when.trim().isNotEmpty) a.when.trim(),
      ].join(' · '),
      id: a.id,
    ));
  }

  out.sort((x, y) => x.score.compareTo(y.score));
  return out;
}

// ------------------------------------------------------------ chip

/// Small "AI" chip shown on cards whose advice came from Gemini.
class AiChip extends StatelessWidget {
  const AiChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.45)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 14, color: AppColors.green),
          SizedBox(width: 4),
          Text('AI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}