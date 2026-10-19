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
  final String code; // sent to the ESP32 during setup; empty for members
  final bool mq5Enabled;
  final DateTime? lastSeenAt;
  final SensorReading? latestReading;

  /// Level to show: the latest reading's, held at the most severe level of
  /// the last minute so a brief puff of gas doesn't flash past.
  final AlertLevel? statusLevel;

  /// True when this user set it up; false when someone in the household
  /// shared it with them (they see it and get its alerts, but can't change it).
  final bool isOwner;
  final String ownerName;

  Detector({
    required this.id,
    required this.room,
    required this.name,
    required this.code,
    required this.mq5Enabled,
    required this.lastSeenAt,
    required this.latestReading,
    this.statusLevel,
    this.isOwner = true,
    this.ownerName = '',
  });

  factory Detector.fromJson(Map<String, dynamic> json) {
    final latest = json['latest_reading'] as Map<String, dynamic>?;
    final status = json['status_level'] as String?;
    return Detector(
      id: json['id'] as int,
      room: json['room'] as String? ?? '',
      name: json['name'] as String? ?? '',
      code: json['code'] as String? ?? '',
      mq5Enabled: json['mq5_enabled'] as bool? ?? true,
      lastSeenAt: _parseDate(json['last_seen_at']),
      latestReading: latest == null ? null : SensorReading.fromJson(latest),
      statusLevel: status == null ? null : levelFromString(status),
      isOwner: (json['role'] as String? ?? 'owner') == 'owner',
      ownerName: json['owner_name'] as String? ?? '',
    );
  }

  DetectorStatus get status {
    if (lastSeenAt == null) return DetectorStatus.notSetUp;
    return DateTime.now().difference(lastSeenAt!) > AppConfig.deviceOfflineAfter
        ? DetectorStatus.offline
        : DetectorStatus.online;
  }

  /// Alert level to show — only trusted while the detector is online.
  AlertLevel? get liveLevel => status == DetectorStatus.online
      ? (statusLevel ?? latestReading?.level)
      : null;
}

/// Someone a detector is shared with, as its owner sees them.
class DetectorMember {
  final int id;
  final String email;
  final String name;
  final bool pending; // invited, but hasn't created/verified that account yet

  DetectorMember(
      {required this.id, required this.email, required this.name, required this.pending});

  factory DetectorMember.fromJson(Map<String, dynamic> json) => DetectorMember(
        id: json['id'] as int,
        email: json['email'] as String,
        name: json['name'] as String? ?? '',
        pending: json['status'] == 'pending',
      );
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
