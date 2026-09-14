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
    final banner =
        '\n===== ${_redact(title)} @ ${DateTime.now().toIso8601String()} =====\n';
    for (final path in lastPaths) {
      await File(path).writeAsString(banner, flush: true);
      await _chmod600(path);
    }
    await File(historyPath)
        .writeAsString(banner, mode: FileMode.append, flush: true);
    await _chmod600(historyPath);
    stderr.writeln(banner.trim());
  }

  static Future<void> line(String message) async {
    await _ensureDir();
    final text =
        '[${DateTime.now().toIso8601String()}] ${_redact(message)}\n';
    stderr.writeln(text.trim());
    // Avoid flush:true — syncing every line stalls the UI/SSH hot path.
    for (final path in lastPaths) {
      await File(path).writeAsString(text, mode: FileMode.append);
      await _chmod600(path);
    }
    await File(historyPath).writeAsString(text, mode: FileMode.append);
    await _chmod600(historyPath);
  }

  static String _redact(String message) {
    var out = message;
    out = out.replaceAllMapped(
      RegExp(r'(password|passwd|secret|token)\s*[:=]\s*\S+', caseSensitive: false),
      (m) => '${m.group(1)}=***',
    );
    out = out.replaceAllMapped(
      RegExp(r'/p:[^\s]+'),
      (_) => '/p:***',
    );
    out = out.replaceAllMapped(
      RegExp(r'MORIXTERM_SSH_PASS=\S+'),
      (_) => 'MORIXTERM_SSH_PASS=***',
    );
    return out;
  }

  static Future<void> _chmod600(String path) async {
    try {
      await Process.run('chmod', ['600', path]);
    } catch (_) {}
  }

  static Future<void> _ensureDir() async {
    await File(lastPath).parent.create(recursive: true);
  }
}
