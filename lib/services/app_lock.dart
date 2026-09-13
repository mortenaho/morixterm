import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local app lock — stores a salted SHA-256 hash, never the plaintext password.
class AppLock {
  static const _enabledKey = 'app_lock_enabled';
  static const _hashKey = 'app_lock_password_hash';
  static const _saltKey = 'app_lock_password_salt';

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_enabledKey) != true) return false;
    final hash = prefs.getString(_hashKey);
    final salt = prefs.getString(_saltKey);
    return hash != null &&
        hash.isNotEmpty &&
        salt != null &&
        salt.isNotEmpty;
  }

  Future<bool> verify(String password) async {
    final prefs = await SharedPreferences.getInstance();
    final hash = prefs.getString(_hashKey);
    final salt = prefs.getString(_saltKey);
    if (hash == null || salt == null) return false;
    return _hash(password, salt) == hash;
  }

  Future<void> enable(String password) async {
    final trimmed = password.trim();
    if (trimmed.length < 4) {
      throw AppLockException('Password must be at least 4 characters');
    }
    final salt = _newSalt();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_saltKey, salt);
    await prefs.setString(_hashKey, _hash(trimmed, salt));
    await prefs.setBool(_enabledKey, true);
  }

  Future<void> changePassword({
    required String current,
    required String next,
  }) async {
    if (!await verify(current)) {
      throw AppLockException('Current password is incorrect');
    }
    await enable(next);
  }

  Future<void> disable(String current) async {
    if (!await verify(current)) {
      throw AppLockException('Current password is incorrect');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
    await prefs.remove(_hashKey);
    await prefs.remove(_saltKey);
  }

  static String _hash(String password, String salt) {
    final bytes = utf8.encode('$salt:$password');
    return sha256.convert(bytes).toString();
  }

  static String _newSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }
}

class AppLockException implements Exception {
  AppLockException(this.message);
  final String message;

  @override
  String toString() => message;
}
