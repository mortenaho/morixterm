import 'package:flutter_test/flutter_test.dart';

import 'package:morixterm/services/ssh_welcome_banner.dart';

void main() {
  test('renders the SSH welcome banner with the active session', () {
    final banner = sshWelcomeBanner(
      username: 'alice',
      host: 'example.com',
      port: 2222,
    );

    expect(banner, contains('MORI'));
    expect(banner, contains('X'));
    expect(banner, contains('T'));
    expect(banner, contains('E'));
    expect(banner, contains('R'));
    expect(banner, contains('M'));
    expect(banner, contains('v1.0.0'));
    expect(banner, contains('alice'));
    expect(banner, contains('@'));
    expect(banner, contains('example.com'));
    expect(banner, contains('2222'));
    expect(banner, contains('CONNECTED'));
    expect(banner, contains('Connect · Manage · Explore'));
    expect(banner, contains('Interactive shell'));
    expect(banner, contains('SCP file browser'));
    expect(banner, contains('\x1b['));
    expect(banner, contains('\r\n'));
    // No wide Unicode block art that breaks terminal cells.
    expect(banner, isNot(contains('█')));
    expect(banner, isNot(contains('╗')));
  });
}
