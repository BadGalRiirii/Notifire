import 'dart:async';
import 'dart:ui' show Color;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';
import 'session.dart';

/// Push notifications (Firebase Cloud Messaging).
///
/// When the app is closed or in the background, Android shows alerts by
/// itself using the channel the server names. While the app is open, they
/// are shown here through flutter_local_notifications. Without
/// google-services.json in the build, Firebase is unavailable and push is
/// simply off — the rest of the app works normally.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  // Channel ids must match backend/monitoring/notifications.py.
  static const alarmsChannel = AndroidNotificationChannel(
    'notifire_alarms',
    'Fire alarms',
    description: 'DANGER alerts when a detector senses smoke, gas or heat.',
    importance: Importance.max,
  );
  static const alertsChannel = AndroidNotificationChannel(
    'notifire_alerts',
    'Detector alerts',
    description: 'Warnings, and detectors going offline or back online.',
    importance: Importance.high,
  );

  final _local = FlutterLocalNotificationsPlugin();
  final _openTarget = StreamController<AlertTarget>.broadcast();
  final _liveAlerts = StreamController<LiveAlert>.broadcast();

  bool _available = false;
  String? _token;

  /// False when the build has no Firebase config (push disabled).
  bool get available => _available;

  /// This phone's FCM token, once registered.
  String? get token => _token;

  /// What to open because the user tapped a notification.
  Stream<AlertTarget> get openTarget => _openTarget.stream;

  /// DANGER/WARNING alerts that arrive while the app is open (for a pop-up).
  Stream<LiveAlert> get liveAlerts => _liveAlerts.stream;

  /// Set when the app was launched by tapping a notification.
  AlertTarget? launchTarget;

  Future<void> init() async {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Push disabled (no Firebase config): $e');
      return;
    }
    _available = true;

    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_notifire'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final target = AlertTarget.fromPayload(response.payload);
        if (target != null) _openTarget.add(target);
      },
    );
    final android = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(alarmsChannel);
    await android?.createNotificationChannel(alertsChannel);

    FirebaseMessaging.onMessage.listen(_showWhileOpen);
    FirebaseMessaging.onMessageOpenedApp.listen((m) {
      final target = AlertTarget.fromData(m.data);
      if (target != null) _openTarget.add(target);
    });
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) launchTarget = AlertTarget.fromData(initial.data);

    // Classic FCM tokens (deprecated in favour of register()/onRegistered,
    // which return Installation IDs the server's Admin SDK can't target yet).
    // ignore: deprecated_member_use
    FirebaseMessaging.instance.onTokenRefresh.listen((t) => _register(t));
    Session.instance.tokenChanged.listen((_) => syncToken(askPermission: false));
  }

  /// Whether Android currently allows NotiFire to show notifications.
  Future<bool> permissionGranted() async {
    if (!_available) return false;
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized;
  }

  /// Asks for notification permission (Android 13+, first time only) and
  /// registers this phone with the server. Safe to call repeatedly.
  Future<bool> syncToken({bool askPermission = true}) async {
    final session = Session.instance;
    if (!_available || !session.isLoggedIn || session.needsVerification) return false;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = askPermission
          ? await messaging.requestPermission()
          : await messaging.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        return false;
      }
      // ignore: deprecated_member_use
      final token = await messaging.getToken();
      if (token == null) return false;
      await _register(token);
      return true;
    } catch (e) {
      debugPrint('Push registration failed: $e');
      return false;
    }
  }

  Future<void> _register(String token) async {
    _token = token;
    final session = Session.instance;
    if (!session.isLoggedIn || session.needsVerification) return;
    try {
      await ApiService().registerPushToken(token);
    } catch (e) {
      debugPrint('Could not register push token: $e');
    }
  }

  /// After logout: stop this phone receiving the previous account's alerts.
  Future<void> clearToken() async {
    _token = null;
    if (!_available) return;
    try {
      // ignore: deprecated_member_use
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  Future<void> _showWhileOpen(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return;
    final target = AlertTarget.fromData(message.data);
    final kind = message.data['kind']?.toString() ?? '';
    if ((kind == 'DANGER' || kind == 'WARNING') && target != null) {
      _liveAlerts.add(LiveAlert(
          kind: kind, title: n.title ?? '', body: n.body ?? '', target: target));
    }
    final channel = kind == 'DANGER' ? alarmsChannel : alertsChannel;
    await _local.show(
      id: target?.detectorId ?? message.hashCode,  // one per room: replaces
      title: n.title,
      body: n.body,
      payload: target?.toPayload(),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: channel.importance,
          priority: Priority.high,
          icon: 'ic_stat_notifire',
          color: const Color(0xFFE53935),
        ),
      ),
    );
  }

}

/// Where a tapped notification leads: the alert's details when it has a
/// History entry, otherwise the detector's live screen.
class AlertTarget {
  final int detectorId;
  final int? logId;
  const AlertTarget(this.detectorId, this.logId);

  static AlertTarget? fromData(Map<String, dynamic> data) {
    final detector = int.tryParse(data['detector_id']?.toString() ?? '');
    if (detector == null) return null;
    return AlertTarget(detector, int.tryParse(data['log_id']?.toString() ?? ''));
  }

  String toPayload() => '$detectorId:${logId ?? ''}';

  static AlertTarget? fromPayload(String? payload) {
    final parts = (payload ?? '').split(':');
    final detector = int.tryParse(parts.first);
    if (detector == null) return null;
    return AlertTarget(detector, parts.length > 1 ? int.tryParse(parts[1]) : null);
  }
}

/// A DANGER/WARNING alert received while the app is in the foreground.
class LiveAlert {
  final String kind; // DANGER | WARNING
  final String title;
  final String body;
  final AlertTarget target;
  const LiveAlert(
      {required this.kind, required this.title, required this.body, required this.target});
}
