import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/live_poll.dart';
import '../services/session.dart';
import '../widgets/detector_sheets.dart';
import '../widgets/notice.dart';
import 'detector_screen.dart';
import 'help_screen.dart';
import 'setup_device_screen.dart';

/// The panel: every detector the user owns, with its live status.
class DetectorsScreen extends StatefulWidget {
  const DetectorsScreen({super.key});

  @override
  State<DetectorsScreen> createState() => _DetectorsScreenState();
}

class _DetectorsScreenState extends State<DetectorsScreen>
    with WidgetsBindingObserver, LivePolling<DetectorsScreen> {
  final _api = ApiService();

  List<Detector>? _detectors;
  String? _error;

  @override
  Future<void> poll() async {
    try {
      final list = await _api.fetchDetectors();
      if (!mounted) return;
      setState(() {
        _detectors = list;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Create a detector and connect its device; repeats while the user taps
  /// "Add another detector" so several rooms can be set up in one go.
  Future<void> _add() async {
    while (true) {
      if (!mounted) return;
      final created = await showDetectorFormSheet(context);
      if (created == null || !mounted) return;
      setState(() => _detectors = [...?_detectors, created]);
      final result = await Navigator.of(context).push<SetupResult>(
          MaterialPageRoute(builder: (_) => SetupDeviceScreen(detector: created)));
      refreshNow();
      if (result != SetupResult.addAnother) return;
    }
  }

  Future<void> _open(Detector d) async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DetectorScreen(initial: d)));
    refreshNow(); // may have been renamed/deleted
  }

  @override
  Widget build(BuildContext context) {
    final detectors = _detectors;
    final firstName = (Session.instance.user?.name ?? '').split(' ').first;
    final alerts = (detectors ?? [])
        .where((d) =>
            d.liveLevel == AlertLevel.danger || d.liveLevel == AlertLevel.warning)
        .toList()
      ..sort((a, b) => b.liveLevel!.index.compareTo(a.liveLevel!.index));

    return Scaffold(
      floatingActionButton: detectors == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('Add detector'),
            ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: refreshNow,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              const Row(
                children: [
                  Icon(Icons.local_fire_department,
                      color: Color(0xFFFF7043), size: 30),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('NotiFire',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                firstName.isEmpty ? 'My detectors' : 'Hi, $firstName',
                style: TextStyle(
                    fontSize: 14, color: Colors.white.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 16),
              if (_error != null) Notice(icon: Icons.wifi_off, text: _error!),
              for (final d in alerts) _AlertBanner(detector: d, onTap: () => _open(d)),
              if (detectors == null && _error == null)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (detectors != null && detectors.isEmpty)
                _EmptyState(onAdd: _add)
              else if (detectors != null) ...[
                _Summary(detectors: detectors),
                const SizedBox(height: 16),
                Text('My detectors (${detectors.length})',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                for (final d in detectors)
                  _DetectorCard(detector: d, onTap: () => _open(d)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DetectorCard extends StatelessWidget {
  final Detector detector;
  final VoidCallback onTap;
  const _DetectorCard({required this.detector, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = detector;
    final (color, icon, label) = detectorBadge(d);
    final r = d.latestReading;
    final muted = Colors.white.withValues(alpha: 0.55);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.room,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                    Text(d.name,
                        style: TextStyle(fontSize: 12, color: muted),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(
                      d.status == DetectorStatus.notSetUp
                          ? 'Tap to connect your device'
                          : r == null
                              ? 'No readings yet'
                              : [
                                  if (r.gas != null) 'Gas ${r.gas!.toStringAsFixed(0)}',
                                  r.temperature != null
                                      ? '${r.temperature!.toStringAsFixed(1)}°C'
                                      : '--°C',
                                  r.humidity != null
                                      ? '${r.humidity!.toStringAsFixed(0)}%RH'
                                      : '--%RH',
                                ].join(' • '),
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Colour, icon and short label for a detector's current state.
(Color, IconData, String) detectorBadge(Detector d) {
  switch (d.status) {
    case DetectorStatus.notSetUp:
      return (Colors.blueGrey, Icons.settings_input_antenna, 'SET UP');
    case DetectorStatus.offline:
      return (Colors.grey, Icons.sensors_off, 'OFFLINE');
    case DetectorStatus.online:
      return switch (d.latestReading?.level ?? AlertLevel.safe) {
        AlertLevel.danger => (
            const Color(0xFFE53935),
            Icons.local_fire_department,
            'DANGER'
          ),
        AlertLevel.warning => (
            const Color(0xFFFFB300),
            Icons.warning_amber_rounded,
            'WARNING'
          ),
        AlertLevel.safe => (const Color(0xFF43A047), Icons.verified_user, 'SAFE'),
      };
  }
}

class _AlertBanner extends StatelessWidget {
  final Detector detector;
  final VoidCallback onTap;
  const _AlertBanner({required this.detector, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final danger = detector.liveLevel == AlertLevel.danger;
    final color = danger ? const Color(0xFFE53935) : const Color(0xFFFFB300);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(danger ? Icons.local_fire_department : Icons.warning_amber_rounded,
                    color: Colors.white, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${danger ? 'DANGER' : 'WARNING'} — ${detector.room}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
                      Text(
                        danger
                            ? 'Fire threat detected! Check this room immediately.'
                            : 'Readings are rising above normal levels.',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One-line health overview of every detector in the home.
class _Summary extends StatelessWidget {
  final List<Detector> detectors;
  const _Summary({required this.detectors});

  @override
  Widget build(BuildContext context) {
    int count(bool Function(Detector) test) => detectors.where(test).length;
    final danger = count((d) => d.liveLevel == AlertLevel.danger);
    final warning = count((d) => d.liveLevel == AlertLevel.warning);
    final safe = count((d) => d.liveLevel == AlertLevel.safe);
    final offline = count((d) => d.status == DetectorStatus.offline);
    final notSetUp = count((d) => d.status == DetectorStatus.notSetUp);

    final (headline, color) = danger > 0
        ? ('Fire risk in $danger room${danger == 1 ? '' : 's'}', const Color(0xFFE53935))
        : warning > 0
            ? ('$warning room${warning == 1 ? ' needs' : 's need'} attention', const Color(0xFFFFB300))
            : offline > 0
                ? ('$offline detector${offline == 1 ? ' is' : 's are'} offline', Colors.grey)
                : safe > 0
                    ? ('All rooms are safe', const Color(0xFF43A047))
                    : ('Connect your detectors to start monitoring', Colors.blueGrey);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.home_outlined, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(headline,
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold, color: color)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (safe > 0) _Pill('$safe safe', const Color(0xFF43A047)),
                if (warning > 0) _Pill('$warning warning', const Color(0xFFFFB300)),
                if (danger > 0) _Pill('$danger danger', const Color(0xFFE53935)),
                if (offline > 0) _Pill('$offline offline', Colors.grey),
                if (notSetUp > 0) _Pill('$notSetUp not connected', Colors.blueGrey),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Icon(Icons.sensors, size: 64, color: Colors.white.withValues(alpha: 0.25)),
          const SizedBox(height: 14),
          const Text('No detectors yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            'Add one for each room you want to protect,\nlike your bedroom or living room.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add your first detector'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const HelpScreen())),
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('New here? How to use NotiFire'),
          ),
        ],
      ),
    );
  }
}
