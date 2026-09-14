import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';

import '../models/connection_snapshot.dart';
import '../models/remote_entry.dart';
import '../models/remote_system_stats.dart';
import '../models/saved_session.dart';
import '../models/upload_job.dart';
import 'app_log.dart';
import 'app_version.dart';
import 'scp_transfer.dart';
import 'ssh_welcome_banner.dart';

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
  final _cwdOut = StreamController<String>.broadcast();
  ConnectionSnapshot _snapshot = const ConnectionSnapshot(phase: ConnectionPhase.idle);
  Terminal? _terminal;
  bool _stopping = false;
  String _oscCarry = '';
  String? _shellCwd;
  DateTime _lastShellActivity = DateTime.fromMillisecondsSinceEpoch(0);
  var _statsBusy = false;

  Stream<ConnectionSnapshot> get changes => _out.stream;
  Stream<String> get cwdChanges => _cwdOut.stream;
  ConnectionSnapshot get snapshot => _snapshot;
  Terminal? get terminal => _terminal;
  String? get shellCwd => _shellCwd;
  bool get canTransfer => _client != null && _snapshot.phase == ConnectionPhase.connected;

  void _noteShellActivity() {
    _lastShellActivity = DateTime.now();
  }

  bool get _shellRecentlyActive =>
      DateTime.now().difference(_lastShellActivity) < const Duration(seconds: 2);

  Future<void> connect(SshConnectionRequest request) async {
    final endpoint = parseEndpoint(request.host, request.port);
    if (endpoint.host.isEmpty) {
      throw SshException('Enter a server address');
    }
    if (request.username.trim().isEmpty) {
      throw SshException('Enter a username');
    }

    await disconnect();
    _stopping = false;
    _request = request;
    _terminal = Terminal(maxLines: 2500);
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
        // Do not use printDebug → AppLog here: dartssh2 emits often and
        // flushing disk logs on every packet makes typing feel laggy.
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
      terminal.onOutput = (data) {
        _noteShellActivity();
        final shell = _shell;
        if (shell == null) return;
        shell.write(Uint8List.fromList(utf8.encode(data)));
      };
      terminal.onResize = shell.resizeTerminal;
      _stdoutSub = shell.stdout.listen(_writeToTerminal);
      _stderrSub = shell.stderr.listen(_writeToTerminal);
      // Local welcome art (not sent to the remote shell).
      terminal.write('\x1b[?25h\x1b[?12l');
      terminal.write(sshWelcomeBanner(
        username: request.username.trim(),
        host: endpoint.host,
        port: endpoint.port,
        version: AppVersion.label,
      ));
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
      final message = '${_friendlyError(error)}\n$error\nLog: ${AppLog.lastPath}';
      _fail(message);
      await _closeRemote();
      throw SshException(message);
    }
  }

  Future<void> disconnect() async {
    _stopping = true;
    await _closeRemote();
    _terminal = null;
    _shellCwd = null;
    _oscCarry = '';
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

  Future<void> uploadFile(
    String localPath, {
    String remoteDir = '.',
    UploadJob? job,
  }) async {
    _requireClient('upload');
    final name = localPath.split(Platform.pathSeparator).last;
    if (name.isEmpty) throw SshException('Invalid file name');
    final size = await File(localPath).length();
    await AppLog.line('SCP upload $name (${size}B) -> $remoteDir');
    Object? lastError;
    void report(int sent, {bool indeterminate = false}) {
      job?.report(sent, indeterminate: indeterminate);
    }

    try {
      job?.throwIfCancelled();
      try {
        await _uploadWithSftp(localPath, remoteDir, job: job);
      } catch (error) {
        if (error is UploadCancelledException ||
            error is ScpCancelledException) {
          rethrow;
        }
        lastError = error;
        await AppLog.line('SFTP upload failed, trying system scp: $error');
        job?.throwIfCancelled();
        try {
          await _uploadWithSystemScp(localPath, remoteDir, job: job);
        } catch (error2) {
          if (error2 is UploadCancelledException ||
              error2 is ScpCancelledException) {
            rethrow;
          }
          lastError = error2;
          await AppLog.line('system scp failed, dartscp fallback: $error2');
          job?.throwIfCancelled();
          await _uploadWithIsolatedClient(localPath, remoteDir, job: job);
        }
      }
      report(size);
      await AppLog.line('SCP upload done $name');
    } on UploadCancelledException {
      await AppLog.line('SCP upload cancelled $name');
      rethrow;
    } on ScpCancelledException {
      await AppLog.line('SCP upload cancelled $name');
      throw UploadCancelledException();
    } on ScpException catch (error) {
      await AppLog.line('SCP upload failed: ${error.message}');
      throw SshException(error.message);
    } catch (error) {
      final message = error is SshException
          ? error.message
          : '${lastError ?? error}';
      await AppLog.line('SCP upload failed: $message');
      throw SshException(message);
    } finally {
      job?.clearCancel();
    }
  }

  Future<void> downloadFile(
    String remotePath,
    String localPath, {
    UploadJob? job,
  }) async {
    _requireClient('download');
    final name = remotePath.split('/').where((part) => part.isNotEmpty).last;
    if (name.isEmpty) throw SshException('Invalid remote path');
    await AppLog.line('SCP download $remotePath -> $localPath');
    Object? lastError;
    void report(int received, {bool indeterminate = false}) {
      job?.report(received, indeterminate: indeterminate);
    }

    try {
      job?.throwIfCancelled();
      try {
        await _downloadWithSftp(remotePath, localPath, job: job);
      } catch (error) {
        if (error is UploadCancelledException ||
            error is ScpCancelledException) {
          rethrow;
        }
        lastError = error;
        await AppLog.line('SFTP download failed, trying system scp: $error');
        job?.throwIfCancelled();
        try {
          await _downloadWithSystemScp(remotePath, localPath, job: job);
        } catch (error2) {
          if (error2 is UploadCancelledException ||
              error2 is ScpCancelledException) {
            rethrow;
          }
          lastError = error2;
          await AppLog.line('system scp failed, dartscp fallback: $error2');
          job?.throwIfCancelled();
          await _downloadWithIsolatedClient(remotePath, localPath, job: job);
        }
      }
      if (job != null && job.totalBytes > 0) {
        report(job.totalBytes);
      }
      await AppLog.line('SCP download done $name');
    } on UploadCancelledException {
      await AppLog.line('SCP download cancelled $name');
      await _deletePartialDownload(localPath);
      rethrow;
    } on ScpCancelledException {
      await AppLog.line('SCP download cancelled $name');
      await _deletePartialDownload(localPath);
      throw UploadCancelledException();
    } on ScpException catch (error) {
      await AppLog.line('SCP download failed: ${error.message}');
      await _deletePartialDownload(localPath);
      throw SshException(error.message);
    } catch (error) {
      final message = error is SshException
          ? error.message
          : '${lastError ?? error}';
      await AppLog.line('SCP download failed: $message');
      await _deletePartialDownload(localPath);
      throw SshException(message);
    } finally {
      job?.clearCancel();
    }
  }

  Future<void> _deletePartialDownload(String localPath) async {
    try {
      final file = File(localPath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<SSHClient> _openTransferClient() async {
    final request = _request;
    if (request == null) throw SshException('Connect to an SSH session first');
    final endpoint = parseEndpoint(request.host, request.port);
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
      onVerifyHostKey: (type, fingerprint) => true,
      keepAliveInterval: const Duration(seconds: 15),
      handshakeTimeout: const Duration(seconds: 15),
      authTimeout: const Duration(seconds: 15),
    );
    await client.authenticated.timeout(const Duration(seconds: 20));
    return client;
  }

  Future<void> _uploadWithSftp(
    String localPath,
    String remoteDir, {
    UploadJob? job,
  }) async {
    final name = localPath.split(Platform.pathSeparator).last;
    final remotePath = _joinRemotePath(remoteDir, name);
    final size = await File(localPath).length();
    final client = await _openTransferClient();
    SftpClient? sftp;
    SftpFileWriter? writer;
    try {
      job?.bindCancel(() {
        final active = writer;
        if (active != null) {
          unawaited(active.abort());
        }
        unawaited(client.close());
      });
      job?.throwIfCancelled();
      sftp = await client.sftp();
      final remote = await sftp.open(
        remotePath,
        mode: SftpFileOpenMode.create |
            SftpFileOpenMode.truncate |
            SftpFileOpenMode.write,
      );
      try {
        job?.throwIfCancelled();
        writer = remote.write(
          File(localPath).openRead().map(Uint8List.fromList),
          onProgress: (sent) {
            job?.report(sent.clamp(0, size));
          },
        );
        await writer.done;
        if (job?.cancelling == true) {
          throw UploadCancelledException();
        }
      } catch (error) {
        if (job?.cancelling == true || error is UploadCancelledException) {
          throw UploadCancelledException();
        }
        rethrow;
      } finally {
        await remote.close();
      }
    } finally {
      job?.clearCancel();
      try {
        await sftp?.close();
      } catch (_) {}
      try {
        await client.close();
      } catch (_) {}
    }
  }

  Future<void> _uploadWithIsolatedClient(
    String localPath,
    String remoteDir, {
    UploadJob? job,
  }) async {
    final client = await _openTransferClient();
    try {
      job?.bindCancel(() {
        try {
          client.close();
        } catch (_) {}
      });
      job?.throwIfCancelled();
      await ScpTransfer.upload(
        client: client,
        localPath: localPath,
        remoteDir: remoteDir,
        onProgress: (sent, total) => job?.report(sent),
        isCancelled: () => job?.cancelling == true,
      );
    } on ScpCancelledException {
      throw UploadCancelledException();
    } finally {
      job?.clearCancel();
      try {
        await client.close();
      } catch (_) {}
    }
  }

  Future<void> _uploadWithSystemScp(
    String localPath,
    String remoteDir, {
    UploadJob? job,
  }) async {
    final request = _request;
    if (request == null) throw SshException('Connect to an SSH session first');
    final endpoint = parseEndpoint(request.host, request.port);
    // Do not shell-quote the remote path — OpenSSH scp sends it as an SCP
    // protocol argument; extra quotes become part of the filename.
    final destDir = remoteDir.isEmpty || remoteDir == '.'
        ? '.'
        : (remoteDir.endsWith('/')
            ? remoteDir.substring(0, remoteDir.length - 1)
            : remoteDir);
    final dest = '${request.username.trim()}@${endpoint.host}:$destDir';
    final work = await Directory.systemTemp.createTemp('morixterm-scp-');
    final askpass = File('${work.path}/askpass');
    await askpass.writeAsString(
        '#!/bin/sh\nprintf %s "\$MORIXTERM_SSH_PASS"\n');
    await Process.run('chmod', ['700', askpass.path]);
    Process? process;
    try {
      final environment = Map<String, String>.from(Platform.environment);
      if (request.password.isNotEmpty) {
        environment['MORIXTERM_SSH_PASS'] = request.password;
        environment['SSH_ASKPASS'] = askpass.path;
        environment['SSH_ASKPASS_REQUIRE'] = 'force';
        environment['DISPLAY'] = environment['DISPLAY'] ?? ':0';
      }
      final size = await File(localPath).length();
      // Allow roughly 1 minute per 8 MiB, with a floor/ceiling.
      final timeoutSec =
          (60 + (size ~/ (8 * 1024 * 1024)) * 60).clamp(90, 3600);
      job?.report(0, indeterminate: true);
      job?.throwIfCancelled();
      process = await Process.start(
        'scp',
        [
          '-O',
          '-q',
          '-o',
          'StrictHostKeyChecking=no',
          '-o',
          'UserKnownHostsFile=/dev/null',
          '-o',
          'ConnectTimeout=20',
          '-o',
          'ServerAliveInterval=15',
          '-o',
          'ServerAliveCountMax=4',
          '-o',
          'PreferredAuthentications=${request.password.isEmpty ? 'publickey' : 'password,keyboard-interactive,publickey'}',
          '-P',
          '${endpoint.port}',
          '--',
          localPath,
          dest,
        ],
        environment: environment,
      );
      job?.bindCancel(() {
        try {
          process?.kill(ProcessSignal.sigterm);
        } catch (_) {}
      });
      final stderrBuf = StringBuffer();
      final stderrSub = process.stderr
          .transform(utf8.decoder)
          .listen((chunk) => stderrBuf.write(chunk));
      final exitCode = await process.exitCode.timeout(
        Duration(seconds: timeoutSec),
        onTimeout: () {
          try {
            process?.kill(ProcessSignal.sigkill);
          } catch (_) {}
          throw ScpException('SCP upload timed out');
        },
      );
      await stderrSub.cancel();
      if (job?.cancelling == true) {
        throw UploadCancelledException();
      }
      if (exitCode != 0) {
        final err = stderrBuf.toString().trim();
        throw ScpException(
            err.isEmpty ? 'SCP upload failed (exit $exitCode)' : err);
      }
      job?.report(size, indeterminate: false);
    } finally {
      job?.clearCancel();
      try {
        await work.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> _downloadWithSftp(
    String remotePath,
    String localPath, {
    UploadJob? job,
  }) async {
    final client = await _openTransferClient();
    SftpClient? sftp;
    IOSink? sink;
    var created = false;
    try {
      job?.bindCancel(() {
        unawaited(client.close());
        unawaited(sink?.close());
      });
      job?.throwIfCancelled();
      sftp = await client.sftp();
      final remote = await sftp.open(
        remotePath,
        mode: SftpFileOpenMode.read,
      );
      try {
        job?.throwIfCancelled();
        final attrs = await remote.stat();
        final size = attrs.size ?? 0;
        if (size > 0) {
          job?.setTotal(size);
          job?.indeterminate = false;
        } else {
          job?.report(0, indeterminate: true);
        }
        final out = File(localPath);
        await out.parent.create(recursive: true);
        sink = out.openWrite();
        created = true;
        var received = 0;
        await for (final chunk in remote.read(
          length: size > 0 ? size : null,
          onProgress: (bytesRead) {
            if (size > 0) {
              job?.report(bytesRead.clamp(0, size));
            } else {
              job?.report(bytesRead, indeterminate: true);
            }
          },
        )) {
          job?.throwIfCancelled();
          sink.add(chunk);
          received += chunk.length;
          if (size <= 0) {
            job?.report(received, indeterminate: true);
          }
        }
        await sink.flush();
        await sink.close();
        sink = null;
        if (size > 0) {
          job?.report(size);
        } else {
          job?.setTotal(received);
          job?.report(received, indeterminate: false);
        }
        if (job?.cancelling == true) {
          throw UploadCancelledException();
        }
      } catch (error) {
        if (job?.cancelling == true || error is UploadCancelledException) {
          throw UploadCancelledException();
        }
        rethrow;
      } finally {
        await remote.close();
      }
    } finally {
      job?.clearCancel();
      try {
        await sink?.close();
      } catch (_) {}
      if (created && job?.cancelling == true) {
        await _deletePartialDownload(localPath);
      }
      try {
        await sftp?.close();
      } catch (_) {}
      try {
        await client.close();
      } catch (_) {}
    }
  }

  Future<void> _downloadWithIsolatedClient(
    String remotePath,
    String localPath, {
    UploadJob? job,
  }) async {
    final client = await _openTransferClient();
    try {
      job?.bindCancel(() {
        try {
          client.close();
        } catch (_) {}
      });
      job?.throwIfCancelled();
      await ScpTransfer.download(
        client: client,
        remotePath: remotePath,
        localPath: localPath,
        onProgress: (received, total) {
          if (total > 0) {
            job?.setTotal(total);
            job?.report(received, indeterminate: false);
          } else {
            job?.report(received, indeterminate: true);
          }
        },
        isCancelled: () => job?.cancelling == true,
      );
    } on ScpCancelledException {
      throw UploadCancelledException();
    } finally {
      job?.clearCancel();
      try {
        await client.close();
      } catch (_) {}
    }
  }

  Future<void> _downloadWithSystemScp(
    String remotePath,
    String localPath, {
    UploadJob? job,
  }) async {
    final request = _request;
    if (request == null) throw SshException('Connect to an SSH session first');
    final endpoint = parseEndpoint(request.host, request.port);
    final source = '${request.username.trim()}@${endpoint.host}:$remotePath';
    final work = await Directory.systemTemp.createTemp('morixterm-scp-dl-');
    final askpass = File('${work.path}/askpass');
    await askpass.writeAsString(
        '#!/bin/sh\nprintf %s "\$MORIXTERM_SSH_PASS"\n');
    await Process.run('chmod', ['700', askpass.path]);
    Process? process;
    try {
      final environment = Map<String, String>.from(Platform.environment);
      if (request.password.isNotEmpty) {
        environment['MORIXTERM_SSH_PASS'] = request.password;
        environment['SSH_ASKPASS'] = askpass.path;
        environment['SSH_ASKPASS_REQUIRE'] = 'force';
        environment['DISPLAY'] = environment['DISPLAY'] ?? ':0';
      }
      final knownTotal = job?.totalBytes ?? 0;
      final timeoutSec =
          (60 + (knownTotal ~/ (8 * 1024 * 1024)) * 60).clamp(90, 3600);
      job?.report(0, indeterminate: true);
      job?.throwIfCancelled();
      await File(localPath).parent.create(recursive: true);
      process = await Process.start(
        'scp',
        [
          '-O',
          '-q',
          '-o',
          'StrictHostKeyChecking=no',
          '-o',
          'UserKnownHostsFile=/dev/null',
          '-o',
          'ConnectTimeout=20',
          '-o',
          'ServerAliveInterval=15',
          '-o',
          'ServerAliveCountMax=4',
          '-o',
          'PreferredAuthentications=${request.password.isEmpty ? 'publickey' : 'password,keyboard-interactive,publickey'}',
          '-P',
          '${endpoint.port}',
          '--',
          source,
          localPath,
        ],
        environment: environment,
      );
      job?.bindCancel(() {
        try {
          process?.kill(ProcessSignal.sigterm);
        } catch (_) {}
      });
      final stderrBuf = StringBuffer();
      final stderrSub = process.stderr
          .transform(utf8.decoder)
          .listen((chunk) => stderrBuf.write(chunk));
      final exitCode = await process.exitCode.timeout(
        Duration(seconds: timeoutSec),
        onTimeout: () {
          try {
            process?.kill(ProcessSignal.sigkill);
          } catch (_) {}
          throw ScpException('SCP download timed out');
        },
      );
      await stderrSub.cancel();
      if (job?.cancelling == true) {
        throw UploadCancelledException();
      }
      if (exitCode != 0) {
        final err = stderrBuf.toString().trim();
        throw ScpException(
            err.isEmpty ? 'SCP download failed (exit $exitCode)' : err);
      }
      final size = await File(localPath).length();
      job?.setTotal(size);
      job?.report(size, indeterminate: false);
    } finally {
      job?.clearCancel();
      try {
        await work.delete(recursive: true);
      } catch (_) {}
    }
  }

  static String _joinRemotePath(String dir, String name) {
    if (dir.isEmpty || dir == '.') return name;
    if (dir.endsWith('/')) return '$dir$name';
    return '$dir/$name';
  }

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

  Future<void> mkdirRemote(String parentDir, String name) async {
    try {
      await ScpTransfer.mkdir(_requireClient('mkdir'), parentDir, name);
    } on ScpException catch (error) {
      throw SshException(error.message);
    }
  }

  Future<void> renameRemote(String path, String newName) async {
    try {
      await ScpTransfer.rename(_requireClient('rename'), path, newName);
    } on ScpException catch (error) {
      throw SshException(error.message);
    }
  }

  Future<String> remoteMode(String path) async {
    try {
      return await ScpTransfer.fileMode(_requireClient('mode'), path);
    } on ScpException catch (error) {
      throw SshException(error.message);
    }
  }

  Future<void> chmodRemote(List<String> paths, {required String mode, bool recursive = false}) async {
    try {
      await ScpTransfer.chmod(_requireClient('chmod'), paths, mode: mode, recursive: recursive);
    } on ScpException catch (error) {
      throw SshException(error.message);
    }
  }

  Future<RemoteSystemStats> fetchSystemStats() async {
    // Skip while the user is actively typing/receiving shell data — exec on
    // the shared SSH client otherwise stalls interactive input.
    if (_statsBusy || _shellRecentlyActive) {
      throw SshException('Monitor deferred while shell is active');
    }
    final client = _requireClient('monitor');
    _statsBusy = true;
    try {
      // Lightweight remote snapshot — one round-trip, no interactive shell use.
      const command = r'''
awk '/^cpu /{idle=$5+$6; total=$2+$3+$4+$5+$6+$7+$8+$9+$10+$11; print "CPU",total-idle,total}' /proc/stat
awk '/MemTotal:/{t=$2} /MemAvailable:/{a=$2} /MemFree:/{f=$2} END{avail=(a>0?a:f); print "MEM",t+0,avail+0}' /proc/meminfo
df -Pk / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print "DISK",$2+0,$3+0,$5+0,$6}'
''';
      final result = await client.runWithResult(command);
      final text = utf8.decode(result.stdout, allowMalformed: true);
      return _parseSystemStats(text);
    } finally {
      _statsBusy = false;
    }
  }

  static RemoteSystemStats _parseSystemStats(String text) {
    int? cpuUsed;
    int? cpuTotal;
    int? memTotal;
    int? memAvailable;
    int? diskTotal;
    int? diskUsed;
    var diskMount = '/';

    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.isEmpty) continue;
      switch (parts.first) {
        case 'CPU':
          if (parts.length >= 3) {
            cpuUsed = int.tryParse(parts[1]);
            cpuTotal = int.tryParse(parts[2]);
          }
        case 'MEM':
          if (parts.length >= 3) {
            memTotal = int.tryParse(parts[1]);
            memAvailable = int.tryParse(parts[2]);
          }
        case 'DISK':
          if (parts.length >= 4) {
            diskTotal = int.tryParse(parts[1]);
            diskUsed = int.tryParse(parts[2]);
            if (parts.length >= 5) diskMount = parts[4];
          }
      }
    }

    if (cpuUsed == null ||
        cpuTotal == null ||
        memTotal == null ||
        memAvailable == null ||
        diskTotal == null ||
        diskUsed == null) {
      throw SshException('Could not read remote system stats');
    }

    return RemoteSystemStats(
      cpuUsedTicks: cpuUsed,
      cpuTotalTicks: cpuTotal,
      memTotalKb: memTotal,
      memAvailableKb: memAvailable,
      diskTotalKb: diskTotal,
      diskUsedKb: diskUsed,
      diskMount: diskMount,
    );
  }

  SSHClient _requireClient(String action) {
    final client = _client;
    if (client == null || _snapshot.phase != ConnectionPhase.connected) {
      AppLog.line('SCP $action denied phase=${_snapshot.phase} client=${client != null}');
      throw SshException('Connect to an SSH session first');
    }
    return client;
  }

  Future<void> dispose() async {
    await disconnect();
    await _out.close();
    await _cwdOut.close();
  }

  void _writeToTerminal(Uint8List data) {
    _noteShellActivity();
    final text = utf8.decode(data, allowMalformed: true);
    if (text.isEmpty) return;
    // Fast path: no OSC cwd sequences in this chunk.
    if (_oscCarry.isEmpty && !text.contains('\x1b]777;cwd;')) {
      _terminal?.write(text);
      return;
    }
    final filtered = _consumeOscCwd(_oscCarry + text);
    if (filtered.isNotEmpty) {
      _terminal?.write(filtered);
    }
  }

  String _consumeOscCwd(String input) {
    final out = StringBuffer();
    var i = 0;
    while (i < input.length) {
      final esc = input.indexOf('\x1b]777;cwd;', i);
      if (esc < 0) {
        out.write(input.substring(i));
        break;
      }
      out.write(input.substring(i, esc));
      final pathStart = esc + '\x1b]777;cwd;'.length;
      final bel = input.indexOf('\x07', pathStart);
      final st = input.indexOf('\x1b\\', pathStart);
      int end;
      int next;
      if (bel >= 0 && (st < 0 || bel < st)) {
        end = bel;
        next = bel + 1;
      } else if (st >= 0) {
        end = st;
        next = st + 2;
      } else {
        // Incomplete OSC — keep for the next chunk.
        _oscCarry = input.substring(esc);
        return out.toString();
      }
      final path = input.substring(pathStart, end).trim();
      if (path.isNotEmpty && path != _shellCwd) {
        _shellCwd = path;
        if (!_cwdOut.isClosed) _cwdOut.add(path);
      }
      i = next;
    }
    _oscCarry = '';
    return out.toString();
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
      return 'SSH connection timed out.';
    }
    if (text.contains('auth') || text.contains('permission denied') || text.contains('password')) {
      return 'SSH authentication failed. Check password or key.';
    }
    if (text.contains('refused')) {
      return 'SSH connection refused. Check host and port.';
    }
    if (text.contains('failed host lookup') || text.contains('name or service')) {
      return 'SSH host could not be resolved.';
    }
    return 'SSH connection failed.';
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
