import 'dart:io';

class AppLog {
  AppLog._();

  static String get lastPath {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return '$home/.local/share/morixterm/morixterm-last.log';
    }
    return '${Directory.current.path}/morixterm-last.log';
  }

  static String get historyPath {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return '$home/.local/share/morixterm/morixterm.log';
    }
    return '${Directory.current.path}/morixterm.log';
  }

  static List<String> get lastPaths => [
        lastPath,
        '${Directory.current.path}/morixterm-last.log',
      ];

  static Future<void> startAttempt(String title) async {
    await _ensureDir();
    final banner = '\n===== $title @ ${DateTime.now().toIso8601String()} =====\n';
    for (final path in lastPaths) {
      await File(path).writeAsString(banner, flush: true);
    }
    await File(historyPath).writeAsString(banner, mode: FileMode.append, flush: true);
    stderr.writeln(banner.trim());
  }

  static Future<void> line(String message) async {
    await _ensureDir();
    final text = '[${DateTime.now().toIso8601String()}] $message\n';
    stderr.writeln(text.trim());
    for (final path in lastPaths) {
      await File(path).writeAsString(text, mode: FileMode.append, flush: true);
    }
    await File(historyPath).writeAsString(text, mode: FileMode.append, flush: true);
  }

  static Future<void> _ensureDir() async {
    await File(lastPath).parent.create(recursive: true);
  }
}
