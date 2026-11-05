// HarBest - AI insights data layer (Gemini results saved by the gemini-advisor
// Edge Function). Put this file in lib/services/.
//
// Used by:
//   - widgets/ai_recommendation_card.dart (dashboard card)
//   - plant_profile/profile.dart (insight & recommendation cards, growth timeline)
//
// IMPORTANT: create the streams once (e.g. in initState) and keep them in a
// field. Creating them inside build() reconnects on every rebuild.
//
//   late final _recStream = AiInsightsService.recommendation(deviceId);
//   late final _growthStream = AiInsightsService.growthHistory(deviceId);

import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------- enums

/// Same three filters as the plant profile's chips (All / Water / Nutrient / Growth).
enum AiFilter { water, nutrient, growth }

/// Same three levels as the profile's badges (CRITICAL / CAUTION / normal).
enum AiSeverity { critical, caution, info }

extension AiSeverityX on AiSeverity {
  String get label => switch (this) {
        AiSeverity.critical => 'CRITICAL',
        AiSeverity.caution => 'CAUTION',
        AiSeverity.info => 'TIP',
      };
  int get rank => switch (this) {
        AiSeverity.critical => 0,
        AiSeverity.caution => 1,
        AiSeverity.info => 2,
      };
}

// ---------------------------------------------------------------- friendly names

const Map<String, String> _sensorNames = {
  'temperature': 'Air temperature',
  'humidity': 'Humidity',
  'heat_index': 'Heat index',
  'soil_temp': 'Soil temperature',
  'moisture': 'Soil moisture',
  'moisture_pct': 'Soil moisture',
  'ph': 'Soil pH',
  'ec': 'EC (salinity)',
  'nitrogen': 'Nitrogen',
  'phosphorus': 'Phosphorus',
  'potassium': 'Potassium',
};

/// Turns a sensor issue into readable text. Older saved answers may contain
/// bare field names like "moisture_pct" - those become "Soil moisture: no reading".
String friendlySensorIssue(String raw) {
  final s = raw.trim();
  final key = s.toLowerCase();
  if (_sensorNames.containsKey(key)) {
    return key == 'soil_temp'
        ? 'Soil temperature sensor not connected yet'
        : '${_sensorNames[key]}: no reading';
  }
  // Replace any field names inside a sentence, e.g. "moisture_pct sensor failed".
  var out = s;
  _sensorNames.forEach((field, name) {
    if (field.contains('_')) out = out.replaceAll(field, name.toLowerCase());
  });
  return out.isEmpty ? out : out[0].toUpperCase() + out.substring(1);
}

/// Groups N, P and K into one line when all three are listed separately.
List<String> friendlySensorIssues(List<String> raw) {
  final keys = raw.map((s) => s.trim().toLowerCase()).toSet();
  final npkAll = keys.containsAll(['nitrogen', 'phosphorus', 'potassium']);
  final out = <String>[];
  if (npkAll) out.add('Nutrient (NPK) sensor: no reading');
  for (final s in raw) {
    final k = s.trim().toLowerCase();
    if (npkAll && (k == 'nitrogen' || k == 'phosphorus' || k == 'potassium')) continue;
    final f = friendlySensorIssue(s);
    if (f.isNotEmpty && !out.contains(f)) out.add(f);
  }
  return out;
}

// ---------------------------------------------------------------- models

class AiAction {
  AiAction({
    required this.category,
    required this.priority,
    required this.title,
    required this.reason,
    required this.when,
  });

  factory AiAction.fromMap(Map<String, dynamic> m) => AiAction(
        category: '${m['category'] ?? 'sensor'}',
        priority: '${m['priority'] ?? 'low'}',
        title: '${m['action'] ?? ''}',
        reason: '${m['reason'] ?? ''}',
        when: '${m['when'] ?? ''}',
      );

  /// irrigation, fertilizer, soil_ph, climate, pest, disease, sensor
  final String category;

  /// high, medium, low
  final String priority;
  final String title;
  final String reason;
  final String when;

  AiFilter get filter => switch (category) {
        'irrigation' => AiFilter.water,
        'fertilizer' || 'soil_ph' => AiFilter.nutrient,
        _ => AiFilter.growth, // climate, pest, disease, sensor
      };

  AiSeverity get severity => switch (priority) {
        'high' => AiSeverity.critical,
        'medium' => AiSeverity.caution,
        _ => AiSeverity.info,
      };

  /// "When · why" in one line, for the card's advice text.
  String get detail => [when, reason].where((s) => s.trim().isNotEmpty).join(' · ');

  /// Stable id for "Mark as done" / "Dismiss": the same advice keeps the same id
  /// even when Gemini is asked again with the same conditions.
  String get id => 'ai:$category:${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';
}

class AiRecommendation {
  AiRecommendation({
    required this.status,
    required this.summary,
    required this.actions,
    required this.forecastNote,
    required this.photoNote,
    required this.sensorIssues,
    required this.source,
    required this.model,
    required this.createdAt,
    required this.lastUsedAt,
  });

  factory AiRecommendation.fromRow(Map<String, dynamic> row) {
    final rec = Map<String, dynamic>.from(row['recommendation'] as Map? ?? {});
    final actions = (rec['actions'] as List? ?? [])
        .map((a) => AiAction.fromMap(Map<String, dynamic>.from(a as Map)))
        .toList()
      ..sort((a, b) => a.severity.rank.compareTo(b.severity.rank));
    return AiRecommendation(
      status: '${rec['overall_status'] ?? 'watch'}',
      summary: '${rec['summary'] ?? ''}',
      actions: actions,
      forecastNote: '${rec['forecast_note'] ?? ''}',
      photoNote: '${rec['photo_note'] ?? ''}',
      sensorIssues: friendlySensorIssues(List<String>.from(rec['sensor_issues'] as List? ?? [])),
      source: '${row['source'] ?? 'rule_based'}',
      model: row['model'] as String?,
      createdAt: DateTime.tryParse('${row['created_at']}')?.toLocal(),
      lastUsedAt: DateTime.tryParse('${row['last_used_at']}')?.toLocal(),
    );
  }

  /// good, watch, act_now
  final String status;
  final String summary;
  final List<AiAction> actions;
  final String forecastNote;
  final String photoNote;
  final List<String> sensorIssues;

  /// gemini or rule_based
  final String source;
  final String? model;
  final DateTime? createdAt;

  /// Updated every scheduled run (every 15 min) even when the cache is reused.
  final DateTime? lastUsedAt;

  bool get isAi => source == 'gemini';

  /// False when the advisor hasn't run for a while (schedule stopped, device offline):
  /// the profile then shows its own rule-based cards instead.
  bool isFresh({Duration maxAge = const Duration(hours: 3)}) =>
      lastUsedAt != null && DateTime.now().difference(lastUsedAt!) <= maxAge;

  List<AiAction> actionsFor(AiFilter? filter) =>
      filter == null ? actions : actions.where((a) => a.filter == filter).toList();
}

/// One photo analysis = one point on the growth timeline.
class GrowthObservation {
  GrowthObservation({
    required this.id,
    required this.takenAt,
    required this.stage,
    required this.leafCondition,
    required this.symptoms,
    required this.causes,
    required this.diseaseLabel,
    required this.imageUrl,
    required this.notes,
  });

  factory GrowthObservation.fromRow(Map<String, dynamic> row) {
    final a = Map<String, dynamic>.from(row['analysis'] as Map? ?? {});
    // image_taken_at is copied from sensor_readings.timestamp, whose clock
    // fields are already local time but labelled +00 (same rule the app uses
    // in _updatedText / _lastReadingAsLocal), so rebuild it as local.
    // created_at is written by the server in real UTC, so convert normally.
    DateTime? taken;
    final rawTaken = DateTime.tryParse('${row['image_taken_at']}')?.toUtc();
    if (rawTaken != null) {
      taken = DateTime(rawTaken.year, rawTaken.month, rawTaken.day,
          rawTaken.hour, rawTaken.minute, rawTaken.second);
    } else {
      taken = DateTime.tryParse('${row['created_at']}')?.toLocal();
    }
    return GrowthObservation(
      id: '${row['id']}',
      takenAt: taken,
      stage: '${a['growth_stage'] ?? 'unknown'}',
      leafCondition: '${a['leaf_condition'] ?? 'unknown'}',
      symptoms: List<String>.from(a['observed_symptoms'] as List? ?? []),
      causes: (a['possible_causes'] as List? ?? [])
          .map((c) => Map<String, dynamic>.from(c as Map))
          .map((c) => '${c['name']} (${c['confidence']})')
          .toList(),
      diseaseLabel: '${a['disease_label'] ?? 'unknown'}',
      imageUrl: row['image_url'] as String?,
      notes: '${a['notes'] ?? ''}',
    );
  }

  final String id;
  final DateTime? takenAt;

  /// seedling, vegetative, mature, unknown
  final String stage;

  /// healthy, mild_issue, severe_issue, unknown
  final String leafCondition;
  final List<String> symptoms;

  /// e.g. "nitrogen deficiency (medium)"
  final List<String> causes;
  final String diseaseLabel;
  final String? imageUrl;
  final String notes;

  static const stages = ['seedling', 'vegetative', 'mature'];

  /// 0 = seedling, 1 = vegetative, 2 = mature, -1 = unknown.
  int get stageIndex => stages.indexOf(stage);

  String get stageLabel => switch (stage) {
        'seedling' => 'Seedling',
        'vegetative' => 'Vegetative (leaf growth)',
        'mature' => 'Mature / ready to harvest',
        _ => 'Stage not clear from photo',
      };

  bool get hasProblem => leafCondition == 'mild_issue' || leafCondition == 'severe_issue';

  /// Short line for a timeline entry.
  String get summary {
    if (!hasProblem) return leafCondition == 'healthy' ? 'Leaves look healthy' : 'No clear signs in photo';
    final what = symptoms.isNotEmpty ? symptoms.take(2).join(', ') : diseaseLabel;
    return 'Possible problem: $what';
  }
}

// ---------------------------------------------------------------- service

class AiInsightsService {
  AiInsightsService._();
  static SupabaseClient get _db => Supabase.instance.client;

  /// Latest recommendation for a device, live.
  static Stream<AiRecommendation?> recommendation(String deviceId) => _db
      .from('ai_recommendations')
      .stream(primaryKey: ['id'])
      .eq('device_id', deviceId)
      .order('last_used_at', ascending: false)
      .limit(1)
      .map((rows) => rows.isEmpty ? null : AiRecommendation.fromRow(rows.first));

  /// Photo analyses for the growth timeline, newest first, live.
  /// Unusable photos (too dark, blurry, no plant) are left out.
  static Stream<List<GrowthObservation>> growthHistory(String deviceId, {int limit = 30}) => _db
      .from('ai_image_analyses')
      .stream(primaryKey: ['id'])
      .eq('device_id', deviceId)
      .order('created_at', ascending: false)
      .limit(limit)
      .map((rows) => rows
          .where((r) => (r['analysis'] as Map?)?['image_usable'] == true)
          .map(GrowthObservation.fromRow)
          .toList());

  /// Most recent photo with a clear growth stage, or null.
  static GrowthObservation? currentStage(List<GrowthObservation> history) {
    for (final o in history) {
      if (o.stageIndex >= 0) return o;
    }
    return null;
  }
}