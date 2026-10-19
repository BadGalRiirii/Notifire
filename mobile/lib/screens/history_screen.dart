import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../widgets/export_sheet.dart';
import 'alert_detail_screen.dart';
import '../services/api_service.dart';

/// WARNING/DANGER log. Shows every detector (bottom tab), or just one when
/// [detector] is given (opened from a detector's menu).
class HistoryScreen extends StatefulWidget {
  final Detector? detector;
  const HistoryScreen({super.key, this.detector});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _api = ApiService();
  Timer? _timer;

  List<DetectionLog> _logs = [];
  String? _filter; // null = all, 'WARNING', 'DANGER'
  List<Detector> _rooms = []; // for the room filter (all-detectors view only)
  int? _roomId; // null = all rooms
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final allRooms = widget.detector == null;
      final results = await Future.wait([
        _api.fetchLogs(
            level: _filter, detectorId: widget.detector?.id ?? _roomId),
        if (allRooms) _api.fetchDetectors(),
      ]);
      if (!mounted) return;
      setState(() {
        _logs = results[0] as List<DetectionLog>;
        if (allRooms) {
          _rooms = results[1] as List<Detector>;
          // The selected room was deleted — fall back to all rooms.
          if (_roomId != null && !_rooms.any((d) => d.id == _roomId)) {
            _roomId = null;
          }
        }
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  void _setFilter(String? f) {
    setState(() {
      _filter = f;
      _loading = true;
    });
    _load();
  }

  void _setRoom(int? id) {
    setState(() {
      _roomId = id;
      _loading = true;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final single = widget.detector;
    final body = SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (single == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Detection History',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  ),
                  TextButton.icon(
                    onPressed: () => showExportSheet(context, detectors: _rooms),
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Export'),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 8,
              children: [
                _FilterChip(
                    label: 'All',
                    selected: _filter == null,
                    onTap: () => _setFilter(null)),
                _FilterChip(
                    label: 'Warning',
                    color: Colors.amber,
                    selected: _filter == 'WARNING',
                    onTap: () => _setFilter('WARNING')),
                _FilterChip(
                    label: 'Danger',
                    color: Colors.redAccent,
                    selected: _filter == 'DANGER',
                    onTap: () => _setFilter('DANGER')),
              ],
            ),
          ),
          if (single == null && _rooms.length > 1)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _FilterChip(
                        label: 'All rooms',
                        icon: Icons.home_outlined,
                        selected: _roomId == null,
                        onTap: () => _setRoom(null)),
                  ),
                  for (final d in _rooms)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _FilterChip(
                          label: d.room,
                          icon: Icons.meeting_room_outlined,
                          selected: _roomId == d.id,
                          onTap: () => _setRoom(d.id)),
                    ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _logs.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.shield_outlined,
                                    size: 56,
                                    color:
                                        Colors.white.withValues(alpha: 0.25)),
                                const SizedBox(height: 12),
                                Text('No detections logged',
                                    style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.5))),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                              itemCount: _logs.length,
                              itemBuilder: (_, i) => _LogTile(
                                  log: _logs[i], showDetector: single == null),
                            ),
                          ),
          ),
        ],
      ),
    );

    if (single == null) return body;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('${single.room} — History'),
        actions: [
          IconButton(
            tooltip: 'Export',
            icon: const Icon(Icons.ios_share),
            onPressed: () =>
                showExportSheet(context, detectors: [single], only: single),
          ),
        ],
      ),
      body: body,
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;
  final IconData? icon;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color = Colors.white,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      avatar: icon == null || selected
          ? null
          : Icon(icon, size: 16, color: Colors.white70),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: color.withValues(alpha: 0.25),
      labelStyle: TextStyle(color: selected ? color : Colors.white70),
    );
  }
}

class _LogTile extends StatelessWidget {
  final DetectionLog log;
  final bool showDetector;
  const _LogTile({required this.log, required this.showDetector});

  @override
  Widget build(BuildContext context) {
    final isDanger = log.level == AlertLevel.danger;
    final color = isDanger ? Colors.redAccent : Colors.amber;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) =>
                AlertDetailScreen(log: log, detectorId: log.detectorId))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isDanger
                      ? Icons.local_fire_department
                      : Icons.warning_amber_rounded,
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          isDanger ? 'DANGER' : 'WARNING',
                          style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              letterSpacing: 1),
                        ),
                        const Spacer(),
                        Text(
                          DateFormat('MMM d • hh:mm a').format(log.createdAt),
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.45)),
                        ),
                      ],
                    ),
                    if (showDetector && log.room.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            Icon(Icons.sensors,
                                size: 13,
                                color: Colors.white.withValues(alpha: 0.6)),
                            const SizedBox(width: 4),
                            Text(log.room,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        Colors.white.withValues(alpha: 0.75))),
                          ],
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(log.message, style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 6),
                    Text(
                      '${log.gas != null ? 'Gas ${log.gas!.toStringAsFixed(0)} • ' : ''}'
                      '${log.temperature != null ? '${log.temperature!.toStringAsFixed(1)}°C' : '--°C'} • '
                      '${log.humidity != null ? '${log.humidity!.toStringAsFixed(1)}%' : '--%'}',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.55)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: Colors.white.withValues(alpha: 0.35)),
            ],
          ),
        ),
      ),
    );
  }
}
