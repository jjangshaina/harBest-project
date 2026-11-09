import 'package:flutter/material.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';

/// How long since we last heard from the device decides its connection
/// state. The Pi sends a heartbeat every 30 s and a full reading every
/// ~90 s, so 3 minutes means at least one beat and two readings were missed.
const Duration kOnlineWithin = Duration(minutes: 3);
const Duration kDelayedWithin = Duration(minutes: 10);

enum DeviceConnection { online, delayed, offline, unknown }

extension DeviceConnectionX on DeviceConnection {
  String get label => switch (this) {
        DeviceConnection.online => 'Online',
        DeviceConnection.delayed => 'Delayed',
        DeviceConnection.offline => 'Offline',
        DeviceConnection.unknown => 'No signal yet',
      };

  Color get color => switch (this) {
        DeviceConnection.online => AppColors.optimal,
        DeviceConnection.delayed => AppColors.caution,
        DeviceConnection.offline => AppColors.critical,
        DeviceConnection.unknown => AppColors.textTertiary,
      };

  IconData get icon => switch (this) {
        DeviceConnection.online => AppIcons.online,
        DeviceConnection.delayed => AppIcons.warning,
        DeviceConnection.offline => AppIcons.offline,
        DeviceConnection.unknown => AppIcons.offline,
      };

  String get explanation => switch (this) {
        DeviceConnection.online => 'Your device is connected and sending data.',
        DeviceConnection.delayed =>
          'The device has been quiet for a few minutes. It may have a weak '
              'Wi-Fi signal or be restarting.',
        DeviceConnection.offline =>
          'We have not heard from the device in over '
              '${kDelayedWithin.inMinutes} minutes. Check that it is plugged '
              'in and connected to Wi-Fi.',
        DeviceConnection.unknown =>
          'The device has not connected yet. Make sure it is switched on and '
              'connected to Wi-Fi.',
      };
}

DeviceConnection connectionFor(DateTime? lastSeen, {DateTime? now}) {
  if (lastSeen == null) return DeviceConnection.unknown;
  final age = (now ?? DateTime.now()).difference(lastSeen);
  if (age <= kOnlineWithin) return DeviceConnection.online;
  if (age <= kDelayedWithin) return DeviceConnection.delayed;
  return DeviceConnection.offline;
}

/// One row of the `device_status` table (written by the Pi's heartbeat).
class DeviceStatus {
  final String deviceId;
  final DateTime? lastSeen; // real instant (stored as true UTC by the server)
  final bool? dht22Ok;
  final bool? npkOk;
  final bool? cameraOk;
  final bool? mqttOk;
  final int? wifiRssi;
  final String? ipAddress;
  final int? uptimeSeconds;
  final double? cpuTemp;
  final double? batteryPct; // 0-100, null = no battery board / not read
  final double? batteryVoltage; // 3S pack volts (9.9 empty - 12.6 full)
  final bool? batteryCharging; // true charging, false on battery, null idle

  const DeviceStatus({
    required this.deviceId,
    this.lastSeen,
    this.dht22Ok,
    this.npkOk,
    this.cameraOk,
    this.mqttOk,
    this.wifiRssi,
    this.ipAddress,
    this.uptimeSeconds,
    this.cpuTemp,
    this.batteryPct,
    this.batteryVoltage,
    this.batteryCharging,
  });

  factory DeviceStatus.fromMap(Map<String, dynamic> m) {
    int? asInt(Object? v) => v is num ? v.toInt() : int.tryParse('$v');
    double? asDouble(Object? v) =>
        v is num ? v.toDouble() : double.tryParse('$v');
    bool? asBool(Object? v) => v is bool ? v : null;

    return DeviceStatus(
      deviceId: '${m['device_id']}',
      lastSeen: DateTime.tryParse('${m['last_seen']}')?.toLocal(),
      dht22Ok: asBool(m['dht22_ok']),
      npkOk: asBool(m['npk_ok']),
      cameraOk: asBool(m['camera_ok']),
      mqttOk: asBool(m['mqtt_ok']),
      wifiRssi: asInt(m['wifi_rssi']),
      ipAddress: m['ip_address'] as String?,
      uptimeSeconds: asInt(m['uptime_s']),
      cpuTemp: asDouble(m['cpu_temp']),
      batteryPct: asDouble(m['battery_pct']),
      batteryVoltage: asDouble(m['battery_voltage']),
      batteryCharging: asBool(m['battery_charging']),
    );
  }

  // --- Battery ---------------------------------------------------------

  bool get hasBattery => batteryPct != null;

  /// Matches BATTERY_LOW_PCT in harbest2.0.py.
  static const double lowBatteryPct = 20;

  bool get isBatteryLow => hasBattery && batteryPct! <= lowBatteryPct;

  /// "73%" or "--".
  String get batteryLabel =>
      hasBattery ? '${batteryPct!.round()}%' : '--';

  /// "11.83 V · On battery" for a tooltip / detail line.
  String get batteryDetail {
    if (!hasBattery) return 'No battery data';
    final state = switch (batteryCharging) {
      true => 'Charging',
      false => 'On battery',
      null => 'Idle',
    };
    return [
      if (batteryVoltage != null) '${batteryVoltage!.toStringAsFixed(2)} V',
      state,
    ].join(' · ');
  }

  Color get batteryColor {
    if (!hasBattery) return AppColors.textTertiary;
    if (isBatteryLow) return AppColors.critical;
    if (batteryPct! <= 50) return AppColors.caution;
    return AppColors.optimal;
  }

  IconData get batteryIcon {
    if (!hasBattery) return Icons.battery_unknown;
    if (batteryCharging == true) return Icons.battery_charging_full;
    final p = batteryPct!;
    if (p <= lowBatteryPct) return Icons.battery_alert;
    if (p >= 95) return Icons.battery_full;
    if (p >= 80) return Icons.battery_6_bar;
    if (p >= 65) return Icons.battery_5_bar;
    if (p >= 50) return Icons.battery_4_bar;
    if (p >= 35) return Icons.battery_3_bar;
    return Icons.battery_2_bar;
  }

  /// "Excellent" / "Good" / "Fair" / "Weak" from the dBm value.
  String? get wifiQuality {
    final r = wifiRssi;
    if (r == null || r == 0) return null;
    if (r >= -50) return 'Excellent';
    if (r >= -60) return 'Good';
    if (r >= -70) return 'Fair';
    return 'Weak';
  }
}

/// Compact battery readout (icon + "73%") to sit inside the device status
/// card, e.g. next to the Online badge. Tap it to see voltage and state.
/// Greyed out when the device isn't online, because the value is then
/// only the last known reading.
///
///   BatteryBadge(status: status, connection: connectionFor(status.lastSeen))
class BatteryBadge extends StatelessWidget {
  final DeviceStatus status;
  final DeviceConnection connection;

  const BatteryBadge({
    super.key,
    required this.status,
    required this.connection,
  });

  @override
  Widget build(BuildContext context) {
    final live = connection == DeviceConnection.online;
    final color = live ? status.batteryColor : AppColors.textTertiary;
    final tip = live
        ? status.batteryDetail
        : 'Last known: ${status.batteryLabel} · ${status.batteryDetail}';

    return Tooltip(
      message: tip,
      triggerMode: TooltipTriggerMode.tap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RotatedBox(
            quarterTurns: 1, // horizontal battery: same height as the text
            child: Icon(status.batteryIcon, size: 18, color: color),
          ),
          const SizedBox(width: 4),
          Text(
            status.batteryLabel,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

/// "Just now", "4 min ago", "2 h ago", "3 days ago".
String formatAgo(DateTime? t, {DateTime? now}) {
  if (t == null) return 'Never';
  final d = (now ?? DateTime.now()).difference(t);
  if (d.isNegative || d.inSeconds < 60) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  final days = d.inDays;
  return '$days day${days == 1 ? '' : 's'} ago';
}

/// "2 d 4 h", "5 h 12 min", "8 min".
String formatUptime(int seconds) {
  final d = Duration(seconds: seconds);
  if (d.inDays > 0) return '${d.inDays} d ${d.inHours % 24} h';
  if (d.inHours > 0) return '${d.inHours} h ${d.inMinutes % 60} min';
  return '${d.inMinutes} min';
}