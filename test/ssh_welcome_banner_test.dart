import 'package:flutter_test/flutter_test.dart';

import 'package:morixterm/services/ssh_welcome_banner.dart';

void main() {
  test('renders the SSH welcome banner with the active session', () {
    final banner = sshWelcomeBanner(
      username: 'alice',
      host: 'example.com',
      port: 2222,
      version: 'v0.1.0-build.42',
    );

    expect(banner, contains('__  __'));
    expect(banner, contains('v0.1.0-build.42'));
    expect(banner, contains('alice'));
    expect(banner, contains('@'));
    expect(banner, contains('example.com'));
    expect(banner, contains('2222'));
    expect(banner, contains('LIVE'));
    expect(banner, contains('channel open'));
    expect(banner, contains('Connect · Manage · Explore'));
    expect(banner, contains('host'));
    expect(banner, contains('when'));
    expect(banner, contains('tools'));
    expect(banner, contains('keys'));
    expect(banner, contains('shell'));
    expect(banner, contains('upload'));
    expect(banner, contains('monitor'));
    expect(banner, contains('Ready'));
    expect(banner, contains('\x1b['));
    expect(banner, contains('\r\n'));
    // No wide Unicode block art that breaks terminal cells.
    expect(banner, isNot(contains('█')));
    expect(banner, isNot(contains('╗')));
  });
}
