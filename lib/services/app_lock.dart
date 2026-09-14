import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'credential_vault.dart';
import 'secure_crypto.dart';

/// Local app lock — salted PBKDF2 verifier (legacy SHA-256 migrated on use).
class AppLock {
  static const _enabledKey = 'app_lock_enabled';
  static const _hashKey = 'app_lock_password_hash';
  static const _saltKey = 'app_lock_password_salt';
  static const _algoKey = 'app_lock_algo';
  static const _itersKey = 'app_lock_iters';
  static const _algoLegacy = 'sha256';
  static const _algoPbkdf2 = 'pbkdf2-sha256';
  static const idleLockMinutesKey = 'app_lock_idle_minutes';
  static const defaultIdleMinutes = 10;

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

  Future<int> idleLockMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(idleLockMinutesKey) ?? defaultIdleMinutes;
  }

  Future<void> setIdleLockMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(idleLockMinutesKey, minutes.clamp(0, 240));
  }

  Future<bool> verify(String password) async {
    final prefs = await SharedPreferences.getInstance();
    final hash = prefs.getString(_hashKey);
    final saltB64 = prefs.getString(_saltKey);
    if (hash == null || saltB64 == null) return false;
    final algo = prefs.getString(_algoKey) ?? _algoLegacy;
    final ok = switch (algo) {
      _algoPbkdf2 =>
        _pbkdf2Hash(password, saltB64, prefs.getInt(_itersKey)) == hash,
      _ => _legacyHash(password, saltB64) == hash,
    };
    if (ok && algo == _algoLegacy) {
      await _storeVerifier(password);
    }
    return ok;
  }

  Future<void> enable(String password) async {
    final trimmed = password.trim();
    if (trimmed.length < 4) {
      throw AppLockException('Password must be at least 4 characters');
    }
    final vault = CredentialVault.instance;
    if (!vault.isUnlocked) {
      await vault.unlockWithDeviceKey();
    }
    await vault.wrapMasterKeyWithPassword(
      trimmed,
      vault.exportMasterKeyForWrap(),
    );
    await vault.deleteRawKeyFile();
    await _storeVerifier(trimmed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, true);
  }

  Future<void> changePassword({
    required String current,
    required String next,
  }) async {
    if (!await verify(current)) {
      throw AppLockException('Current password is incorrect');
    }
    final vault = CredentialVault.instance;
    if (!vault.isUnlocked) {
      await vault.unlockWithAppPassword(current);
    }
    final trimmed = next.trim();
    if (trimmed.length < 4) {
      throw AppLockException('Password must be at least 4 characters');
    }
    await vault.wrapMasterKeyWithPassword(
      trimmed,
      vault.exportMasterKeyForWrap(),
    );
    await vault.deleteRawKeyFile();
    await _storeVerifier(trimmed);
  }

  Future<void> disable(String current) async {
    if (!await verify(current)) {
      throw AppLockException('Current password is incorrect');
    }
    final vault = CredentialVault.instance;
    if (!vault.isUnlocked) {
      await vault.unlockWithAppPassword(current);
    }
    await vault.unwrapToDeviceKey(current);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
    await prefs.remove(_hashKey);
    await prefs.remove(_saltKey);
    await prefs.remove(_algoKey);
    await prefs.remove(_itersKey);
  }

  Future<void> _storeVerifier(String password) async {
    final salt = SecureCrypto.randomBytes(16);
    final saltB64 = SecureCrypto.encodeBytes(salt);
    final hash = _pbkdf2Hash(password, saltB64, SecureCrypto.pbkdf2Iterations);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_saltKey, saltB64);
    await prefs.setString(_hashKey, hash);
    await prefs.setString(_algoKey, _algoPbkdf2);
    await prefs.setInt(_itersKey, SecureCrypto.pbkdf2Iterations);
  }

  static String _legacyHash(String password, String salt) {
    final bytes = utf8.encode('$salt:$password');
    return sha256.convert(bytes).toString();
  }

  static String _pbkdf2Hash(String password, String saltB64, int? iters) {
    final salt = SecureCrypto.decodeBytes(saltB64);
    final key = SecureCrypto.pbkdf2(
      password: password,
      salt: salt,
      iterations: iters ?? SecureCrypto.pbkdf2Iterations,
    );
    return SecureCrypto.encodeBytes(key);
  }
}

class AppLockException implements Exception {
  AppLockException(this.message);
  final String message;

  @override
  String toString() => message;
}
