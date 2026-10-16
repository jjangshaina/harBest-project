import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_harbest_1/services/crop_services.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/widgets/app_header.dart';
import 'package:flutter_application_harbest_1/widgets/app_card.dart';
import 'package:flutter_application_harbest_1/widgets/app_empty_state.dart';

class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _alerts = [];
  bool _isLoading = true;
  RealtimeChannel? _alertsChannel;
  String? _deviceId;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    CropService.instance.addListener(_onCropChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onCropChanged());
  }

  @override
  void dispose() {
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
    });
    if (id != null) {
      _fetchAlerts(id);
      _subscribeToAlerts(id);
    }
  }

  Future<void> _fetchAlerts(String deviceId) async {
    try {
      final response = await _supabase
          .from('alerts')
          .select()
          .eq('device_id', deviceId)
          .order('created_at', ascending: false)
          .limit(100);

      if (!mounted || deviceId != _deviceId) return;

      setState(() {
        _alerts = List<Map<String, dynamic>>.from(response)
            .where((a) => a['device_id'] == deviceId)
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      debugPrint('Alerts fetch error: $e');
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
    return Column(
      children: [
        const AppHeader(title: 'Recent Alerts'),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _alerts.isEmpty
                  ? const AppEmptyState(
                      icon: AppIcons.alertsOff,
                      title: 'No recent alerts',
                      message:
                          'Alerts will appear here once your sensors detected a problem.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(AppSpace.page),
                      itemCount: _alerts.length,
                      itemBuilder: (context, index) =>
                          _buildAlertCard(_alerts[index]),
                    ),
        ),
      ],
    );
  }
}