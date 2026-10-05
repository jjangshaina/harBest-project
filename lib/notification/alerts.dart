import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  late final RealtimeChannel _alertsChannel;

  @override
  void initState() {
    super.initState();
    _fetchAlerts();
    _subscribeToAlerts();
  }

  @override
  void dispose() {
    _supabase.removeChannel(_alertsChannel);
    super.dispose();
  }

  Future<void> _fetchAlerts() async {
    try {
      final response = await _supabase
          .from('alerts')
          .select()
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        _alerts = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      debugPrint("Alerts fetch error: $e");
    }
  }

  void _subscribeToAlerts() {
    _alertsChannel = _supabase
        .channel('alerts_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: '',
          callback: (payload) {
            if (!mounted) return;
            setState(() {
              _alerts.insert(0, Map<String, dynamic>.from(payload.newRecord));
            });
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

        // Body
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