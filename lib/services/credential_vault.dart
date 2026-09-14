import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_session.dart';
import 'secure_crypto.dart';

/// Encrypted password vault for saved sessions.
///
/// Passwords never sit in SharedPreferences plaintext. The vault file is
/// AES-GCM encrypted with a random master key. That master key is either:
/// - wrapped with the app-lock password (PBKDF2), or
/// - stored locally with mode 0600 when app lock is off.
class CredentialVault {
  CredentialVault._();
  static final CredentialVault instance = CredentialVault._();

  static const _prefsWrappedKey = 'credential_vault_wrapped_key';
  static const _prefsWrapSalt = 'credential_vault_wrap_salt';
  static const _prefsWrapIters = 'credential_vault_wrap_iters';

  Uint8List? _masterKey;
  Map<String, String> _secrets = {};

  bool get isUnlocked => _masterKey != null;

  static String get _dir {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return '$home/.local/share/morixterm';
    }
    return '${Directory.current.path}/.morixterm';
  }

  static String get vaultPath => '$_dir/credentials.vault';
  static String get rawKeyPath => '$_dir/master.key';

  static String keyFor(SavedSession session) =>
      '${session.protocol.name}|${session.host}|${session.port}|${session.username}';

  Future<void> unlockWithDeviceKey() async {
    final key = await _loadOrCreateDeviceKey();
    _masterKey = key;
    await _loadVault();
  }

  Future<void> unlockWithAppPassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    final wrapped = prefs.getString(_prefsWrappedKey);
    final saltB64 = prefs.getString(_prefsWrapSalt);
    if (wrapped == null || saltB64 == null) {
      // First time after enabling lock — migrate device key under password.
      final deviceKey = await _loadOrCreateDeviceKey();
      await wrapMasterKeyWithPassword(password, deviceKey);
      _masterKey = deviceKey;
      await _loadVault();
      await _deleteRawKeyFile();
      return;
    }
    final salt = SecureCrypto.decodeBytes(saltB64);
    final wrapKey = SecureCrypto.pbkdf2(password: password, salt: salt);
    final master = SecureCrypto.decodeBytes(
      SecureCrypto.decrypt(key: wrapKey, payload: wrapped),
    );
    _masterKey = master;
    await _loadVault();
  }

  Future<void> wrapMasterKeyWithPassword(
    String password,
    Uint8List masterKey,
  ) async {
    final salt = SecureCrypto.randomBytes(16);
    final wrapKey = SecureCrypto.pbkdf2(password: password, salt: salt);
    final wrapped = SecureCrypto.encrypt(
      key: wrapKey,
      plaintext: SecureCrypto.encodeBytes(masterKey),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsWrappedKey, wrapped);
    await prefs.setString(_prefsWrapSalt, SecureCrypto.encodeBytes(salt));
    await prefs.setInt(_prefsWrapIters, SecureCrypto.pbkdf2Iterations);
  }

  Future<void> unwrapToDeviceKey(String password) async {
    await unlockWithAppPassword(password);
    final master = _masterKey;
    if (master == null) return;
    await _writeRawKey(master);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsWrappedKey);
    await prefs.remove(_prefsWrapSalt);
    await prefs.remove(_prefsWrapIters);
  }

  void lock() {
    _masterKey = null;
    _secrets = {};
  }

  /// Exposed so AppLock can re-wrap the in-memory master key.
  Uint8List exportMasterKeyForWrap() {
    final key = _masterKey;
    if (key == null) {
      throw StateError('Credential vault is locked');
    }
    return Uint8List.fromList(key);
  }

  Future<String?> read(SavedSession session) async {
    await _ensureUnlocked();
    return _secrets[keyFor(session)];
  }

  Future<void> write(SavedSession session, String password) async {
    await _ensureUnlocked();
    final key = keyFor(session);
    if (password.isEmpty) {
      _secrets.remove(key);
    } else {
      _secrets[key] = password;
    }
    await _persistVault();
  }

  Future<void> remove(SavedSession session) async {
    await _ensureUnlocked();
    _secrets.remove(keyFor(session));
    await _persistVault();
  }

  Future<void> migratePlaintextPasswords(List<SavedSession> sessions) async {
    await _ensureUnlocked();
    var changed = false;
    for (final session in sessions) {
      if (session.password.isEmpty) continue;
      _secrets[keyFor(session)] = session.password;
      changed = true;
    }
    if (changed) await _persistVault();
  }

  Future<void> _ensureUnlocked() async {
    if (_masterKey != null) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_prefsWrappedKey) != null) {
      throw StateError('Credential vault is locked');
    }
    await unlockWithDeviceKey();
  }

  Future<Uint8List> _loadOrCreateDeviceKey() async {
    final file = File(rawKeyPath);
    if (await file.exists()) {
      final text = (await file.readAsString()).trim();
      if (text.isNotEmpty) return SecureCrypto.decodeBytes(text);
    }
    final key = SecureCrypto.randomBytes(SecureCrypto.keyBytes);
    await _writeRawKey(key);
    return key;
  }

  Future<void> _writeRawKey(Uint8List key) async {
    final file = File(rawKeyPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(SecureCrypto.encodeBytes(key));
    try {
      await Process.run('chmod', ['600', file.path]);
    } catch (_) {}
  }

  Future<void> _deleteRawKeyFile() async {
    try {
      final file = File(rawKeyPath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> deleteRawKeyFile() => _deleteRawKeyFile();

  Future<void> _loadVault() async {
    final master = _masterKey;
    if (master == null) return;
    final file = File(vaultPath);
    if (!await file.exists()) {
      _secrets = {};
      return;
    }
    try {
      final payload = await file.readAsString();
      final json = SecureCrypto.decrypt(key: master, payload: payload);
      final map = jsonDecode(json);
      if (map is Map) {
        _secrets = {
          for (final e in map.entries)
            if (e.value is String) e.key.toString(): e.value as String,
        };
      } else {
        _secrets = {};
      }
    } catch (_) {
      _secrets = {};
    }
  }

  Future<void> _persistVault() async {
    final master = _masterKey;
    if (master == null) return;
    final file = File(vaultPath);
    await file.parent.create(recursive: true);
    final payload = SecureCrypto.encrypt(
      key: master,
      plaintext: jsonEncode(_secrets),
    );
    await file.writeAsString(payload);
    try {
      await Process.run('chmod', ['600', file.path]);
    } catch (_) {}
  }
}
