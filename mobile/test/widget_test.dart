import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notifire/models/models.dart';
import 'package:notifire/screens/alert_detail_screen.dart';
import 'package:notifire/screens/auth_screens.dart';
import 'package:notifire/services/push_service.dart';
import 'package:notifire/services/device_setup.dart';
import 'package:notifire/widgets/detector_sheets.dart';
import 'package:notifire/widgets/ppm_gauge.dart';

Map<String, dynamic> _detectorJson({String? lastSeen, Map<String, dynamic>? latest}) => {
      'id': 1,
      'room': 'Bedroom',
      'name': 'Smoke Alarm 1',
      'code': 'NF-7K3Q-9XPA',
      'mq5_enabled': true,
      'last_seen_at': lastSeen,
      'created_at': '2026-10-19T01:00:00+08:00',
      'latest_reading': latest,
    };

void main() {
  test('SensorReading tolerates DHT22 errors (null temp/humidity)', () {
    final r = SensorReading.fromJson({
      'gas': 400,
      'temperature': null,
      'humidity': null,
      'mq5_enabled': true,
      'level': 'SAFE',
      'created_at': '2026-10-19T02:40:00+08:00',
    });
    expect(r.gas, 400);
    expect(r.temperature, isNull);
    expect(r.humidity, isNull);
  });

  test('Detector status: not set up, online, offline', () {
    expect(Detector.fromJson(_detectorJson()).status, DetectorStatus.notSetUp);

    final now = DateTime.now().toUtc();
    final reading = {
      'gas': 1620,
      'temperature': 31.4,
      'humidity': 76,
      'mq5_enabled': true,
      'level': 'DANGER',
      'created_at': now.toIso8601String(),
    };
    final online = Detector.fromJson(
        _detectorJson(lastSeen: now.toIso8601String(), latest: reading));
    expect(online.status, DetectorStatus.online);
    expect(online.liveLevel, AlertLevel.danger);
    expect(online.code, 'NF-7K3Q-9XPA');
    expect(online.room, 'Bedroom');
    expect(online.name, 'Smoke Alarm 1');

    final stale = now.subtract(const Duration(minutes: 5)).toIso8601String();
    final offline =
        Detector.fromJson(_detectorJson(lastSeen: stale, latest: reading));
    expect(offline.status, DetectorStatus.offline);
    expect(offline.liveLevel, isNull); // stale DANGER isn't shown as live
  });

  test('DetectionLog carries the detector name', () {
    final log = DetectionLog.fromJson({
      'id': 3,
      'detector': 1,
      'detector_name': 'Kitchen Detector',
      'room': 'Kitchen',
      'level': 'WARNING',
      'message': 'Smoke/gas level rising (1300)',
      'gas': 1300,
      'temperature': 30,
      'humidity': 70,
      'created_at': '2026-10-19T02:40:00+08:00',
    });
    expect(log.room, 'Kitchen');
    expect(log.detectorName, 'Kitchen Detector');
    expect(log.level, AlertLevel.warning);
  });

  testWidgets('Gas gauge shows raw value and hardware danger threshold',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PpmGauge(ppm: 1620, enabled: true)),
    ));
    expect(find.text('1620'), findsOneWidget);
    expect(find.text('raw (0–4095)'), findsOneWidget);
    expect(find.text('Danger > 1500'), findsOneWidget);
  });

  test('AppUser carries verification and notification settings', () {
    final u = AppUser.fromJson({
      'id': 1,
      'name': 'Maria',
      'email': 'maria@example.com',
      'email_verified': true,
      'notify_danger': true,
      'notify_warning': false,
      'notify_offline': true,
    });
    expect(u.emailVerified, isTrue);
    expect(u.notifyWarning, isFalse);
    final round = AppUser.fromJson(u.toJson());
    expect(round.notifyOffline, isTrue);
    expect(round.emailVerified, isTrue);
  });

  testWidgets('Verify email screen: 6-digit code + resend countdown',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: VerifyEmailScreen()));
    await tester.tap(find.widgetWithText(FilledButton, 'Verify email'));
    await tester.pump();
    expect(find.text('Enter the 6-digit code'), findsOneWidget);
    expect(find.textContaining('Resend code in'), findsOneWidget);
    await tester.pump(const Duration(seconds: 61));
    expect(find.text("Didn't get it? Resend code"), findsOneWidget);
  });

  testWidgets('Login links to forgot password', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.text('Reset password'), findsOneWidget);
    expect(find.text('Send code'), findsOneWidget);
  });

  test('Notification tap target survives the payload round trip', () {
    final t = AlertTarget.fromData({'detector_id': '7', 'log_id': '42', 'kind': 'DANGER'})!;
    expect((t.detectorId, t.logId), (7, 42));
    final back = AlertTarget.fromPayload(t.toPayload())!;
    expect((back.detectorId, back.logId), (7, 42));
    final offline = AlertTarget.fromData({'detector_id': '7', 'log_id': ''})!;
    expect(offline.logId, isNull); // offline notices open the live view
  });

  testWidgets('Alert details explain what triggered the alert', (tester) async {
    final log = DetectionLog.fromJson({
      'id': 42,
      'detector': 7,
      'detector_name': 'SMK1',
      'room': 'Living room',
      'level': 'DANGER',
      'message': 'Smoke or gas detected (level 2346)',
      'gas': 2346,
      'temperature': 28.4,
      'humidity': 80.9,
      'created_at': DateTime.now().toIso8601String(),
    });
    await tester.pumpWidget(
        MaterialApp(home: AlertDetailScreen(log: log, detectorId: 7)));
    await tester.pump();
    expect(find.text('DANGER'), findsOneWidget);
    expect(find.text('Living room'), findsOneWidget);
    expect(find.text('Smoke or gas detected (level 2346)'), findsOneWidget);
    expect(find.text('2346'), findsOneWidget);       // reading at that moment
    expect(find.text('80.9%'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('If you see smoke or fire'), 200);
    expect(find.text('If you see smoke or fire'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // stop the refresh timer
  });

  test('Wi-Fi signal bars from RSSI', () {
    WifiNetwork n(int rssi) => WifiNetwork(ssid: 'x', rssi: rssi, secure: true);
    expect([n(-45).bars, n(-60).bars, n(-72).bars, n(-90).bars], [3, 2, 1, 0]);
  });

  testWidgets('Add detector form: room required, quick picks, name optional',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDetectorFormSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next: connect device'));
    await tester.pump();
    expect(find.text('Which room is this detector in?'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Kitchen'));
    await tester.pump();
    expect(find.text('Leave blank to call it "Kitchen Detector"'), findsOneWidget);
    expect(find.text('Detector name (optional)'), findsOneWidget);
  });

  testWidgets('Login validates input and links to registration', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pump();
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);

    await tester.tap(find.text('Create one'));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsWidgets);
    expect(find.text('Confirm password'), findsOneWidget);
  });
}
