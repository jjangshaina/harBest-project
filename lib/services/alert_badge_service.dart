import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_harbest_1/services/crop_services.dart';

/// Tracks whether there are alerts the user has not seen yet, so the
/// bottom nav can show a red dot on the Alerts icon.
///
/// - A new alert arriving (realtime insert) while the user is NOT on the
///   Alerts tab turns the dot on.
/// - Opening the Alerts tab turns it off and remembers the newest alert
///   that was seen (per device), so the dot also survives app restarts.
class AlertBadgeService extends ChangeNotifier {
  AlertBadgeService._();
  static final instance = AlertBadgeService._();

  static const _prefPrefix = 'alerts_last_seen_';

  final _db = Supabase.instance.client;

  bool hasUnread = false;

  RealtimeChannel? _channel;
  String? _deviceId;
  bool _started = false;
  bool _viewing = false; // true while the Alerts tab is open
  DateTime? _latest; // newest alert created_at known for this device

  /// Call once after sign-in (safe to call again).
  void start() {
    if (_started) return;
    _started = true;
    CropService.instance.addListener(_onCropChanged);
    _onCropChanged();
  }

  /// Tell the service whether the Alerts tab is currently showing.
  void setViewing(bool viewing) {
    _viewing = viewing;
    if (viewing) _markSeen();
  }

  void _teardown() {
    if (_channel != null) {
      _db.removeChannel(_channel!);
      _channel = null;
    }
  }

  void _onCropChanged() {
    final svc = CropService.instance;
    if (!svc.loaded) {
      // Signed out (or not loaded yet): reset everything.
      _teardown();
      _deviceId = null;
      _latest = null;
      if (hasUnread) {
        hasUnread = false;
        notifyListeners();
      }
      return;
    }

    final id = svc.selected?.deviceId;
    if (id == _deviceId) return;

    _teardown();
    _deviceId = id;
    _latest = null;
    hasUnread = false;
    notifyListeners();

    if (id != null) {
      _checkExisting(id);
      _subscribe(id);
    }
  }

  DateTime? _parse(dynamic v) => DateTime.tryParse('$v')?.toUtc();

  Future<void> _checkExisting(String deviceId) async {
    try {
      final rows = await _db
          .from('alerts')
          .select('created_at')
          .eq('device_id', deviceId)
          .order('created_at', ascending: false)
          .limit(1);
      if (deviceId != _deviceId) return;
      if ((rows as List).isEmpty) return;

      final newest = _parse(rows.first['created_at']);
      if (newest == null) return;
      if (_latest == null || newest.isAfter(_latest!)) _latest = newest;

      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('$_prefPrefix$deviceId');
      if (deviceId != _deviceId) return;

      if (saved == null) {
        // First run on this device: don't flag old alerts as new.
        await prefs.setString(
          '$_prefPrefix$deviceId',
          newest.toIso8601String(),
        );
        return;
      }

      final lastSeen = DateTime.tryParse(saved)?.toUtc();
      if (!_viewing && lastSeen != null && newest.isAfter(lastSeen)) {
        hasUnread = true;
        notifyListeners();
      } else if (_viewing) {
        _markSeen();
      }
    } catch (e) {
      debugPrint('AlertBadgeService check error: $e');
    }
  }

  void _subscribe(String deviceId) {
    _channel = _db
        .channel('alert_badge_$deviceId')
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
            if (deviceId != _deviceId) return;
            final created = _parse(payload.newRecord['created_at']);
            if (created != null && (_latest == null || created.isAfter(_latest!))) {
              _latest = created;
            }
            if (_viewing) {
              _markSeen();
            } else if (!hasUnread) {
              hasUnread = true;
              notifyListeners();
            }
          },
        )
        .subscribe();
  }

  Future<void> _markSeen() async {
    if (hasUnread) {
      hasUnread = false;
      notifyListeners();
    }
    final id = _deviceId;
    final latest = _latest;
    if (id == null || latest == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefPrefix$id', latest.toIso8601String());
    } catch (_) {}
  }
}