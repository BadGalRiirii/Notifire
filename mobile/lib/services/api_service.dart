import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/models.dart';

class ApiService {
  final String baseUrl;
  ApiService({this.baseUrl = AppConfig.baseUrl});

  Uri _u(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  /// Latest reading + device state — polled by the dashboard.
  Future<DashboardData> fetchLatest() async {
    final resp = await http
        .get(_u('/api/readings/latest/'))
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw Exception('Server error ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final readingJson = body['reading'] as Map<String, dynamic>?;
    final device = body['device'] as Map<String, dynamic>;
    return DashboardData(
      reading: readingJson == null ? null : SensorReading.fromJson(readingJson),
      mq5Enabled: device['mq5_enabled'] as bool? ?? true,
    );
  }

  /// History logs — WARNING and DANGER detections only.
  Future<List<DetectionLog>> fetchLogs({String? level, int limit = 100}) async {
    final query = <String, String>{'limit': '$limit'};
    if (level != null) query['level'] = level;
    final resp =
        await http.get(_u('/api/logs/', query)).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw Exception('Server error ${resp.statusCode}');
    }
    final list = jsonDecode(resp.body) as List<dynamic>;
    return list
        .map((e) => DetectionLog.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Toggle the MQ-5 sensor ON/OFF from the app.
  Future<bool> setMq5Enabled(bool enabled) async {
    final resp = await http
        .post(
          _u('/api/device/'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'mq5_enabled': enabled}),
        )
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw Exception('Server error ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return body['mq5_enabled'] as bool;
  }
}
