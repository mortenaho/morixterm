import 'dart:async';

import 'package:xterm/xterm.dart';

import '../services/rdp_session_service.dart';
import '../services/ssh_session_service.dart';
import 'connection_snapshot.dart';
import 'remote_entry.dart';
import 'saved_session.dart';

class LiveSession {
  LiveSession({required this.id, required this.bookmark})
      : ssh = bookmark.isSsh ? SshSessionService() : null,
        rdp = bookmark.isSsh ? null : RdpSessionService();

  final String id;
  SavedSession bookmark;
  final SshSessionService? ssh;
  final RdpSessionService? rdp;
  StreamSubscription<ConnectionSnapshot>? subscription;
  StreamSubscription<String>? cwdSubscription;
  String explorerPath = '';
  List<RemoteEntry> explorerEntries = const [];
  final Set<String> selectedPaths = {};
  FileClipboard? clipboard;
  bool explorerBusy = false;
  /// Right-hand files panel next to the SSH terminal.
  bool filesSidebarOpen = false;
  /// Width of the SSH files sidebar (user-resizable).
  double filesSidebarWidth = 320;
  /// When true, explorer path tracks the interactive shell PWD.
  bool followTerminalCwd = true;

  bool get isSsh => bookmark.isSsh;
  ConnectionSnapshot get snapshot =>
      ssh?.snapshot ??
      rdp?.snapshot ??
      const ConnectionSnapshot(phase: ConnectionPhase.idle);
  bool get connected => snapshot.phase == ConnectionPhase.connected;
  bool get isActive => snapshot.isActive;
  Terminal? get terminal => ssh?.terminal;

  Future<void> connect({required String username, required String password}) {
    if (isSsh) {
      return ssh!.connect(SshConnectionRequest(
        host: bookmark.host,
        port: bookmark.port,
        username: username,
        password: password,
        title: bookmark.name,
      ));
    }
    return rdp!.connect(RdpConnectionRequest(
      host: bookmark.host,
      port: bookmark.port,
      username: username,
      password: password,
      title: bookmark.name,
    ));
  }

  Future<void> disconnect() async {
    await ssh?.disconnect();
    await rdp?.disconnect();
    filesSidebarOpen = false;
    followTerminalCwd = true;
    explorerPath = '';
    explorerEntries = const [];
    selectedPaths.clear();
    clipboard = null;
  }

  Future<void> dispose() async {
    await subscription?.cancel();
    subscription = null;
    await cwdSubscription?.cancel();
    cwdSubscription = null;
    await ssh?.dispose();
    await rdp?.dispose();
  }
}
