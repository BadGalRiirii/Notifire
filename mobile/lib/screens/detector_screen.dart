import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/live_poll.dart';
import '../services/push_service.dart';
import '../widgets/detector_sheets.dart';
import '../widgets/household_sheet.dart';
import '../widgets/notice.dart';
import '../widgets/ppm_gauge.dart';
import '../widgets/sensor_card.dart';
import '../widgets/status_banner.dart';
import 'history_screen.dart';
import 'setup_device_screen.dart';

/// Live dashboard for one detector (room).
class DetectorScreen extends StatefulWidget {
  final Detector initial;
  const DetectorScreen({super.key, required this.initial});

  @override
  State<DetectorScreen> createState() => _DetectorScreenState();
}

class _DetectorScreenState extends State<DetectorScreen>
    with WidgetsBindingObserver, LivePolling<DetectorScreen> {
  final _api = ApiService();

  late Detector _detector = widget.initial;
  String? _error;
  bool _toggleBusy = false;
  bool _silenceBusy = false;

  @override
  Future<void> poll() async {
    try {
      final d = await _api.fetchDetector(_detector.id);
      if (!mounted) return;
      setState(() {
        _detector = d;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _toggleMq5(bool enabled) async {
    setState(() => _toggleBusy = true);
    try {
      final d = await _api.updateDetector(_detector.id, mq5Enabled: enabled);
      if (!mounted) return;
      setState(() => _detector = d);
      _snack(enabled
          ? 'MQ-5 smoke sensor enabled'
          : 'MQ-5 smoke sensor disabled — the gas alarm on this detector is muted');
    } on ApiException catch (e) {
      _snack('Toggle failed: ${e.message}');
    } finally {
      if (mounted) setState(() => _toggleBusy = false);
    }
  }

  Future<void> _silence() async {
    setState(() => _silenceBusy = true);
    try {
      final silenced = await _api.silenceBuzzer(_detector.id);
      PushService.instance.stopAlarm(_detector.id);
      _snack(silenced
          ? 'Silencing the buzzer — it stops within a few seconds.'
          : 'The alarm is already over.');
    } on ApiException catch (e) {
      _snack('Could not silence the buzzer: ${e.message}');
    } finally {
      if (mounted) setState(() => _silenceBusy = false);
    }
  }

  Future<void> _edit() async {
    final saved = await showDetectorFormSheet(context, detector: _detector);
    if (saved != null && mounted) setState(() => _detector = saved);
  }

  Future<void> _connectDevice() async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SetupDeviceScreen(detector: _detector)));
    refreshNow();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${_detector.room} detector?'),
        content: const Text(
            'Its readings and history will be deleted, and the device in this room will stop being accepted. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteDetector(_detector.id);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      _snack('Delete failed: ${e.message}');
    }
  }

  Future<void> _leave() async {
    final d = _detector;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Stop getting the ${d.room} detector?'),
        content: Text(
            'You will no longer see its readings or get its alerts. ${d.ownerName} can share it with you again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Stop getting it')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.leaveDetector(d.id);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String title, {Color? color}) =>
      PopupMenuItem(
          value: value,
          child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon, color: color),
              title: Text(title)));

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    final d = _detector;
    final reading = d.latestReading;
    final mq5On = d.mq5Enabled;
    final status = d.status;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(d.room, overflow: TextOverflow.ellipsis),
            Text(d.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12, color: Colors.white.withValues(alpha: 0.6))),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'history' => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => HistoryScreen(detector: d))),
              'share' => showHouseholdSheet(context, d),
              'connect' => _connectDevice(),
              'edit' => _edit(),
              'delete' => _delete(),
              'leave' => _leave(),
              _ => null,
            },
            itemBuilder: (_) => [
              _menuItem('history', Icons.history, 'History'),
              _menuItem('share', Icons.group_outlined,
                  d.isOwner ? 'Share with household' : 'Who gets these alerts'),
              if (d.isOwner) ...[
                _menuItem('connect', Icons.wifi, 'Connect device / change Wi-Fi'),
                _menuItem('edit', Icons.edit_outlined, 'Edit room / name'),
                _menuItem('delete', Icons.delete_outline, 'Delete detector',
                    color: Colors.redAccent),
              ] else
                _menuItem('leave', Icons.logout, 'Stop getting this detector',
                    color: Colors.redAccent),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refreshNow,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          children: [
            if (_error != null)
              Notice(icon: Icons.wifi_off, text: _error!),
            if (status == DetectorStatus.notSetUp)
              _SetupCard(onConnect: d.isOwner ? _connectDevice : null, ownerName: d.ownerName)
            else ...[
              if (status == DetectorStatus.offline)
                Notice(
                  icon: Icons.sensors_off,
                  text: 'Detector offline — no data since '
                      '${DateFormat('MMM d, hh:mm a').format(d.lastSeenAt!)}. '
                      'Readings below may be outdated.',
                ),
              if (reading != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Updated ${DateFormat('hh:mm:ss a').format(reading.createdAt)}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 11, color: Colors.white.withValues(alpha: 0.5)),
                  ),
                ),
              if (status == DetectorStatus.online)
                StatusBanner(level: d.statusLevel ?? reading?.level ?? AlertLevel.safe),
              if (d.liveLevel == AlertLevel.danger) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE53935),
                      minimumSize: const Size.fromHeight(48)),
                  onPressed: _silenceBusy ? null : _silence,
                  icon: const Icon(Icons.volume_off),
                  label: const Text('Silence buzzer'),
                ),
              ],
              const SizedBox(height: 16),
              PpmGauge(ppm: mq5On ? reading?.gas : null, enabled: mq5On),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SensorCard(
                      icon: Icons.thermostat,
                      iconColor: const Color(0xFFFF7043),
                      label: 'Temperature',
                      value: reading?.temperature != null
                          ? '${reading!.temperature!.toStringAsFixed(1)}°C'
                          : '--',
                      subtitle: reading != null && reading.temperature == null
                          ? 'Sensor error'
                          : 'Danger > 40°C',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SensorCard(
                      icon: Icons.water_drop,
                      iconColor: const Color(0xFF42A5F5),
                      label: 'Humidity',
                      value: reading?.humidity != null
                          ? '${reading!.humidity!.toStringAsFixed(0)}%'
                          : '--',
                      subtitle: reading != null && reading.humidity == null
                          ? 'Sensor error'
                          : 'Danger > 85%RH',
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Card(
              child: SwitchListTile(
                title: const Text('MQ-5 Smoke Sensor',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  (mq5On
                          ? 'Active — monitoring smoke & gas levels'
                          : 'Disabled — gas detection paused') +
                      (d.isOwner ? '' : ' (only ${d.ownerName} can change this)'),
                  style: TextStyle(
                      fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
                ),
                secondary: Icon(
                  mq5On ? Icons.sensors : Icons.sensors_off,
                  color: mq5On ? Colors.greenAccent : Colors.grey,
                ),
                value: mq5On,
                // Muting the gas alarm is the owner's call.
                onChanged: _toggleBusy || !d.isOwner ? null : _toggleMq5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupCard extends StatelessWidget {
  final VoidCallback? onConnect; // null: shared with this user, owner connects it
  final String ownerName;
  const _SetupCard({required this.onConnect, required this.ownerName});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.settings_input_antenna,
                size: 48, color: Colors.white.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text('No device connected yet',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              onConnect == null
                  ? "$ownerName hasn't connected this detector yet. Readings appear once it is online."
                  : 'Plug in your NotiFire device and connect it to your Wi-Fi from here. Readings appear once it is online.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: Colors.white.withValues(alpha: 0.6)),
            ),
            if (onConnect != null) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onConnect,
                icon: const Icon(Icons.bluetooth_searching),
                label: const Text('Connect device'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
