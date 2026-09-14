import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:morixterm/services/credential_vault.dart';
import 'package:morixterm/services/known_hosts.dart';
import 'package:morixterm/services/secure_crypto.dart';
import 'package:morixterm/models/saved_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CredentialVault.instance.lock();
  });

  test('SecureCrypto round-trip', () {
    final key = SecureCrypto.randomBytes(32);
    final cipher = SecureCrypto.encrypt(key: key, plaintext: 'hello secret');
    expect(SecureCrypto.decrypt(key: key, payload: cipher), 'hello secret');
  });

  test('CredentialVault stores secrets encrypted', () async {
    await CredentialVault.instance.unlockWithDeviceKey();
    const session = SavedSession(
      name: 'demo',
      host: 'example.com',
      port: 22,
      username: 'alice',
      protocol: SessionProtocol.ssh,
    );
    await CredentialVault.instance.write(session, 's3cret');
    expect(await CredentialVault.instance.read(session), 's3cret');

    final vaultFile = File(CredentialVault.vaultPath);
    expect(await vaultFile.exists(), isTrue);
    final raw = await vaultFile.readAsString();
    expect(raw.contains('s3cret'), isFalse);
  });

  test('KnownHosts detects unknown and trusted keys', () async {
    final hosts = KnownHosts.instance;
    await hosts.forget('unit-test.example', 22);
    final first = await hosts.check(
      host: 'unit-test.example',
      port: 22,
      keyType: 'ssh-ed25519',
      fingerprint: 'SHA256:abc',
    );
    expect(first.status, HostKeyTrust.unknown);

    await hosts.trust(
      host: 'unit-test.example',
      port: 22,
      keyType: 'ssh-ed25519',
      fingerprint: 'SHA256:abc',
    );
    final trusted = await hosts.check(
      host: 'unit-test.example',
      port: 22,
      keyType: 'ssh-ed25519',
      fingerprint: 'SHA256:abc',
    );
    expect(trusted.status, HostKeyTrust.trusted);

    final mismatch = await hosts.check(
      host: 'unit-test.example',
      port: 22,
      keyType: 'ssh-ed25519',
      fingerprint: 'SHA256:other',
    );
    expect(mismatch.status, HostKeyTrust.mismatch);
    await hosts.forget('unit-test.example', 22);
  });
}
