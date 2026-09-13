import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:morixterm/services/app_version.dart';

void main() {
  test('formats CI pubspec version like the GitHub release tag', () {
    final info = PackageInfo(
      appName: 'morixterm',
      packageName: 'com.example.morixterm',
      version: '0.1.0-build.42',
      buildNumber: '42',
    );
    expect(AppVersion.formatFromPackageInfo(info), 'v0.1.0-build.42');
  });

  test('keeps local 0.1.0+1 as v0.1.0', () {
    final info = PackageInfo(
      appName: 'morixterm',
      packageName: 'com.example.morixterm',
      version: '0.1.0',
      buildNumber: '1',
    );
    expect(AppVersion.formatFromPackageInfo(info), 'v0.1.0');
  });
}
