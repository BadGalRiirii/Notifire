enum AlertLevel { safe, warning, danger }

AlertLevel levelFromString(String? s) {
  switch (s) {
    case 'DANGER':
      return AlertLevel.danger;
    case 'WARNING':
      return AlertLevel.warning;
    default:
      return AlertLevel.safe;
  }
}

class SensorReading {
  final double? ppm; // null when MQ-5 disabled
  final double temperature;
  final double humidity;
  final bool mq5Enabled;
  final AlertLevel level;
  final DateTime createdAt;

  SensorReading({
    required this.ppm,
    required this.temperature,
    required this.humidity,
    required this.mq5Enabled,
    required this.level,
    required this.createdAt,
  });

  factory SensorReading.fromJson(Map<String, dynamic> json) => SensorReading(
        ppm: (json['ppm'] as num?)?.toDouble(),
        temperature: (json['temperature'] as num).toDouble(),
        humidity: (json['humidity'] as num).toDouble(),
        mq5Enabled: json['mq5_enabled'] as bool? ?? true,
        level: levelFromString(json['level'] as String?),
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );
}

class DetectionLog {
  final int id;
  final AlertLevel level;
  final String message;
  final double? ppm;
  final double temperature;
  final double humidity;
  final DateTime createdAt;

  DetectionLog({
    required this.id,
    required this.level,
    required this.message,
    required this.ppm,
    required this.temperature,
    required this.humidity,
    required this.createdAt,
  });

  factory DetectionLog.fromJson(Map<String, dynamic> json) => DetectionLog(
        id: json['id'] as int,
        level: levelFromString(json['level'] as String?),
        message: json['message'] as String,
        ppm: (json['ppm'] as num?)?.toDouble(),
        temperature: (json['temperature'] as num).toDouble(),
        humidity: (json['humidity'] as num).toDouble(),
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );
}

class DashboardData {
  final SensorReading? reading;
  final bool mq5Enabled;

  DashboardData({required this.reading, required this.mq5Enabled});
}
