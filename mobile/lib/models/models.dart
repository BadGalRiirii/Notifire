import '../config.dart';

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

DateTime? _parseDate(Object? v) =>
    v == null ? null : DateTime.parse(v as String).toLocal();

class AppUser {
  final int id;
  final String name;
  final String email;
  final bool emailVerified;
  final bool notifyDanger;
  final bool notifyWarning;
  final bool notifyOffline;

  AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.emailVerified = false,
    this.notifyDanger = true,
    this.notifyWarning = false,
    this.notifyOffline = true,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        email: json['email'] as String,
        emailVerified: json['email_verified'] as bool? ?? false,
        notifyDanger: json['notify_danger'] as bool? ?? true,
        notifyWarning: json['notify_warning'] as bool? ?? false,
        notifyOffline: json['notify_offline'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'email_verified': emailVerified,
        'notify_danger': notifyDanger,
        'notify_warning': notifyWarning,
        'notify_offline': notifyOffline,
      };
}

class SensorReading {
  final double? gas; // raw MQ-5 ADC (0–4095); null when MQ-5 disabled
  final double? temperature; // null on DHT22 sensor error
  final double? humidity; // null on DHT22 sensor error
  final bool mq5Enabled;
  final AlertLevel level;
  final DateTime createdAt;

  SensorReading({
    required this.gas,
    required this.temperature,
    required this.humidity,
    required this.mq5Enabled,
    required this.level,
    required this.createdAt,
  });

  factory SensorReading.fromJson(Map<String, dynamic> json) => SensorReading(
        gas: (json['gas'] as num?)?.toDouble(),
        temperature: (json['temperature'] as num?)?.toDouble(),
        humidity: (json['humidity'] as num?)?.toDouble(),
        mq5Enabled: json['mq5_enabled'] as bool? ?? true,
        level: levelFromString(json['level'] as String?),
        createdAt: _parseDate(json['created_at'])!,
      );
}

/// Connection state of a detector, derived from when it last sent data.
enum DetectorStatus { notSetUp, offline, online }

class Detector {
  final int id;
  final String room; // e.g. "Bedroom"
  final String name; // e.g. "Bedroom Detector" (server defaults it from room)
  final String code; // sent to the ESP32 over Bluetooth during setup
  final bool mq5Enabled;
  final DateTime? lastSeenAt;
  final SensorReading? latestReading;

  Detector({
    required this.id,
    required this.room,
    required this.name,
    required this.code,
    required this.mq5Enabled,
    required this.lastSeenAt,
    required this.latestReading,
  });

  factory Detector.fromJson(Map<String, dynamic> json) {
    final latest = json['latest_reading'] as Map<String, dynamic>?;
    return Detector(
      id: json['id'] as int,
      room: json['room'] as String? ?? '',
      name: json['name'] as String? ?? '',
      code: json['code'] as String,
      mq5Enabled: json['mq5_enabled'] as bool? ?? true,
      lastSeenAt: _parseDate(json['last_seen_at']),
      latestReading: latest == null ? null : SensorReading.fromJson(latest),
    );
  }

  DetectorStatus get status {
    if (lastSeenAt == null) return DetectorStatus.notSetUp;
    return DateTime.now().difference(lastSeenAt!) > AppConfig.deviceOfflineAfter
        ? DetectorStatus.offline
        : DetectorStatus.online;
  }

  /// Alert level to show — only trusted while the detector is online.
  AlertLevel? get liveLevel =>
      status == DetectorStatus.online ? latestReading?.level : null;
}

class DetectionLog {
  final int id;
  final int detectorId;
  final String detectorName;
  final String room;
  final AlertLevel level;
  final String message;
  final double? gas;
  final double? temperature;
  final double? humidity;
  final DateTime createdAt;

  DetectionLog({
    required this.id,
    required this.detectorId,
    required this.detectorName,
    required this.room,
    required this.level,
    required this.message,
    required this.gas,
    required this.temperature,
    required this.humidity,
    required this.createdAt,
  });

  factory DetectionLog.fromJson(Map<String, dynamic> json) => DetectionLog(
        id: json['id'] as int,
        detectorId: json['detector'] as int,
        detectorName: json['detector_name'] as String? ?? '',
        room: json['room'] as String? ?? '',
        level: levelFromString(json['level'] as String?),
        message: json['message'] as String,
        gas: (json['gas'] as num?)?.toDouble(),
        temperature: (json['temperature'] as num?)?.toDouble(),
        humidity: (json['humidity'] as num?)?.toDouble(),
        createdAt: _parseDate(json['created_at'])!,
      );
}
