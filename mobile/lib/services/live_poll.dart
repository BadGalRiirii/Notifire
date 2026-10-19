import 'dart:async';

import 'package:flutter/widgets.dart';

import '../config.dart';
import 'api_service.dart';

/// Keeps a screen's data live by polling the server every
/// [AppConfig.pollInterval], from any network (home Wi-Fi, another Wi-Fi or
/// mobile data — the detectors and the app both talk to the cloud server).
///
/// - Never stacks requests: a tick is skipped while the previous poll is
///   still waiting (slow mobile data, or the server waking up).
/// - Stops while the app is in the background (push notifications cover
///   that), and on return refreshes at once on a fresh connection, since the
///   phone may have changed networks meanwhile.
mixin LivePolling<T extends StatefulWidget> on State<T>, WidgetsBindingObserver {
  Timer? _pollTimer;
  bool _polling = false;

  /// Fetch fresh data and update the screen. Must handle its own errors.
  Future<void> poll();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ApiService.resetConnection();
      _start();
    } else if (state == AppLifecycleState.paused) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  /// Poll now (also used by pull-to-refresh).
  Future<void> refreshNow() async {
    if (_polling) return;
    _polling = true;
    try {
      await poll();
    } finally {
      _polling = false;
    }
  }

  void _start() {
    _pollTimer?.cancel();
    refreshNow();
    _pollTimer = Timer.periodic(AppConfig.pollInterval, (_) => refreshNow());
  }
}
