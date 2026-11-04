import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/app_style.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/crop_services.dart' show CropService;

enum AppSnackType { success, error, info }

/// One way to show a message at the bottom of the screen.
///   AppSnack.show(context, 'Saved', type: AppSnackType.success);
class AppSnack {
  AppSnack._();

  static void show(
    BuildContext context,
    String message, {
    AppSnackType type = AppSnackType.info,
  }) => showOn(ScaffoldMessenger.of(context), message, type: type);

  /// Same message, but through a messenger you already hold (used for
  /// push notifications that arrive while the app is open).
  static void showOn(
    ScaffoldMessengerState messenger,
    String message, {
    AppSnackType type = AppSnackType.info,
  }) {
    final IconData icon = switch (type) {
      AppSnackType.success => AppIcons.success,
      AppSnackType.error => AppIcons.error,
      AppSnackType.info => AppIcons.info,
    };
    final Color color = switch (type) {
      AppSnackType.success => AppColors.optimal,
      AppSnackType.error => AppColors.critical,
      AppSnackType.info => const Color(0xFF3A3A3C),
    };

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: color,
          content: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// NO INTERNET
// ─────────────────────────────────────────────────────────────────────────

/// How long a request may take before the phone is treated as offline.
/// Without it a request can hang for minutes with no signal, which also
/// leaves the pull-to-refresh spinner stuck.
const Duration kRequestTimeout = Duration(seconds: 12);

/// Index of the bottom-nav tab on screen (MainNavigation keeps it current).
/// All five tabs stay alive in an IndexedStack, so the pages use this to
/// make sure only the visible one shows the "no internet" snackbar.
final ValueNotifier<int> currentTab = ValueNotifier<int>(0);

/// True when [e] means the server could not be reached (no internet,
/// no DNS, connection dropped or timed out), as opposed to the server
/// answering with an error.
///
/// Every Supabase request first asks Firebase for a login token. Offline,
/// once the token is over an hour old, that fails with Firebase's
/// "network-request-failed", so it counts as no internet too.
bool isConnectionError(Object e) {
  if (e is TimeoutException) return true;
  final s = e.toString().toLowerCase();
  return s.contains('network-request-failed') ||
      s.contains('network error') ||
      s.contains('network_error') ||
      s.contains('networkexception') ||
      s.contains('authretryablefetchexception') ||
      s.contains('no address associated') ||
      s.contains('timed out') ||
      s.contains('os error') ||
      s.contains('socketexception') ||
      s.contains('failed host lookup') ||
      s.contains('clientexception') ||
      s.contains('network is unreachable') ||
      s.contains('connection refused') ||
      s.contains('connection reset') ||
      s.contains('connection closed') ||
      s.contains('connection abort') ||
      s.contains('handshakeexception') ||
      s.contains('xmlhttprequest error');
}

/// Knows, for the whole app, whether the server can be reached.
///
/// As soon as any request fails for lack of internet, it starts checking
/// the server every few seconds. The moment one check gets through it marks
/// the app online again and tells every page, which then reloads its data
/// by itself. No pull-to-refresh or restart is needed.
///
/// It also checks again whenever the app comes back to the foreground.
class ConnectionWatcher extends ChangeNotifier with WidgetsBindingObserver {
  ConnectionWatcher._() {
    WidgetsBinding.instance.addObserver(this);
  }
  static final instance = ConnectionWatcher._();

  static const Duration _checkEvery = Duration(seconds: 3);

  // Right after the phone wakes up, the network needs a moment to come back
  // and connections opened before the app slept are often dead. Requests
  // failing in that moment do not mean there is no internet.
  static const Duration _wakeUpDelay = Duration(seconds: 2);

  /// False while the server cannot be reached (confirmed by [confirmOffline]).
  bool online = true;

  /// Goes up each time the app returns to the foreground, so the pages can
  /// refresh what they show.
  int resumeCount = 0;

  bool _inForeground = true;
  Timer? _timer;
  bool _checking = false;
  Future<bool>? _confirming;

  void reportOffline() {
    _timer ??= Timer.periodic(_checkEvery, (_) => check());
    if (!online) return;
    online = false;
    notifyListeners();
  }

  void reportOnline() {
    _timer?.cancel();
    _timer = null;
    if (online) return;
    online = true;
    // The crop list may have failed too; reload it first.
    if (CropService.instance.offline) CropService.instance.load();
    notifyListeners();
  }

  /// One small request to the server. Any answer, even an error, means the
  /// internet works; only a connection failure means it does not.
  Future<bool> _reachable() async {
    try {
      await Supabase.instance.client
          .from('crops')
          .select('crop_id')
          .limit(1)
          .timeout(const Duration(seconds: 6));
      return true;
    } catch (e) {
      return !isConnectionError(e);
    }
  }

  /// Used while offline: checks every few seconds until the server answers.
  Future<void> check() async {
    if (_checking || !_inForeground) return;
    _checking = true;
    try {
      if (await _reachable()) {
        reportOnline();
      } else {
        reportOffline();
      }
    } finally {
      _checking = false;
    }
  }

  /// Called when a page's request failed for lack of internet. Returns true
  /// only when the internet is really gone: failures while the app is in the
  /// background, or a brief blip while it wakes up, return false.
  /// Pages failing at the same moment share one confirmation.
  Future<bool> confirmOffline() {
    if (!_inForeground) return Future.value(false);
    if (!online) return Future.value(true);
    return _confirming ??= _confirm().whenComplete(() => _confirming = null);
  }

  Future<bool> _confirm() async {
    // Give the phone time to reconnect, then ask the server twice.
    await Future.delayed(_wakeUpDelay);
    for (var attempt = 0; attempt < 2; attempt++) {
      if (!_inForeground) return false;
      if (await _reachable()) return false;
      if (attempt == 0) await Future.delayed(_wakeUpDelay);
    }
    if (!_inForeground) return false;
    reportOffline();
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      // Leaving the app: pause the checks; nothing failing now counts.
      _inForeground = false;
      return;
    }
    _inForeground = true;
    // Reload once the network has had a moment to come back.
    Future.delayed(_wakeUpDelay, () {
      if (!_inForeground) return;
      resumeCount++;
      notifyListeners();
      if (!online) check();
    });
  }
}

/// Shared "no internet" behaviour for the bottom-nav pages: an [offline]
/// flag for the page and the snackbar.
mixin OfflineNotice<T extends StatefulWidget> on State<T> {
  /// This page's position in the bottom navigation.
  int get tabIndex;

  /// Whether the page still has earlier data on screen.
  bool get hasLastData;

  /// True once the app confirmed there is no internet.
  bool offline = false;

  /// Reloads the page's data. Called by itself when the internet comes back
  /// and when the app returns to the foreground.
  void onBackOnline() {}

  int _seenResumes = 0;

  static DateTime? _lastSnackAt;

  // Whether this page already showed the snackbar since the connection was
  // lost. It shows once per page; after that only pull-to-refresh shows it
  // again. Reset when the connection comes back.
  bool _snackShown = false;

  // A request failed but the internet turned out to be fine (e.g. just
  // after waking up). The page then retries once by itself, at most once
  // every 30 s so it can never loop.
  DateTime? _lastBlipRetry;

  @override
  void initState() {
    super.initState();
    currentTab.addListener(_onTabChanged);
    _seenResumes = ConnectionWatcher.instance.resumeCount;
    ConnectionWatcher.instance.addListener(_onConnectionChanged);
  }

  @override
  void dispose() {
    currentTab.removeListener(_onTabChanged);
    ConnectionWatcher.instance.removeListener(_onConnectionChanged);
    super.dispose();
  }

  void _onConnectionChanged() {
    if (!mounted) return;
    final watcher = ConnectionWatcher.instance;
    if (!watcher.online) return;
    if (offline) {
      // Internet is back: clear the offline state and reload by itself.
      markConnection(true);
    } else if (watcher.resumeCount != _seenResumes) {
      // Back in the foreground: show fresh data.
      onBackOnline();
    }
    _seenResumes = watcher.resumeCount;
  }

  // The first visit to this tab while offline tells the user once; later
  // visits stay quiet.
  void _onTabChanged() {
    if (!mounted || currentTab.value != tabIndex || _snackShown) return;
    final noCropList =
        CropService.instance.offline && !ConnectionWatcher.instance.online;
    if (offline || noCropList) showOfflineSnack();
  }

  /// Call after each request. [ok] is false when the server could not be
  /// reached. A failure is only treated as "no internet" after the app has
  /// confirmed it, so waking the phone never shows the snackbar by mistake.
  /// [userAction] is true for pull-to-refresh and Retry: those always show
  /// the snackbar again. Otherwise it shows only once per page.
  void markConnection(bool ok, {bool userAction = false}) {
    if (!mounted) return;
    if (ok) {
      final wasOffline = offline;
      if (wasOffline) setState(() => offline = false);
      _snackShown = false;
      ConnectionWatcher.instance.reportOnline();
      if (wasOffline) onBackOnline();
      return;
    }
    _confirmOffline(userAction);
  }

  Future<void> _confirmOffline(bool userAction) async {
    final reallyOffline = await ConnectionWatcher.instance.confirmOffline();
    if (!mounted) return;
    if (!reallyOffline) {
      // Just a blip: the internet works. Quietly try again instead.
      final now = DateTime.now();
      final last = _lastBlipRetry;
      if (last == null || now.difference(last) > const Duration(seconds: 30)) {
        _lastBlipRetry = now;
        if (CropService.instance.offline) await CropService.instance.load();
        if (mounted) onBackOnline();
      }
      return;
    }
    if (!offline) setState(() => offline = true);
    if (userAction || !_snackShown) showOfflineSnack();
  }

  void showOfflineSnack() {
    if (!mounted || currentTab.value != tabIndex) return;
    _snackShown = true;
    // Several requests can fail together; show one snackbar for them.
    final now = DateTime.now();
    final last = _lastSnackAt;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      return;
    }
    _lastSnackAt = now;
    AppSnack.show(
      context,
      hasLastData
          ? 'No internet connection. Showing the last data.'
          : 'No internet connection. Check your Wi-Fi or mobile data.',
      type: AppSnackType.error,
    );
  }
}