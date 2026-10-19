import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A Wi-Fi network read from a QR code.
class WifiQr {
  final String ssid;
  final String password;
  final bool open; // no password
  const WifiQr({required this.ssid, required this.password, required this.open});

  /// Parses the standard Wi-Fi QR format used by routers and Android's
  /// "Share Wi-Fi": `WIFI:T:WPA;S:<name>;P:<password>;H:false;;`
  /// (fields in any order; `\` escapes `;`, `,`, `:`, `\` and `"`).
  /// Returns null if the text isn't a Wi-Fi QR code.
  static WifiQr? parse(String? raw) {
    if (raw == null || raw.length < 5 || raw.substring(0, 5).toUpperCase() != 'WIFI:') {
      return null;
    }
    final fields = <String, String>{};
    final body = raw.substring(5);
    var key = StringBuffer();
    var value = StringBuffer();
    var inValue = false;
    for (var i = 0; i < body.length; i++) {
      final c = body[i];
      if (c == r'\' && i + 1 < body.length) {
        (inValue ? value : key).write(body[++i]);
      } else if (!inValue && c == ':') {
        inValue = true;
      } else if (c == ';') {
        if (key.isNotEmpty) fields[key.toString().toUpperCase()] = value.toString();
        key = StringBuffer();
        value = StringBuffer();
        inValue = false;
      } else {
        (inValue ? value : key).write(c);
      }
    }
    if (key.isNotEmpty) fields[key.toString().toUpperCase()] = value.toString();

    var ssid = fields['S'] ?? '';
    var password = fields['P'] ?? '';
    // Some generators wrap values in quotes.
    String unquote(String s) =>
        s.length >= 2 && s.startsWith('"') && s.endsWith('"') ? s.substring(1, s.length - 1) : s;
    ssid = unquote(ssid);
    password = unquote(password);
    if (ssid.isEmpty) return null;
    final type = (fields['T'] ?? '').toUpperCase();
    return WifiQr(ssid: ssid, password: password, open: type == 'NOPASS' || password.isEmpty);
  }
}

/// Wi-Fi passwords that worked before, kept in Android's encrypted storage
/// on this phone only — so setting up the next detector needs no typing.
class WifiCredentials {
  WifiCredentials._();
  static final WifiCredentials instance = WifiCredentials._();

  static const _storage = FlutterSecureStorage();
  static const _key = 'wifi_passwords';

  Future<Map<String, String>> _all() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return {};
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<String?> passwordFor(String ssid) async => (await _all())[ssid];

  Future<Set<String>> savedNetworks() async => (await _all()).keys.toSet();

  Future<void> save(String ssid, String password) async {
    final all = await _all();
    all[ssid] = password;
    try {
      await _storage.write(key: _key, value: jsonEncode(all));
    } catch (_) {
      // Not critical — the user can type it next time.
    }
  }

  Future<void> forgetAll() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}
