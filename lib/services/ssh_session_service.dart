import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';

import '../models/connection_snapshot.dart';
import '../models/remote_entry.dart';
import '../models/saved_session.dart';
import 'app_log.dart';
import 'scp_transfer.dart';

class SshConnectionRequest {
  const SshConnectionRequest({
    required this.host,
    required this.username,
    required this.password,
    this.port = 22,
    this.title = 'SSH',
  });

  final String host;
  final String username;
  final String password;
  final int port;
  final String title;
}

class SshException implements Exception {
  SshException(this.message);
  final String message;

  @override
  String toString() => message;
}

class SshSessionService {
  SSHClient? _client;
  SshConnectionRequest? _request;
  SSHSession? _shell;
  StreamSubscription<Uint8List>? _stdoutSub;
  StreamSubscription<Uint8List>? _stderrSub;
  final _out = StreamController<ConnectionSnapshot>.broadcast();
  ConnectionSnapshot _snapshot = const ConnectionSnapshot(phase: ConnectionPhase.idle);
  Terminal? _terminal;
  bool _stopping = false;

  Stream<ConnectionSnapshot> get changes => _out.stream;
  ConnectionSnapshot get snapshot => _snapshot;
  Terminal? get terminal => _terminal;
  bool get canTransfer => _client != null && _snapshot.phase == ConnectionPhase.connected;

  Future<void> connect(SshConnectionRequest request) async {
    final endpoint = parseEndpoint(request.host, request.port);
    if (endpoint.host.isEmpty) {
      throw SshException('آدرس سرور را وارد کنید');
    }
    if (request.username.trim().isEmpty) {
      throw SshException('نام کاربری را وارد کنید');
    }

    await disconnect();
    _stopping = false;
    _request = request;
    _terminal = Terminal(maxLines: 5000);
    await AppLog.startAttempt('SSH ${request.title} ${endpoint.host}:${endpoint.port} user=${request.username.trim()}');
    _emit(ConnectionSnapshot(
      phase: ConnectionPhase.connecting,
      protocol: SessionProtocol.ssh,
      host: endpoint.host,
      port: endpoint.port,
      username: request.username.trim(),
      title: request.title,
    ));

    try {
      final socket = await SSHSocket.connect(
        endpoint.host,
        endpoint.port,
        timeout: const Duration(seconds: 12),
      );
      final identities = await _loadIdentities(request.password);
      final password = request.password;
      final client = SSHClient(
        socket,
        username: request.username.trim(),
        identities: identities.isEmpty ? null : identities,
        onPasswordRequest: password.isEmpty ? null : () => password,
        onUserInfoRequest: password.isEmpty
            ? null
            : (info) => List<String>.filled(info.prompts.length, password),
        onVerifyHostKey: (type, fingerprint) {
          AppLog.line('SSH host key $type $fingerprint');
          return true;
        },
        printDebug: (msg) => AppLog.line('SSH debug: $msg'),
        keepAliveInterval: const Duration(seconds: 20),
        handshakeTimeout: const Duration(seconds: 15),
        authTimeout: const Duration(seconds: 15),
      );
      await AppLog.line('SSH socket connected, keys=${identities.length}');
      await client.authenticated.timeout(const Duration(seconds: 20));
      _client = client;

      final terminal = _terminal!;
      final shell = await client.shell(
        pty: SSHPtyConfig(
          type: 'xterm-256color',
          width: terminal.viewWidth > 0 ? terminal.viewWidth : 120,
          height: terminal.viewHeight > 0 ? terminal.viewHeight : 32,
        ),
      );
      _shell = shell;
      terminal.onOutput = (data) => shell.write(Uint8List.fromList(utf8.encode(data)));
      terminal.onResize = shell.resizeTerminal;
      _stdoutSub = shell.stdout.listen(_writeToTerminal);
      _stderrSub = shell.stderr.listen(_writeToTerminal);
      shell.done.then((_) {
        if (!_stopping && _snapshot.phase == ConnectionPhase.connected) {
          _emit(const ConnectionSnapshot(phase: ConnectionPhase.idle));
        }
      });
      client.done.then((_) {
        if (!_stopping && _snapshot.isActive) {
          _emit(const ConnectionSnapshot(phase: ConnectionPhase.idle));
        }
      });

      await AppLog.line('SSH authenticated, starting shell');
      _emit(ConnectionSnapshot(
        phase: ConnectionPhase.connected,
        protocol: SessionProtocol.ssh,
        host: endpoint.host,
        port: endpoint.port,
        username: request.username.trim(),
        title: request.title,
      ));
    } catch (error, stack) {
      await AppLog.line('SSH ERROR: $error');
      await AppLog.line('$stack');
      final message = '${_friendlyError(error)}\n$error\nلاگ: ${AppLog.lastPath}';
      _fail(message);
      await _closeRemote();
      throw SshException(message);
    }
  }

  Future<void> disconnect() async {
    _stopping = true;
    await _closeRemote();
    _terminal = null;
    if (_snapshot.phase != ConnectionPhase.idle) {
      _emit(const ConnectionSnapshot(phase: ConnectionPhase.idle));
    }
    _stopping = false;
  }

  Future<String> homeDir() async {
    try {
      return await ScpTransfer.homeDir(_requireClient('home'));
    } on ScpException catch (error) {
      throw SshException(error.message);
    }
  }

  Future<List<RemoteEntry>> listRemote([String path = '.']) async {
    try {
      return await ScpTransfer.listEntries(_requireClient('list'), path);
    } on ScpException catch (error) {
      throw SshException(error.message);
    }
  }

  Future<void> uploadFile(String localPath, {String remoteDir = '.'}) async {
    _requireClient('upload');
    final name = localPath.split(Platform.pathSeparator).last;
    if (name.isEmpty) throw SshException('نام فایل نامعتبر است');
    await AppLog.line('SCP upload $name -> $remoteDir');
    try {
      try {
        await _uploadWithSystemScp(localPath, remoteDir);
      } catch (error) {
        await AppLog.line('system scp failed, isolated channel: $error');
        await _uploadWithIsolatedClient(localPath, remoteDir);
      }
      await AppLog.line('SCP upload done $name');
    } on ScpException catch (error) {
      await AppLog.line('SCP upload failed: ${error.message}');
      throw SshException(error.message);
    }
  }

  Future<void> _uploadWithIsolatedClient(String localPath, String remoteDir) async {
    final request = _request;
    if (request == null) throw SshException('ابتدا به یک جلسه SSH متصل شوید');
    final endpoint = parseEndpoint(request.host, request.port);
    final socket = await SSHSocket.connect(endpoint.host, endpoint.port, timeout: const Duration(seconds: 12));
    final identities = await _loadIdentities(request.password);
    final password = request.password;
    final client = SSHClient(
      socket,
      username: request.username.trim(),
      identities: identities.isEmpty ? null : identities,
      onPasswordRequest: password.isEmpty ? null : () => password,
      onUserInfoRequest: password.isEmpty ? null : (info) => List<String>.filled(info.prompts.length, password),
      onVerifyHostKey: (type, fingerprint) => true,
    );
    try {
      await client.authenticated.timeout(const Duration(seconds: 20));
      await ScpTransfer.upload(client: client, localPath: localPath, remoteDir: remoteDir);
    } finally {
      try {
        await client.close();
      } catch (_) {}
    }
  }

  Future<void> _uploadWithSystemScp(String localPath, String remoteDir) async {
    final request = _request;
    if (request == null) throw SshException('ابتدا به یک جلسه SSH متصل شوید');
    final endpoint = parseEndpoint(request.host, request.port);
    final destDir = remoteDir.isEmpty || remoteDir == '.' ? '~/' : (remoteDir.endsWith('/') ? remoteDir : '$remoteDir/');
    final dest = '${request.username.trim()}@${endpoint.host}:${_scpQuote(destDir)}';
    final work = await Directory.systemTemp.createTemp('morixtrem-scp-');
    final askpass = File('${work.path}/askpass');
    await askpass.writeAsString('#!/bin/sh\nprintf %s "\$MORIXTREM_SSH_PASS"\n');
    await Process.run('chmod', ['700', askpass.path]);
    try {
      final environment = Map<String, String>.from(Platform.environment);
      if (request.password.isNotEmpty) {
        environment['MORIXTREM_SSH_PASS'] = request.password;
        environment['SSH_ASKPASS'] = askpass.path;
        environment['SSH_ASKPASS_REQUIRE'] = 'force';
        environment['DISPLAY'] = environment['DISPLAY'] ?? ':0';
      }
      final result = await Process.run(
        'scp',
        [
          '-O',
          '-q',
          '-o', 'StrictHostKeyChecking=no',
          '-o', 'UserKnownHostsFile=/dev/null',
          '-o', 'PreferredAuthentications=${request.password.isEmpty ? 'publickey' : 'password,keyboard-interactive,publickey'}',
          '-P', '${endpoint.port}',
          '--',
          localPath,
          dest,
        ],
        environment: environment,
      );
      if (result.exitCode != 0) {
        final err = '${result.stderr}'.trim();
        throw ScpException(err.isEmpty ? 'ارسال SCP ناموفق بود (کد ${result.exitCode})' : err);
      }
    } finally {
      try {
        await work.delete(recursive: true);
      } catch (_) {}
    }
  }

  static String _scpQuote(String path) => "'${path.replaceAll("'", r"'\''")}'";

  Future<void> copyRemote(List<String> sources, String destDir) async {
    try {
      await ScpTransfer.copyTo(_requireClient('copy'), sources, destDir);
    } on ScpException catch (error) {
      throw SshException(error.message);
    }
  }

  Future<void> moveRemote(List<String> sources, String destDir) async {
    try {
      await ScpTransfer.moveTo(_requireClient('move'), sources, destDir);
    } on ScpException catch (error) {
      throw SshException(error.message);
    }
  }

  SSHClient _requireClient(String action) {
    final client = _client;
    if (client == null || _snapshot.phase != ConnectionPhase.connected) {
      AppLog.line('SCP $action denied phase=${_snapshot.phase} client=${client != null}');
      throw SshException('ابتدا به یک جلسه SSH متصل شوید');
    }
    return client;
  }

  Future<void> dispose() async {
    await disconnect();
    await _out.close();
  }

  void _writeToTerminal(Uint8List data) {
    _terminal?.write(utf8.decode(data, allowMalformed: true));
  }

  Future<void> _closeRemote() async {
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    try {
      _shell?.close();
    } catch (_) {}
    _shell = null;
    try {
      await _client?.close();
    } catch (_) {}
    _client = null;
    _request = null;
  }

  static Future<List<SSHIdentity>> _loadIdentities(String passphrase) async {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return const [];
    final identities = <SSHIdentity>[];
    for (final name in const ['id_ed25519', 'id_rsa', 'id_ecdsa']) {
      final file = File('$home/.ssh/$name');
      if (!file.existsSync()) continue;
      try {
        identities.addAll(SSHKeyPair.fromPem(await file.readAsString()));
      } catch (_) {
        if (passphrase.isEmpty) continue;
        try {
          identities.addAll(SSHKeyPair.fromPem(await file.readAsString(), passphrase));
        } catch (_) {}
      }
    }
    return identities;
  }

  static String _friendlyError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('timeout') || text.contains('timed out')) {
      return 'زمان اتصال SSH تمام شد.';
    }
    if (text.contains('auth') || text.contains('permission denied') || text.contains('password')) {
      return 'ورود SSH ناموفق بود. رمز عبور یا کلید را بررسی کنید.';
    }
    if (text.contains('refused')) {
      return 'سرور اتصال SSH را رد کرد. آدرس و پورت ۲۲ را بررسی کنید.';
    }
    if (text.contains('failed host lookup') || text.contains('name or service')) {
      return 'آدرس سرور SSH پیدا نشد.';
    }
    return 'اتصال SSH برقرار نشد.';
  }

  void _fail(String message) {
    AppLog.line('SSH FAIL: $message');
    _emit(ConnectionSnapshot(
      phase: ConnectionPhase.failed,
      protocol: SessionProtocol.ssh,
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
