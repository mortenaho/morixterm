import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/connection_snapshot.dart';
import '../models/remote_entry.dart';
import '../models/saved_session.dart';
import 'app_log.dart';

class RdpConnectionRequest {
  const RdpConnectionRequest({
    required this.host,
    required this.username,
    required this.password,
    this.port = 3389,
    this.title = 'morixterm',
  });

  final String host;
  final String username;
  final String password;
  final int port;
  final String title;
}

class RdpException implements Exception {
  RdpException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Starts an RDP desktop window via FreeRDP (bundled or system `xfreerdp`).
///
/// No Remmina — FreeRDP opens its own remote-desktop window.
class RdpSessionService {
  Process? _process;
  StreamSubscription<String>? _stderrSub;
  StreamSubscription<String>? _stdoutSub;
  final _out = StreamController<ConnectionSnapshot>.broadcast();
  ConnectionSnapshot _snapshot = const ConnectionSnapshot(phase: ConnectionPhase.idle);
  bool _stopping = false;

  Stream<ConnectionSnapshot> get changes => _out.stream;
  ConnectionSnapshot get snapshot => _snapshot;

  Future<void> connect(RdpConnectionRequest request) async {
    final endpoint = parseEndpoint(request.host, request.port);
    if (endpoint.host.isEmpty) {
      throw RdpException('Enter a server address');
    }
    if (request.username.trim().isEmpty) {
      throw RdpException('Enter a username');
    }
    if (request.password.isEmpty) {
      throw RdpException('Enter a password');
    }

    await disconnect();
    _stopping = false;
    await AppLog.startAttempt('RDP ${request.title} ${endpoint.host}:${endpoint.port} user=${request.username.trim()}');
    _emit(ConnectionSnapshot(
      phase: ConnectionPhase.connecting,
      protocol: SessionProtocol.rdp,
      host: endpoint.host,
      port: endpoint.port,
      username: request.username.trim(),
      title: request.title,
    ));

    final freerdp = await locateFreeRdpClient();
    await AppLog.line('RDP FreeRDP binary: ${freerdp ?? 'NOT FOUND'}');

    if (freerdp == null) {
      _fail(
        'FreeRDP client not found.\n'
        'Place xfreerdp next to the app, in linux/vendor/, or install:\n'
        '  sudo apt install freerdp-x11\n'
        'Log: ${AppLog.lastPath}',
      );
      throw RdpException(_snapshot.error!);
    }

    try {
      await _startFreeRdp(freerdp, request, endpoint);
    } catch (error, stack) {
      await AppLog.line('RDP connect exception: $error');
      await AppLog.line('$stack');
      if (_snapshot.phase != ConnectionPhase.failed) {
        _fail('Failed to start connection: $error\nLog: ${AppLog.lastPath}');
      }
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _stopping = true;
    _stderrSub?.cancel();
    _stdoutSub?.cancel();
    _stderrSub = null;
    _stdoutSub = null;
    final process = _process;
    _process = null;
    if (process != null) {
      process.kill(ProcessSignal.sigterm);
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {
        process.kill(ProcessSignal.sigkill);
      }
    }
    if (_snapshot.phase != ConnectionPhase.idle) {
      _emit(const ConnectionSnapshot(phase: ConnectionPhase.idle));
    }
    _stopping = false;
  }

  Future<void> dispose() async {
    await disconnect();
    await _out.close();
  }

  static String get sharePath {
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    return '$home/.local/share/morixterm/share';
  }

  static Future<Directory> ensureShareDir() async {
    final dir = Directory(sharePath);
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> shareLocalFile(String localPath, {String? destDir}) async {
    if (_snapshot.phase != ConnectionPhase.connected) {
      await AppLog.line('RDP share denied phase=${_snapshot.phase}');
      throw RdpException('Connect to an RDP session first');
    }
    final dir = destDir == null ? await ensureShareDir() : Directory(destDir);
    await dir.create(recursive: true);
    final name = localPath.split(Platform.pathSeparator).last;
    if (name.isEmpty) throw RdpException('Invalid file name');
    return File(localPath).copy('${dir.path}/$name');
  }

  Future<List<RemoteEntry>> listSharedEntries(String path) async {
    final root = await ensureShareDir();
    if (!_insideShare(path, root.path)) {
      throw RdpException('Path is outside the shared drive');
    }
    final dir = Directory(path);
    if (!dir.existsSync()) throw RdpException('Folder not found');
    final entries = <RemoteEntry>[];
    await for (final item in dir.list()) {
      final name = item.path.split(Platform.pathSeparator).last;
      if (name.isEmpty) continue;
      entries.add(RemoteEntry(
        name: name,
        path: item.path,
        isDirectory: FileSystemEntity.isDirectorySync(item.path),
      ));
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  Future<void> copyShared(List<String> sources, String destDir) async {
    final result = await Process.run('cp', ['-a', ...sources, destDir]);
    if (result.exitCode != 0) {
      throw RdpException((result.stderr as String).trim().isEmpty ? 'Copy failed' : (result.stderr as String).trim());
    }
  }

  Future<void> moveShared(List<String> sources, String destDir) async {
    final result = await Process.run('mv', [...sources, destDir]);
    if (result.exitCode != 0) {
      throw RdpException((result.stderr as String).trim().isEmpty ? 'Move failed' : (result.stderr as String).trim());
    }
  }

  Future<void> mkdirShared(String parentDir, String name) async {
    final root = await ensureShareDir();
    if (!_insideShare(parentDir, root.path)) {
      throw RdpException('Path is outside the shared drive');
    }
    if (name.isEmpty || name.contains('/') || name.contains('\\') || name == '.' || name == '..') {
      throw RdpException('Invalid folder name');
    }
    final path = RemoteEntry.join(parentDir, name);
    final dir = Directory(path);
    if (await dir.exists()) {
      throw RdpException('Folder already exists');
    }
    await dir.create();
  }

  Future<void> renameShared(String path, String newName) async {
    final root = await ensureShareDir();
    if (!_insideShare(path, root.path)) {
      throw RdpException('Path is outside the shared drive');
    }
    if (newName.isEmpty || newName.contains('/') || newName.contains('\\') || newName == '.' || newName == '..') {
      throw RdpException('Invalid new name');
    }
    final parent = RemoteEntry.parent(path);
    final dest = RemoteEntry.join(parent, newName);
    if (dest == path) return;
    final result = await Process.run('mv', ['--', path, dest]);
    if (result.exitCode != 0) {
      throw RdpException((result.stderr as String).trim().isEmpty ? 'Rename failed' : (result.stderr as String).trim());
    }
  }

  Future<String> sharedMode(String path) async {
    final root = await ensureShareDir();
    if (!_insideShare(path, root.path)) {
      throw RdpException('Path is outside the shared drive');
    }
    final result = await Process.run('stat', ['-c', '%a', '--', path]);
    if (result.exitCode != 0) {
      throw RdpException('Could not read permissions');
    }
    var mode = (result.stdout as String).trim();
    if (mode.length == 4) mode = mode.substring(1);
    return mode;
  }

  Future<void> chmodShared(List<String> paths, {required String mode, bool recursive = false}) async {
    final root = await ensureShareDir();
    for (final path in paths) {
      if (!_insideShare(path, root.path)) {
        throw RdpException('Path is outside the shared drive');
      }
    }
    final normalized = mode.trim();
    if (!RegExp(r'^[0-7]{3,4}$').hasMatch(normalized)) {
      throw RdpException('Mode must look like 755 or 644');
    }
    final args = <String>[
      if (recursive) '-R',
      normalized.length == 4 ? normalized.substring(1) : normalized,
      '--',
      ...paths,
    ];
    final result = await Process.run('chmod', args);
    if (result.exitCode != 0) {
      throw RdpException((result.stderr as String).trim().isEmpty ? 'Permission change failed' : (result.stderr as String).trim());
    }
  }

  bool _insideShare(String path, String root) {
    final resolved = File(path).absolute.path;
    final base = Directory(root).absolute.path;
    return resolved == base || resolved.startsWith('$base/');
  }

  /// Prefer app-bundled FreeRDP, then PATH — never Remmina.
  static Future<String?> locateFreeRdpClient() async {
    final home = Platform.environment['HOME'] ?? '';
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final bundled = <String>[
      '$exeDir/xfreerdp',
      '$exeDir/xfreerdp3',
      if (home.isNotEmpty) '$home/.local/share/morixterm/xfreerdp',
      if (home.isNotEmpty) '$home/.local/share/morixterm/xfreerdp3',
      '${Directory.current.path}/linux/vendor/xfreerdp',
      '${Directory.current.path}/linux/vendor/xfreerdp3',
      // flutter run from project root / build dirs
      '$exeDir/../../../../linux/vendor/xfreerdp',
      '$exeDir/../../../../../linux/vendor/xfreerdp',
    ];
    for (final path in bundled) {
      final file = File(path);
      if (await file.exists()) return file.absolute.path;
    }

    const names = [
      'xfreerdp3',
      'xfreerdp',
      'wlfreerdp',
      'wlfreerdp3',
      'sdl-freerdp',
      'sdl-freerdp3',
    ];
    for (final name in names) {
      final fromPath = await _which(name);
      if (fromPath != null && !fromPath.toLowerCase().contains('remmina')) {
        return fromPath;
      }
    }
    return null;
  }

  Future<void> _startFreeRdp(
    String client,
    RdpConnectionRequest request,
    ({String host, int port}) endpoint,
  ) async {
    final argsFile = File(
      '${Directory.systemTemp.path}/morixterm-${DateTime.now().microsecondsSinceEpoch}.args',
    );
    await ensureShareDir();
    await argsFile.writeAsString([
      '/v:${endpoint.host}:${endpoint.port}',
      '/u:${request.username.trim()}',
      '/p:${request.password}',
      '/cert:tofu',
      '+clipboard',
      '+dynamic-resolution',
      '/network:auto',
      '/drive:morixterm,$sharePath',
      '/t:${request.title}',
    ].join('\n'));
    try {
      await Process.run('chmod', ['600', argsFile.path]);
    } catch (_) {}

    Future<void> deleteArgs() async {
      try {
        if (await argsFile.exists()) await argsFile.delete();
      } catch (_) {}
    }

    await AppLog.line(
        'RDP command: $client /args-from:file:<temp> /v:${endpoint.host}:${endpoint.port} /u:${request.username.trim()} (password hidden)');

    late final Process process;
    try {
      process = await Process.start(client, ['/args-from:file:${argsFile.path}']);
    } catch (error) {
      await deleteArgs();
      rethrow;
    }
    await AppLog.line('RDP pid: ${process.pid}');
    _process = process;
    Future<void>.delayed(const Duration(seconds: 2), deleteArgs);

    final log = StringBuffer();
    void capture(String stream, String chunk) {
      log.write(chunk);
      AppLog.line('RDP $stream: $chunk');
      final error = _extractError(log.toString());
      if (error != null && _snapshot.phase == ConnectionPhase.connecting) {
        _fail('$error\nLog: ${AppLog.lastPath}');
      }
    }

    _stderrSub = process.stderr.transform(utf8.decoder).listen((chunk) => capture('stderr', chunk));
    _stdoutSub = process.stdout.transform(utf8.decoder).listen((chunk) => capture('stdout', chunk));

    process.exitCode.then((code) {
      AppLog.line('RDP exit code: $code');
      deleteArgs();
      if (_stopping) return;
      if (_snapshot.phase == ConnectionPhase.connecting) {
        _fail('${_extractError(log.toString()) ?? 'Connection failed (exit $code).'}\nLog: ${AppLog.lastPath}');
      } else if (_snapshot.phase == ConnectionPhase.connected) {
        _emit(const ConnectionSnapshot(phase: ConnectionPhase.idle));
      }
      _process = null;
    });

    final outcome = await Future.any<String>([
      process.exitCode.then((code) => 'exit:$code'),
      Future<String>.delayed(const Duration(milliseconds: 2500), () => 'alive'),
    ]);

    if (outcome.startsWith('exit:')) {
      final code = int.tryParse(outcome.split(':').last) ?? 1;
      final error = '${_extractError(log.toString()) ?? 'Connection failed (exit $code).'}\nLog: ${AppLog.lastPath}';
      _fail(error);
      throw RdpException(error);
    }

    if (_snapshot.phase == ConnectionPhase.connecting) {
      _emit(ConnectionSnapshot(
        phase: ConnectionPhase.connected,
        protocol: SessionProtocol.rdp,
        host: endpoint.host,
        port: endpoint.port,
        username: request.username.trim(),
        title: request.title,
      ));
    }
  }

  static String? _extractError(String log) {
    final lines = log
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    for (final line in lines.reversed) {
      final lower = line.toLowerCase();
      if (lower.contains('logon failed') ||
          lower.contains('status_logon_failure') ||
          lower.contains('authentication failure') ||
          lower.contains('access denied') ||
          lower.contains('errconnect') ||
          lower.contains('connection refused') ||
          lower.contains('name or service not known') ||
          lower.contains('timed out') ||
          lower.contains('unable to connect') ||
          lower.contains('failed to connect')) {
        return _friendlyError(line);
      }
    }
    return null;
  }

  static String _friendlyError(String line) {
    final lower = line.toLowerCase();
    if (lower.contains('logon') ||
        lower.contains('authentication') ||
        lower.contains('access denied') ||
        lower.contains('connect_cancelled') ||
        lower.contains('nla begin failed')) {
      return 'Authentication failed. Check username or password.';
    }
    if (lower.contains('refused')) {
      return 'Connection refused. Check RDP host and port.';
    }
    if (lower.contains('timed out')) {
      return 'Connection timed out. Check that the server is reachable.';
    }
    if (lower.contains('name or service not known')) {
      return 'Host could not be resolved.';
    }
    return 'RDP connection failed.';
  }

  static Future<String?> _which(String name) async {
    try {
      final result = await Process.run('which', [name]);
      if (result.exitCode != 0) return null;
      final path = (result.stdout as String).trim();
      return path.isEmpty ? null : path;
    } catch (_) {
      return null;
    }
  }

  void _fail(String message) {
    AppLog.line('RDP FAIL: $message');
    _emit(ConnectionSnapshot(
      phase: ConnectionPhase.failed,
      protocol: SessionProtocol.rdp,
      host: _snapshot.host,
      port: _snapshot.port,
      username: _snapshot.username,
      title: _snapshot.title,
      error: message,
    ));
  }

  void _emit(ConnectionSnapshot snapshot) {
    _snapshot = snapshot;
    if (!_out.isClosed) _out.add(snapshot);
  }
}
