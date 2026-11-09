import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_harbest_1/theme/app_style.dart';
import 'package:flutter_application_harbest_1/widgets/app_button.dart';

// ─────────────────────────────────────────────────────────────────────────
// APP WALKTHROUGH
// Shown ONCE per install, the first time the app is opened, before the
// Welcome / Log in screens. Get started (or Skip) continues to the normal
// start screen. Wired up in main.dart (_AppStartup); nothing else to call.
//
//   • Replay from My Account:  AppWalkthrough.replay(context);
// ─────────────────────────────────────────────────────────────────────────

class AppWalkthrough {
  AppWalkthrough._();

  /// Saved on the phone, so it is per install (not per account). Bump the
  /// version (v1 -> v2) to show the tour once more after changing it.
  static const String _seenKey = 'walkthrough_seen_v1';

  /// True only the very first time the app is opened.
  static Future<bool> shouldShow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_seenKey) != true;
    } catch (_) {
      return false; // never block the app because of this
    }
  }

  static Future<void> _markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_seenKey, true);
    } catch (_) {}
  }

  /// Opens the tour again (e.g. from My Account). Closing just returns.
  static Future<void> replay(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const WalkthroughPage(replay: true),
      ),
    );
  }
}

class _Step {
  final IconData icon;
  final String title;
  final String body;
  final String? tip;
  const _Step({
    required this.icon,
    required this.title,
    required this.body,
    this.tip,
  });
}

const List<_Step> _steps = [
  _Step(
    icon: AppIcons.plant,
    title: 'Welcome to HarBest Application!',
    body:
        'Monitor your crop with IoT sensors and AI-powered analytics. '
        'Take a quick tour of what you can do.',
  ),
  _Step(
    icon: AppIcons.device,
    title: 'Link your device',
    body:
        'Be sure you are connected on the internet. On the Dashboard page, tap Add your device and enter the code that came '
        'with your HarBest device. Name your crop and pick its planting '
        'date.',
    tip: 'The planting date sets your crop\'s growth stage, so choose it '
        'carefully. You can edit it later in the Plant page.',
  ),
  _Step(
    icon: AppIcons.home,
    title: 'Dashboard: your crop at a glance',
    body:
        'See your all sensors, their current readings, and whether they are in the good range'
        ' to monitor your crop\'s health.',
    tip: 'Tap the ONLINE tag to check device status and whether each '
        'sensor is working.',
  ),
  _Step(
    icon: AppIcons.analytics,
    title: 'Analytics: spot trends',
    body:
        'Pick a sensor to see weekly averages, readings by crop health, how it relates to '
        'other sensors, and a 7-day rolling trend.',
    tip: 'Charts get richer as your device collects more days of data.',
  ),
  _Step(
    icon: AppIcons.timeline,
    title: 'Plant: growth, insights, and recommendations',
    body:
        'Follow your crop from its growth timeline, and get clear '
        'recommendations whenever a reading drifts out of its ideal range.',
    tip: 'Press and hold the current growth stage to see its ideal '
        'conditions. Release to close.',
  ),
  _Step(
    icon: AppIcons.forecast,
    title: 'Forecast and Alerts',
    body:
        'Forecast predicts when a reading may leave its optimal range and provides'
        ' suggestive actions. Alerts notifies and shows problems as soon as your sensors detect them.'
  ),
];

class WalkthroughPage extends StatefulWidget {
  /// True when opened again from My Account: closing just goes back.
  final bool replay;

  /// Called after Get started / Skip on the first open. main.dart uses it to
  /// continue to the normal start screen.
  final VoidCallback? onFinish;

  const WalkthroughPage({super.key, this.replay = false, this.onFinish});

  @override
  State<WalkthroughPage> createState() => _WalkthroughPageState();
}

class _WalkthroughPageState extends State<WalkthroughPage> {
  final _controller = PageController();
  int _index = 0;

  bool get _isLast => _index == _steps.length - 1;

  @override
  void initState() {
    super.initState();
    // Mark it seen as soon as it is shown, so it can never appear twice.
    if (!widget.replay) AppWalkthrough._markSeen();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Get started and Skip both end here.
  void _close() {
    if (widget.replay) {
      Navigator.of(context).pop();
      return;
    }
    widget.onFinish?.call();
  }

  void _next() {
    if (_isLast) {
      _close();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _dots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_steps.length, (i) {
        final active = i == _index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? AppColors.green : AppColors.track,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  Widget _stepView(_Step s) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.page + 8),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: AppColors.green.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(s.icon, size: 56, color: AppColors.darkGreen),
          ),
          const SizedBox(height: 32),
          Text(
            s.title,
            textAlign: TextAlign.center,
            style: AppText.sectionTitle.copyWith(color: AppColors.darkGreen),
          ),
          const SizedBox(height: 12),
          Text(
            s.body,
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(height: 1.5),
          ),
          if (s.tip != null) ...[
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.field),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(AppIcons.tip, size: 18, color: AppColors.darkGreen),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.tip!,
                      style: AppText.body.copyWith(fontSize: 13.5, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Skip (hidden but still taking space on the last page)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, AppSpace.page, 0),
                child: Visibility(
                  visible: !_isLast,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: TextButton(
                    onPressed: _close,
                    child: Text(
                      'Skip',
                      style: AppText.label.copyWith(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _steps.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _stepView(_steps[i]),
              ),
            ),
            _dots(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.page,
                20,
                AppSpace.page,
                AppSpace.page,
              ),
              child: AppButton(
                label: _isLast ? 'Get started' : 'Next',
                expanded: true,
                onPressed: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}