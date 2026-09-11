import 'package:flutter_test/flutter_test.dart';

import 'package:morixtrem/services/ssh_welcome_banner.dart';

void main() {
  test('renders the SSH welcome banner with the active session', () {
    final banner = sshWelcomeBanner(
      username: 'alice',
      host: 'example.com',
      port: 2222,
    );

    expect(banner, contains('Welcome to Morixtrem!'));
    expect(banner, contains('Morixtrem '));
    expect(banner, contains('v1.0.0'));
    expect(banner, contains('alice@example.com:2222'));
    expect(banner, contains('SSH client'));
    expect(banner, contains('\x1b['));
  });
}
