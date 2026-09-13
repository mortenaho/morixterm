import 'package:flutter_test/flutter_test.dart';

import 'package:morixterm/services/ssh_welcome_banner.dart';

void main() {
  test('renders the SSH welcome banner with the active session', () {
    final banner = sshWelcomeBanner(
      username: 'alice',
      host: 'example.com',
      port: 2222,
    );

    // Brand ASCII wordmark (MORIXTERM) and session identity.
    expect(banner, contains('__  __'));
    expect(banner, contains('v1.0.0'));
    expect(banner, contains('alice'));
    expect(banner, contains('@'));
    expect(banner, contains('example.com'));
    expect(banner, contains('2222'));
    expect(banner, contains('CONNECTED'));
    expect(banner, contains('SSH CHANNEL OPEN'));
    expect(banner, contains('Connect · Manage · Explore'));
    expect(banner, contains('TARGET'));
    expect(banner, contains('WORKSPACE'));
    expect(banner, contains('SHORTCUTS'));
    expect(banner, contains('Interactive shell'));
    expect(banner, contains('SCP / SFTP upload'));
    expect(banner, contains('Monitor'));
    expect(banner, contains('\x1b['));
    expect(banner, contains('\r\n'));
    // No wide Unicode block art that breaks terminal cells.
    expect(banner, isNot(contains('█')));
    expect(banner, isNot(contains('╗')));
  });
}
