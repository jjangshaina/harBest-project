import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_harbest_1/insights/insight_rules.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/widgets/app_button.dart';
import 'package:flutter_application_harbest_1/widgets/app_card.dart';
import 'package:flutter_application_harbest_1/widgets/app_empty_state.dart';
import 'package:flutter_application_harbest_1/widgets/app_header.dart';
import 'package:flutter_application_harbest_1/widgets/app_snackbar.dart';
import 'package:flutter_application_harbest_1/widgets/status_widgets.dart';

// A recommendation the user marked done / dismissed. It stays hidden until
// [until] passes, the sensor returns to range, or it gets worse.
class _Hidden {
  final DateTime until;
  final int level; // HealthLevel.index when it was hidden
  const _Hidden(this.until, this.level);
}

class InsightsRecommendation extends StatefulWidget {
  const InsightsRecommendation({super.key});

  @override
  State<InsightsRecommendation> createState() => _InsightsRecommendationState();
}

class _InsightsRecommendationState extends State<InsightsRecommendation> {
  static const int _historyLength = 20;
  static const Duration _snoozeFor = Duration(hours: 6);
  static const String _hiddenPrefsKey = 'insights_hidden_v1';

  final _supabase = Supabase.instance.client;

  Map<String, dynamic> _reading = {};
  List<Map<String, dynamic>> _history = [];
  List<Recommendation> _recs = [];
  final Map<String, _Hidden> _hidden = {};

  InsightCategory? _filter; // null = All
  bool _isLoading = true;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _init();
    // Re-reads the sensors every 30s; this also keeps "Updated x mins ago"
    // counting up. (This page stays alive inside the bottom-nav IndexedStack.)
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _fetch(silent: true),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadHidden();
    await _fetch(silent: true);
  }

  // ── DATA ──────────────────────────────────────────────────────────────

  Future<void> _fetch({bool silent = false}) async {
    try {
      final response = await _supabase
          .from('sensor_readings')
          .select()
          .order('id', ascending: false)
          .limit(_historyLength);
      if (!mounted) return;

      final rows = List<Map<String, dynamic>>.from(
        (response as List).map((e) => Map<String, dynamic>.from(e)),
      );

      if (rows.isEmpty) {
        setState(() {
          _error = 'No sensor data found. Start your Raspberry Pi!';
          _isLoading = false;
        });
        return;
      }

      final history = rows.reversed.toList(); // oldest → newest
      final recs = buildRecommendations(rows.first, history);

      // Forget hidden items whose sensor is back in range, so a new problem
      // later is not silently hidden.
      final before = _hidden.length;
      _hidden.removeWhere((k, _) => !recs.any((r) => r.key == k));

      setState(() {
        _reading = rows.first;
        _history = history;
        _recs = recs;
        _isLoading = false;
        _error = null;
      });
      if (_hidden.length != before) _saveHidden();
    } catch (e) {
      debugPrint('Insights fetch error: $e');
      if (!mounted) return;
      if (_reading.isEmpty) {
        setState(() {
          _error = 'Could not load sensor data. Check your connection.';
          _isLoading = false;
        });
      } else if (!silent) {
        AppSnack.show(context, 'Could not refresh. Showing the last data.',
            type: AppSnackType.error);
      }
    }
  }

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

  // "Updated 5 mins ago", from the newest reading's timestamp. Same handling
  // as the Dashboard: the stored clock fields are already local time, so they
  // are rebuilt as a local DateTime before comparing with now.
  String _updatedText() {
    final raw = _reading['timestamp'];
    if (raw == null) return '';
    final utc = DateTime.tryParse(raw.toString())?.toUtc();
    if (utc == null) return '';
    final dt = DateTime(utc.year, utc.month, utc.day, utc.hour, utc.minute,
        utc.second);
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

  // ── UI PIECES ─────────────────────────────────────────────────────────

  Widget _buildSummaryStrip(List<Recommendation> open) {
    final critical = open.where((r) => r.level == HealthLevel.critical).length;
    final priorities = open.where((r) => r.score < kPriorityBelowScore).length;

    final AppStatusPill status;
    if (open.isEmpty) {
      status = AppStatusPill.level(HealthLevel.optimal, text: 'ALL CLEAR');
    } else if (critical > 0) {
      status = AppStatusPill.level(HealthLevel.critical);
    } else {
      status = AppStatusPill.level(HealthLevel.caution);
    }

    return SizedBox(
      width: double.infinity,
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          children: [
            Row(
              children: [
                const Text('Overall status', style: AppText.label),
                const Spacer(),
                status,
              ],
            ),
            const Divider(height: 22, color: AppColors.divider),
            Row(
              children: [
                _stat('Actions', '${open.length}'),
                _stat('Priorities', '$priorities'),
                _stat('Critical', '$critical',
                    color: critical > 0 ? AppColors.critical : null),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, {Color? color}) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: AppText.sectionTitle.copyWith(color: color)),
          const SizedBox(height: 2),
          Text(label, style: AppText.label.copyWith(color: color)),
        ],
      ),
    );
  }

  Widget _iconTile(Recommendation r) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: r.level.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(r.def.icon, size: 22, color: r.level.color),
    );
  }

  Widget _recHeader(Recommendation r) {
    return Row(
      children: [
        _iconTile(r),
        const SizedBox(width: 12),
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
              Text(r.subtitle, style: AppText.label),
            ],
          ),
        ),
      ],
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
      child: Text(message, style: AppText.body.copyWith(fontSize: 14, height: 1.4)),
    );
  }

  Widget _actions(Recommendation r) {
    return Row(
      children: [
        Expanded(
          child: AppButton(
            label: 'Mark as done',
            expanded: true,
            onPressed: () => _hide(r, done: true),
          ),
        ),
        const SizedBox(width: AppSpace.gap),
        Expanded(
          child: AppButton(
            label: 'Dismiss',
            style: AppButtonStyle.outline,
            expanded: true,
            onPressed: () => _hide(r, done: false),
          ),
        ),
      ],
    );
  }

  // Always the sensor furthest outside its optimal range.
  Widget _buildTopPriority(Recommendation r) {
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        outlineColor: AppColors.emphasisOutline,
        padding: const EdgeInsets.all(AppSpace.cardGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'TOP PRIORITY',
                  style: AppText.label.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppColors.darkGreen,
                  ),
                ),
                const Spacer(),
                AppStatusPill.level(r.level),
              ],
            ),
            const SizedBox(height: 12),
            _recHeader(r),
            const SizedBox(height: 10),
            AppProgressBar(value: r.score / 100, color: r.level.color, height: 6),
            const SizedBox(height: 12),
            _messageBox(r.message),
            const SizedBox(height: 14),
            _actions(r),
          ],
        ),
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
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final option = options[i];
          final selected = option == _filter;
          return ChoiceChip(
            label: Text(
              option?.label ?? 'All',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.onGreen : AppColors.darkGreen,
              ),
            ),
            selected: selected,
            showCheckmark: false,
            selectedColor: AppColors.darkGreen,
            backgroundColor: AppColors.green.withOpacity(0.2),
            side: BorderSide.none,
            onSelected: (_) => setState(() => _filter = option),
          );
        },
      ),
    );
  }

  Widget _buildRecCard(Recommendation r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.cardGap),
      child: SizedBox(
        width: double.infinity,
        child: AppCard(
          padding: const EdgeInsets.all(AppSpace.cardGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _recHeader(r)),
                  const SizedBox(width: 8),
                  AppStatusPill.level(r.level),
                ],
              ),
              const SizedBox(height: 12),
              _messageBox(r.message),
              const SizedBox(height: 14),
              _actions(r),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_error != null && _reading.isEmpty) {
      return Column(
        children: [
          Expanded(
            child: AppEmptyState(
              icon: AppIcons.offline,
              title: 'No insights yet',
              message: _error!,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.section),
            child: AppButton(
              label: 'Retry',
              icon: AppIcons.refresh,
              onPressed: () {
                setState(() => _isLoading = true);
                _fetch(silent: true);
              },
            ),
          ),
        ],
      );
    }

    final open = _recs.where(_isOpen).toList();
    final others = open
        .skip(1)
        .where((r) => _filter == null || r.category == _filter)
        .toList();

    return RefreshIndicator(
      color: AppColors.green,
      onRefresh: () => _fetch(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpace.page),
        children: [
          _buildSummaryStrip(open),
          const SizedBox(height: AppSpace.cardGap),
          if (open.isEmpty)
            const SizedBox(
              height: 320,
              child: AppEmptyState(
                icon: AppIcons.success,
                title: 'All clear',
                message:
                    'All your sensors are in their optimal range. Nothing needs your attention right now.',
              ),
            )
          else ...[
            _buildTopPriority(open.first),
            const SizedBox(height: AppSpace.cardGap),
            _buildFilterChips(),
            const SizedBox(height: AppSpace.cardGap),
            if (others.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.section),
                child: Center(
                  child: Text(
                    _filter == null
                        ? 'No other recommendations right now.'
                        : 'No ${_filter!.label.toLowerCase()} recommendations right now.',
                    style: AppText.subtitle,
                  ),
                ),
              )
            else
              for (final r in others) _buildRecCard(r),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final updated = _updatedText();
    return Column(
      children: [
        AppHeader(
          title: 'AI Insights & Recommendations',
          subtitle: updated.isEmpty ? null : updated,
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }
}