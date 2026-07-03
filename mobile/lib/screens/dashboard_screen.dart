import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/ppm_gauge.dart';
import '../widgets/sensor_card.dart';
import '../widgets/status_banner.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _api = ApiService();
  Timer? _timer;

  DashboardData? _data;
  String? _error;
  bool _toggleBusy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(AppConfig.pollInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final data = await _api.fetchLatest();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Cannot reach server: $e');
    }
  }

  Future<void> _toggleMq5(bool enabled) async {
    setState(() => _toggleBusy = true);
    try {
      final result = await _api.setMq5Enabled(enabled);
      if (!mounted) return;
      setState(() {
        _data = DashboardData(reading: _data?.reading, mq5Enabled: result);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result
            ? 'MQ-5 smoke sensor enabled'
            : 'MQ-5 smoke sensor disabled'),
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Toggle failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _toggleBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reading = _data?.reading;
    final mq5On = _data?.mq5Enabled ?? true;
    final level = reading?.level ?? AlertLevel.safe;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const Icon(Icons.local_fire_department,
                    color: Color(0xFFFF7043), size: 30),
                const SizedBox(width: 8),
                const Text('NotiFire',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (reading != null)
                  Text(
                    'Updated ${DateFormat('hh:mm:ss a').format(reading.createdAt)}',
                    style: TextStyle(
                        fontSize: 11, color: Colors.white.withOpacity(0.5)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_error!,
                            style: const TextStyle(fontSize: 12))),
                  ],
                ),
              ),
            StatusBanner(level: level),
            const SizedBox(height: 16),
            PpmGauge(
              ppm: mq5On ? reading?.ppm : null,
              enabled: mq5On,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SensorCard(
                    icon: Icons.thermostat,
                    iconColor: const Color(0xFFFF7043),
                    label: 'Temperature',
                    value: reading != null
                        ? '${reading.temperature.toStringAsFixed(1)}°C'
                        : '--',
                    subtitle: 'Danger ≥ 55°C',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SensorCard(
                    icon: Icons.water_drop,
                    iconColor: const Color(0xFF42A5F5),
                    label: 'Humidity',
                    value: reading != null
                        ? '${reading.humidity.toStringAsFixed(0)}%'
                        : '--',
                    subtitle: 'Danger ≥ 85%RH',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: SwitchListTile(
                title: const Text('MQ-5 Smoke Sensor',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  mq5On
                      ? 'Active — monitoring smoke & gas levels'
                      : 'Disabled — gas detection paused',
                  style: TextStyle(
                      fontSize: 12, color: Colors.white.withOpacity(0.6)),
                ),
                secondary: Icon(
                  mq5On ? Icons.sensors : Icons.sensors_off,
                  color: mq5On ? Colors.greenAccent : Colors.grey,
                ),
                value: mq5On,
                onChanged: _toggleBusy ? null : _toggleMq5,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Solar-Powered IoT Fire Detection • Cagayan de Oro City',
                style: TextStyle(
                    fontSize: 11, color: Colors.white.withOpacity(0.35)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
