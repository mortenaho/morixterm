import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../models/remote_entry.dart';

class ScpException implements Exception {
  ScpException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ScpCancelledException implements Exception {
  @override
  String toString() => 'Upload cancelled';
}

class ScpTransfer {
  static Future<String> homeDir(SSHClient client) async {
    final result = await client.runWithResult(r'printf %s "$HOME"');
    if ((result.exitCode ?? 0) != 0) {
      throw ScpException('Home folder not found');
    }
    final home = utf8.decode(result.stdout, allowMalformed: true).trim();
    if (home.isEmpty) throw ScpException('Home folder not found');
    return home;
  }

  static Future<List<RemoteEntry>> listEntries(SSHClient client, String path) async {
    try {
      return _parseLs(await _run(client, 'LC_ALL=C ls -1Ap --quoting-style=literal -- ${_shellQuote(path)}', 'Could not list folder'), path);
    } on ScpException {
      return _parseFind(await _run(client, 'find ${_shellQuote(path)} -mindepth 1 -maxdepth 1 -printf "%Y\\t%f\\n"', 'Could not list folder'), path);
    }
  }

  static List<RemoteEntry> _parseLs(String output, String path) {
    final entries = <RemoteEntry>[];
    for (final raw in output.split(RegExp(r'\r?\n'))) {
      if (raw.isEmpty || raw == '.' || raw == '..' || raw == './' || raw == '../') continue;
      final isDirectory = raw.endsWith('/');
      final name = isDirectory ? raw.substring(0, raw.length - 1) : raw;
      if (name.isEmpty || name == '.' || name == '..') continue;
      entries.add(RemoteEntry(name: name, path: RemoteEntry.join(path, name), isDirectory: isDirectory));
    }
    return _sortEntries(entries);
  }

  static List<RemoteEntry> _parseFind(String output, String path) {
    final entries = <RemoteEntry>[];
    for (final raw in output.split(RegExp(r'\r?\n'))) {
      if (raw.isEmpty) continue;
      final tab = raw.indexOf('\t');
      if (tab <= 0) continue;
      final kind = raw.substring(0, tab);
      final name = raw.substring(tab + 1);
      if (name.isEmpty || name == '.' || name == '..') continue;
      entries.add(RemoteEntry(name: name, path: RemoteEntry.join(path, name), isDirectory: kind == 'd' || kind == 'D'));
    }
    return _sortEntries(entries);
  }

  static List<RemoteEntry> _sortEntries(List<RemoteEntry> entries) {
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  static Future<void> copyTo(SSHClient client, List<String> sources, String destDir) async {
    await _run(client, 'cp -a -- ${_args(sources, destDir)}', 'Copy failed');
  }

  static Future<void> moveTo(SSHClient client, List<String> sources, String destDir) async {
    await _run(client, 'mv -- ${_args(sources, destDir)}', 'Move failed');
  }

  static Future<void> mkdir(SSHClient client, String parentDir, String name) async {
    if (!_safeName(name)) {
      throw ScpException('Invalid folder name');
    }
    final path = RemoteEntry.join(parentDir, name);
    await _run(client, 'mkdir -- ${_shellQuote(path)}', 'Could not create folder');
  }

  static Future<void> rename(SSHClient client, String path, String newName) async {
    if (!_safeName(newName)) {
      throw ScpException('Invalid new name');
    }
    final parent = RemoteEntry.parent(path);
    final dest = RemoteEntry.join(parent, newName);
    if (dest == path) return;
    await _run(client, 'mv -- ${_shellQuote(path)} ${_shellQuote(dest)}', 'Rename failed');
  }

  static Future<String> fileMode(SSHClient client, String path) async {
    try {
      final out = await _run(client, 'stat -c %a -- ${_shellQuote(path)}', 'Could not read permissions');
      final mode = out.trim().split(RegExp(r'\s+')).first;
      if (RegExp(r'^[0-7]{3,4}$').hasMatch(mode)) {
        return mode.length == 4 ? mode.substring(1) : mode;
      }
    } catch (_) {}
    final out = await _run(client, 'LC_ALL=C ls -ld -- ${_shellQuote(path)}', 'Could not read permissions');
    return _modeFromLs(out.trim().split(RegExp(r'\s+')).first);
  }

  static Future<void> chmod(
    SSHClient client,
    List<String> paths, {
    required String mode,
    bool recursive = false,
  }) async {
    final normalized = _normalizeMode(mode);
    final flag = recursive ? '-R ' : '';
    await _run(
      client,
      'chmod $flag$normalized -- ${paths.map(_shellQuote).join(' ')}',
      'Permission change failed',
    );
  }

  static String _normalizeMode(String mode) {
    final trimmed = mode.trim();
    if (!RegExp(r'^[0-7]{3,4}$').hasMatch(trimmed)) {
      throw ScpException('Mode must look like 755 or 644');
    }
    return trimmed.length == 4 ? trimmed.substring(1) : trimmed;
  }

  static String _modeFromLs(String perms) {
    if (perms.length < 10) return '644';
    int bit(String c, String expect) => c == expect ? 1 : 0;
    int triad(int i) =>
        (bit(perms[i], 'r') << 2) | (bit(perms[i + 1], 'w') << 1) | bit(perms[i + 2], 'x');
    final value = (triad(1) << 6) | (triad(4) << 3) | triad(7);
    return value.toRadixString(8).padLeft(3, '0');
  }

  static Future<String> _run(SSHClient client, String command, String fallback) async {
    final result = await client.runWithResult(command);
    if ((result.exitCode ?? 0) != 0) {
      final err = utf8.decode(result.stderr, allowMalformed: true).trim();
      throw ScpException(err.isEmpty ? fallback : err);
    }
    return utf8.decode(result.stdout, allowMalformed: true);
  }

  static String _args(List<String> sources, String destDir) =>
      [...sources.map(_shellQuote), _shellQuote(destDir)].join(' ');

  static Future<void> upload({
    required SSHClient client,
    required String localPath,
    String remoteDir = '.',
    void Function(int sent, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final file = File(localPath);
    if (!file.existsSync()) {
      throw ScpException('Local file not found');
    }
    final name = localPath.split(Platform.pathSeparator).last;
    if (!_safeName(name)) {
      throw ScpException('Invalid file name for SCP');
    }

    final size = await file.length();
    final mode = (await file.stat()).mode & 0x1FF;
    final modeText = mode.toRadixString(8).padLeft(4, '0');
    final session = await client.execute('scp -t ${_shellQuote(remoteDir)}');
    final wire = _ScpWire(session);
    // Scale timeouts with file size (about 1 min per 8 MiB, capped).
    final ioTimeout = Duration(
      seconds: (60 + (size ~/ (8 * 1024 * 1024)) * 60).clamp(90, 3600),
    );
    void checkCancel() {
      if (isCancelled?.call() == true) {
        throw ScpCancelledException();
      }
    }

    try {
      checkCancel();
      await wire.expectOk(timeout: ioTimeout);
      checkCancel();
      session.write(Uint8List.fromList(utf8.encode('C$modeText $size $name\n')));
      await session.flush();
      await wire.expectOk(timeout: ioTimeout);

      var sent = 0;
      var pending = 0;
      const flushEvery = 256 * 1024;
      onProgress?.call(0, size);
      await for (final chunk in file.openRead()) {
        checkCancel();
        final bytes = Uint8List.fromList(chunk);
        session.write(bytes);
        pending += bytes.length;
        sent += bytes.length;
        onProgress?.call(sent.clamp(0, size), size);
        if (pending >= flushEvery) {
          await session.flush();
          pending = 0;
        }
      }
      checkCancel();
      if (pending > 0) await session.flush();
      session.write(Uint8List.fromList(const [0]));
      await session.flush();
      await wire.expectOk(timeout: ioTimeout);
      await session.stdin.close();
      await session.done.timeout(ioTimeout);
      if ((session.exitCode ?? 0) != 0) {
        throw ScpException(wire.stderr.isEmpty
            ? 'SCP upload failed'
            : wire.stderr.toString().trim());
      }
      onProgress?.call(size, size);
    } on ScpCancelledException {
      try {
        session.close();
      } catch (_) {}
      rethrow;
    } on TimeoutException {
      throw ScpException('SCP upload timed out');
    } on ScpException {
      rethrow;
    } catch (error) {
      final detail =
          wire.stderr.isEmpty ? '$error' : wire.stderr.toString().trim();
      throw ScpException(detail);
    } finally {
      await wire.dispose();
    }
  }

  static String _shellQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";

  static bool _safeName(String name) {
    if (name.isEmpty || name == '.' || name == '..') return false;
    return !name.contains('/') && !name.contains('\\') && !name.contains('\n') && !name.contains('\r') && !name.contains('\u0000');
  }
}

class _ScpWire {
  _ScpWire(this.session) {
    _stdout = session.stdout.listen((chunk) {
      _buffer.addAll(chunk);
      _wake();
    }, onDone: () {
      _closed = true;
      _wake();
    });
    _stderr = session.stderr.listen((chunk) {
      stderr.write(utf8.decode(chunk, allowMalformed: true));
    });
  }

  final SSHSession session;
  final StringBuffer stderr = StringBuffer();
  final List<int> _buffer = <int>[];
  Completer<void>? _waiter;
  bool _closed = false;
  late final StreamSubscription<Uint8List> _stdout;
  late final StreamSubscription<Uint8List> _stderr;

  Future<void> expectOk({Duration timeout = const Duration(seconds: 30)}) async {
    final code = await _readByte().timeout(timeout);
    if (code == 0) return;
    final message = StringBuffer();
    while (true) {
      final next = await _readByte().timeout(timeout);
      if (next == 10) break;
      message.writeCharCode(next);
    }
    final text = message.toString().trim();
    throw ScpException(text.isEmpty ? 'SCP server returned an error' : text);
  }

  Future<int> _readByte() async {
    while (_buffer.isEmpty && !_closed) {
      _waiter = Completer<void>();
      await _waiter!.future;
    }
    if (_buffer.isEmpty) {
      throw ScpException(stderr.isEmpty ? 'SCP connection closed' : stderr.toString().trim());
    }
    return _buffer.removeAt(0);
  }

  void _wake() {
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  Future<void> dispose() async {
    await _stdout.cancel();
    await _stderr.cancel();
    session.close();
  }
}
