import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/alert_detail_screen.dart';
import 'screens/auth_screens.dart';
import 'screens/detector_screen.dart';
import 'screens/detectors_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'services/api_service.dart';
import 'services/push_service.dart';
import 'services/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Session.instance.load();
  await PushService.instance.init();
  runApp(const NotiFireApp());
}

/// Which top-level screen the session calls for.
enum _Stage { loggedOut, verifying, home }

class NotiFireApp extends StatefulWidget {
  const NotiFireApp({super.key});

  @override
  State<NotiFireApp> createState() => _NotiFireAppState();
}

class _NotiFireAppState extends State<NotiFireApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late _Stage _stage = _currentStage();
  StreamSubscription<AlertTarget>? _openSub;
  StreamSubscription<LiveAlert>? _liveSub;
  bool _popupShowing = false;

  _Stage _currentStage() {
    final s = Session.instance;
    if (!s.isLoggedIn) return _Stage.loggedOut;
    return s.needsVerification ? _Stage.verifying : _Stage.home;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Session.instance.addListener(_onSessionChanged);
    _openSub = PushService.instance.openTarget.listen(_open);
    _liveSub = PushService.instance.liveAlerts.listen(_showPopup);
    if (_stage == _Stage.home) _onReachedHome();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Session.instance.removeListener(_onSessionChanged);
    _openSub?.cancel();
    _liveSub?.cancel();
    super.dispose();
  }

  // Re-register this phone for alerts every time the app comes back, so an
  // earlier failed registration (offline, server waking up) or an account
  // switch can't leave alerts going to the wrong account.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _stage == _Stage.home) {
      PushService.instance.syncToken(askPermission: false);
    }
  }

  /// Only a real change of stage (log in/out, email verified) resets the
  /// screen stack — saving settings or rotating the token does not.
  void _onSessionChanged() {
    final stage = _currentStage();
    if (stage == _stage) return;
    _navigatorKey.currentState?.popUntil((r) => r.isFirst);
    setState(() => _stage = stage);
    if (stage == _Stage.home) _onReachedHome();
  }

  void _onReachedHome() {
    // Ask for notification permission and register this phone.
    PushService.instance.syncToken();
    final launch = PushService.instance.launchTarget;
    if (launch != null) {
      PushService.instance.launchTarget = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(launch));
    }
  }

  /// After tapping a notification: the alert's details (why it fired), or
  /// the detector's live view for offline/online notices.
  Future<void> _open(AlertTarget target) async {
    if (_stage != _Stage.home) return;
    final nav = _navigatorKey.currentState;
    if (nav == null) return;
    if (target.logId != null) {
      nav.push(MaterialPageRoute(
          builder: (_) => AlertDetailScreen(
              logId: target.logId, detectorId: target.detectorId)));
      return;
    }
    try {
      final detector = await ApiService().fetchDetector(target.detectorId);
      nav.push(MaterialPageRoute(builder: (_) => DetectorScreen(initial: detector)));
    } on ApiException {
      // Detector deleted or unreachable — stay where we are.
    }
  }

  /// DANGER/WARNING while the app is open: a pop-up over whatever screen is
  /// showing, so it can't be missed. One at a time.
  Future<void> _showPopup(LiveAlert alert) async {
    final context = _navigatorKey.currentContext;
    if (_stage != _Stage.home || context == null || _popupShowing) return;
    _popupShowing = true;
    final danger = alert.kind == 'DANGER';
    final color = danger ? const Color(0xFFE53935) : const Color(0xFFFFB300);
    final viewDetails = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(danger ? Icons.local_fire_department : Icons.warning_amber_rounded,
            color: color, size: 48),
        title: Text(alert.title, textAlign: TextAlign.center),
        content: Text(alert.body, textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('OK')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('View details'),
          ),
        ],
      ),
    );
    _popupShowing = false;
    if (viewDetails == true) _open(alert.target);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NotiFire',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE53935),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF12141A),
        cardTheme: const CardThemeData(
          color: Color(0xFF1D2129),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(14))),
        ),
      ),
      home: switch (_stage) {
        _Stage.loggedOut => const LoginScreen(key: ValueKey('login')),
        _Stage.verifying => const VerifyEmailScreen(key: ValueKey('verify')),
        _Stage.home => const RootScaffold(key: ValueKey('home')),
      },
    );
  }
}

class RootScaffold extends StatefulWidget {
  const RootScaffold({super.key});

  @override
  State<RootScaffold> createState() => _RootScaffoldState();
}

class _RootScaffoldState extends State<RootScaffold> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [DetectorsScreen(), HistoryScreen(), SettingsScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.sensors_outlined),
            selectedIcon: Icon(Icons.sensors),
            label: 'Detectors',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
