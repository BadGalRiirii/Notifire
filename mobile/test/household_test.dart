import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:notifire/models/models.dart';
import 'package:notifire/screens/detector_screen.dart';
import 'package:notifire/services/api_service.dart';
import 'package:notifire/widgets/household_sheet.dart';

Map<String, dynamic> _detector({required String role}) => {
      'id': 7,
      'room': 'Bedroom',
      'name': 'Bedroom Detector',
      'code': role == 'owner' ? 'NF-7K3Q-9XPA' : '',
      'mq5_enabled': true,
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      'created_at': '2026-10-19T01:00:00Z',
      'latest_reading': {
        'gas': 400,
        'temperature': 30.1,
        'humidity': 77,
        'mq5_enabled': true,
        'level': 'SAFE',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
      'status_level': 'SAFE',
      'role': role,
      'owner_name': 'Nicolas',
    };

/// A tiny stand-in for the NotiFire server: one detector and its members.
class _FakeServer {
  final String role;
  final members = <Map<String, dynamic>>[
    {'id': 1, 'email': 'juan@example.com', 'name': 'Juan', 'status': 'active'},
  ];
  final requests = <String>[];

  _FakeServer(this.role);

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  Future<http.Response> handle(http.Request r) async {
    requests.add('${r.method} ${r.url.path}');
    final path = r.url.path;
    if (path == '/api/detectors/7/' && r.method == 'GET') return _json(_detector(role: role));
    if (path == '/api/detectors/7/members/' && r.method == 'GET') return _json(members);
    if (path == '/api/detectors/7/members/' && r.method == 'POST') {
      final email = (jsonDecode(r.body) as Map)['email'] as String;
      if (members.any((m) => m['email'] == email)) {
        return _json({'email': ['This person already has access.']}, 400);
      }
      final m = {'id': members.length + 1, 'email': email, 'name': '', 'status': 'pending'};
      members.add(m);
      return _json(m, 201);
    }
    if (path.startsWith('/api/detectors/7/members/') && r.method == 'DELETE') {
      return http.Response('', 204);
    }
    return _json({'detail': 'Not found.'}, 404);
  }
}

Future<void> _openSheet(WidgetTester tester, Detector d) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
              onPressed: () => showHouseholdSheet(context, d), child: const Text('open')),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Owner shares a detector with someone new (pending invite)', (tester) async {
    final server = _FakeServer('owner');
    ApiService.useClient(MockClient(server.handle));
    await _openSheet(tester, Detector.fromJson(_detector(role: 'owner')));

    expect(find.text('Share with household'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Juan'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), ' Ana@Example.com ');
    await tester.tap(find.text('Add person'));
    await tester.pumpAndSettle();

    expect(server.requests, contains('POST /api/detectors/7/members/'));
    expect(find.textContaining('Invite sent to ana@example.com'), findsOneWidget);
    expect(find.textContaining('Invited, no account yet'), findsOneWidget);

    // Adding the same person again shows the server's reason.
    await tester.enterText(find.byType(TextFormField), 'juan@example.com');
    await tester.tap(find.text('Add person'));
    await tester.pumpAndSettle();
    expect(find.text('This person already has access.'), findsOneWidget);
  });

  testWidgets('Members see who gets alerts but cannot add or remove anyone', (tester) async {
    ApiService.useClient(MockClient(_FakeServer('member').handle));
    await _openSheet(tester, Detector.fromJson(_detector(role: 'member')));

    expect(find.text('Who gets these alerts'), findsOneWidget);
    expect(find.text('Nicolas'), findsOneWidget);
    expect(find.text('Juan'), findsOneWidget);
    expect(find.text('Add person'), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('A member’s detector screen hides owner-only actions', (tester) async {
    ApiService.useClient(MockClient(_FakeServer('member').handle));
    await tester.pumpWidget(MaterialApp(
        home: DetectorScreen(initial: Detector.fromJson(_detector(role: 'member')))));
    await tester.pump();

    final mq5 = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(mq5.onChanged, isNull); // only the owner can mute the gas alarm
    expect(find.textContaining('only Nicolas can change this'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Stop getting this detector'), findsOneWidget);
    expect(find.text('Who gets these alerts'), findsOneWidget);
    expect(find.text('Delete detector'), findsNothing);
    expect(find.text('Edit room / name'), findsNothing);
    expect(find.text('Connect device / change Wi-Fi'), findsNothing);

    await tester.pumpWidget(const SizedBox()); // stop live polling
  });

  testWidgets('The owner’s detector screen offers sharing and all actions', (tester) async {
    ApiService.useClient(MockClient(_FakeServer('owner').handle));
    await tester.pumpWidget(MaterialApp(
        home: DetectorScreen(initial: Detector.fromJson(_detector(role: 'owner')))));
    await tester.pump();

    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged, isNotNull);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    for (final item in ['Share with household', 'Connect device / change Wi-Fi',
        'Edit room / name', 'Delete detector']) {
      expect(find.text(item), findsOneWidget, reason: item);
    }
    expect(find.text('Stop getting this detector'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}
