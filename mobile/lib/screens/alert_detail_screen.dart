import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'detector_screen.dart';
import 'detectors_screen.dart' show detectorBadge;

/// Explains one alert: what triggered it, the readings at that moment, and
/// how the room is right now — so an alert still makes sense after the
/// readings have already gone back to normal.
class AlertDetailScreen extends StatefulWidget {
  final DetectionLog? log; // when opened from History
  final int? logId; // when opened from a notification
  final int detectorId;

  const AlertDetailScreen({super.key, this.log, this.logId, required this.detectorId})
      : assert(log != null || logId != null);

  @override
  State<AlertDetailScreen> createState() => _AlertDetailScreenState();
}

class _AlertDetailScreenState extends State<AlertDetailScreen> {
  final _api = ApiService();
  Timer? _timer;
  late DetectionLog? _log = widget.log;
  Detector? _detector;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(AppConfig.pollInterval, (_) => _loadDetector());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if (_log == null) {
        final log = await _api.fetchLog(widget.logId!);
        if (mounted) setState(() => _log = log);
      }
      await _loadDetector();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _loadDetector() async {
    try {
      final d = await _api.fetchDetector(widget.detectorId);
      if (mounted) setState(() => _detector = d);
    } on ApiException {
      // keep the alert visible even if the live status can't load
    }
  }

  @override
  Widget build(BuildContext context) {
    final log = _log;
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('Alert details')),
      body: log == null
          ? Center(
              child: _error != null
                  ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!))
                  : const CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                _Header(log: log),
                const SizedBox(height: 16),
                const _Label('What triggered it'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final reason in log.message.split('; '))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.circle, size: 8, color: _color(log.level)),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Text(reason,
                                        style: const TextStyle(
                                            fontSize: 16, fontWeight: FontWeight.w600))),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const _Label('Readings at that moment'),
                Row(
                  children: [
                    Expanded(
                        child: _Reading(
                      icon: Icons.air,
                      label: 'Smoke / gas',
                      value: log.gas?.toStringAsFixed(0),
                      limit: 'Danger above 1500',
                      over: log.gas != null && log.gas! > 1200,
                    )),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _Reading(
                      icon: Icons.thermostat,
                      label: 'Temperature',
                      value: log.temperature == null
                          ? null
                          : '${log.temperature!.toStringAsFixed(1)}°C',
                      limit: 'Danger above 40°C',
                      over: log.temperature != null && log.temperature! >= 35,
                    )),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _Reading(
                      icon: Icons.water_drop,
                      label: 'Humidity',
                      value: log.humidity == null
                          ? null
                          : '${log.humidity!.toStringAsFixed(1)}%',
                      limit: 'Danger above 85%',
                      over: log.humidity != null && log.humidity! > 85,
                    )),
                  ],
                ),
                const SizedBox(height: 16),
                const _Label('Right now'),
                _NowCard(detector: _detector),
                const SizedBox(height: 12),
                Text(
                  'Smoke and gas can clear within seconds, so the room may already be back to normal. '
                  'This page keeps what the detector measured when it alerted you.',
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.55)),
                ),
                if (log.level == AlertLevel.danger) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: const Color(0xFFE53935).withValues(alpha: 0.15),
                    child: const ListTile(
                      leading: Icon(Icons.emergency, color: Color(0xFFE53935)),
                      title: Text('If you see smoke or fire'),
                      subtitle: Text('Get everyone out of the house first, then call 911 (Bureau of Fire Protection).'),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (_detector != null)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => DetectorScreen(initial: _detector!))),
                    icon: const Icon(Icons.sensors),
                    label: Text('Open ${_detector!.room} live view'),
                  ),
              ],
            ),
    );
  }
}

Color _color(AlertLevel level) => switch (level) {
      AlertLevel.danger => const Color(0xFFE53935),
      AlertLevel.warning => const Color(0xFFFFB300),
      AlertLevel.safe => const Color(0xFF43A047),
    };

String _when(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final time = DateFormat('h:mm:ss a').format(t);
  if (day == today) return 'Today, $time';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday, $time';
  return '${DateFormat('MMM d').format(t)}, $time';
}

class _Header extends StatelessWidget {
  final DetectionLog log;
  const _Header({required this.log});

  @override
  Widget build(BuildContext context) {
    final danger = log.level == AlertLevel.danger;
    final color = _color(log.level);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.85), color.withValues(alpha: 0.55)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(danger ? Icons.local_fire_department : Icons.warning_amber_rounded,
              color: Colors.white, size: 42),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(danger ? 'DANGER' : 'WARNING',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2)),
                Text(log.room.isEmpty ? log.detectorName : log.room,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                Text(_when(log.createdAt),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Reading extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final String limit;
  final bool over;

  const _Reading({
    required this.icon,
    required this.label,
    required this.value,
    required this.limit,
    required this.over,
  });

  @override
  Widget build(BuildContext context) {
    final color = over ? const Color(0xFFFF7043) : Colors.white;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: over
            ? const BorderSide(color: Color(0xFFFF7043), width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6))),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value ?? '—',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            ),
            const SizedBox(height: 2),
            Text(limit, style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.45))),
          ],
        ),
      ),
    );
  }
}

class _NowCard extends StatelessWidget {
  final Detector? detector;
  const _NowCard({required this.detector});

  @override
  Widget build(BuildContext context) {
    final d = detector;
    if (d == null) {
      return const Card(
          child: ListTile(leading: CircularProgressIndicator(), title: Text('Checking…')));
    }
    final (color, icon, label) = detectorBadge(d);
    final updated = d.latestReading?.createdAt;
    final String text = switch (d.status) {
      DetectorStatus.online when d.liveLevel == AlertLevel.safe => 'Back to normal — all readings are safe',
      DetectorStatus.online when d.liveLevel == AlertLevel.danger => 'Still in DANGER — check the room now',
      DetectorStatus.online => 'Readings are still above normal',
      DetectorStatus.offline => 'Detector is offline — no recent readings',
      DetectorStatus.notSetUp => 'Detector is not connected',
    };
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: updated == null
            ? null
            : Text('$label • updated ${DateFormat('h:mm:ss a').format(updated)}'),
        trailing: d.status == DetectorStatus.online
            ? Icon(Icons.circle, size: 10, color: color)
            : null,
      ),
    );
  }
}

/// Small section label used on the alert page.
class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 12,
                letterSpacing: 1,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.55))),
      );
}
