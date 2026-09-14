import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Small crypto helpers for vault + app lock (PBKDF2 + AES-GCM).
class SecureCrypto {
  static const pbkdf2Iterations = 120000;
  static const keyBytes = 32;
  static const ivBytes = 12;
  static const macBits = 128;

  static Uint8List randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static Uint8List pbkdf2({
    required String password,
    required Uint8List salt,
    int iterations = pbkdf2Iterations,
    int length = keyBytes,
  }) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, length));
    return derivator.process(Uint8List.fromList(utf8.encode(password)));
  }

  /// Returns base64(iv || ciphertext+tag).
  static String encrypt({
    required Uint8List key,
    required String plaintext,
  }) {
    final iv = randomBytes(ivBytes);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), macBits, iv, Uint8List(0)),
      );
    final input = Uint8List.fromList(utf8.encode(plaintext));
    final out = cipher.process(input);
    final packed = Uint8List(iv.length + out.length)
      ..setAll(0, iv)
      ..setAll(iv.length, out);
    return base64Encode(packed);
  }

  static String decrypt({
    required Uint8List key,
    required String payload,
  }) {
    final packed = base64Decode(payload);
    if (packed.length < ivBytes + 16) {
      throw StateError('Invalid ciphertext');
    }
    final iv = packed.sublist(0, ivBytes);
    final cipherText = packed.sublist(ivBytes);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(KeyParameter(key), macBits, iv, Uint8List(0)),
      );
    final out = cipher.process(cipherText);
    return utf8.decode(out);
  }

  static String encodeBytes(Uint8List bytes) => base64UrlEncode(bytes);

  static Uint8List decodeBytes(String value) =>
      Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));
}
