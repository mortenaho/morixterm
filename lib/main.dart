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
import 'models/saved_session.dart';
import 'services/app_log.dart';
import 'services/rdp_session_service.dart';
import 'services/session_storage.dart';
import 'services/ssh_session_service.dart';
import 'widgets/morixtrem_logo.dart';
import 'widgets/ssh_terminal_pane.dart';

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
    showMessage('جلسه حذف شد');
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Moba.toolbar));
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
      showMessage('این پوشه از قبل وجود دارد');
      return;
    }
    final previous = folders;
    setState(() => folders = {...folders, value});
    try {
      await sessionStorage.saveFolders(folders);
      if (mounted) showMessage('پوشه ایجاد شد؛ session را روی آن بکشید');
    } catch (error) {
      if (mounted) {
        setState(() => folders = previous);
        showMessage('ساخت پوشه ناموفق بود: $error');
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
      if (mounted)
        showMessage(folder == null
            ? 'session به بخش بدون پوشه منتقل شد'
            : 'session به پوشهٔ $folder منتقل شد');
    } catch (error) {
      if (mounted) {
        setState(() => sessions = previous);
        showMessage('جابجایی session ناموفق بود: $error');
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
      showMessage('A folder with this name already exists');
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
      if (mounted) showMessage('Folder renamed to $value');
    } catch (error) {
      if (mounted) {
        setState(() {
          folders = previousFolders;
          sessions = previousSessions;
          collapsedFolders
            ..clear()
            ..addAll(previousCollapsed);
        });
        showMessage('Could not rename folder: $error');
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
      showMessage(count == 0
          ? 'Folder deleted'
          : 'Folder deleted. Sessions moved to No folder.');
    }
  }

  void _watchLive(LiveSession live) {
    final changes = live.ssh?.changes ?? live.rdp?.changes;
    live.subscription = changes?.listen((_) {
      if (mounted) setState(() {});
    });
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
      } on RdpException catch (error) {
        if (mounted) showMessage(error.message);
      } on SshException catch (error) {
        if (mounted) showMessage(error.message);
      } catch (error) {
        if (mounted) showMessage('اتصال ناموفق بود: $error');
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
    if (mounted) showMessage('اتصال قطع شد');
  }

  Future<void> _openFilesPane() async {
    final live = focused;
    await AppLog.line(
        'files pane focused=${live?.bookmark.name} ssh=$sshConnected rdp=$rdpConnected');
    if (live == null || !live.connected) {
      showMessage('اول به یک جلسه SSH یا RDP وصل شوید، بعد Files را باز کنید');
      return;
    }
    setState(() => pane = _Pane.files);
    if (live.explorerPath.isEmpty) {
      try {
        final start = live.isSsh
            ? await live.ssh!.homeDir()
            : RdpSessionService.sharePath;
        if (!mounted) return;
        live.explorerPath = start;
      } catch (error) {
        if (mounted) showMessage('خواندن پوشه خانگی ناموفق بود: $error');
        return;
      }
    }
    await _refreshFiles();
  }

  Future<void> _refreshFiles() async {
    final live = focused;
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
      if (mounted) showMessage('خواندن فایل‌ها ناموفق بود: $error');
    } finally {
      if (mounted) setState(() => live.explorerBusy = false);
    }
  }

  Future<void> _openExplorerPath(String path) async {
    final live = focused;
    if (live == null) return;
    if (!live.isSsh && !path.startsWith(RdpSessionService.sharePath)) {
      path = RdpSessionService.sharePath;
    }
    setState(() {
      live.explorerPath = path;
      live.selectedPaths.clear();
    });
    await _refreshFiles();
  }

  Future<void> _goExplorerUp() async {
    final live = focused;
    if (live == null || live.explorerPath.isEmpty) return;
    if (!live.isSsh && live.explorerPath == RdpSessionService.sharePath) return;
    if (live.isSsh && live.explorerPath == '/') return;
    await _openExplorerPath(RemoteEntry.parent(live.explorerPath));
  }

  void _selectEntry(RemoteEntry entry, {required bool toggle}) {
    final live = focused;
    if (live == null) return;
    setState(() {
      if (toggle) {
        if (!live.selectedPaths.remove(entry.path))
          live.selectedPaths.add(entry.path);
      } else {
        live.selectedPaths
          ..clear()
          ..add(entry.path);
      }
    });
  }

  void _copySelection({required bool cut}) {
    final live = focused;
    if (live == null || live.selectedPaths.isEmpty) {
      showMessage('اول یک فایل یا پوشه را انتخاب کنید');
      return;
    }
    setState(() {
      live.clipboard = FileClipboard(
          paths: live.selectedPaths.toList(),
          cut: cut,
          sourceDir: live.explorerPath);
    });
    showMessage(cut
        ? 'بریده شد — به پوشه مقصد بروید و Paste کنید'
        : 'کپی شد — به پوشه مقصد بروید و Paste کنید');
  }

  Future<void> _pasteClipboard() async {
    final live = focused;
    final clip = live?.clipboard;
    if (live == null || clip == null || clip.isEmpty) {
      showMessage('چیزی برای چسباندن نیست');
      return;
    }
    final dest = live.explorerPath;
    final sources = clip.paths
        .where((path) => RemoteEntry.parent(path) != dest && path != dest)
        .toList();
    if (sources.isEmpty) {
      showMessage('به پوشه دیگری بروید و بعد Paste کنید');
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
      if (mounted) showMessage(clip.cut ? 'منتقل شد' : 'کپی شد');
      await _refreshFiles();
    } catch (error) {
      await AppLog.line('paste failed: $error');
      if (mounted) showMessage('عملیات فایل ناموفق بود: $error');
    } finally {
      if (mounted) setState(() => live.explorerBusy = false);
    }
  }

  Future<void> _createRemoteFolder() async {
    final live = focused;
    if (live == null || !live.connected) {
      showMessage('Connect a session first');
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
      if (mounted) showMessage('Folder created');
      await _refreshFiles();
    } catch (error) {
      await AppLog.line('mkdir failed: $error');
      if (mounted) showMessage('Could not create folder: $error');
    } finally {
      if (mounted) setState(() => live.explorerBusy = false);
    }
  }

  Future<void> _renameSelection() async {
    final live = focused;
    if (live == null || !live.connected) {
      showMessage('Connect a session first');
      return;
    }
    if (live.selectedPaths.length != 1) {
      showMessage('Select exactly one item to rename');
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
      if (mounted) showMessage('Renamed');
      await _refreshFiles();
    } catch (error) {
      await AppLog.line('rename failed: $error');
      if (mounted) showMessage('Rename failed: $error');
    } finally {
      if (mounted) setState(() => live.explorerBusy = false);
    }
  }

  Future<void> _chmodSelection() async {
    final live = focused;
    if (live == null || !live.connected) {
      showMessage('Connect a session first');
      return;
    }
    if (live.selectedPaths.isEmpty) {
      showMessage('Select a file or folder first');
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
        await live.ssh!.chmodRemote(paths, mode: result.mode, recursive: result.recursive);
      } else {
        await live.rdp!.chmodShared(paths, mode: result.mode, recursive: result.recursive);
      }
      if (mounted) {
        showMessage(result.recursive
            ? 'Permissions ${result.mode} applied recursively'
            : 'Permissions ${result.mode} applied');
      }
      await _refreshFiles();
    } catch (error) {
      await AppLog.line('chmod failed: $error');
      if (mounted) showMessage('Permission change failed: $error');
    } finally {
      if (mounted) setState(() => live.explorerBusy = false);
    }
  }

  Future<void> _pickAndUpload() async {
    final live = focused;
    await AppLog.line(
        'upload click ssh=$sshConnected rdp=$rdpConnected path=${live?.explorerPath}');
    if (live == null || !live.connected) {
      showMessage('اول به یک جلسه SSH یا RDP وصل شوید');
      return;
    }
    final file = await openFile(confirmButtonText: 'انتخاب');
    if (file == null) return;
    setState(() => live.explorerBusy = true);
    try {
      if (live.isSsh) {
        await live.ssh!.uploadFile(file.path,
            remoteDir: live.explorerPath.isEmpty ? '.' : live.explorerPath);
        if (mounted) showMessage('فایل ${file.name} با SCP ارسال شد');
      } else {
        await live.rdp!.shareLocalFile(file.path, destDir: live.explorerPath);
        if (mounted) showMessage('فایل در درایو اشتراکی قرار گرفت');
      }
      await _refreshFiles();
    } catch (error) {
      await AppLog.line('upload failed: $error');
      if (mounted) showMessage('ارسال فایل ناموفق بود: $error');
    } finally {
      if (mounted) setState(() => live.explorerBusy = false);
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
    showMessage('تنظیمات session ذخیره شد');
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
                      ),
                      Expanded(
                        child: IndexedStack(
                          index: paneIndex,
                          children: [
                            const _WelcomePane(),
                            _FilesPane(
                              ssh: sshConnected,
                              rdp: rdpConnected,
                              path: live?.explorerPath ?? '',
                              entries: live?.explorerEntries ?? const [],
                              selectedPaths: live?.selectedPaths ?? {},
                              clipboard: live?.clipboard,
                              busy: live?.explorerBusy ?? false,
                              canGoUp: live != null &&
                                  live.explorerPath.isNotEmpty &&
                                  live.explorerPath != '/' &&
                                  !(!live.isSsh &&
                                      live.explorerPath ==
                                          RdpSessionService.sharePath),
                              onOpen: _openExplorerPath,
                              onUp: _goExplorerUp,
                              onSelect: _selectEntry,
                              onCopy: () => _copySelection(cut: false),
                              onCut: () => _copySelection(cut: true),
                              onPaste: _pasteClipboard,
                              onUpload: _pickAndUpload,
                              onNewFolder: _createRemoteFolder,
                              onRename: _renameSelection,
                              onPermissions: _chmodSelection,
                              onRefresh: _refreshFiles,
                            ),
                            ...openSessions.map((item) => _SessionSurface(
                                  key: ValueKey(item.id),
                                  snapshot: item.snapshot,
                                  session: item.bookmark,
                                  terminal: item.terminal,
                                  onDisconnect: () => _closeLive(item),
                                  onRetry: () => _connectSession(item.bookmark,
                                      prompt: true),
                                )),
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
        _ToolBtn(
            icon: Icons.info_outline,
            label: 'About',
            color: Colors.lightBlueAccent,
            onTap: onAbout),
        _ToolBtn(icon: Icons.fullscreen, label: 'Fullscreen', onTap: () {}),
        _ToolBtn(
          icon: Icons.link_off,
          label: 'Stop',
          color: connected ? Colors.redAccent : Colors.white38,
          onTap: onDisconnect,
        ),
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
  });
  final _Pane pane;
  final List<LiveSession> openSessions;
  final String? focusedId;
  final VoidCallback onHome;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;
  final VoidCallback onFiles;

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
                  color: live.isSsh
                      ? const Color(0xFF3A3320)
                      : const Color(0xFF1D4770),
                  onTap: () => onSelect(live.id),
                  onClose: () => onClose(live.id),
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
  const _Tab(
      {required this.label,
      required this.selected,
      required this.onTap,
      this.color,
      this.onClose});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onClose;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      mouseCursor: WidgetStateMouseCursor.clickable,
      child: Container(
        padding: EdgeInsets.only(left: 12, right: onClose == null ? 14 : 4),
        alignment: Alignment.center,
        color:
            selected ? (color ?? const Color(0xFF3A3A3A)) : Colors.transparent,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
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

class _WelcomePane extends StatelessWidget {
  const _WelcomePane();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Moba.terminal,
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MorixtermWordmark(logoSize: 64),
              const SizedBox(height: 18),
              Text(
                [
                  'SSH / RDP client',
                  '',
                  '  Session     create SSH or RDP connection',
                  '  Files       browse folders, copy/cut/paste, SCP upload',
                  '  Several SSH and RDP sessions can stay open together',
                ].join('\n'),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  height: 1.45,
                  color: Color(0xFF9CDCFE),
                ),
              ),
            ],
          ),
        ),
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
  });

  final bool ssh;
  final bool rdp;
  final String path;
  final List<RemoteEntry> entries;
  final Set<String> selectedPaths;
  final FileClipboard? clipboard;
  final bool busy;
  final bool canGoUp;
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
          autofocus: true,
          child: ColoredBox(
            color: const Color(0xFF1A1A1A),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 36,
                    color: Moba.toolbar,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
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
                      const VerticalDivider(width: 16, color: Colors.white24),
                      _ExplorerBtn(
                          icon: Icons.copy,
                          label: 'Copy',
                          onTap: ready && hasSelection ? onCopy : null),
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
                          onTap: ready && canRename ? onRename : null),
                      _ExplorerBtn(
                          icon: Icons.lock_outline,
                          label: 'Permissions',
                          onTap: ready && hasSelection ? onPermissions : null),
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
                    height: 28,
                    color: const Color(0xFF2A2A2A),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      ready
                          ? RemoteEntry.displayPath(path.isEmpty ? '/' : path)
                          : 'not connected',
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: Color(0xFF9CDCFE)),
                    ),
                  ),
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
                            child: Text('اول یک جلسه را وصل کنید',
                                style: TextStyle(color: Colors.white38)))
                        : Stack(children: [
                            GestureDetector(
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
                                            icon: Icons.create_new_folder_outlined,
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
                                        case 'refresh':
                                          onRefresh();
                                      }
                                    }
                                  : null,
                              child: ListView.builder(
                              itemCount: entries.length + (canGoUp ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (canGoUp && index == 0) {
                                  return _FileRow(
                                    name: '..',
                                    directory: true,
                                    selected: false,
                                    cut: false,
                                    onTap: onUp,
                                    onDoubleTap: onUp,
                                    onNewFolder: onNewFolder,
                                    onPaste: canPaste ? onPaste : null,
                                  );
                                }
                                final entry =
                                    entries[index - (canGoUp ? 1 : 0)];
                                final selected =
                                    selectedPaths.contains(entry.path);
                                final cut = clipboard != null &&
                                    clipboard!.cut &&
                                    clipboard!.paths.contains(entry.path);
                                return _FileRow(
                                  name: entry.name,
                                  directory: entry.isDirectory,
                                  selected: selected,
                                  cut: cut,
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
                                );
                              },
                            ),
                            ),
                            if (busy)
                              const ColoredBox(
                                  color: Color(0x33000000),
                                  child: Center(
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))),
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
    this.onDoubleTap,
    this.onCopy,
    this.onCut,
    this.onPaste,
    this.onNewFolder,
    this.onRename,
    this.onPermissions,
  });

  final String name;
  final bool directory;
  final bool selected;
  final bool cut;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onCopy;
  final VoidCallback? onCut;
  final VoidCallback? onPaste;
  final VoidCallback? onNewFolder;
  final VoidCallback? onRename;
  final VoidCallback? onPermissions;

  IconData get _icon {
    if (directory) return Icons.folder;
    final lower = name.toLowerCase();
    if (lower.endsWith('.html') || lower.endsWith('.htm'))
      return Icons.language;
    if (lower.endsWith('.sh') || lower.endsWith('.bash')) return Icons.terminal;
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    final hasMenu = onCopy != null ||
        onCut != null ||
        onPaste != null ||
        onNewFolder != null ||
        onRename != null ||
        onPermissions != null;
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
                case 'rename':
                  onRename?.call();
                case 'chmod':
                  onPermissions?.call();
              }
            },
      mouseCursor: WidgetStateMouseCursor.clickable,
      child: Container(
        color: selected ? Moba.green.withValues(alpha: 0.28) : null,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(children: [
          Icon(_icon,
              size: 18,
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
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Host and username are required')));
      return;
    }
    if (protocol == SessionProtocol.rdp && password.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('RDP password is required')));
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

class _SessionSurface extends StatelessWidget {
  const _SessionSurface({
    super.key,
    required this.snapshot,
    required this.session,
    required this.terminal,
    required this.onDisconnect,
    this.onRetry,
  });

  final ConnectionSnapshot snapshot;
  final SavedSession? session;
  final Terminal? terminal;
  final VoidCallback onDisconnect;
  final VoidCallback? onRetry;

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
        child: SshTerminalPane(terminal: terminal!),
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
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: value ? Moba.green.withValues(alpha: 0.22) : const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: value ? Moba.green : const Color(0xFF444444),
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: value ? Moba.green : Colors.white54,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: TextStyle(
                  fontSize: 10,
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
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Moba.green),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _bit('R', 'Read', r, (v) => onChanged(v, w, x)),
              const SizedBox(width: 8),
              _bit('W', 'Write', w, (v) => onChanged(r, v, x)),
              const SizedBox(width: 8),
              _bit('X', 'Execute', x, (v) => onChanged(r, w, v)),
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
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Moba.green.withValues(alpha: 0.2) : Moba.toolbar,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? Moba.green : const Color(0xFF4A4A4A),
            ),
          ),
          child: Column(
            children: [
              Text(mode,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    color: selected ? Moba.green : Colors.white,
                  )),
              Text(label,
                  style: TextStyle(
                    fontSize: 10,
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

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 460,
        decoration: BoxDecoration(
          color: Moba.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF3A3A3A)),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 28, offset: Offset(0, 14)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
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
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Moba.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.lock_outline, color: Moba.green),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        const Text('Unix file mode · Owner / Group / Others',
                            style: TextStyle(fontSize: 12, color: Colors.white54)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Moba.green.withValues(alpha: 0.45)),
                    ),
                    child: Text(
                      currentMode,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Moba.green,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Quick presets',
                      style: TextStyle(fontSize: 12, color: Colors.white54)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _preset('755', 'Folders'),
                      const SizedBox(width: 8),
                      _preset('644', 'Files'),
                      const SizedBox(width: 8),
                      _preset('700', 'Private'),
                      const SizedBox(width: 8),
                      _preset('777', 'Open'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: modeController,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Octal mode',
                      hintText: '755',
                      filled: true,
                      fillColor: const Color(0xFF252525),
                      prefixIcon: const Icon(Icons.tag, size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF444444)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF444444)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Moba.green),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF252525),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF3A3A3A)),
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: recursive,
                      activeThumbColor: Moba.green,
                      onChanged: (value) => setState(() => recursive = value),
                      secondary: Icon(
                        Icons.account_tree_outlined,
                        color: recursive ? Moba.green : Colors.white54,
                      ),
                      title: const Text('Recursive',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text('Apply to all subfolders and files (chmod -R)',
                          style: TextStyle(fontSize: 11)),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              decoration: const BoxDecoration(color: Color(0x22101010)),
              child: Row(
                children: [
                  Text('chmod ${recursive ? '-R ' : ''}$currentMode',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.white38,
                      )),
                  const Spacer(),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _apply,
                    icon: const Icon(Icons.check, size: 18),
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

