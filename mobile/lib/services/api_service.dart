import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/models.dart';
import 'session.dart';

/// Error with a message that is safe to show to the user.
class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

class ApiService {
  final String baseUrl;
  ApiService({this.baseUrl = AppConfig.baseUrl});

  // Generous: slow mobile data, and a cold database connection can take a
  // few seconds. Requests that truly fail still error out promptly.
  static const _timeout = Duration(seconds: 20);

  // One shared client so polls reuse an open HTTPS connection instead of a
  // new TLS handshake every 3 s (slow on mobile data). After the phone
  // switches networks (Wi-Fi ↔ mobile data, another Wi-Fi) that connection
  // is dead, so any network failure drops it and the next request redials.
  static http.Client _shared = http.Client();

  /// Forget open connections, e.g. when the app returns to the foreground
  /// on a different network than when it left.
  static void resetConnection() {
    _shared.close();
    _shared = http.Client();
  }

  http.Client get _client => _shared;

  Uri _u(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (Session.instance.token != null)
          'Authorization': 'Token ${Session.instance.token}',
      };

  Future<dynamic> _send(Future<http.Response> Function() request) async {
    final http.Response resp;
    try {
      resp = await request().timeout(_timeout);
    } on TimeoutException {
      resetConnection();
      throw ApiException('Server is not responding. Check your internet connection.');
    } on SocketException {
      resetConnection();
      throw ApiException('Cannot reach server. Check your internet connection.');
    } on http.ClientException {
      resetConnection();
      throw ApiException('Cannot reach server. Check your internet connection.');
    }

    if (resp.statusCode == 401 && Session.instance.isLoggedIn) {
      await Session.instance.signOut(); // token revoked/expired → back to login
      throw ApiException('Your session has ended. Please log in again.');
    }
    if (resp.statusCode == 429) {
      throw ApiException('Too many attempts. Please wait a minute and try again.');
    }
    if (resp.statusCode >= 400) {
      throw ApiException(_errorMessage(resp));
    }
    return resp.body.isEmpty ? null : jsonDecode(resp.body);
  }

  /// Turns DRF errors ({"detail": ...} or {"field": ["msg"]}) into one line.
  String _errorMessage(http.Response resp) {
    try {
      final body = jsonDecode(resp.body);
      if (body is Map) {
        if (body['detail'] is String) return body['detail'] as String;
        for (final value in body.values) {
          if (value is List && value.isNotEmpty) return value.first.toString();
          if (value is String) return value;
        }
      }
    } catch (_) {}
    return 'Something went wrong (error ${resp.statusCode}).';
  }

  // ---------------------------------------------------------------- auth --

  /// Returns false if the account was created but the verification email
  /// could not be sent (the user can tap "Resend code").
  Future<bool> register(String name, String email, String password) async {
    final body = await _send(() => _client.post(_u('/api/auth/register/'),
        headers: _headers,
        body: jsonEncode({'name': name, 'email': email, 'password': password})));
    await _saveSession(body as Map<String, dynamic>);
    return body['email_sent'] as bool? ?? true;
  }

  Future<void> login(String email, String password) async {
    final body = await _send(() => _client.post(_u('/api/auth/login/'),
        headers: _headers,
        body: jsonEncode({'email': email, 'password': password})));
    await _saveSession(body as Map<String, dynamic>);
  }

  /// [pushToken]: this phone's notification token, so the server stops
  /// sending alerts to it.
  Future<void> logout({String? pushToken}) async {
    try {
      await _send(() => _client.post(_u('/api/auth/logout/'),
          headers: _headers,
          body: jsonEncode({if (pushToken != null) 'push_token': pushToken})));
    } catch (_) {
      // Offline logout still clears the token on this phone.
    }
    await Session.instance.signOut();
  }

  Future<void> verifyEmail(String code) async {
    final body = await _send(() => _client.post(_u('/api/auth/verify-email/'),
        headers: _headers, body: jsonEncode({'code': code})));
    await Session.instance.updateUser(AppUser.fromJson(body as Map<String, dynamic>));
  }

  /// Returns the server's confirmation message.
  Future<String> resendVerificationCode() async {
    final body =
        await _send(() => _client.post(_u('/api/auth/resend-code/'), headers: _headers));
    return (body as Map<String, dynamic>)['detail'] as String? ?? 'Code sent.';
  }

  Future<String> forgotPassword(String email) async {
    final body = await _send(() => _client.post(_u('/api/auth/forgot-password/'),
        headers: _headers, body: jsonEncode({'email': email})));
    return (body as Map<String, dynamic>)['detail'] as String? ?? 'Code sent.';
  }

  /// Resets the password with the emailed code and logs in.
  Future<void> resetPassword(String email, String code, String newPassword) async {
    final body = await _send(() => _client.post(_u('/api/auth/reset-password/'),
        headers: _headers,
        body: jsonEncode(
            {'email': email, 'code': code, 'new_password': newPassword})));
    await _saveSession(body as Map<String, dynamic>);
  }

  Future<AppUser> fetchMe() async {
    final body = await _send(() => _client.get(_u('/api/auth/me/'), headers: _headers));
    final user = AppUser.fromJson(body as Map<String, dynamic>);
    await Session.instance.updateUser(user);
    return user;
  }

  Future<AppUser> updateMe(
      {String? name, bool? notifyDanger, bool? notifyWarning, bool? notifyOffline}) async {
    final body = await _send(() => _client.patch(_u('/api/auth/me/'),
        headers: _headers,
        body: jsonEncode({
          if (name != null) 'name': name,
          if (notifyDanger != null) 'notify_danger': notifyDanger,
          if (notifyWarning != null) 'notify_warning': notifyWarning,
          if (notifyOffline != null) 'notify_offline': notifyOffline,
        })));
    final user = AppUser.fromJson(body as Map<String, dynamic>);
    await Session.instance.updateUser(user);
    return user;
  }

  /// Signs out other phones; this phone keeps working with a new token.
  Future<void> changePassword(String current, String newPassword) async {
    final body = await _send(() => _client.post(_u('/api/auth/change-password/'),
        headers: _headers,
        body: jsonEncode(
            {'current_password': current, 'new_password': newPassword})));
    await _saveSession(body as Map<String, dynamic>);
  }

  /// Step 1: emails a code to [newEmail].
  Future<String> requestEmailChange(String password, String newEmail) async {
    final body = await _send(() => _client.post(_u('/api/auth/change-email/'),
        headers: _headers,
        body: jsonEncode({'password': password, 'new_email': newEmail})));
    return (body as Map<String, dynamic>)['detail'] as String? ?? 'Code sent.';
  }

  /// Step 2: confirms the code sent to the new address.
  Future<void> confirmEmailChange(String code) async {
    final body = await _send(() => _client.post(_u('/api/auth/change-email/confirm/'),
        headers: _headers, body: jsonEncode({'code': code})));
    await Session.instance.updateUser(AppUser.fromJson(body as Map<String, dynamic>));
  }

  Future<void> deleteAccount(String password) async {
    await _send(() => _client.delete(_u('/api/auth/me/'),
        headers: _headers, body: jsonEncode({'password': password})));
    await Session.instance.signOut();
  }

  Future<void> registerPushToken(String token) async {
    await _send(() => _client.post(_u('/api/push/register/'),
        headers: _headers, body: jsonEncode({'token': token})));
  }

  Future<void> _saveSession(Map<String, dynamic> body) => Session.instance.signIn(
      body['token'] as String,
      AppUser.fromJson(body['user'] as Map<String, dynamic>));

  // ----------------------------------------------------------- detectors --

  Future<List<Detector>> fetchDetectors() async {
    final list =
        await _send(() => _client.get(_u('/api/detectors/'), headers: _headers));
    return (list as List)
        .map((e) => Detector.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Detector> fetchDetector(int id) async {
    final body =
        await _send(() => _client.get(_u('/api/detectors/$id/'), headers: _headers));
    return Detector.fromJson(body as Map<String, dynamic>);
  }

  /// [name] may be empty — the server then names it "<room> Detector".
  Future<Detector> createDetector(String room, String name) async {
    final body = await _send(() => _client.post(_u('/api/detectors/'),
        headers: _headers,
        body: jsonEncode({'room': room, 'name': name})));
    return Detector.fromJson(body as Map<String, dynamic>);
  }

  Future<Detector> updateDetector(int id,
      {String? room, String? name, bool? mq5Enabled}) async {
    final body = await _send(() => _client.patch(_u('/api/detectors/$id/'),
        headers: _headers,
        body: jsonEncode({
          if (room != null) 'room': room,
          if (name != null) 'name': name,
          if (mq5Enabled != null) 'mq5_enabled': mq5Enabled,
        })));
    return Detector.fromJson(body as Map<String, dynamic>);
  }

  Future<void> deleteDetector(int id) async {
    await _send(() => _client.delete(_u('/api/detectors/$id/'), headers: _headers));
  }

  // ------------------------------------------------------------- history --

  /// Fire-and-forget request so a sleeping free server starts waking up
  /// (takes up to a minute) before a detector needs it.
  void wakeServer() {
    _client.get(_u('/api/health/')).timeout(const Duration(seconds: 90)).ignore();
  }

  /// Downloads a CSV export. Returns the file contents and its file name.
  Future<(List<int>, String)> downloadCsv(String path, Map<String, String> query) async {
    final http.Response resp;
    try {
      resp = await _client
          .get(_u(path, query), headers: _headers)
          .timeout(const Duration(seconds: 90)); // big exports + cold start
    } on TimeoutException {
      throw ApiException('The export is taking too long. Try a shorter period.');
    } on SocketException {
      resetConnection();
      throw ApiException('Cannot reach server. Check your internet connection.');
    } on http.ClientException {
      resetConnection();
      throw ApiException('Cannot reach server. Check your internet connection.');
    }
    if (resp.statusCode == 401 && Session.instance.isLoggedIn) {
      await Session.instance.signOut();
      throw ApiException('Your session has ended. Please log in again.');
    }
    if (resp.statusCode >= 400) throw ApiException(_errorMessage(resp));
    final disposition = resp.headers['content-disposition'] ?? '';
    final name = RegExp(r'filename="([^"]+)"').firstMatch(disposition)?.group(1) ??
        'notifire-export.csv';
    return (resp.bodyBytes.toList(), name);
  }

  /// One alert: what triggered it and the readings at that moment.
  Future<DetectionLog> fetchLog(int id) async {
    final body = await _send(() => _client.get(_u('/api/logs/$id/'), headers: _headers));
    return DetectionLog.fromJson(body as Map<String, dynamic>);
  }

  /// WARNING and DANGER detections across the user's detectors.
  Future<List<DetectionLog>> fetchLogs(
      {String? level, int? detectorId, int limit = 100}) async {
    final query = <String, String>{
      'limit': '$limit',
      if (level != null) 'level': level,
      if (detectorId != null) 'detector': '$detectorId',
    };
    final list =
        await _send(() => _client.get(_u('/api/logs/', query), headers: _headers));
    return (list as List)
        .map((e) => DetectionLog.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
