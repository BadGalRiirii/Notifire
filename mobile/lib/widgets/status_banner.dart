import 'package:flutter/material.dart';

import '../models/models.dart';

/// Large SAFE / WARNING / DANGER banner at the top of the dashboard.
class StatusBanner extends StatelessWidget {
  final AlertLevel level;

  const StatusBanner({super.key, required this.level});

  @override
  Widget build(BuildContext context) {
    final (color, icon, title, subtitle) = switch (level) {
      AlertLevel.danger => (
          const Color(0xFFE53935),
          Icons.local_fire_department,
          'DANGER',
          'Fire threat detected! Check your home immediately.'
        ),
      AlertLevel.warning => (
          const Color(0xFFFFB300),
          Icons.warning_amber_rounded,
          'WARNING',
          'Sensor readings are rising above normal levels.'
        ),
      AlertLevel.safe => (
          const Color(0xFF43A047),
          Icons.verified_user,
          'SAFE',
          'All sensor readings are within normal range.'
        ),
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.85), color.withValues(alpha: 0.55)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 42),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
