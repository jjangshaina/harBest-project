import 'package:flutter/material.dart';
import '../theme/app_style.dart';
import '../services/alert_badge_service.dart';

/// The green bottom navigation bar shared by all main pages.
/// The Alerts icon gets a red dot whenever a new alert has arrived that the
/// user has not opened yet.
class AppBottomNav extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const _icons = [
    AppIcons.home,
    AppIcons.analytics,
    AppIcons.plant,
    AppIcons.forecast,
    AppIcons.alerts,
  ];

  static const _labels = [
    'Home',
    'Analytics',
    'Plant',
    'Forecast',
    'Alerts',
  ];

  static const int _alertsIndex = 4;

  @override
  State<AppBottomNav> createState() => _AppBottomNavState();
}

class _AppBottomNavState extends State<AppBottomNav> {
  @override
  void initState() {
    super.initState();
    AlertBadgeService.instance.start();
    _syncViewing();
  }

  @override
  void didUpdateWidget(covariant AppBottomNav old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) _syncViewing();
  }

  // Tells the badge service whether the Alerts tab is showing. Deferred so
  // it never notifies listeners in the middle of a build.
  void _syncViewing() {
    final viewing = widget.currentIndex == AppBottomNav._alertsIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AlertBadgeService.instance.setViewing(viewing);
    });
  }

  Widget _icon(int i, bool isSelected) {
    final icon = Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.navSelected : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(AppBottomNav._icons[i], color: Colors.white, size: 26),
    );

    if (i != AppBottomNav._alertsIndex) return icon;

    // Red dot in the top-right corner of the Alerts icon.
    return ListenableBuilder(
      listenable: AlertBadgeService.instance,
      builder: (_, _) {
        final show = AlertBadgeService.instance.hasUnread;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            icon,
            Positioned(
              right: 4,
              top: 4,
              child: AnimatedScale(
                scale: show ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: AppColors.critical,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.green, width: 1.5),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: 14,
        left: 12,
        right: 12,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: const BoxDecoration(
        color: AppColors.green,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppRadius.header),
          topRight: Radius.circular(AppRadius.header),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(AppBottomNav._icons.length, (i) {
          final isSelected = widget.currentIndex == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => widget.onTap(i),
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _icon(i, isSelected),
                  const SizedBox(height: 3),
                  Text(
                    AppBottomNav._labels[i],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}