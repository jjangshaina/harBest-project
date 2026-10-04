import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
        return (icon: Icons.error, color: Colors.red);
      case 'info':
        return (icon: Icons.info, color: Colors.blue);
      case 'warning':
      default:
        return (icon: Icons.warning_rounded, color: Colors.orange);
    }
  }

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    final style = _severityStyle(alert['severity'] as String?);
    final title = alert['title'] ?? alert['message'] ?? 'Alert';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(style.icon, color: style.color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  _timeAgo(alert['created_at'] as String?),
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.notifications_off_rounded, size: 56, color: Colors.black26),
            const SizedBox(height: 16),
            const Text(
              'No recent alerts',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Alerts will appear here once your sensors detected a problem.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // GREEN HEADER
        Container(
          padding: const EdgeInsets.only(
            top: 60,
            left: 20,
            right: 20,
            bottom: 20,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF7CB342),
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(30),
              bottomRight: Radius.circular(30),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Alerts',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),

        // Body
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _alerts.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: _alerts.length,
                      itemBuilder: (context, index) => _buildAlertCard(_alerts[index]),
                    ),
        ),
      ],
    );
  }
}