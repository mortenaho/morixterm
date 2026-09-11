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

class ScpTransfer {
  static Future<String> homeDir(SSHClient client) async {
    final result = await client.runWithResult(r'printf %s "$HOME"');
    if ((result.exitCode ?? 0) != 0) {
      throw ScpException('پوشه خانگی پیدا نشد');
    }
    final home = utf8.decode(result.stdout, allowMalformed: true).trim();
    if (home.isEmpty) throw ScpException('پوشه خانگی پیدا نشد');
    return home;
  }

  static Future<List<RemoteEntry>> listEntries(SSHClient client, String path) async {
    try {
      return _parseLs(await _run(client, 'LC_ALL=C ls -1Ap --quoting-style=literal -- ${_shellQuote(path)}', 'خواندن پوشه ناموفق بود'), path);
    } on ScpException {
      return _parseFind(await _run(client, 'find ${_shellQuote(path)} -mindepth 1 -maxdepth 1 -printf "%Y\\t%f\\n"', 'خواندن پوشه ناموفق بود'), path);
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
    await _run(client, 'cp -a -- ${_args(sources, destDir)}', 'کپی فایل ناموفق بود');
  }

  static Future<void> moveTo(SSHClient client, List<String> sources, String destDir) async {
    await _run(client, 'mv -- ${_args(sources, destDir)}', 'انتقال فایل ناموفق بود');
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
  }) async {
    final file = File(localPath);
    if (!file.existsSync()) {
      throw ScpException('فایل محلی پیدا نشد');
    }
    final name = localPath.split(Platform.pathSeparator).last;
    if (!_safeName(name)) {
      throw ScpException('نام فایل برای SCP نامعتبر است');
    }

    final size = await file.length();
    final mode = (await file.stat()).mode & 0x1FF;
    final modeText = mode.toRadixString(8).padLeft(4, '0');
    final session = await client.execute('scp -t ${_shellQuote(remoteDir)}');
    final wire = _ScpWire(session);
    try {
      await wire.expectOk();
      session.write(Uint8List.fromList(utf8.encode('C$modeText $size $name\n')));
      await session.flush();
      await wire.expectOk();
      await for (final chunk in file.openRead()) {
        session.write(Uint8List.fromList(chunk));
      }
      session.write(Uint8List.fromList(const [0]));
      await session.flush();
      await wire.expectOk();
      await session.stdin.close();
      await session.done.timeout(const Duration(seconds: 20));
      if ((session.exitCode ?? 0) != 0) {
        throw ScpException(wire.stderr.isEmpty ? 'ارسال SCP ناموفق بود' : wire.stderr.toString().trim());
      }
    } on TimeoutException {
      throw ScpException('زمان ارسال SCP تمام شد');
    } on ScpException {
      rethrow;
    } catch (error) {
      final detail = wire.stderr.isEmpty ? '$error' : wire.stderr.toString().trim();
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

  Future<void> expectOk() async {
    final code = await _readByte().timeout(const Duration(seconds: 20));
    if (code == 0) return;
    final message = StringBuffer();
    while (true) {
      final next = await _readByte().timeout(const Duration(seconds: 20));
      if (next == 10) break;
      message.writeCharCode(next);
    }
    final text = message.toString().trim();
    throw ScpException(text.isEmpty ? 'سرور SCP خطا داد' : text);
  }

  Future<int> _readByte() async {
    while (_buffer.isEmpty && !_closed) {
      _waiter = Completer<void>();
      await _waiter!.future;
    }
    if (_buffer.isEmpty) {
      throw ScpException(stderr.isEmpty ? 'اتصال SCP قطع شد' : stderr.toString().trim());
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
