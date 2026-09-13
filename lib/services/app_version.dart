import 'package:package_info_plus/package_info_plus.dart';

/// App version label aligned with GitHub release tags (`v0.1.0-build.N`).
class AppVersion {
  AppVersion._();

  static String _label = 'v0.1.0';
  static bool _loaded = false;

  /// Cached display label, e.g. `v0.1.0-build.42`.
  static String get label => _label;

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    final info = await PackageInfo.fromPlatform();
    _label = formatFromPackageInfo(info);
    _loaded = true;
  }

  /// Maps Flutter `version` / `buildNumber` to the release-style label.
  ///
  /// CI writes `0.1.0-build.N+N` into pubspec so [PackageInfo.version] is
  /// already `0.1.0-build.N`. Local `0.1.0+1` stays `v0.1.0`.
  static String formatFromPackageInfo(PackageInfo info) {
    final version = info.version.trim();
    final build = info.buildNumber.trim();
    if (version.startsWith('v')) return version;
    if (version.contains('-build.')) return 'v$version';
    if (build.isNotEmpty && build != '0' && build != '1') {
      return 'v$version-build.$build';
    }
    return 'v$version';
  }
}
