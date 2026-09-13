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
    expect(banner, contains('example.com'));
    expect(banner, contains('2222'));
    expect(banner, contains('LIVE'));
    expect(banner, contains('channel open'));
    expect(banner, contains('Connect · Manage · Explore'));
    expect(banner, contains('user'));
    expect(banner, contains('host'));
    expect(banner, contains('port'));
    expect(banner, contains('time'));
    expect(banner, contains('SSH-2'));
    expect(banner, isNot(contains('tools')));
    expect(banner, contains('\x1b['));
    expect(banner, contains('\r\n'));
    expect(banner, isNot(contains('█')));
    expect(banner, isNot(contains('╗')));
  });
}
