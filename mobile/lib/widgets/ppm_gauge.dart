import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Semi-circular gauge showing the MQ-5 smoke/gas concentration in ppm.
/// Danger threshold: > 1000 ppm (Chapter 3). Gauge is scaled 0–2000 ppm.
class PpmGauge extends StatelessWidget {
  final double? ppm;
  final bool enabled;

  const PpmGauge({super.key, required this.ppm, required this.enabled});

  static const double maxPpm = 2000;
  static const double warningPpm = 700;
  static const double dangerPpm = 1000;

  Color get _color {
    if (!enabled || ppm == null) return Colors.grey;
    if (ppm! > dangerPpm) return Colors.redAccent;
    if (ppm! > warningPpm) return Colors.amber;
    return Colors.greenAccent;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.air, color: _color, size: 20),
                const SizedBox(width: 8),
                const Text('Smoke / Gas Level (MQ-5)',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 150,
              child: CustomPaint(
                size: const Size(double.infinity, 150),
                painter: _GaugePainter(
                  value: enabled ? (ppm ?? 0).clamp(0, maxPpm) : 0,
                  max: maxPpm,
                  color: _color,
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        !enabled
                            ? 'OFF'
                            : ppm == null
                                ? '--'
                                : ppm!.toStringAsFixed(0),
                        style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: _color),
                      ),
                      Text(
                        !enabled ? 'Sensor disabled' : 'ppm',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.5)),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0',
                    style: TextStyle(
                        fontSize: 11, color: Colors.white.withOpacity(0.4))),
                Text('Danger > ${dangerPpm.toInt()} ppm',
                    style: TextStyle(
                        fontSize: 11, color: Colors.white.withOpacity(0.4))),
                Text('${maxPpm.toInt()}',
                    style: TextStyle(
                        fontSize: 11, color: Colors.white.withOpacity(0.4))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final double max;
  final Color color;

  _GaugePainter({required this.value, required this.max, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.95);
    final radius = math.min(size.width / 2, size.height) - 10;
    const startAngle = math.pi;
    const sweepAngle = math.pi;
    const stroke = 16.0;

    final bgPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        startAngle, sweepAngle, false, bgPaint);

    final fraction = (value / max).clamp(0.0, 1.0);
    if (fraction > 0) {
      final fgPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
          startAngle, sweepAngle * fraction, false, fgPaint);
    }

    // danger tick at 1000 ppm
    final tickAngle = startAngle + sweepAngle * (PpmGauge.dangerPpm / max);
    final tickPaint = Paint()
      ..color = Colors.redAccent.withOpacity(0.8)
      ..strokeWidth = 3;
    final inner = Offset(center.dx + (radius - 14) * math.cos(tickAngle),
        center.dy + (radius - 14) * math.sin(tickAngle));
    final outer = Offset(center.dx + (radius + 14) * math.cos(tickAngle),
        center.dy + (radius + 14) * math.sin(tickAngle));
    canvas.drawLine(inner, outer, tickPaint);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.value != value || old.color != color;
}
