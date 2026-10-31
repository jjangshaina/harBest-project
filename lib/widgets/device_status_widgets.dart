import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_harbest_1/services/device_status.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';

/// Everything the status pill and sheet need, in one value so the open
/// sheet can rebuild live while the dashboard keeps polling.
class DeviceStatusView {
  final String? deviceId;
  final String? cropName;

  /// From the Pi's heartbeat (null until the Pi runs the updated script).
  final DeviceStatus? status;

  /// Time of the newest row in `sensor_readings`, as a local DateTime.
  final DateTime? lastReading;

  const DeviceStatusView({
    this.deviceId,
    this.cropName,
    this.status,
    this.lastReading,
  });

  /// Most recent sign of life: heartbeat or reading, whichever is newer.
  DateTime? get lastSeen {
    final a = status?.lastSeen;
    final b = lastReading;
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  DeviceConnection get connection => connectionFor(lastSeen);
}

/// Small tappable "● ONLINE" tag. Sits next to the Sensor Overview title.
class DeviceStatusPill extends StatelessWidget {
  final DeviceConnection connection;
  final VoidCallback? onTap;

  const DeviceStatusPill({super.key, required this.connection, this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = connection.color;
    return Semantics(
      button: onTap != null,
      label: 'Device ${connection.label}. Tap for details.',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PulsingDot(
                color: color,
                pulse: connection == DeviceConnection.online,
              ),
              const SizedBox(width: 6),
              Text(
                connection.label.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: 0.3,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 2),
                Icon(AppIcons.forward, size: 12, color: color),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  final bool pulse;
  const _PulsingDot({required this.color, required this.pulse});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant _PulsingDot old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_c.isAnimating) _c.repeat();
    if (!widget.pulse && _c.isAnimating) _c.reset();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 14,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Stack(
          alignment: Alignment.center,
          children: [
            if (widget.pulse)
              Container(
                width: 8 + 6 * _c.value,
                height: 8 + 6 * _c.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withOpacity(0.35 * (1 - _c.value)),
                ),
              ),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet with the connection state and the health of each sensor.
/// [view] keeps updating while the sheet is open.
Future<void> showDeviceStatusSheet(
  BuildContext context,
  ValueListenable<DeviceStatusView> view,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.dialog)),
    ),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: ValueListenableBuilder<DeviceStatusView>(
          valueListenable: view,
          builder: (_, v, _) => _DeviceStatusSheet(view: v),
        ),
      ),
    ),
  );
}

class _DeviceStatusSheet extends StatelessWidget {
  final DeviceStatusView view;
  const _DeviceStatusSheet({required this.view});

  @override
  Widget build(BuildContext context) {
    final conn = view.connection;
    final s = view.status;
    final live = conn == DeviceConnection.online;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.track,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Device status', style: AppText.cardTitle),
          if (view.deviceId != null) ...[
            const SizedBox(height: 2),
            Text(
              [
                if (view.cropName != null && view.cropName!.isNotEmpty)
                  view.cropName!,
                view.deviceId!,
              ].join(' · '),
              style: AppText.subtitle,
            ),
          ],
          const SizedBox(height: 16),

          // ── Connection summary ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: conn.color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: conn.color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(conn.icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conn.label,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: conn.color,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(conn.explanation, style: AppText.subtitle),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          _row(
            icon: AppIcons.clock,
            label: 'Last seen',
            value: formatAgo(view.lastSeen),
          ),
          _row(
            icon: AppIcons.sensors,
            label: 'Last reading',
            value: formatAgo(view.lastReading),
          ),
          if (s?.wifiRssi != null && s!.wifiQuality != null)
            _row(
              icon: AppIcons.online,
              label: 'Wi-Fi signal',
              value: '${s.wifiQuality} (${s.wifiRssi} dBm)',
            ),

          const SizedBox(height: 14),
          Text(
            live ? 'Sensors' : 'Sensors (last known)',
            style: AppText.label.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          if (s == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Sensor details will appear once the device sends its '
                'first status update.',
                style: AppText.subtitle,
              ),
            )
          else ...[
            _sensorRow(AppIcons.temperature, 'Temperature & humidity',
                s.dht22Ok, live),
            _sensorRow(AppIcons.nitrogen, 'Soil (NPK, pH, moisture)',
                s.npkOk, live),
            _sensorRow(AppIcons.camera, 'Camera', s.cameraOk, live),
            _sensorRow(AppIcons.device, 'Data upload (MQTT)', s.mqttOk, live),
          ],

          if (s != null &&
              (s.uptimeSeconds != null || s.cpuTemp != null)) ...[
            const SizedBox(height: 14),
            Text(
              'Raspberry Pi',
              style: AppText.label.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            if (s.uptimeSeconds != null)
              _row(
                icon: AppIcons.clock,
                label: 'Running for',
                value: formatUptime(s.uptimeSeconds!),
              ),
            if (s.cpuTemp != null)
              _row(
                icon: AppIcons.temperature,
                label: 'Board temperature',
                value: '${s.cpuTemp!.toStringAsFixed(1)} °C',
                valueColor: s.cpuTemp! >= 75
                    ? AppColors.critical
                    : s.cpuTemp! >= 65
                        ? AppColors.caution
                        : null,
              ),
            if (s.ipAddress != null)
              _row(
                icon: AppIcons.info,
                label: 'IP address',
                value: s.ipAddress!,
              ),
          ],
        ],
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: AppText.body)),
          Text(
            value,
            style: AppText.body.copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sensorRow(IconData icon, String label, bool? ok, bool live) {
    final (text, color) = switch (ok) {
      true => ('Working', AppColors.optimal),
      false => ('Not responding', AppColors.critical),
      null => ('Unknown', AppColors.textTertiary),
    };
    final shown = live ? color : color.withOpacity(0.55);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: AppText.body)),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: shown, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: shown,
            ),
          ),
        ],
      ),
    );
  }
}
