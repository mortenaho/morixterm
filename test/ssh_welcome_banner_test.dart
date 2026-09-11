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
    expect(banner, contains('XTERM'));
    expect(banner, contains('v1.0.0'));
    expect(banner, contains('alice@example.com'));
    expect(banner, contains('on port 2222'));
    expect(banner, contains('● CONNECTED'));
    expect(banner, contains('Authenticated and ready for commands'));
    expect(banner, contains('Search terminal output'));
    expect(banner, contains('\x1b['));
  });
}
