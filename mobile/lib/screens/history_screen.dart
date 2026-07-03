import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/api_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _api = ApiService();
  Timer? _timer;

  List<DetectionLog> _logs = [];
  String? _filter; // null = all, 'WARNING', 'DANGER'
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
      final logs = await _api.fetchLogs(level: _filter);
      if (!mounted) return;
      setState(() {
        _logs = logs;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Cannot reach server';
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Detection History',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
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
                                    color: Colors.white.withOpacity(0.25)),
                                const SizedBox(height: 12),
                                Text('No detections logged',
                                    style: TextStyle(
                                        color: Colors.white.withOpacity(0.5))),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 4, 16, 16),
                              itemCount: _logs.length,
                              itemBuilder: (_, i) => _LogTile(log: _logs[i]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: color.withOpacity(0.25),
      labelStyle: TextStyle(color: selected ? color : Colors.white70),
    );
  }
}

class _LogTile extends StatelessWidget {
  final DetectionLog log;
  const _LogTile({required this.log});

  @override
  Widget build(BuildContext context) {
    final isDanger = log.level == AlertLevel.danger;
    final color = isDanger ? Colors.redAccent : Colors.amber;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
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
                            color: Colors.white.withOpacity(0.45)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(log.message, style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 6),
                  Text(
                    '${log.ppm != null ? '${log.ppm!.toStringAsFixed(0)} ppm • ' : ''}'
                    '${log.temperature.toStringAsFixed(1)}°C • '
                    '${log.humidity.toStringAsFixed(0)}%RH',
                    style: TextStyle(
                        fontSize: 11, color: Colors.white.withOpacity(0.55)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
