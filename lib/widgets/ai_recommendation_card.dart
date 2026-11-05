// HarBest - AI recommendation + crop photo cards
//
// Shows the latest Gemini recommendation and photo analysis, updating live
// when the gemini-advisor function writes a new one.
//
// Needs only supabase_flutter (already used by your app).
// The dashboard passes the selected crop's deviceId, e.g.:
//   dependencies:
//     supabase_flutter: ^2.0.0
//
// Use anywhere on a screen:
//   const AiRecommendationCard(deviceId: 'harbest_pi_zero_w'),
//   const AiPhotoCard(deviceId: 'harbest_pi_zero_w'),

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _db = Supabase.instance.client;

/// Latest row of a table for one device, live (Realtime).
Stream<Map<String, dynamic>?> _latest(String table, String deviceId, String orderBy) => _db
    .from(table)
    .stream(primaryKey: ['id'])
    .eq('device_id', deviceId)
    .order(orderBy, ascending: false)
    .limit(1)
    .map((rows) => rows.isEmpty ? null : rows.first);

/// Keeps ONE live connection per card. The dashboard rebuilds often (timers,
/// new readings); creating the stream inside build() would reconnect and
/// flash the spinner every time. It only reconnects when the device changes.
class _LatestRow extends StatefulWidget {
  const _LatestRow({
    required this.table,
    required this.deviceId,
    required this.orderBy,
    required this.builder,
  });
  final String table;
  final String deviceId;
  final String orderBy;
  final AsyncWidgetBuilder<Map<String, dynamic>?> builder;

  @override
  State<_LatestRow> createState() => _LatestRowState();
}

class _LatestRowState extends State<_LatestRow> {
  late Stream<Map<String, dynamic>?> _stream;

  @override
  void initState() {
    super.initState();
    _stream = _latest(widget.table, widget.deviceId, widget.orderBy);
  }

  @override
  void didUpdateWidget(covariant _LatestRow old) {
    super.didUpdateWidget(old);
    if (old.deviceId != widget.deviceId || old.table != widget.table) {
      _stream = _latest(widget.table, widget.deviceId, widget.orderBy);
    }
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<Map<String, dynamic>?>(stream: _stream, builder: widget.builder);
}

String _ago(String? iso) {
  if (iso == null) return '';
  final d = DateTime.now().difference(DateTime.parse(iso).toLocal());
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

// ---------------------------------------------------------------- recommendation
class AiRecommendationCard extends StatelessWidget {
  const AiRecommendationCard({super.key, required this.deviceId});
  final String deviceId;

  static const _status = {
    'good': (Colors.green, Icons.check_circle, 'All good'),
    'watch': (Colors.orange, Icons.visibility, 'Keep an eye on it'),
    'act_now': (Colors.red, Icons.warning_amber_rounded, 'Act now'),
  };
  static const _categoryIcon = {
    'irrigation': Icons.water_drop,
    'fertilizer': Icons.grass,
    'soil_ph': Icons.science,
    'climate': Icons.thermostat,
    'pest': Icons.bug_report,
    'disease': Icons.healing,
    'sensor': Icons.sensors_off,
  };
  static const _priorityColor = {'high': Colors.red, 'medium': Colors.orange, 'low': Colors.blueGrey};

  @override
  Widget build(BuildContext context) {
    return _LatestRow(
      table: 'ai_recommendations',
      deviceId: deviceId,
      orderBy: 'last_used_at',
      builder: (context, snap) {
        if (snap.hasError) return _message(context, 'Could not load recommendation: ${snap.error}');
        if (!snap.hasData) {
          return snap.connectionState == ConnectionState.waiting
              ? const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())))
              : _message(context, 'No recommendation yet. It updates every 15 minutes.');
        }
        final row = snap.data!;
        final rec = Map<String, dynamic>.from(row['recommendation'] as Map);
        final (color, icon, label) = _status[rec['overall_status']] ?? _status['watch']!;
        final actions = List<Map<String, dynamic>>.from(
            (rec['actions'] as List? ?? []).map((a) => Map<String, dynamic>.from(a as Map)));
        final issues = List<String>.from(rec['sensor_issues'] as List? ?? []);
        final isAi = row['source'] == 'gemini';
        final t = Theme.of(context).textTheme;

        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: color.withOpacity(0.12),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(child: Text(label, style: t.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w600))),
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(isAi ? Icons.auto_awesome : Icons.rule, size: 16),
                  label: Text(isAi ? 'AI' : 'Rule-based'),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(rec['summary'] ?? '', style: t.bodyLarge),
            ),
            for (final a in actions)
              ListTile(
                leading: Icon(_categoryIcon[a['category']] ?? Icons.info_outline,
                    color: _priorityColor[a['priority']] ?? Colors.blueGrey),
                title: Text(a['action'] ?? ''),
                subtitle: Text([a['when'], a['reason']].where((s) => (s ?? '').toString().isNotEmpty).join(' · ')),
                dense: true,
              ),
            if ((rec['forecast_note'] ?? '').toString().isNotEmpty)
              _note(context, Icons.timeline, rec['forecast_note']),
            if ((rec['photo_note'] ?? '').toString().isNotEmpty)
              _note(context, Icons.photo_camera, rec['photo_note']),
            if (issues.isNotEmpty) _note(context, Icons.sensors_off, issues.join('\n'), muted: true),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                'Updated ${_ago(row['created_at'])}'
                '${isAi ? ' · AI advice can be wrong - check your plants before acting' : ''}',
                style: t.bodySmall?.copyWith(color: Theme.of(context).hintColor),
              ),
            ),
          ]),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- photo
class AiPhotoCard extends StatelessWidget {
  const AiPhotoCard({super.key, required this.deviceId});
  final String deviceId;

  static const _leaf = {
    'healthy': (Colors.green, 'Leaves look healthy'),
    'mild_issue': (Colors.orange, 'Possible mild problem'),
    'severe_issue': (Colors.red, 'Possible serious problem'),
    'unknown': (Colors.blueGrey, 'Could not tell from the photo'),
  };

  @override
  Widget build(BuildContext context) {
    return _LatestRow(
      table: 'ai_image_analyses',
      deviceId: deviceId,
      orderBy: 'created_at',
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink(); // no photo analysis yet
        final row = snap.data!;
        final a = Map<String, dynamic>.from(row['analysis'] as Map);
        final t = Theme.of(context).textTheme;
        final usable = a['image_usable'] == true;
        final (color, label) = _leaf[a['leaf_condition']] ?? _leaf['unknown']!;
        final symptoms = List<String>.from(a['observed_symptoms'] as List? ?? []);
        final causes = List<Map<String, dynamic>>.from(
            (a['possible_causes'] as List? ?? []).map((c) => Map<String, dynamic>.from(c as Map)));

        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (row['image_url'] != null)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(row['image_url'], fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image))),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.eco, color: usable ? color : Colors.blueGrey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(usable ? label : 'Photo not usable: ${a['quality_issue'] ?? ''}',
                        style: t.titleMedium?.copyWith(color: usable ? color : null)),
                  ),
                ]),
                if (symptoms.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Seen: ${symptoms.join(', ')}'),
                ],
                if (causes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final c in causes)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text('Possible ${c['name']} (${c['confidence']})'),
                      ),
                  ]),
                ],
                const SizedBox(height: 8),
                Text(
                  'Photo checked ${_ago(row['created_at'])} · AI photo analysis is a guide, not a diagnosis',
                  style: t.bodySmall?.copyWith(color: Theme.of(context).hintColor),
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- small helpers
Widget _note(BuildContext context, IconData icon, String text, {bool muted = false}) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: Theme.of(context).hintColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: muted
                  ? Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor)
                  : Theme.of(context).textTheme.bodyMedium),
        ),
      ]),
    );

Widget _message(BuildContext context, String text) =>
    Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(text)));