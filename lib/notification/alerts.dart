import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_harbest_1/services/crop_services.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/widgets/app_header.dart';
import 'package:flutter_application_harbest_1/widgets/app_card.dart';
import 'package:flutter_application_harbest_1/widgets/app_empty_state.dart';
import 'package:flutter_application_harbest_1/widgets/app_snackbar.dart';

class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage>
    with OfflineNotice<AlertsPage> {
  // ── NO INTERNET ──
  @override
  int get tabIndex => 4;

  @override
  bool get hasLastData => _alerts.isNotEmpty;

  // Alerts that arrived while offline were missed by the live updates.
  @override
  void onBackOnline() {
    final id = _deviceId;
    if (id == null) return;
    _reconnectLiveAlerts(id);
    _fetchAlerts(id);
    _fetchLatestReading();
  }

  // Live updates can drop while offline; open them again.
  Future<void> _reconnectLiveAlerts(String id) async {
    final old = _alertsChannel;
    _alertsChannel = null;
    if (old != null) await _supabase.removeChannel(old);
    if (!mounted || id != _deviceId) return;
    _subscribeToAlerts(id);
  }

  // Every 30 s: new alerts (in case a live update was missed) and the
  // "Updated ... ago" time.
  void _autoRefresh() {
    final id = _deviceId;
    if (id != null) _fetchAlerts(id);
    _fetchLatestReading();
  }

  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _alerts = [];
  bool _isLoading = true;
  RealtimeChannel? _alertsChannel;
  String? _deviceId;
  bool _initialized = false;
  Object? _latestTimestamp; // newest sensor_readings.timestamp

  // Re-reads the newest reading every 30s; this also keeps "Updated x mins
  // ago" counting up.
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    CropService.instance.addListener(_onCropChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onCropChanged());
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _autoRefresh(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    CropService.instance.removeListener(_onCropChanged);
    if (_alertsChannel != null) _supabase.removeChannel(_alertsChannel!);
    super.dispose();
  }

  // Runs when the crops finish loading or the user switches crop.
  void _onCropChanged() {
    if (!mounted) return;
    final svc = CropService.instance;
    if (!svc.loaded) return;
    final id = svc.selected?.deviceId;
    if (_initialized && id == _deviceId) return;
    _initialized = true;
    _deviceId = id;
    if (_alertsChannel != null) {
      _supabase.removeChannel(_alertsChannel!);
      _alertsChannel = null;
    }
    setState(() {
      _alerts = [];
      _isLoading = id != null;
      _latestTimestamp = null;
    });
    _fetchLatestReading();
    if (id != null) {
      _fetchAlerts(id);
      _subscribeToAlerts(id);
    }
  }

  Future<void> _fetchAlerts(String deviceId, {bool userAction = false}) async {
    try {
      final response = await _supabase
          .from('alerts')
          .select()
          .eq('device_id', deviceId)
          .order('created_at', ascending: false)
          .limit(100)
          .timeout(kRequestTimeout);

      if (!mounted || deviceId != _deviceId) return;
      markConnection(true);
      LastData.save('alerts_$deviceId', response);

      setState(() {
        _alerts = List<Map<String, dynamic>>.from(
          response,
        ).where((a) => a['device_id'] == deviceId).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Alerts fetch error: $e');
      if (!mounted || deviceId != _deviceId) return;
      // No internet and nothing on screen yet: use the alerts saved on the
      // phone. Alerts already on screen stay there.
      if (_alerts.isEmpty && isConnectionError(e)) {
        final saved = await LastData.read('alerts_$deviceId');
        if (!mounted || deviceId != _deviceId) return;
        if (saved is List) {
          try {
            _alerts = [for (final a in saved) Map<String, dynamic>.from(a)];
          } catch (e) {
            debugPrint('Saved alerts unreadable: $e');
          }
        }
      }
      setState(() => _isLoading = false);
      if (isConnectionError(e)) {
        markConnection(false, userAction: userAction);
      }
    }
  }

  void _subscribeToAlerts(String deviceId) {
    _alertsChannel = _supabase
        .channel('alerts_$deviceId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'alerts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'device_id',
            value: deviceId,
          ),
          callback: (payload) {
            if (!mounted || deviceId != _deviceId) return;
            final row = Map<String, dynamic>.from(payload.newRecord);
            if (row['device_id'] != deviceId) return;
            setState(() => _alerts.insert(0, row));
          },
        )
        .subscribe();
  }

  // Newest sensor reading for the selected crop (drives "Updated ...").
  Future<void> _fetchLatestReading() async {
    final id = CropService.instance.selected?.deviceId;
    if (id == null) {
      if (mounted) setState(() => _latestTimestamp = null);
      return;
    }
    try {
      final rows = await Supabase.instance.client
          .from('sensor_readings')
          .select('timestamp')
          .eq('device_id', id)
          .order('timestamp', ascending: false)
          .limit(1)
          .timeout(kRequestTimeout);
      if (!mounted || CropService.instance.selected?.deviceId != id) return;
      markConnection(true);
      final ts = rows.isEmpty ? null : rows.first['timestamp'];
      LastData.save('latest_reading_$id', ts);
      setState(() => _latestTimestamp = ts);
    } catch (e) {
      debugPrint('Latest reading fetch error: $e');
      if (!mounted || !isConnectionError(e)) return;
      // Opened offline: "Updated ... ago" from the time saved on the phone.
      if (_latestTimestamp == null) {
        final saved = await LastData.read('latest_reading_$id');
        if (!mounted || CropService.instance.selected?.deviceId != id) return;
        if (saved != null) setState(() => _latestTimestamp = saved);
      }
      // Runs every 30 s, so this is also what notices a lost connection.
      markConnection(false);
    }
  }

  // Pull-to-refresh. Also retries the crop list if it could not load.
  Future<void> _refresh() async {
    if (CropService.instance.offline) {
      await CropService.instance.load();
      if (!mounted) return;
    }
    final id = _deviceId;
    if (id == null) {
      if (CropService.instance.offline) {
        markConnection(false, userAction: true);
      }
      return;
    }
    await Future.wait([
      _fetchAlerts(id, userAction: true),
      _fetchLatestReading(),
    ]);
  }

  // "Updated 5 mins ago", from the newest reading's timestamp. The stored
  // clock fields are already local time, so they are rebuilt as a local
  // DateTime before comparing with now (same as the Plant Profile page).
  String _updatedText() {
    final raw = _latestTimestamp;
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

  // "5 mins ago" style formatting from a timestamp string
  String _timeAgo(String? createdAt) {
    if (createdAt == null) return '';
    final time = DateTime.tryParse(createdAt);
    if (time == null) return '';

    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} min${diff.inMinutes == 1 ? '' : 's'} ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours} hr${diff.inHours == 1 ? '' : 's'} ago';
    }
    return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  }

  ({IconData icon, Color color}) _severityStyle(String? severity) {
    switch (severity) {
      case 'critical':
        return (icon: AppIcons.error, color: AppColors.critical);
      case 'info':
        return (icon: AppIcons.info, color: AppColors.info);
      case 'warning':
      default:
        return (icon: AppIcons.warning, color: AppColors.caution);
    }
  }

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    final style = _severityStyle(alert['severity'] as String?);
    final title = alert['title'] ?? alert['message'] ?? 'Alert';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.gap),
      child: SizedBox(
        width: double.infinity,
        child: AppCard(
          padding: const EdgeInsets.all(AppSpace.cardGap),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(style.icon, color: style.color, size: 24),
              const SizedBox(width: AppSpace.gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppText.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _timeAgo(alert['created_at'] as String?),
                      style: AppText.caption.copyWith(fontSize: 12),
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
  final updated = _updatedText();
  final noInternet = offline || CropService.instance.offline;
  final Widget body;
  if (CropService.instance.loaded && CropService.instance.selected == null) {
    body = AppRefreshable(
      onRefresh: _refresh,
      child: CropService.instance.offline
          ? const AppOfflineState()
          : const AppNoCropState(),
    );
  } else if (_isLoading) {
    body = const Center(child: CircularProgressIndicator());
  } else if (_alerts.isEmpty) {
    // Pullable, so the user can check again for new alerts.
    body = AppRefreshable(
      onRefresh: _refresh,
      child: noInternet
          ? const AppOfflineState()
          : const AppEmptyState(
              icon: AppIcons.alertsOff,
              title: 'No recent alerts',
              message:
                  'Alerts will appear here once your sensors detected a problem.',
            ),
    );
  } else {
    // The last alerts stay listed while offline.
    body = RefreshIndicator(
      color: AppColors.green,
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpace.page),
        itemCount: _alerts.length,
        itemBuilder: (context, index) => _buildAlertCard(_alerts[index]),
      ),
    );
  }

  return Column(
    children: [
      AppHeader(
        title: 'Recent Alerts',
        subtitle: updated.isEmpty ? null : updated,
      ),
      Expanded(child: body),
    ],
  );
}
}