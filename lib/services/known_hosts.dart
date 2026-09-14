import 'dart:convert';
import 'dart:io';

import 'app_log.dart';
import 'secure_crypto.dart';

class HostKeyRecord {
  const HostKeyRecord({
    required this.host,
    required this.port,
    required this.keyType,
    required this.fingerprint,
    required this.savedAt,
  });

  final String host;
  final int port;
  final String keyType;
  final String fingerprint;
  final DateTime savedAt;

  String get id => '$host:$port';

  Map<String, Object?> toJson() => {
        'host': host,
        'port': port,
        'keyType': keyType,
        'fingerprint': fingerprint,
        'savedAt': savedAt.toIso8601String(),
      };

  factory HostKeyRecord.fromJson(Map<String, dynamic> json) {
    return HostKeyRecord(
      host: json['host'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 22,
      keyType: json['keyType'] as String? ?? '',
      fingerprint: json['fingerprint'] as String? ?? '',
      savedAt: DateTime.tryParse(json['savedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

enum HostKeyTrust { trusted, unknown, mismatch }

class HostKeyCheck {
  const HostKeyCheck({
    required this.status,
    required this.host,
    required this.port,
    required this.keyType,
    required this.fingerprint,
    this.previous,
  });

  final HostKeyTrust status;
  final String host;
  final int port;
  final String keyType;
  final String fingerprint;
  final HostKeyRecord? previous;
}

/// TOFU store for SSH host-key fingerprints + OpenSSH known_hosts for scp.
class KnownHosts {
  KnownHosts._();

  static final KnownHosts instance = KnownHosts._();

  static String get _dir {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return '$home/.local/share/morixterm';
    }
    return '${Directory.current.path}/.morixterm';
  }

  static String get storePath => '$_dir/known_hosts.json';
  static String get openSshPath => '$_dir/ssh_known_hosts';

  Future<Map<String, HostKeyRecord>> _load() async {
    final file = File(storePath);
    if (!await file.exists()) return {};
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return {};
      final map = <String, HostKeyRecord>{};
      for (final entry in raw.entries) {
        final value = entry.value;
        if (value is Map) {
          final record =
              HostKeyRecord.fromJson(Map<String, dynamic>.from(value));
          map[record.id] = record;
        }
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<void> _save(Map<String, HostKeyRecord> records) async {
    final dir = Directory(_dir);
    await dir.create(recursive: true);
    final file = File(storePath);
    final encoded = jsonEncode({
      for (final entry in records.entries) entry.key: entry.value.toJson(),
    });
    await file.writeAsString(encoded);
    try {
      await Process.run('chmod', ['600', file.path]);
    } catch (_) {}
  }

  HostKeyCheck inspect({
    required String host,
    required int port,
    required String keyType,
    required String fingerprint,
    required Map<String, HostKeyRecord> records,
  }) {
    final previous = records['$host:$port'];
    if (previous == null) {
      return HostKeyCheck(
        status: HostKeyTrust.unknown,
        host: host,
        port: port,
        keyType: keyType,
        fingerprint: fingerprint,
      );
    }
    final same = previous.fingerprint == fingerprint &&
        previous.keyType == keyType;
    return HostKeyCheck(
      status: same ? HostKeyTrust.trusted : HostKeyTrust.mismatch,
      host: host,
      port: port,
      keyType: keyType,
      fingerprint: fingerprint,
      previous: previous,
    );
  }

  Future<HostKeyCheck> check({
    required String host,
    required int port,
    required String keyType,
    required String fingerprint,
  }) async {
    final records = await _load();
    return inspect(
      host: host,
      port: port,
      keyType: keyType,
      fingerprint: fingerprint,
      records: records,
    );
  }

  Future<void> trust({
    required String host,
    required int port,
    required String keyType,
    required String fingerprint,
  }) async {
    final records = await _load();
    records['$host:$port'] = HostKeyRecord(
      host: host,
      port: port,
      keyType: keyType,
      fingerprint: fingerprint,
      savedAt: DateTime.now().toUtc(),
    );
    await _save(records);
    await _refreshOpenSshKnownHosts(host, port);
    await AppLog.line('Trusted SSH host key $host:$port ($keyType)');
  }

  Future<void> forget(String host, int port) async {
    final records = await _load();
    records.remove('$host:$port');
    await _save(records);
  }

  /// Populate OpenSSH known_hosts via ssh-keyscan for system scp.
  Future<void> _refreshOpenSshKnownHosts(String host, int port) async {
    try {
      final result = await Process.run(
        'ssh-keyscan',
        ['-p', '$port', '-T', '5', host],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      final lines = (result.stdout as String)
          .split(RegExp(r'\r?\n'))
          .where((line) => line.isNotEmpty && !line.startsWith('#'))
          .toList();
      if (lines.isEmpty) return;

      final file = File(openSshPath);
      await file.parent.create(recursive: true);
      final existing = await file.exists() ? await file.readAsString() : '';
      final kept = existing
          .split(RegExp(r'\r?\n'))
          .where((line) {
            if (line.isEmpty || line.startsWith('#')) return true;
            // Drop previous entries for this host/port marker.
            return !line.contains(' $host ') &&
                !line.startsWith('$host ') &&
                !line.contains('[$host]:$port');
          })
          .toList();
      final marker = '# morixterm $host:$port';
      final block = [
        marker,
        ...lines.map((line) {
          // Normalize to [host]:port form when non-default port.
          if (port == 22) return line;
          if (line.startsWith('#')) return line;
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length < 3) return line;
          parts[0] = '[$host]:$port';
          return parts.join(' ');
        }),
      ];
      final out = [...kept.where((l) => l.trim().isNotEmpty), ...block, ''];
      await file.writeAsString('${out.join('\n')}\n');
      try {
        await Process.run('chmod', ['600', file.path]);
      } catch (_) {}
    } catch (error) {
      await AppLog.line('ssh-keyscan failed for $host:$port: $error');
    }
  }

  List<String> scpStrictHostKeyArgs() {
    final file = File(openSshPath);
    if (!file.existsSync() || file.lengthSync() == 0) {
      // Fall back to accept-new only when we have no scanned keys yet.
      return const [
        '-o',
        'StrictHostKeyChecking=accept-new',
        '-o',
        'UserKnownHostsFile=/dev/null',
        '-o',
        'GlobalKnownHostsFile=/dev/null',
      ];
    }
    return [
      '-o',
      'StrictHostKeyChecking=yes',
      '-o',
      'UserKnownHostsFile=${file.path}',
      '-o',
      'GlobalKnownHostsFile=/dev/null',
    ];
  }
}
