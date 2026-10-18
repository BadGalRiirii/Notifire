import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/models.dart';

/// Holds the logged-in user's API token, persisted in Android's encrypted
/// storage so the user stays logged in between app launches.
class Session extends ChangeNotifier {
  Session._();
  static final Session instance = Session._();

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user';

  String? _token;
  AppUser? _user;

  String? get token => _token;
  AppUser? get user => _user;
  bool get isLoggedIn => _token != null;
  bool get needsVerification => isLoggedIn && !(_user?.emailVerified ?? false);

  /// Refresh the stored user (after verifying email, changing settings...).
  Future<void> updateUser(AppUser user) async {
    _user = user;
    await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
    notifyListeners();
  }

  Future<void> load() async {
    try {
      _token = await _storage.read(key: _tokenKey);
      final userJson = await _storage.read(key: _userKey);
      _user = userJson == null
          ? null
          : AppUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
    } catch (_) {
      // Corrupt/unreadable storage (e.g. after a reinstall) — start logged out.
      _token = null;
      _user = null;
    }
  }

  /// Also used for token rotation (password change/reset) for the same user.
  Future<void> signIn(String token, AppUser user) async {
    _token = token;
    _user = user;
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
    _tokenChanged.add(token);
    notifyListeners();
  }

  /// Emits whenever a new API token is issued, so this phone's notification
  /// token gets (re-)registered with the server.
  final _tokenChanged = StreamController<String>.broadcast();
  Stream<String> get tokenChanged => _tokenChanged.stream;

  Future<void> signOut() async {
    if (_token == null) return;
    _token = null;
    _user = null;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
    notifyListeners();
  }
}
