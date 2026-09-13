import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import 'models/connection_snapshot.dart';
import 'models/live_session.dart';
import 'models/remote_entry.dart';
import 'models/remote_system_stats.dart';
import 'models/saved_session.dart';
import 'models/upload_job.dart';
import 'services/app_log.dart';
import 'services/rdp_session_service.dart';
import 'services/session_storage.dart';
import 'services/ssh_session_service.dart';
import 'widgets/morixtrem_logo.dart';
import 'widgets/ssh_terminal_pane.dart';
import 'widgets/welcome_pane.dart';

class Moba {
  static const bg = Color(0xFF2B2B2B);
  static const panel = Color(0xFF1E1E1E);
  static const sidebar = Color(0xFF252526);
  static const toolbar = Color(0xFF323232);
  static const menu = Color(0xFF3C3C3C);
  static const green = Color(0xFF3D9970);
  static const terminal = Color(0xFF0C0C0C);
  static const ssh = Color(0xFFE6B422);
  static const rdp = Color(0xFF5B9BD5);
  static const status = Color(0xFF1B7A5A);
  static const toastSuccess = Color(0xFF1F4D3A);
  static const toastError = Color(0xFF5A2222);
  static const toastWarning = Color(0xFF5A4520);
  static const toastInfo = Color(0xFF2A3B4D);
  static const toastSuccessAccent = Color(0xFF4CAF7A);
  static const toastErrorAccent = Color(0xFFFF6B6B);
  static const toastWarningAccent = Color(0xFFE6B422);
  static const toastInfoAccent = Color(0xFF5B9BD5);
}

enum ToastKind { info, success, warning, error }

void showAppToast(
  BuildContext context,
  String message, {
  ToastKind kind = ToastKind.info,
}) {
  final (bg, accent, icon) = switch (kind) {
    ToastKind.success => (
        Moba.toastSuccess,
        Moba.toastSuccessAccent,
        Icons.check_circle_rounded
      ),
    ToastKind.error => (
        Moba.toastError,
        Moba.toastErrorAccent,
        Icons.error_rounded
      ),
    ToastKind.warning => (
        Moba.toastWarning,
        Moba.toastWarningAccent,
        Icons.warning_amber_rounded
      ),
    ToastKind.info => (
        Moba.toastInfo,
        Moba.toastInfoAccent,
        Icons.info_rounded
      ),
  };

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: EdgeInsets.zero,
        duration: Duration(
          milliseconds: kind == ToastKind.error ? 4500 : 3200,
        ),
        content: Material(
          color: bg,
          elevation: 6,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(10),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                    child: Icon(icon, size: 20, color: accent),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 8, 12),
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        ScaffoldMessenger.of(context).hideCurrentSnackBar(),
                    icon: const Icon(Icons.close, size: 16),
                    color: Colors.white54,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Dismiss',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    AppLog.line('FLUTTER ERROR: ${details.exceptionAsString()}');
    AppLog.line('${details.stack}');
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.line('UNHANDLED: $error');
    AppLog.line('$stack');
    return true;
  };
  runApp(const MorixtermApp());
}

class MorixtermApp extends StatelessWidget {
  const MorixtermApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MoriXterm',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Moba.bg,
        colorScheme: const ColorScheme.dark(
          primary: Moba.green,
          surface: Moba.panel,
        ),
        fontFamily: 'Segoe UI',
        useMaterial3: false,
        textButtonTheme: const TextButtonThemeData(
            style: ButtonStyle(mouseCursor: WidgetStateMouseCursor.clickable)),
        filledButtonTheme: const FilledButtonThemeData(
            style: ButtonStyle(mouseCursor: WidgetStateMouseCursor.clickable)),
        elevatedButtonTheme: const ElevatedButtonThemeData(
            style: ButtonStyle(mouseCursor: WidgetStateMouseCursor.clickable)),
        outlinedButtonTheme: const OutlinedButtonThemeData(
            style: ButtonStyle(mouseCursor: WidgetStateMouseCursor.clickable)),
        iconButtonTheme: const IconButtonThemeData(
            style: ButtonStyle(mouseCursor: WidgetStateMouseCursor.clickable)),
        checkboxTheme: const CheckboxThemeData(
            mouseCursor: WidgetStateMouseCursor.clickable),
        segmentedButtonTheme: const SegmentedButtonThemeData(
            style: ButtonStyle(mouseCursor: WidgetStateMouseCursor.clickable)),
        popupMenuTheme: PopupMenuThemeData(
          color: Moba.menu,
          surfaceTintColor: Colors.transparent,
          elevation: 12,
          shadowColor: Colors.black87,
          textStyle: const TextStyle(color: Colors.white, fontSize: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFF4A4A4A)),
          ),
        ),
      ),
      home: const WorkspacePage(),
    );
  }
}

enum _Pane { home, session, files }

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({super.key});

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  _Pane pane = _Pane.home;
  int _liveSeq = 0;
  String? focusedId;
  final List<LiveSession> openSessions = [];
  final Set<String> _connectingSessionKeys = <String>{};
  final SessionStorage sessionStorage = SessionStorage();
  Set<String> folders = <String>{};
  final Set<String> collapsedFolders = <String>{};
  List<SavedSession> sessions = const [
    SavedSession(
        name: 'Windows Server',
        host: '192.168.1.10',
        port: 3389,
        username: 'مدیر'),
    SavedSession(
        name: 'Linux SSH',
        host: '192.168.1.20',
        port: 22,
        username: 'root',
        protocol: SessionProtocol.ssh),
  ];

  LiveSession? get focused {
    for (final item in openSessions) {
      if (item.id == focusedId) return item;
    }
    return openSessions.isEmpty ? null : openSessions.last;
  }

  ConnectionSnapshot get snapshot =>
      focused?.snapshot ??
      const ConnectionSnapshot(phase: ConnectionPhase.idle);
  bool get hasLiveSession => openSessions.any((item) => item.connected);
  bool get sshConnected => focused?.isSsh == true && focused!.connected;
  bool get rdpConnected =>
      focused != null && !focused!.isSsh && focused!.connected;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  @override
  void dispose() {
    for (final live in openSessions) {
      live.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSessions() async {
    final stored = await sessionStorage.load();
    final storedFolders = await sessionStorage.loadFolders();
    if (!mounted) return;
    setState(() {
      if (stored.isNotEmpty) sessions = stored;
      folders = storedFolders.toSet();
      folders.addAll(
          sessions.map((session) => session.folder).whereType<String>());
    });
  }

  Future<void> _deleteSession(int index) async {
    final updated = [...sessions]..removeAt(index);
    setState(() => sessions = updated);
    await sessionStorage.saveAll(updated);
    showMessage('Session deleted', kind: ToastKind.success);
  }

  void showMessage(String message, {ToastKind kind = ToastKind.info}) {
    showAppToast(context, message, kind: kind);
  }

  Future<void> _replaceSession(
      SavedSession original, SavedSession updated) async {
    final index = sessions.indexWhere((item) => item.sameBookmark(original));
    final next = [...sessions];
    if (index >= 0) {
      next[index] = updated;
    } else {
      next.add(updated);
    }
    setState(() {
      sessions = next;
      for (final live in openSessions) {
        if (live.bookmark.sameBookmark(original)) live.bookmark = updated;
      }
    });
    await sessionStorage.saveAll(next);
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New session folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Folder name'),
          onSubmitted: (_) => Navigator.pop(context, controller.text),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Create')),
        ],
      ),
    );
    controller.dispose();
    final value = name?.trim() ?? '';
    if (value.isEmpty || !mounted) return;
    if (folders.contains(value)) {
      showMessage('A folder with this name already exists',
          kind: ToastKind.warning);
      return;
    }
    final previous = folders;
    setState(() => folders = {...folders, value});
    try {
      await sessionStorage.saveFolders(folders);
      if (mounted) {
        showMessage('Folder created — drag a session onto it',
            kind: ToastKind.success);
      }
    } catch (error) {
      if (mounted) {
        setState(() => folders = previous);
        showMessage('Could not create folder: $error', kind: ToastKind.error);
      }
    }
  }

  Future<void> _moveSessionToFolder(
      SavedSession session, String? folder) async {
    final index = sessions.indexWhere((item) => item.sameBookmark(session));
    if (index < 0 || sessions[index].folder == folder) return;
    final previous = sessions;
    final updated = [...sessions];
    updated[index] = session.copyWith(folder: folder);
    setState(() => sessions = updated);
    try {
      await sessionStorage.saveAll(updated);
      if (mounted) {
        showMessage(
            folder == null
                ? 'Session moved to No folder'
                : 'Session moved to “$folder”',
            kind: ToastKind.success);
      }
    } catch (error) {
      if (mounted) {
        setState(() => sessions = previous);
        showMessage('Could not move session: $error', kind: ToastKind.error);
      }
    }
  }

  void _toggleFolder(String folder) {
    setState(() {
      if (!collapsedFolders.remove(folder)) collapsedFolders.add(folder);
    });
  }

  Future<void> _renameFolder(String folder) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _NamePromptDialog(
        title: 'Rename folder',
        label: 'Folder name',
        confirmLabel: 'Rename',
        initialValue: folder,
      ),
    );
    final value = name?.trim() ?? '';
    if (value.isEmpty || !mounted) return;
    if (value == folder) return;
    if (folders.contains(value)) {
      showMessage('A folder with this name already exists',
          kind: ToastKind.warning);
      return;
    }

    final previousFolders = folders;
    final previousSessions = sessions;
    final previousCollapsed = {...collapsedFolders};
    final updatedSessions = sessions
        .map((session) =>
            session.folder == folder ? session.copyWith(folder: value) : session)
        .toList();
    final nextFolders = {...folders}
      ..remove(folder)
      ..add(value);
    setState(() {
      folders = nextFolders;
      sessions = updatedSessions;
      if (collapsedFolders.remove(folder)) collapsedFolders.add(value);
    });
    try {
      await sessionStorage.saveAll(updatedSessions);
      await sessionStorage.saveFolders(folders);
      if (mounted) showMessage('Folder renamed to $value', kind: ToastKind.success);
    } catch (error) {
      if (mounted) {
        setState(() {
          folders = previousFolders;
          sessions = previousSessions;
          collapsedFolders
            ..clear()
            ..addAll(previousCollapsed);
        });
        showMessage('Could not rename folder: $error', kind: ToastKind.error);
      }
    }
  }

  Future<void> _deleteFolder(String folder) async {
    final count = sessions.where((session) => session.folder == folder).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete folder?'),
        content: Text(
          count == 0
              ? 'Delete folder "$folder"? This cannot be undone.'
              : 'Delete folder "$folder"?\n$count session(s) inside will move to "No folder".',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB91C1C)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final updatedSessions = sessions
        .map((session) =>
            session.folder == folder ? session.copyWith(folder: null) : session)
        .toList();
    setState(() {
      folders = {...folders}..remove(folder);
      sessions = updatedSessions;
    });
    await sessionStorage.saveAll(updatedSessions);
    await sessionStorage.saveFolders(folders);
    if (mounted) {
      showMessage(
          count == 0
              ? 'Folder deleted'
              : 'Folder deleted. Sessions moved to No folder.',
          kind: ToastKind.success);
    }
  }

  void _watchLive(LiveSession live) {
    final changes = live.ssh?.changes ?? live.rdp?.changes;
    live.subscription = changes?.listen((snapshot) {
      if (!mounted) return;
      setState(() {});
      if (live.isSsh &&
          snapshot.phase == ConnectionPhase.connected &&
          !live.filesSidebarOpen) {
        unawaited(_openSshFilesSidebar(live));
      }
    });
    live.cwdSubscription?.cancel();
    live.cwdSubscription = live.ssh?.cwdChanges.listen((path) {
      if (!mounted || !live.followTerminalCwd) return;
      if (path == live.explorerPath) return;
      live.explorerPath = path;
      live.selectedPaths.clear();
      setState(() {});
      unawaited(_refreshFiles(live));
    });
  }

  Future<void> _openSshFilesSidebar(LiveSession live) async {
    if (!live.isSsh || !live.connected) return;
    live.filesSidebarOpen = true;
    live.followTerminalCwd = true;
    if (!mounted) return;
    setState(() {});
    final cwd = live.ssh?.shellCwd;
    if (cwd != null && cwd.isNotEmpty) {
      live.explorerPath = cwd;
    } else if (live.explorerPath.isEmpty) {
      try {
        live.explorerPath = await live.ssh!.homeDir();
      } catch (error) {
        if (mounted) showMessage('Could not open home folder: $error', kind: ToastKind.error);
        return;
      }
    }
    if (!mounted) return;
    setState(() {});
    await _refreshFiles(live);
  }

  void _toggleFilesSidebar(LiveSession live) {
    if (!live.isSsh) return;
    if (live.filesSidebarOpen) {
      setState(() => live.filesSidebarOpen = false);
      return;
    }
    unawaited(_openSshFilesSidebar(live));
  }

  void _syncExplorerToTerminal(LiveSession live) {
    final cwd = live.ssh?.shellCwd;
    setState(() {
      live.followTerminalCwd = true;
      if (cwd != null && cwd.isNotEmpty) {
        live.explorerPath = cwd;
        live.selectedPaths.clear();
      }
    });
    unawaited(_refreshFiles(live));
  }

  LiveSession _createLive(SavedSession bookmark) {
    final live = LiveSession(id: 'live-${++_liveSeq}', bookmark: bookmark);
    _watchLive(live);
    openSessions.add(live);
    focusedId = live.id;
    pane = _Pane.session;
    return live;
  }

  String _sessionKey(SavedSession session) =>
      '${session.protocol.name}|${session.name}|${session.host}|${session.port}|${session.username}';

  Future<void> _connectSession(SavedSession session,
      {String? password, bool prompt = false}) async {
    final already = openSessions
        .where((item) => item.bookmark.sameBookmark(session))
        .toList();
    if (already.isNotEmpty && already.first.connected && !prompt) {
      setState(() {
        focusedId = already.first.id;
        pane = _Pane.session;
      });
      return;
    }

    final key = _sessionKey(session);
    if (!_connectingSessionKeys.add(key)) return;

    try {
      var username = session.username;
      var secret = password;
      var savePassword = session.hasSavedPassword;

      if (secret == null) {
        if (!prompt && session.hasSavedPassword) {
          secret = session.password;
        } else {
          final credentials = await _promptCredentials(session);
          if (credentials == null || !mounted) return;
          username = credentials.username;
          secret = credentials.password;
          savePassword = credentials.savePassword;
        }
      }

      final usedPassword = secret;
      final connecting = session.copyWith(
        username: username,
        password: savePassword ? usedPassword : '',
      );
      await _replaceSession(session, connecting);

      var live = already.isEmpty ? null : already.first;
      setState(() {
        if (live == null) {
          live = _createLive(connecting);
        } else {
          live!.bookmark = connecting;
          focusedId = live!.id;
          pane = _Pane.session;
        }
      });
      try {
        await live!.connect(username: username, password: usedPassword);
        if (mounted && live!.isSsh && live!.connected) {
          await _openSshFilesSidebar(live!);
        }
      } on RdpException catch (error) {
        if (mounted) showMessage(error.message, kind: ToastKind.error);
      } on SshException catch (error) {
        if (mounted) showMessage(error.message, kind: ToastKind.error);
      } catch (error) {
        if (mounted) showMessage('Connection failed: $error', kind: ToastKind.error);
      }
    } finally {
      _connectingSessionKeys.remove(key);
    }
  }

  Future<({String username, String password, bool savePassword})?>
      _promptCredentials(SavedSession session) {
    return showDialog<({String username, String password, bool savePassword})>(
      context: context,
      builder: (context) => _CredentialsDialog(session: session),
    );
  }

  Future<void> _closeLive(LiveSession live) async {
    await live.disconnect();
    await live.dispose();
    if (!mounted) return;
    setState(() {
      openSessions.removeWhere((item) => item.id == live.id);
      if (focusedId == live.id) {
        focusedId = openSessions.isEmpty ? null : openSessions.last.id;
        if (openSessions.isEmpty) pane = _Pane.home;
      }
    });
  }

  Future<void> _disconnect() async {
    final live = focused;
    if (live == null) return;
    await _closeLive(live);
    if (mounted) showMessage('Disconnected', kind: ToastKind.info);
  }

  Future<void> _openFilesPane() async {
    final live = focused;
    await AppLog.line(
        'files pane focused=${live?.bookmark.name} ssh=$sshConnected rdp=$rdpConnected');
    if (live == null || !live.connected) {
      showMessage('Connect an SSH or RDP session first, then open Files',
          kind: ToastKind.warning);
      return;
    }
    if (live.isSsh) {
      setState(() => pane = _Pane.session);
      if (live.filesSidebarOpen) {
        await _refreshFiles(live);
      } else {
        await _openSshFilesSidebar(live);
      }
      return;
    }
    setState(() => pane = _Pane.files);
    if (live.explorerPath.isEmpty) {
      try {
        final start = RdpSessionService.sharePath;
        if (!mounted) return;
        live.explorerPath = start;
      } catch (error) {
        if (mounted) showMessage('Could not open home folder: $error', kind: ToastKind.error);
        return;
      }
    }
    await _refreshFiles(live);
  }

  Widget _buildFilesPane(LiveSession live,
      {required bool compact, VoidCallback? onClose}) {
    final canGoUp = live.explorerPath.isNotEmpty &&
        live.explorerPath != '/' &&
        !(!live.isSsh && live.explorerPath == RdpSessionService.sharePath);
    return _FilesPane(
      ssh: live.isSsh && live.connected,
      rdp: !live.isSsh && live.connected,
      path: live.explorerPath,
      entries: live.explorerEntries,
      selectedPaths: live.selectedPaths,
      clipboard: live.clipboard,
      busy: live.explorerBusy,
      upload: live.upload,
      onCancelUpload: live.upload == null
          ? null
          : () {
              live.upload?.cancel();
              setState(() {});
            },
      canGoUp: canGoUp,
      compact: compact,
      following: live.followTerminalCwd,
      autofocus: !compact,
      onClose: onClose,
      onFollow: live.isSsh ? () => _syncExplorerToTerminal(live) : null,
      onOpen: (path) => _openExplorerPath(path, target: live),
      onUp: () => _goExplorerUp(target: live),
      onSelect: (entry, {required toggle}) =>
          _selectEntry(entry, toggle: toggle, target: live),
      onCopy: () => _copySelection(cut: false, target: live),
      onCut: () => _copySelection(cut: true, target: live),
      onPaste: () => _pasteClipboard(target: live),
      onUpload: () => _pickAndUpload(target: live),
      onNewFolder: () => _createRemoteFolder(target: live),
      onRename: () => _renameSelection(target: live),
      onPermissions: () => _chmodSelection(target: live),
      onRefresh: () => _refreshFiles(live),
      onCopyPath: () => _copyExplorerPath(live),
    );
  }

  Future<void> _copyExplorerPath(LiveSession live, {String? itemPath}) async {
    final value = (itemPath ?? live.explorerPath).trim();
    if (value.isEmpty) {
      showMessage('No path to copy', kind: ToastKind.warning);
      return;
    }
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) showMessage('Path copied', kind: ToastKind.success);
  }

  Future<void> _refreshFiles([LiveSession? target]) async {
    final live = target ?? focused;
    if (live == null || !live.connected || live.explorerPath.isEmpty) return;
    setState(() => live.explorerBusy = true);
    try {
      final entries = live.isSsh
          ? await live.ssh!.listRemote(live.explorerPath)
          : await live.rdp!.listSharedEntries(live.explorerPath);
      if (!mounted) return;
      setState(() {
        live.explorerEntries = entries;
        live.selectedPaths
            .removeWhere((path) => entries.every((item) => item.path != path));
      });
    } catch (error) {
      await AppLog.line('refresh files failed: $error');
      if (mounted) showMessage('Could not list files: $error', kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => live.explorerBusy = false);
    }
  }

  Future<void> _openExplorerPath(String path, {LiveSession? target}) async {
    final live = target ?? focused;
    if (live == null) return;
    if (!live.isSsh && !path.startsWith(RdpSessionService.sharePath)) {
      path = RdpSessionService.sharePath;
    }
    setState(() {
      live.explorerPath = path;
      live.selectedPaths.clear();
      if (live.isSsh) live.followTerminalCwd = false;
    });
    await _refreshFiles(live);
  }

  Future<void> _goExplorerUp({LiveSession? target}) async {
    final live = target ?? focused;
    if (live == null || live.explorerPath.isEmpty) return;
    if (!live.isSsh && live.explorerPath == RdpSessionService.sharePath) return;
    if (live.isSsh && live.explorerPath == '/') return;
    await _openExplorerPath(RemoteEntry.parent(live.explorerPath),
        target: live);
  }

  void _selectEntry(RemoteEntry entry,
      {required bool toggle, LiveSession? target}) {
    final live = target ?? focused;
    if (live == null) return;
    setState(() {
      if (toggle) {
        if (!live.selectedPaths.remove(entry.path)) {
          live.selectedPaths.add(entry.path);
        }
      } else {
        live.selectedPaths
          ..clear()
          ..add(entry.path);
      }
    });
  }

  void _copySelection({required bool cut, LiveSession? target}) {
    final live = target ?? focused;
    if (live == null || live.selectedPaths.isEmpty) {
      showMessage('Select a file or folder first', kind: ToastKind.warning);
      return;
    }
    setState(() {
      live.clipboard = FileClipboard(
          paths: live.selectedPaths.toList(),
          cut: cut,
          sourceDir: live.explorerPath);
    });
    showMessage(
        cut
            ? 'Cut — go to the destination folder and Paste'
            : 'Copied — go to the destination folder and Paste',
        kind: ToastKind.info);
  }

  Future<void> _pasteClipboard({LiveSession? target}) async {
    final live = target ?? focused;
    final clip = live?.clipboard;
    if (live == null || clip == null || clip.isEmpty) {
      showMessage('Clipboard is empty', kind: ToastKind.warning);
      return;
    }
    final dest = live.explorerPath;
    final sources = clip.paths
        .where((path) => RemoteEntry.parent(path) != dest && path != dest)
        .toList();
    if (sources.isEmpty) {
      showMessage('Open another folder, then Paste', kind: ToastKind.warning);
      return;
    }
    setState(() => live.explorerBusy = true);
    try {
      if (live.isSsh) {
        if (clip.cut) {
          await live.ssh!.moveRemote(sources, dest);
        } else {
          await live.ssh!.copyRemote(sources, dest);
        }
      } else {
        if (clip.cut) {
          await live.rdp!.moveShared(sources, dest);
        } else {
          await live.rdp!.copyShared(sources, dest);
        }
      }
      if (clip.cut && mounted) setState(() => live.clipboard = null);
      if (mounted) showMessage(clip.cut ? 'Moved' : 'Copied', kind: ToastKind.success);
      await _refreshFiles(live);
    } catch (error) {
      await AppLog.line('paste failed: $error');
      if (mounted) showMessage('File operation failed: $error', kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => live.explorerBusy = false);
    }
  }

  Future<void> _createRemoteFolder({LiveSession? target}) async {
    final live = target ?? focused;
    if (live == null || !live.connected) {
      showMessage('Connect a session first', kind: ToastKind.warning);
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _NamePromptDialog(
        title: 'New folder',
        label: 'Folder name',
        confirmLabel: 'Create',
        initialValue: 'New folder',
      ),
    );
    final folderName = name?.trim() ?? '';
    if (folderName.isEmpty || !mounted) return;
    setState(() => live.explorerBusy = true);
    try {
      if (live.isSsh) {
        await live.ssh!.mkdirRemote(live.explorerPath, folderName);
      } else {
        await live.rdp!.mkdirShared(live.explorerPath, folderName);
      }
      if (mounted) showMessage('Folder created', kind: ToastKind.success);
      await _refreshFiles(live);
    } catch (error) {
      await AppLog.line('mkdir failed: $error');
      if (mounted) showMessage('Could not create folder: $error', kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => live.explorerBusy = false);
    }
  }

  Future<void> _renameSelection({LiveSession? target}) async {
    final live = target ?? focused;
    if (live == null || !live.connected) {
      showMessage('Connect a session first', kind: ToastKind.warning);
      return;
    }
    if (live.selectedPaths.length != 1) {
      showMessage('Select exactly one item to rename', kind: ToastKind.warning);
      return;
    }
    final path = live.selectedPaths.first;
    final currentName = path.split('/').where((part) => part.isNotEmpty).last;
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initialName: currentName),
    );
    if (newName == null || newName.trim().isEmpty || !mounted) return;
    if (newName.trim() == currentName) return;
    setState(() => live.explorerBusy = true);
    try {
      if (live.isSsh) {
        await live.ssh!.renameRemote(path, newName.trim());
      } else {
        await live.rdp!.renameShared(path, newName.trim());
      }
      live.selectedPaths
        ..clear()
        ..add(RemoteEntry.join(RemoteEntry.parent(path), newName.trim()));
      if (mounted) showMessage('Renamed', kind: ToastKind.success);
      await _refreshFiles(live);
    } catch (error) {
      await AppLog.line('rename failed: $error');
      if (mounted) showMessage('Rename failed: $error', kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => live.explorerBusy = false);
    }
  }

  Future<void> _chmodSelection({LiveSession? target}) async {
    final live = target ?? focused;
    if (live == null || !live.connected) {
      showMessage('Connect a session first', kind: ToastKind.warning);
      return;
    }
    if (live.selectedPaths.isEmpty) {
      showMessage('Select a file or folder first', kind: ToastKind.warning);
      return;
    }
    final paths = live.selectedPaths.toList();
    final hasDirectory = live.explorerEntries
        .any((entry) => paths.contains(entry.path) && entry.isDirectory);
    String initialMode = '755';
    try {
      initialMode = live.isSsh
          ? await live.ssh!.remoteMode(paths.first)
          : await live.rdp!.sharedMode(paths.first);
    } catch (_) {}
    if (!mounted) return;
    final result = await showDialog<({String mode, bool recursive})>(
      context: context,
      builder: (context) => _PermissionsDialog(
        initialMode: initialMode,
        itemCount: paths.length,
        suggestRecursive: hasDirectory,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => live.explorerBusy = true);
    try {
      if (live.isSsh) {
        await live.ssh!
            .chmodRemote(paths, mode: result.mode, recursive: result.recursive);
      } else {
        await live.rdp!.chmodShared(paths,
            mode: result.mode, recursive: result.recursive);
      }
      if (mounted) {
        showMessage(
            result.recursive
                ? 'Permissions ${result.mode} applied recursively'
                : 'Permissions ${result.mode} applied',
            kind: ToastKind.success);
      }
      await _refreshFiles(live);
    } catch (error) {
      await AppLog.line('chmod failed: $error');
      if (mounted) showMessage('Permission change failed: $error', kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => live.explorerBusy = false);
    }
  }

  Future<void> _pickAndUpload({LiveSession? target}) async {
    final live = target ?? focused;
    await AppLog.line(
        'upload click ssh=$sshConnected rdp=$rdpConnected path=${live?.explorerPath}');
    if (live == null || !live.connected) {
      showMessage('Connect an SSH or RDP session first', kind: ToastKind.warning);
      return;
    }
    if (live.upload != null) {
      showMessage('Another upload is already in progress', kind: ToastKind.warning);
      return;
    }
    final file = await openFile(confirmButtonText: 'Select');
    if (file == null) return;
    final total = await file.length();
    final job = UploadJob(fileName: file.name, totalBytes: total);
    var lastUi = DateTime.fromMillisecondsSinceEpoch(0);
    void bumpUi({bool force = false}) {
      final now = DateTime.now();
      if (!force &&
          now.difference(lastUi).inMilliseconds < 80 &&
          job.sentBytes < job.totalBytes) {
        return;
      }
      lastUi = now;
      if (mounted) setState(() {});
    }

    setState(() {
      live.explorerBusy = true;
      live.upload = job;
    });
    try {
      if (live.isSsh) {
        // Poll UI while SFTP progress callbacks update job fields.
        final ticker = Timer.periodic(const Duration(milliseconds: 120), (_) {
          if (live.upload == job) bumpUi();
        });
        try {
          await live.ssh!.uploadFile(
            file.path,
            remoteDir: live.explorerPath.isEmpty ? '.' : live.explorerPath,
            job: job,
          );
        } finally {
          ticker.cancel();
        }
        if (mounted) showMessage('Uploaded ${file.name}', kind: ToastKind.success);
      } else {
        await _uploadSharedWithProgress(live, file.path, job, bumpUi);
        if (mounted) showMessage('File added to the shared drive', kind: ToastKind.success);
      }
      await _refreshFiles(live);
    } on UploadCancelledException {
      if (mounted) showMessage('Upload cancelled', kind: ToastKind.warning);
    } catch (error) {
      await AppLog.line('upload failed: $error');
      if (mounted) showMessage('Upload failed: $error', kind: ToastKind.error);
    } finally {
      if (mounted) {
        setState(() {
          live.explorerBusy = false;
          live.upload = null;
        });
      } else {
        live.explorerBusy = false;
        live.upload = null;
      }
    }
  }

  Future<void> _uploadSharedWithProgress(
    LiveSession live,
    String localPath,
    UploadJob job,
    void Function({bool force}) bumpUi,
  ) async {
    final destDirPath = live.explorerPath.isEmpty
        ? (await RdpSessionService.ensureShareDir()).path
        : live.explorerPath;
    final targetDir = Directory(destDirPath);
    await targetDir.create(recursive: true);
    final name = localPath.split(Platform.pathSeparator).last;
    final outPath = '${targetDir.path}${Platform.pathSeparator}$name';
    final sink = File(outPath).openWrite();
    var sent = 0;
    try {
      job.bindCancel(() {
        // Closing the sink interrupts the pipe on the next write.
        unawaited(sink.close());
      });
      job.throwIfCancelled();
      await for (final chunk in File(localPath).openRead()) {
        job.throwIfCancelled();
        sink.add(chunk);
        sent += chunk.length;
        job.report(sent);
        bumpUi();
      }
      await sink.flush();
      await sink.close();
      job.report(job.totalBytes);
      bumpUi(force: true);
    } catch (error) {
      try {
        await sink.close();
      } catch (_) {}
      try {
        await File(outPath).delete();
      } catch (_) {}
      if (job.cancelling || error is UploadCancelledException) {
        throw UploadCancelledException();
      }
      rethrow;
    } finally {
      job.clearCancel();
    }
  }

  Future<void> _openNewSession() async {
    final result = await showDialog<
        ({SavedSession session, String password, bool savePassword})>(
      context: context,
      builder: (context) => const _NewSessionDialog(),
    );
    if (result == null || !mounted) return;
    final stored = result.savePassword
        ? result.session.copyWith(password: result.password)
        : result.session;
    sessionStorage.saveAll([...sessions, stored]);
    setState(() => sessions = [...sessions, stored]);
    await _connectSession(stored, password: result.password);
  }

  Future<void> _editSession(SavedSession original) async {
    final result = await showDialog<
        ({SavedSession session, String password, bool savePassword})>(
      context: context,
      builder: (context) => _NewSessionDialog(initial: original),
    );
    if (result == null || !mounted) return;
    final updated = (result.savePassword
            ? result.session.copyWith(password: result.password)
            : result.session.copyWith(password: null))
        .copyWith(folder: original.folder);
    await _replaceSession(original, updated);
    showMessage('Session settings saved', kind: ToastKind.success);
  }

  Future<void> _changeTabColor(String liveId, int? tabColorArgb) async {
    final liveIndex = openSessions.indexWhere((item) => item.id == liveId);
    if (liveIndex < 0) return;
    final live = openSessions[liveIndex];
    final original = live.bookmark;
    final updated = original.copyWith(tabColor: tabColorArgb);
    await _replaceSession(original, updated);
  }

  Future<void> _showAbout() async {
    await showDialog<void>(
      context: context,
      builder: (context) => const _AboutDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = snapshot;
    final live = focused;
    final focusedIndex = openSessions.indexWhere((item) => item.id == live?.id);
    final paneIndex =
        pane == _Pane.home || (pane == _Pane.session && openSessions.isEmpty)
            ? 0
            : pane == _Pane.files
                ? 1
                : 2 + (focusedIndex < 0 ? 0 : focusedIndex);
    return Scaffold(
      backgroundColor: Moba.bg,
      body: Column(
        children: [
          _ToolBar(
            onSession: _openNewSession,
            onFiles: _openFilesPane,
            onAbout: _showAbout,
            onDisconnect: hasLiveSession ? _disconnect : null,
            connected: hasLiveSession,
          ),
          Expanded(
            child: Row(
              children: [
                _SessionSidebar(
                  sessions: sessions,
                  folders: folders,
                  active: live?.bookmark,
                  openBookmarks: openSessions
                      .where((item) => item.connected)
                      .map((item) => item.bookmark)
                      .toList(),
                  onOpen: (session) => _connectSession(session),
                  onDelete: _deleteSession,
                  onEdit: _editSession,
                  onCreateFolder: _createFolder,
                  onRenameFolder: _renameFolder,
                  onDeleteFolder: _deleteFolder,
                  onMoveSession: _moveSessionToFolder,
                  collapsedFolders: collapsedFolders,
                  onToggleFolder: _toggleFolder,
                ),
                Expanded(
                  child: Column(
                    children: [
                      _TabStrip(
                        pane: pane,
                        openSessions: openSessions,
                        focusedId: focusedId,
                        onHome: () => setState(() => pane = _Pane.home),
                        onSelect: (id) => setState(() {
                          focusedId = id;
                          pane = _Pane.session;
                        }),
                        onClose: (id) {
                          final match =
                              openSessions.where((item) => item.id == id);
                          if (match.isNotEmpty) _closeLive(match.first);
                        },
                        onFiles: _openFilesPane,
                        onChangeTabColor: _changeTabColor,
                      ),
                      Expanded(
                        child: IndexedStack(
                          index: paneIndex,
                          children: [
                            WelcomePane(
                              onNewSession: _openNewSession,
                              onOpenFiles: _openFilesPane,
                            ),
                            live == null
                                ? const ColoredBox(
                                    color: Color(0xFF1A1A1A),
                                    child: Center(
                                      child: Text('Connect a session to browse files',
                                          style: TextStyle(color: Colors.white38)),
                                    ),
                                  )
                                : _buildFilesPane(live, compact: false),
                            ...openSessions.map((item) {
                              final showSidebar = item.isSsh &&
                                  item.connected &&
                                  item.filesSidebarOpen;
                              return Row(
                                key: ValueKey(item.id),
                                children: [
                                  Expanded(
                                    child: _SessionSurface(
                                      snapshot: item.snapshot,
                                      session: item.bookmark,
                                      terminal: item.terminal,
                                      onDisconnect: () => _closeLive(item),
                                      onRetry: () => _connectSession(
                                          item.bookmark,
                                          prompt: true),
                                      onToggleFiles:
                                          item.isSsh && item.connected
                                              ? () => _toggleFilesSidebar(item)
                                              : null,
                                      filesOpen: showSidebar,
                                      fetchSystemStats:
                                          item.isSsh && item.connected
                                              ? () => item.ssh!.fetchSystemStats()
                                              : null,
                                    ),
                                  ),
                                  if (showSidebar) ...[
                                    _SidebarResizeHandle(
                                      onDrag: (delta) {
                                        setState(() {
                                          item.filesSidebarWidth =
                                              (item.filesSidebarWidth - delta)
                                                  .clamp(220.0, 640.0);
                                        });
                                      },
                                    ),
                                    SizedBox(
                                      width: item.filesSidebarWidth,
                                      child: _buildFilesPane(
                                        item,
                                        compact: true,
                                        onClose: () =>
                                            _toggleFilesSidebar(item),
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _StatusBar(snapshot: current, live: hasLiveSession),
        ],
      ),
    );
  }
}

class _ToolBar extends StatelessWidget {
  const _ToolBar(
      {required this.onSession,
      required this.onFiles,
      required this.onAbout,
      required this.connected,
      this.onDisconnect});
  final VoidCallback onSession;
  final VoidCallback onFiles;
  final VoidCallback onAbout;
  final VoidCallback? onDisconnect;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      color: Moba.toolbar,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        _ToolBtn(
            icon: Icons.computer,
            label: 'Session',
            color: Moba.green,
            onTap: onSession),
        _ToolBtn(
            icon: Icons.folder,
            label: 'Files',
            color: Colors.orangeAccent,
            onTap: onFiles),
        _ToolBtn(icon: Icons.fullscreen, label: 'Fullscreen', onTap: () {}),
        _ToolBtn(
          icon: Icons.link_off,
          label: 'Disconnect',
          color: connected ? Colors.redAccent : Colors.white38,
          onTap: onDisconnect,
        ),
        _ToolBtn(
            icon: Icons.info_outline,
            label: 'About',
            color: Colors.lightBlueAccent,
            onTap: onAbout),
      ]),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  const _ToolBtn(
      {required this.icon, required this.label, this.onTap, this.color});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      mouseCursor: WidgetStateMouseCursor.clickable,
      child: SizedBox(
        width: 72,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color ?? Colors.white70, size: 22),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
      ),
    );
  }
}

class _SessionSidebar extends StatelessWidget {
  const _SessionSidebar({
    required this.sessions,
    required this.folders,
    required this.active,
    required this.openBookmarks,
    required this.onOpen,
    required this.onDelete,
    required this.onEdit,
    required this.onCreateFolder,
    required this.onRenameFolder,
    required this.onDeleteFolder,
    required this.onMoveSession,
    required this.collapsedFolders,
    required this.onToggleFolder,
  });
  final List<SavedSession> sessions;
  final Set<String> folders;
  final SavedSession? active;
  final List<SavedSession> openBookmarks;
  final ValueChanged<SavedSession> onOpen;
  final ValueChanged<int> onDelete;
  final ValueChanged<SavedSession> onEdit;
  final VoidCallback onCreateFolder;
  final ValueChanged<String> onRenameFolder;
  final ValueChanged<String> onDeleteFolder;
  final void Function(SavedSession session, String? folder) onMoveSession;
  final Set<String> collapsedFolders;
  final ValueChanged<String> onToggleFolder;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      color: Moba.sidebar,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: 28,
          color: const Color(0xFF333333),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(children: [
            const Expanded(
                child: Text('User sessions',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
            IconButton(
              tooltip: 'New folder',
              onPressed: onCreateFolder,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 24, height: 24),
              icon: const Icon(Icons.create_new_folder_outlined,
                  size: 16, color: Colors.white70),
            ),
          ]),
          ),
          Expanded(
          child: ListView(
                children: [
              _folderHeader(context, null,
                  collapsed: collapsedFolders.contains('')),
              if (!collapsedFolders.contains(''))
                for (var index = 0; index < sessions.length; index++)
                  if (sessions[index].folder == null)
                    _sessionTile(context, sessions[index], index),
              for (final folder in (folders.toList()..sort())) ...[
                _folderHeader(context, folder,
                    collapsed: collapsedFolders.contains(folder)),
                if (!collapsedFolders.contains(folder))
                  for (var index = 0; index < sessions.length; index++)
                    if (sessions[index].folder == folder)
                      _sessionTile(context, sessions[index], index),
              ],
            ],
          ),
        ),
      ]),
    );
  }

  Widget _folderHeader(BuildContext context, String? folder,
      {required bool collapsed}) {
    return DragTarget<SavedSession>(
      onWillAcceptWithDetails: (details) => details.data.folder != folder,
      onAcceptWithDetails: (details) => onMoveSession(details.data, folder),
      builder: (context, candidates, rejects) => Material(
        color: candidates.isNotEmpty
            ? Moba.green.withValues(alpha: 0.28)
            : const Color(0xFF202020),
        child: InkWell(
          onTap: () => onToggleFolder(folder ?? ''),
          child: Padding(
            padding:
                const EdgeInsets.only(left: 10, right: 4, top: 5, bottom: 4),
            child: Row(children: [
              Icon(
                collapsed ? Icons.chevron_right : Icons.expand_more,
                size: 20,
                color: Colors.white70,
              ),
              const SizedBox(width: 2),
              Icon(
                  folder == null ? Icons.inbox_outlined : Icons.folder_outlined,
                  size: 15,
                  color: Colors.white54),
              const SizedBox(width: 6),
                  Expanded(
                  child: Text(folder ?? 'No folder',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white60))),
              if (folder != null) ...[
                IconButton(
                  tooltip: 'Rename folder',
                  onPressed: () => onRenameFolder(folder),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 24, height: 22),
                  icon: const Icon(Icons.edit_outlined,
                      size: 15, color: Colors.white54),
                ),
                IconButton(
                  tooltip: 'Delete folder',
                  onPressed: () => onDeleteFolder(folder),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 24, height: 22),
                  icon: const Icon(Icons.delete_outline,
                      size: 16, color: Color(0xFFFF6B6B)),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _sessionTile(BuildContext context, SavedSession session, int index) {
    final selected = active != null && session.sameBookmark(active!);
    final opened = openBookmarks.any((item) => item.sameBookmark(session));
    return Draggable<SavedSession>(
      data: session,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(8),
          color: Moba.menu,
          child: Row(children: [
            Icon(session.isSsh ? Icons.terminal : Icons.desktop_windows,
                size: 16, color: session.isSsh ? Moba.ssh : Moba.rdp),
            const SizedBox(width: 8),
            Expanded(
                child: Text(session.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white))),
          ]),
        ),
      ),
      child: InkWell(
        onTap: () => onOpen(session),
        onSecondaryTapUp: (details) =>
            _showSessionMenu(context, details, session, index),
        mouseCursor: WidgetStateMouseCursor.clickable,
        child: Container(
          color: selected ? Moba.green.withValues(alpha: 0.25) : null,
          padding: const EdgeInsets.only(left: 18, right: 4, top: 6, bottom: 6),
          child: Row(children: [
            Icon(session.isSsh ? Icons.terminal : Icons.desktop_windows,
                size: 16, color: session.isSsh ? Moba.ssh : Moba.rdp),
            if (opened)
              const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.circle, size: 7, color: Moba.green)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(session.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                    Text('${session.isSsh ? 'SSH' : 'RDP'} ${session.host}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white54)),
                  ]),
            ),
            if (session.hasSavedPassword)
              const Icon(Icons.lock, size: 13, color: Colors.white38),
          ]),
        ),
      ),
    );
  }

  Future<void> _showSessionMenu(BuildContext context, TapUpDetails details,
      SavedSession session, int index) async {
    final action = await _showAppMenu(
      context,
      details.globalPosition,
      const [
        _CtxItem(
          value: 'edit',
          label: 'Edit session',
          icon: Icons.edit_outlined,
        ),
        _CtxItem(
          value: 'delete',
          label: 'Delete session',
          icon: Icons.delete_outline,
          danger: true,
          dividerBefore: true,
        ),
      ],
    );
    if (!context.mounted) return;
    if (action == 'edit') {
      onEdit(session);
      return;
    }
    if (action != 'delete') return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete session?'),
        content: Text('Delete “${session.name}” from saved sessions?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) onDelete(index);
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.pane,
    required this.openSessions,
    required this.focusedId,
    required this.onHome,
    required this.onSelect,
    required this.onClose,
    required this.onFiles,
    this.onChangeTabColor,
  });
  final _Pane pane;
  final List<LiveSession> openSessions;
  final String? focusedId;
  final VoidCallback onHome;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;
  final VoidCallback onFiles;
  final void Function(String liveId, int? tabColorArgb)? onChangeTabColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      color: const Color(0xFF1A1A1A),
      child: Row(children: [
        _Tab(label: 'Start', selected: pane == _Pane.home, onTap: onHome),
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final live in openSessions)
                _Tab(
                  label: '${live.isSsh ? 'SSH' : 'RDP'} ${live.bookmark.name}',
                  selected: pane == _Pane.session && live.id == focusedId,
                  color: live.bookmark.tabBackground,
                  accent: live.bookmark.accentColor,
                  onTap: () => onSelect(live.id),
                  onClose: () => onClose(live.id),
                  onChangeColor: onChangeTabColor == null
                      ? null
                      : (colorArgb) => onChangeTabColor!(live.id, colorArgb),
                ),
        ],
      ),
        ),
        _Tab(label: 'Files', selected: pane == _Pane.files, onTap: onFiles),
      ]),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
    this.accent,
    this.onClose,
    this.onChangeColor,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onClose;
  final Color? color;
  final Color? accent;
  final ValueChanged<int?>? onChangeColor;

  Future<void> _pickColor(BuildContext context, Offset position) async {
    if (onChangeColor == null) return;
    final chosen = await showMenu<Object>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: Moba.menu,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF555555)),
      ),
      items: [
        const PopupMenuItem<Object>(
          value: 'default',
          height: 40,
          child: Row(
            children: [
              Icon(Icons.palette_outlined, size: 18, color: Colors.white70),
              SizedBox(width: 10),
              Text('Protocol default'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        for (final c in SavedSession.tabPalette)
          PopupMenuItem<Object>(
            value: c.toARGB32(),
            height: 40,
            child: Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
          ),
      ],
    );
    if (chosen == null) return;
    if (chosen == 'default') {
      onChangeColor!(null);
    } else if (chosen is int) {
      onChangeColor!(chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = accent;
    return InkWell(
      onTap: onTap,
      onSecondaryTapDown: onChangeColor == null
          ? null
          : (details) => _pickColor(context, details.globalPosition),
      mouseCursor: WidgetStateMouseCursor.clickable,
      child: Container(
        padding: EdgeInsets.only(left: accentColor == null ? 12 : 8, right: onClose == null ? 14 : 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? (color ?? const Color(0xFF3A3A3A)) : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: selected && accentColor != null
                  ? accentColor
                  : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (accentColor != null) ...[
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: accentColor.withValues(alpha: 0.55),
                          blurRadius: 6,
                        )
                      ]
                    : null,
              ),
            ),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: selected ? Colors.white : Colors.white70)),
          if (onClose != null)
            InkWell(
              onTap: onClose,
              mouseCursor: WidgetStateMouseCursor.clickable,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Icon(Icons.close, size: 12, color: Colors.white54),
              ),
            ),
        ]),
      ),
    );
  }
}

class _AboutDialog extends StatelessWidget {
  const _AboutDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 520,
        decoration: BoxDecoration(
          color: Moba.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x335B9BD5)),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 28, offset: Offset(0, 14))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 22, 16, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF263C58), Color(0xFF302640)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  const MorixtermLogo(size: 68),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('MoriXterm', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                        SizedBox(height: 5),
                        Text('Remote workspace, simplified.', style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(20)),
                    child: const Text('v0.1.0', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('About this workspace', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(child: _AboutInfoTile(icon: Icons.person_outline, label: 'Developer', value: 'mortenaho')),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _AboutInfoTile(
                          icon: Icons.language,
                          label: 'Website',
                          value: 'mortenaho.ir',
                          link: true,
                          onTap: () => _openExternalUrl('https://mortenaho.ir'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('Built-in capabilities', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70)),
                  const SizedBox(height: 10),
                  const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _AboutChip(icon: Icons.terminal, label: 'SSH terminal'),
                      _AboutChip(icon: Icons.desktop_windows_outlined, label: 'RDP sessions'),
                      _AboutChip(icon: Icons.folder_outlined, label: 'SCP file transfer'),
                      _AboutChip(icon: Icons.palette_outlined, label: 'Terminal themes'),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Connect to remote machines, manage multiple sessions, browse files, and transfer data from one focused desktop workspace.',
                    style: TextStyle(height: 1.45, color: Colors.white54),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 18, 12),
              decoration: const BoxDecoration(color: Color(0x22101010)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutInfoTile extends StatelessWidget {
  const _AboutInfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.link = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool link;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Moba.green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                const SizedBox(height: 3),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: link ? const Color(0xFF6CB6FF) : Colors.white,
                    fontWeight: FontWeight.w600,
                    decoration: link ? TextDecoration.underline : TextDecoration.none,
                    decorationColor: const Color(0xFF6CB6FF),
                  ),
                ),
              ],
            ),
          ),
          if (link) const Icon(Icons.open_in_new, size: 14, color: Color(0xFF6CB6FF)),
        ],
      ),
    );
    if (onTap == null) return tile;
    return InkWell(
      onTap: onTap,
      mouseCursor: WidgetStateMouseCursor.clickable,
      borderRadius: BorderRadius.circular(10),
      child: tile,
    );
  }
}

Future<void> _openExternalUrl(String url) async {
  try {
    if (Platform.isLinux) {
      await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
    } else if (Platform.isMacOS) {
      await Process.start('open', [url], mode: ProcessStartMode.detached);
    } else if (Platform.isWindows) {
      await Process.start('cmd', ['/c', 'start', '', url], mode: ProcessStartMode.detached);
    }
  } catch (error) {
    await AppLog.line('open url failed: $error');
  }
}

class _AboutChip extends StatelessWidget {
  const _AboutChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x142E90FA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x334A90E2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, size: 15, color: Moba.green),
          const SizedBox(width: 6),
          Icon(icon, size: 15, color: Colors.white70),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ],
      ),
    );
  }
}

class _FilesPane extends StatelessWidget {
  const _FilesPane({
    required this.ssh,
    required this.rdp,
    required this.path,
    required this.entries,
    required this.selectedPaths,
    required this.clipboard,
    required this.busy,
    this.upload,
    this.onCancelUpload,
    required this.canGoUp,
    required this.onOpen,
    required this.onUp,
    required this.onSelect,
    required this.onCopy,
    required this.onCut,
    required this.onPaste,
    required this.onUpload,
    required this.onNewFolder,
    required this.onRename,
    required this.onPermissions,
    required this.onRefresh,
    required this.onCopyPath,
    this.compact = false,
    this.following = false,
    this.autofocus = true,
    this.onClose,
    this.onFollow,
  });

  final bool ssh;
  final bool rdp;
  final String path;
  final List<RemoteEntry> entries;
  final Set<String> selectedPaths;
  final FileClipboard? clipboard;
  final bool busy;
  final UploadJob? upload;
  final VoidCallback? onCancelUpload;
  final bool canGoUp;
  final bool compact;
  final bool following;
  final bool autofocus;
  final ValueChanged<String> onOpen;
  final VoidCallback onUp;
  final void Function(RemoteEntry entry, {required bool toggle}) onSelect;
  final VoidCallback onCopy;
  final VoidCallback onCut;
  final VoidCallback onPaste;
  final VoidCallback onUpload;
  final VoidCallback onNewFolder;
  final VoidCallback onRename;
  final VoidCallback onPermissions;
  final VoidCallback onRefresh;
  final VoidCallback onCopyPath;
  final VoidCallback? onClose;
  final VoidCallback? onFollow;

  @override
  Widget build(BuildContext context) {
    final ready = ssh || rdp;
    final hasSelection = selectedPaths.isNotEmpty;
    final canRename = selectedPaths.length == 1;
    final canPaste = clipboard != null && clipboard!.paths.isNotEmpty;
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyC):
            _ExplorerIntent.copy,
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyX):
            _ExplorerIntent.cut,
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyV):
            _ExplorerIntent.paste,
        LogicalKeySet(LogicalKeyboardKey.f2): _ExplorerIntent.rename,
        LogicalKeySet(LogicalKeyboardKey.backspace): _ExplorerIntent.up,
        LogicalKeySet(LogicalKeyboardKey.f5): _ExplorerIntent.refresh,
      },
      child: Actions(
        actions: {
          _ExplorerIntent: CallbackAction<_ExplorerIntent>(onInvoke: (intent) {
            switch (intent.kind) {
              case _ExplorerAction.copy:
                if (hasSelection) onCopy();
              case _ExplorerAction.cut:
                if (hasSelection) onCut();
              case _ExplorerAction.paste:
                if (canPaste) onPaste();
              case _ExplorerAction.rename:
                if (canRename) onRename();
              case _ExplorerAction.up:
                if (canGoUp) onUp();
              case _ExplorerAction.refresh:
                onRefresh();
            }
            return null;
          }),
        },
        child: Focus(
          autofocus: autofocus,
          canRequestFocus: autofocus,
          skipTraversal: !autofocus,
          child: ColoredBox(
            color: compact ? Moba.sidebar : const Color(0xFF1A1A1A),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (compact)
                    Container(
                      height: 38,
                      color: Moba.toolbar,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.folder_open,
                              size: 16, color: Colors.orangeAccent),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text('Remote files',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                          if (onFollow != null)
                            IconButton(
                              tooltip: following
                                  ? 'Following terminal path'
                                  : 'Sync to terminal path',
                              onPressed: onFollow,
                              icon: Icon(
                                following
                                    ? Icons.link
                                    : Icons.link_off,
                                size: 16,
                                color: following ? Moba.green : Colors.white54,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                  width: 28, height: 28),
                            ),
                          if (onClose != null)
                            IconButton(
                              tooltip: 'Close',
                              onPressed: onClose,
                              icon: const Icon(Icons.close, size: 16),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                  width: 28, height: 28),
                            ),
                        ],
                      ),
                    ),
                  Container(
                    height: compact ? 34 : 36,
                    color: Moba.toolbar,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: compact
                        ? ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _ExplorerIconBtn(
                                  icon: Icons.arrow_upward,
                                  tooltip: 'Up',
                                  onTap: ready && canGoUp ? onUp : null),
                              _ExplorerIconBtn(
                                  icon: Icons.refresh,
                                  tooltip: 'Refresh',
                                  onTap: ready ? onRefresh : null),
                              _ExplorerIconBtn(
                                  icon: Icons.upload,
                                  tooltip: 'Upload',
                                  onTap: ready ? onUpload : null),
                              _ExplorerIconBtn(
                                  icon: Icons.create_new_folder_outlined,
                                  tooltip: 'New folder',
                                  onTap: ready ? onNewFolder : null),
                              _ExplorerIconBtn(
                                  icon: Icons.copy,
                                  tooltip: 'Copy',
                                  onTap: ready && hasSelection ? onCopy : null),
                              _ExplorerIconBtn(
                                  icon: Icons.content_cut,
                                  tooltip: 'Cut',
                                  onTap: ready && hasSelection ? onCut : null),
                              _ExplorerIconBtn(
                                  icon: Icons.content_paste,
                                  tooltip: 'Paste',
                                  onTap: ready && canPaste ? onPaste : null),
                              _ExplorerIconBtn(
                                  icon: Icons.drive_file_rename_outline,
                                  tooltip: 'Rename',
                                  onTap:
                                      ready && canRename ? onRename : null),
                              _ExplorerIconBtn(
                                  icon: Icons.lock_outline,
                                  tooltip: 'Permissions',
                                  onTap: ready && hasSelection
                                      ? onPermissions
                                      : null),
                            ],
                          )
                        : Row(children: [
                            _ExplorerBtn(
                                icon: Icons.arrow_upward,
                                label: 'Up',
                                onTap: ready && canGoUp ? onUp : null),
                            _ExplorerBtn(
                                icon: Icons.refresh,
                                label: 'Refresh',
                                onTap: ready ? onRefresh : null),
                            _ExplorerBtn(
                                icon: Icons.upload,
                                label: 'Upload',
                                onTap: ready ? onUpload : null),
                            _ExplorerBtn(
                                icon: Icons.create_new_folder_outlined,
                                label: 'New folder',
                                onTap: ready ? onNewFolder : null),
                            const VerticalDivider(
                                width: 16, color: Colors.white24),
                            _ExplorerBtn(
                                icon: Icons.copy,
                                label: 'Copy',
                                onTap:
                                    ready && hasSelection ? onCopy : null),
                            _ExplorerBtn(
                                icon: Icons.content_cut,
                                label: 'Cut',
                                onTap: ready && hasSelection ? onCut : null),
                            _ExplorerBtn(
                                icon: Icons.content_paste,
                                label: 'Paste',
                                onTap: ready && canPaste ? onPaste : null),
                            _ExplorerBtn(
                                icon: Icons.drive_file_rename_outline,
                                label: 'Rename',
                                onTap:
                                    ready && canRename ? onRename : null),
                            _ExplorerBtn(
                                icon: Icons.lock_outline,
                                label: 'Permissions',
                                onTap: ready && hasSelection
                                    ? onPermissions
                                    : null),
                            const Spacer(),
                            Text(
                                ssh
                                    ? 'SCP'
                                    : rdp
                                        ? 'RDP share'
                                        : 'Files',
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 12)),
                          ]),
                  ),
                  Container(
                    height: compact ? 28 : 30,
                    color: const Color(0xFF2A2A2A),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.centerLeft,
                    child: ready
                        ? _PathBreadcrumb(
                            path: path.isEmpty ? '/' : path,
                            following: following,
                            compact: compact,
                            onOpen: onOpen,
                          )
                        : Text(
                            'not connected',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: compact ? 11 : 13,
                              color: Colors.white38,
                            ),
                          ),
                  ),
                  if (!compact)
                    Container(
                      height: 24,
                      color: const Color(0xFF333333),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.centerLeft,
                      child: const Text('Name',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  Expanded(
                    child: !ready
                        ? const Center(
                            child: Text('Connect a session first',
                                style: TextStyle(color: Colors.white38)))
                        : Stack(children: [
                            CustomScrollView(
                              slivers: [
                                SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) {
                                      if (canGoUp && index == 0) {
                                        return _FileRow(
                                          name: '..',
                                          directory: true,
                                          selected: false,
                                          cut: false,
                                          compact: compact,
                                          onTap: onUp,
                                          onDoubleTap: onUp,
                                          onNewFolder: onNewFolder,
                                          onPaste: canPaste ? onPaste : null,
                                          onRefresh: onRefresh,
                                          onCopyPath: onCopyPath,
                                        );
                                      }
                                      final entry =
                                          entries[index - (canGoUp ? 1 : 0)];
                                      final selected =
                                          selectedPaths.contains(entry.path);
                                      final cut = clipboard != null &&
                                          clipboard!.cut &&
                                          clipboard!.paths
                                              .contains(entry.path);
                                      return _FileRow(
                                        name: entry.name,
                                        directory: entry.isDirectory,
                                        selected: selected,
                                        cut: cut,
                                        compact: compact,
                                        onTap: () => onSelect(entry,
                                            toggle: HardwareKeyboard
                                                .instance.isControlPressed),
                                        onDoubleTap: entry.isDirectory
                                            ? () => onOpen(entry.path)
                                            : null,
                                        onCopy: onCopy,
                                        onCut: onCut,
                                        onPaste: canPaste ? onPaste : null,
                                        onNewFolder: onNewFolder,
                                        onRename: canRename || selected
                                            ? onRename
                                            : null,
                                        onPermissions: onPermissions,
                                        onRefresh: onRefresh,
                                        onCopyPath: onCopyPath,
                                      );
                                    },
                                    childCount:
                                        entries.length + (canGoUp ? 1 : 0),
                                  ),
                                ),
                                SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onSecondaryTapDown: ready
                                        ? (details) async {
                                            final action = await _showAppMenu(
                                              context,
                                              details.globalPosition,
                                              [
                                                const _CtxItem(
                                                  value: 'mkdir',
                                                  label: 'New folder',
                                                  icon: Icons
                                                      .create_new_folder_outlined,
                                                ),
                                                if (canPaste)
                                                  const _CtxItem(
                                                    value: 'paste',
                                                    label: 'Paste',
                                                    icon: Icons.content_paste,
                                                    shortcut: 'Ctrl+V',
                                                    dividerBefore: true,
                                                  ),
                                                const _CtxItem(
                                                  value: 'copyPath',
                                                  label: 'Copy path',
                                                  icon: Icons.link,
                                                  dividerBefore: true,
                                                ),
                                                const _CtxItem(
                                                  value: 'refresh',
                                                  label: 'Refresh',
                                                  icon: Icons.refresh,
                                                  shortcut: 'F5',
                                                  dividerBefore: true,
                                                ),
                                              ],
                                            );
                                            switch (action) {
                                              case 'mkdir':
                                                onNewFolder();
                                              case 'paste':
                                                onPaste();
                                              case 'copyPath':
                                                onCopyPath();
                                              case 'refresh':
                                                onRefresh();
                                            }
                                          }
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                            if (busy)
                              ColoredBox(
                                color: const Color(0x99000000),
                                child: Center(
                                  child: upload != null
                                      ? _UploadProgressCard(
                                          job: upload!,
                                          onCancel: upload!.cancelling
                                              ? null
                                              : onCancelUpload,
                                        )
                                      : const SizedBox(
                                          width: 28,
                                          height: 28,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Moba.green,
                                          ),
                                        ),
                                ),
                              ),
                          ]),
                  ),
                  if (clipboard != null)
                    Container(
                      height: 22,
                      color: const Color(0xFF2A2A2A),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${clipboard!.cut ? 'Cut' : 'Copied'} ${clipboard!.paths.length} item(s)',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white54),
                      ),
                    ),
                ]),
          ),
        ),
      ),
    );
  }
}

enum _ExplorerAction { copy, cut, paste, rename, up, refresh }

class _UploadProgressCard extends StatelessWidget {
  const _UploadProgressCard({required this.job, this.onCancel});

  final UploadJob job;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final fraction = job.fraction;
    final indeterminate = fraction == null;
    final percentLabel = indeterminate ? '…' : '${job.percent}%';
    final sizeLabel = indeterminate
        ? formatTransferBytes(job.totalBytes)
        : '${formatTransferBytes(job.sentBytes)} / ${formatTransferBytes(job.totalBytes)}';
    final speedLabel = formatTransferSpeed(job.bytesPerSecond);
    final cancelling = job.cancelling;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Material(
        color: const Color(0xFF2A2A2A),
        elevation: 8,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Moba.green.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.upload_rounded,
                        size: 18, color: Moba.green),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cancelling ? 'Cancelling upload…' : 'Uploading',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          job.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    percentLabel,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Moba.green,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: indeterminate ? null : fraction,
                  minHeight: 7,
                  backgroundColor: const Color(0xFF3A3A3A),
                  color: cancelling ? Colors.orangeAccent : Moba.green,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      sizeLabel,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white60),
                    ),
                  ),
                  Text(
                    speedLabel,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: cancelling
                        ? Colors.white38
                        : const Color(0xFFFF8A80),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: Icon(
                    cancelling ? Icons.hourglass_top : Icons.close,
                    size: 15,
                  ),
                  label: Text(
                    cancelling ? 'Cancelling' : 'Cancel',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExplorerIntent extends Intent {
  const _ExplorerIntent(this.kind);
  final _ExplorerAction kind;
  static const copy = _ExplorerIntent(_ExplorerAction.copy);
  static const cut = _ExplorerIntent(_ExplorerAction.cut);
  static const paste = _ExplorerIntent(_ExplorerAction.paste);
  static const rename = _ExplorerIntent(_ExplorerAction.rename);
  static const up = _ExplorerIntent(_ExplorerAction.up);
  static const refresh = _ExplorerIntent(_ExplorerAction.refresh);
}

class _ExplorerBtn extends StatelessWidget {
  const _ExplorerBtn({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      mouseCursor: WidgetStateMouseCursor.clickable,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(children: [
          Icon(icon,
              size: 15, color: onTap == null ? Colors.white24 : Colors.white70),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: onTap == null ? Colors.white24 : Colors.white70)),
        ]),
      ),
    );
  }
}

class _ExplorerIconBtn extends StatelessWidget {
  const _ExplorerIconBtn({required this.icon, required this.tooltip, this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Icon(icon,
              size: 15, color: onTap == null ? Colors.white24 : Colors.white70),
        ),
      ),
    );
  }
}

class _SidebarResizeHandle extends StatefulWidget {
  const _SidebarResizeHandle({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  State<_SidebarResizeHandle> createState() => _SidebarResizeHandleState();
}

class _SidebarResizeHandleState extends State<_SidebarResizeHandle> {
  bool _hover = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final active = _hover || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (details) => widget.onDrag(details.delta.dx),
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        onHorizontalDragCancel: () => setState(() => _dragging = false),
        child: SizedBox(
          width: 5,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: active ? 3 : 1,
              color: active ? Moba.green : const Color(0xFF3A3A3A),
            ),
          ),
        ),
      ),
    );
  }
}

class _PathBreadcrumb extends StatelessWidget {
  const _PathBreadcrumb({
    required this.path,
    required this.onOpen,
    this.following = false,
    this.compact = false,
  });

  final String path;
  final ValueChanged<String> onOpen;
  final bool following;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final crumbs = RemoteEntry.breadcrumbs(path);
    final accent =
        following ? const Color(0xFF98C379) : const Color(0xFF9CDCFE);
    const muted = Colors.white38;
    final fontSize = compact ? 11.0 : 13.0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(
        children: [
          for (var i = 0; i < crumbs.length; i++) ...[
            if (i > 0)
              Icon(Icons.chevron_right, size: fontSize + 2, color: muted),
            _BreadcrumbChip(
              label: crumbs[i].label,
              current: i == crumbs.length - 1,
              accent: accent,
              muted: muted,
              fontSize: fontSize,
              onTap: () {
                if (crumbs[i].path != path) onOpen(crumbs[i].path);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _BreadcrumbChip extends StatelessWidget {
  const _BreadcrumbChip({
    required this.label,
    required this.current,
    required this.accent,
    required this.muted,
    required this.fontSize,
    required this.onTap,
  });

  final String label;
  final bool current;
  final Color accent;
  final Color muted;
  final double fontSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: current ? null : onTap,
      mouseCursor: current
          ? SystemMouseCursors.basic
          : WidgetStateMouseCursor.clickable,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: fontSize,
            fontWeight: current ? FontWeight.w600 : FontWeight.w400,
            color: current ? accent : accent.withValues(alpha: 0.85),
            decoration: current ? null : TextDecoration.underline,
            decorationColor: accent.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}

class _CtxItem {
  const _CtxItem({
    required this.value,
    required this.label,
    required this.icon,
    this.shortcut,
    this.danger = false,
    this.dividerBefore = false,
  });

  final String value;
  final String label;
  final IconData icon;
  final String? shortcut;
  final bool danger;
  final bool dividerBefore;
}

Future<String?> _showAppMenu(
  BuildContext context,
  Offset globalPosition,
  List<_CtxItem> items,
) {
  return showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      globalPosition.dx,
      globalPosition.dy,
    ),
    elevation: 16,
    color: Moba.menu,
    shadowColor: Colors.black.withValues(alpha: 0.65),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: Color(0xFF555555), width: 1),
    ),
    constraints: const BoxConstraints(minWidth: 220, maxWidth: 260),
    items: [
      for (final item in items) ...[
        if (item.dividerBefore)
          const PopupMenuDivider(height: 10),
        PopupMenuItem<String>(
          value: item.value,
          height: 40,
          padding: EdgeInsets.zero,
          child: _CtxMenuTile(
            icon: item.icon,
            label: item.label,
            shortcut: item.shortcut,
            danger: item.danger,
          ),
        ),
      ],
    ],
  );
}

class _CtxMenuTile extends StatelessWidget {
  const _CtxMenuTile({
    required this.icon,
    required this.label,
    this.shortcut,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String? shortcut;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFFF6B6B) : Colors.white;
    final iconColor = danger ? const Color(0xFFFF6B6B) : Moba.green;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: danger
                  ? const Color(0x33FF6B6B)
                  : Moba.green.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 15, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (shortcut != null)
            Text(
              shortcut!,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.name,
    required this.directory,
    required this.selected,
    required this.cut,
    required this.onTap,
    this.compact = false,
    this.onDoubleTap,
    this.onCopy,
    this.onCut,
    this.onPaste,
    this.onNewFolder,
    this.onRename,
    this.onPermissions,
    this.onRefresh,
    this.onCopyPath,
  });

  final String name;
  final bool directory;
  final bool selected;
  final bool cut;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onCopy;
  final VoidCallback? onCut;
  final VoidCallback? onPaste;
  final VoidCallback? onNewFolder;
  final VoidCallback? onRename;
  final VoidCallback? onPermissions;
  final VoidCallback? onRefresh;
  final VoidCallback? onCopyPath;

  IconData get _icon {
    if (directory) return Icons.folder;
    final lower = name.toLowerCase();
    if (lower.endsWith('.html') || lower.endsWith('.htm')) {
      return Icons.language;
    }
    if (lower.endsWith('.sh') || lower.endsWith('.bash')) {
      return Icons.terminal;
    }
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    final hasMenu = onCopy != null ||
        onCut != null ||
        onPaste != null ||
        onNewFolder != null ||
        onRename != null ||
        onPermissions != null ||
        onRefresh != null ||
        onCopyPath != null;
    return InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onSecondaryTapDown: !hasMenu
          ? null
          : (details) async {
              onTap();
              final items = <_CtxItem>[
                if (directory && onDoubleTap != null)
                  const _CtxItem(
                    value: 'open',
                    label: 'Open',
                    icon: Icons.folder_open_outlined,
                  ),
                if (onNewFolder != null)
                  _CtxItem(
                    value: 'mkdir',
                    label: 'New folder',
                    icon: Icons.create_new_folder_outlined,
                    dividerBefore: directory && onDoubleTap != null,
                  ),
                if (onCopy != null)
                  const _CtxItem(
                    value: 'copy',
                    label: 'Copy',
                    icon: Icons.copy_outlined,
                    shortcut: 'Ctrl+C',
                    dividerBefore: true,
                  ),
                if (onCut != null)
                  const _CtxItem(
                    value: 'cut',
                    label: 'Cut',
                    icon: Icons.content_cut,
                    shortcut: 'Ctrl+X',
                  ),
                if (onPaste != null)
                  const _CtxItem(
                    value: 'paste',
                    label: 'Paste',
                    icon: Icons.content_paste,
                    shortcut: 'Ctrl+V',
                  ),
                if (onCopyPath != null)
                  const _CtxItem(
                    value: 'copyPath',
                    label: 'Copy path',
                    icon: Icons.link,
                    dividerBefore: true,
                  ),
                if (onRename != null)
                  const _CtxItem(
                    value: 'rename',
                    label: 'Rename',
                    icon: Icons.drive_file_rename_outline,
                    shortcut: 'F2',
                    dividerBefore: true,
                  ),
                if (onPermissions != null)
                  const _CtxItem(
                    value: 'chmod',
                    label: 'Permissions…',
                    icon: Icons.lock_outline,
                  ),
                if (onRefresh != null)
                  const _CtxItem(
                    value: 'refresh',
                    label: 'Refresh',
                    icon: Icons.refresh,
                    shortcut: 'F5',
                    dividerBefore: true,
                  ),
              ];
              final action =
                  await _showAppMenu(context, details.globalPosition, items);
              switch (action) {
                case 'open':
                  onDoubleTap?.call();
                case 'mkdir':
                  onNewFolder?.call();
                case 'copy':
                  onCopy?.call();
                case 'cut':
                  onCut?.call();
                case 'paste':
                  onPaste?.call();
                case 'copyPath':
                  onCopyPath?.call();
                case 'rename':
                  onRename?.call();
                case 'chmod':
                  onPermissions?.call();
                case 'refresh':
                  onRefresh?.call();
              }
            },
      mouseCursor: WidgetStateMouseCursor.clickable,
      child: Container(
        color: selected ? Moba.green.withValues(alpha: 0.28) : null,
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10, vertical: compact ? 4 : 5),
        child: Row(children: [
          Icon(_icon,
              size: compact ? 16 : 18,
              color: directory ? const Color(0xFFE6B422) : Colors.white70),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: cut ? Colors.white38 : Colors.white,
                fontStyle: cut ? FontStyle.italic : FontStyle.normal,
              ),
            ),
                ),
        ]),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.snapshot, required this.live});
  final ConnectionSnapshot snapshot;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final text = live
        ? '${snapshot.protocol == SessionProtocol.ssh ? 'SSH' : 'RDP'}  ${snapshot.username}@${snapshot.host}:${snapshot.port}'
        : 'ready.';
    return Container(
      height: 22,
      color: Moba.status,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _CredentialsDialog extends StatefulWidget {
  const _CredentialsDialog({required this.session});
  final SavedSession session;

  @override
  State<_CredentialsDialog> createState() => _CredentialsDialogState();
}

class _CredentialsDialogState extends State<_CredentialsDialog> {
  late final TextEditingController user =
      TextEditingController(text: widget.session.username);
  late final TextEditingController password =
      TextEditingController(text: widget.session.password);
  bool showPassword = false;
  bool savePassword = true;

  @override
  void dispose() {
    user.dispose();
    password.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop(context, (
      username: user.text.trim(),
      password: password.text,
      savePassword: savePassword,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return AlertDialog(
      title: Text('Connect to ${session.name}'),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              '${session.isSsh ? 'SSH' : 'RDP'}  •  ${session.host}:${session.port}',
              style: const TextStyle(color: Colors.white60)),
          const SizedBox(height: 16),
          TextField(
              controller: user,
              decoration: const InputDecoration(labelText: 'Username')),
          const SizedBox(height: 14),
          TextField(
            controller: password,
            obscureText: !showPassword,
            autofocus: session.username.isNotEmpty,
            decoration: InputDecoration(
              labelText: session.isSsh
                  ? 'Password (optional with SSH key)'
                  : 'Password',
              suffixIcon: IconButton(
                tooltip: showPassword ? 'Hide password' : 'Show password',
                onPressed: () => setState(() => showPassword = !showPassword),
                icon: Icon(
                    showPassword ? Icons.visibility_off : Icons.visibility),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: savePassword,
            mouseCursor: WidgetStateMouseCursor.clickable,
            onChanged: (value) => setState(() => savePassword = value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Save password'),
          ),
            ]),
          ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.login),
            label: const Text('Connect')),
      ],
    );
  }
}

class _NewSessionDialog extends StatefulWidget {
  const _NewSessionDialog({this.initial});

  final SavedSession? initial;

  @override
  State<_NewSessionDialog> createState() => _NewSessionDialogState();
}

class _NewSessionDialogState extends State<_NewSessionDialog> {
  late SessionProtocol protocol;
  final host = TextEditingController();
  final name = TextEditingController();
  final user = TextEditingController();
  final port = TextEditingController(text: '3389');
  final password = TextEditingController();
  bool showPassword = false;
  late bool savePassword;
  int? tabColor;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    protocol = initial?.protocol ?? SessionProtocol.rdp;
    host.text = initial?.host ?? '';
    name.text = initial?.name ?? '';
    user.text = initial?.username ?? '';
    port.text =
        '${initial?.port ?? (protocol == SessionProtocol.ssh ? 22 : 3389)}';
    password.text = initial?.password ?? '';
    savePassword = initial?.hasSavedPassword ?? true;
    tabColor = initial?.tabColor;
  }

  @override
  void dispose() {
    host.dispose();
    name.dispose();
    user.dispose();
    port.dispose();
    password.dispose();
    super.dispose();
  }

  void _selectProtocol(SessionProtocol next) {
    setState(() {
      protocol = next;
      if (port.text == '3389' || port.text == '22' || port.text.isEmpty) {
        port.text = next == SessionProtocol.ssh ? '22' : '3389';
      }
    });
  }

  void _submit() {
    final address = host.text.trim();
    if (address.isEmpty || user.text.trim().isEmpty) {
      showAppToast(context, 'Host and username are required',
          kind: ToastKind.warning);
      return;
    }
    if (protocol == SessionProtocol.rdp && password.text.isEmpty) {
      showAppToast(context, 'RDP password is required',
          kind: ToastKind.warning);
      return;
    }
    Navigator.pop(context, (
      session: SavedSession(
        name: name.text.trim().isEmpty
            ? (protocol == SessionProtocol.ssh ? 'SSH session' : 'RDP session')
            : name.text.trim(),
        host: address,
        port: int.tryParse(port.text) ??
            (protocol == SessionProtocol.ssh ? 22 : 3389),
        username: user.text.trim(),
        protocol: protocol,
        tabColor: tabColor,
      ),
      password: password.text,
      savePassword: savePassword,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'New session' : 'Edit session'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
          SegmentedButton<SessionProtocol>(
            segments: const [
              ButtonSegment(
                  value: SessionProtocol.rdp,
                  label: Text('RDP'),
                  icon: Icon(Icons.desktop_windows)),
              ButtonSegment(
                  value: SessionProtocol.ssh,
                  label: Text('SSH'),
                  icon: Icon(Icons.terminal)),
            ],
            selected: {protocol},
            onSelectionChanged: (value) => _selectProtocol(value.first),
          ),
          const SizedBox(height: 16),
          TextField(
              controller: host,
              decoration: const InputDecoration(labelText: 'Host')),
          const SizedBox(height: 14),
          TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Session name')),
          const SizedBox(height: 14),
          TextField(
              controller: user,
              decoration: const InputDecoration(labelText: 'Username')),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: port,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Port'))),
            const SizedBox(width: 14),
            Expanded(
              child: TextField(
                controller: password,
                obscureText: !showPassword,
                decoration: InputDecoration(
                  labelText: protocol == SessionProtocol.ssh
                      ? 'Password (optional)'
                      : 'Password',
                  suffixIcon: IconButton(
                    tooltip: showPassword ? 'Hide password' : 'Show password',
                    onPressed: () =>
                        setState(() => showPassword = !showPassword),
                    icon: Icon(
                        showPassword ? Icons.visibility_off : Icons.visibility),
                  ),
                ),
            ),
          ),
        ]),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: savePassword,
            mouseCursor: WidgetStateMouseCursor.clickable,
            onChanged: (value) => setState(() => savePassword = value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Save password'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Tab color',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Tooltip(
                message: 'Protocol default',
                child: InkWell(
                  onTap: () => setState(() => tabColor = null),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: tabColor == null ? Moba.green : Colors.white24,
                        width: tabColor == null ? 2 : 1,
                      ),
                      gradient: const SweepGradient(colors: [
                        Color(0xFFE6B422),
                        Color(0xFF5B9BD5),
                        Color(0xFF3D9970),
                        Color(0xFFE06C75),
                        Color(0xFFE6B422),
                      ]),
                    ),
                    child: tabColor == null
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : null,
                  ),
                ),
              ),
              for (final c in SavedSession.tabPalette)
                Tooltip(
                  message:
                      '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                  child: InkWell(
                    onTap: () => setState(() => tabColor = c.toARGB32()),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: tabColor == c.toARGB32()
                              ? Colors.white
                              : Colors.white24,
                          width: tabColor == c.toARGB32() ? 2.5 : 1,
                        ),
                        boxShadow: tabColor == c.toARGB32()
                            ? [
                                BoxShadow(
                                  color: c.withValues(alpha: 0.55),
                                  blurRadius: 8,
                                )
                              ]
                            : null,
                      ),
                      child: tabColor == c.toARGB32()
                          ? const Icon(Icons.check,
                              size: 14, color: Colors.white)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.login),
            label: Text(widget.initial == null ? 'Connect' : 'Save')),
      ],
    );
  }
}

class _SessionSurface extends StatelessWidget {
  const _SessionSurface({
    required this.snapshot,
    required this.session,
    required this.terminal,
    required this.onDisconnect,
    this.onRetry,
    this.onToggleFiles,
    this.filesOpen = false,
    this.fetchSystemStats,
  });

  final ConnectionSnapshot snapshot;
  final SavedSession? session;
  final Terminal? terminal;
  final VoidCallback onDisconnect;
  final VoidCallback? onRetry;
  final VoidCallback? onToggleFiles;
  final bool filesOpen;
  final Future<RemoteSystemStats> Function()? fetchSystemStats;

  @override
  Widget build(BuildContext context) {
    final kind = snapshot.protocol == SessionProtocol.ssh ? 'SSH' : 'RDP';
    final showTerminal = snapshot.phase == ConnectionPhase.connected &&
        snapshot.protocol == SessionProtocol.ssh &&
        terminal != null;
    if (snapshot.phase == ConnectionPhase.idle) {
      return const ColoredBox(color: Moba.terminal, child: SizedBox.expand());
    }
    if (showTerminal) {
      return ColoredBox(
        color: Moba.terminal,
        child: SshTerminalPane(
          terminal: terminal!,
          onToggleFiles: onToggleFiles,
          filesOpen: filesOpen,
          fetchSystemStats: fetchSystemStats,
        ),
      );
    }
    return ColoredBox(
      color: snapshot.protocol == SessionProtocol.rdp
          ? const Color(0xFF1D4770)
          : Moba.terminal,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (snapshot.phase == ConnectionPhase.connecting) ...[
              const CircularProgressIndicator(color: Moba.green),
              const SizedBox(height: 18),
              Text('Connecting $kind to ${snapshot.host}:${snapshot.port}...'),
            ] else if (snapshot.phase == ConnectionPhase.failed) ...[
              const Icon(Icons.error_outline,
                  size: 64, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(snapshot.error ?? 'Connection failed',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              if (onRetry != null)
                FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry')),
            ] else ...[
              Icon(
                  snapshot.protocol == SessionProtocol.ssh
                      ? Icons.terminal
                      : Icons.desktop_windows,
                  size: 64,
                  color: Colors.white70),
              const SizedBox(height: 12),
              Text('$kind session is active'),
              if (snapshot.protocol == SessionProtocol.rdp)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Remote desktop opened in FreeRDP',
                      style: TextStyle(color: Colors.white70)),
                ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _NamePromptDialog extends StatefulWidget {
  const _NamePromptDialog({
    required this.title,
    required this.label,
    required this.confirmLabel,
    this.initialValue = '',
  });

  final String title;
  final String label;
  final String confirmLabel;
  final String initialValue;

  @override
  State<_NamePromptDialog> createState() => _NamePromptDialogState();
}

class _NamePromptDialogState extends State<_NamePromptDialog> {
  late final TextEditingController controller =
      TextEditingController(text: widget.initialValue);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: (_) => Navigator.pop(context, controller.text.trim()),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(widget.confirmLabel)),
      ],
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialName});
  final String initialName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController controller =
      TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename'),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New name'),
          onSubmitted: (_) => Navigator.pop(context, controller.text.trim()),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Rename')),
      ],
    );
  }
}

class _PermissionsDialog extends StatefulWidget {
  const _PermissionsDialog({
    required this.initialMode,
    required this.itemCount,
    required this.suggestRecursive,
  });

  final String initialMode;
  final int itemCount;
  final bool suggestRecursive;

  @override
  State<_PermissionsDialog> createState() => _PermissionsDialogState();
}

class _PermissionsDialogState extends State<_PermissionsDialog> {
  late final TextEditingController modeController;
  late bool ownerR, ownerW, ownerX;
  late bool groupR, groupW, groupX;
  late bool otherR, otherW, otherX;
  late bool recursive;
  bool syncing = false;

  @override
  void initState() {
    super.initState();
    final mode = _normalize(widget.initialMode);
    modeController = TextEditingController(text: mode);
    _applyOctal(mode);
    recursive = widget.suggestRecursive;
    modeController.addListener(_fromOctalField);
  }

  @override
  void dispose() {
    modeController.dispose();
    super.dispose();
  }

  String get currentMode {
    final value = (ownerR ? 0x100 : 0) |
        (ownerW ? 0x080 : 0) |
        (ownerX ? 0x040 : 0) |
        (groupR ? 0x020 : 0) |
        (groupW ? 0x010 : 0) |
        (groupX ? 0x008 : 0) |
        (otherR ? 0x004 : 0) |
        (otherW ? 0x002 : 0) |
        (otherX ? 0x001 : 0);
    return value.toRadixString(8).padLeft(3, '0');
  }

  String _normalize(String raw) {
    final trimmed = raw.trim();
    if (RegExp(r'^[0-7]{4}$').hasMatch(trimmed)) return trimmed.substring(1);
    if (RegExp(r'^[0-7]{3}$').hasMatch(trimmed)) return trimmed;
    return '644';
  }

  void _applyOctal(String mode) {
    final value = int.tryParse(mode, radix: 8) ?? 420;
    ownerR = (value & 0x100) != 0;
    ownerW = (value & 0x080) != 0;
    ownerX = (value & 0x040) != 0;
    groupR = (value & 0x020) != 0;
    groupW = (value & 0x010) != 0;
    groupX = (value & 0x008) != 0;
    otherR = (value & 0x004) != 0;
    otherW = (value & 0x002) != 0;
    otherX = (value & 0x001) != 0;
  }

  void _fromOctalField() {
    if (syncing) return;
    final text = modeController.text.trim();
    if (!RegExp(r'^[0-7]{3}$').hasMatch(text)) return;
    setState(() => _applyOctal(text));
  }

  void _fromChecks() {
    final text = currentMode;
    syncing = true;
    modeController.text = text;
    modeController.selection = TextSelection.collapsed(offset: text.length);
    syncing = false;
    setState(() {});
  }

  void _applyPreset(String mode) {
    syncing = true;
    modeController.text = mode;
    syncing = false;
    setState(() => _applyOctal(mode));
  }

  Widget _bit(
    String label,
    String hint,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Expanded(
      child: InkWell(
        onTap: () => onChanged(!value),
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: value ? Moba.green.withValues(alpha: 0.22) : const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: value ? Moba.green : const Color(0xFF444444),
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: value ? Moba.green : Colors.white54,
                ),
              ),
              Text(
                hint,
                style: TextStyle(
                  fontSize: 9,
                  color: value ? Colors.white70 : Colors.white38,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roleRow({
    required String title,
    required IconData icon,
    required bool r,
    required bool w,
    required bool x,
    required void Function(bool, bool, bool) onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: Moba.green),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              _bit('R', 'Read', r, (v) => onChanged(v, w, x)),
              const SizedBox(width: 5),
              _bit('W', 'Write', w, (v) => onChanged(r, v, x)),
              const SizedBox(width: 5),
              _bit('X', 'Exec', x, (v) => onChanged(r, w, v)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _preset(String mode, String label) {
    final selected = currentMode == mode;
    return Expanded(
      child: InkWell(
        onTap: () => _applyPreset(mode),
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: selected ? Moba.green.withValues(alpha: 0.2) : Moba.toolbar,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? Moba.green : const Color(0xFF4A4A4A),
            ),
          ),
          child: Column(
            children: [
              Text(mode,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? Moba.green : Colors.white,
                  )),
              Text(label,
                  style: TextStyle(
                    fontSize: 9,
                    color: selected ? Colors.white70 : Colors.white38,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  void _apply() {
    final mode = _normalize(modeController.text);
    if (!RegExp(r'^[0-7]{3}$').hasMatch(mode)) return;
    Navigator.pop(context, (mode: mode, recursive: recursive));
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.itemCount == 1
        ? 'Permissions'
        : 'Permissions · ${widget.itemCount} items';
    final maxBodyHeight = MediaQuery.sizeOf(context).height * 0.72;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Container(
        width: 360,
        constraints: BoxConstraints(maxHeight: maxBodyHeight),
        decoration: BoxDecoration(
          color: Moba.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF3A3A3A)),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, 10)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF2A3A32), Color(0xFF1E1E1E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Moba.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.lock_outline, size: 16, color: Moba.green),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                        const Text('Owner / Group / Others',
                            style: TextStyle(fontSize: 10, color: Colors.white54)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: Moba.green.withValues(alpha: 0.45)),
                    ),
                    child: Text(
                      currentMode,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Moba.green,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Quick presets',
                        style: TextStyle(fontSize: 10, color: Colors.white54)),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        _preset('755', 'Folders'),
                        const SizedBox(width: 5),
                        _preset('644', 'Files'),
                        const SizedBox(width: 5),
                        _preset('700', 'Private'),
                        const SizedBox(width: 5),
                        _preset('777', 'Open'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: modeController,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        labelText: 'Octal mode',
                        hintText: '755',
                        filled: true,
                        fillColor: const Color(0xFF252525),
                        prefixIcon: const Icon(Icons.tag, size: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF444444)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF444444)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Moba.green),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _roleRow(
                      title: 'Owner',
                      icon: Icons.person_outline,
                      r: ownerR,
                      w: ownerW,
                      x: ownerX,
                      onChanged: (r, w, x) {
                        ownerR = r;
                        ownerW = w;
                        ownerX = x;
                        _fromChecks();
                      },
                    ),
                    _roleRow(
                      title: 'Group',
                      icon: Icons.groups_outlined,
                      r: groupR,
                      w: groupW,
                      x: groupX,
                      onChanged: (r, w, x) {
                        groupR = r;
                        groupW = w;
                        groupX = x;
                        _fromChecks();
                      },
                    ),
                    _roleRow(
                      title: 'Others',
                      icon: Icons.public_outlined,
                      r: otherR,
                      w: otherW,
                      x: otherX,
                      onChanged: (r, w, x) {
                        otherR = r;
                        otherW = w;
                        otherX = x;
                        _fromChecks();
                      },
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                      decoration: BoxDecoration(
                        color: const Color(0xFF252525),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF3A3A3A)),
                      ),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        value: recursive,
                        activeThumbColor: Moba.green,
                        onChanged: (value) => setState(() => recursive = value),
                        secondary: Icon(
                          Icons.account_tree_outlined,
                          size: 18,
                          color: recursive ? Moba.green : Colors.white54,
                        ),
                        title: const Text('Recursive',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 12)),
                        subtitle: const Text('chmod -R on subfolders/files',
                            style: TextStyle(fontSize: 10)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: const BoxDecoration(color: Color(0x22101010)),
              child: Row(
                children: [
                  Text('chmod ${recursive ? '-R ' : ''}$currentMode',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Colors.white38,
                      )),
                  const Spacer(),
                  TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: _apply,
                    icon: const Icon(Icons.check, size: 15),
                    label: const Text('Apply'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

