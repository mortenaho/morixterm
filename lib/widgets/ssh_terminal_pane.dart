import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../models/remote_system_stats.dart';
import '../services/session_storage.dart';

class SshTerminalPane extends StatefulWidget {
  const SshTerminalPane({
    super.key,
    required this.terminal,
    this.onToggleFiles,
    this.filesOpen = false,
    this.fetchSystemStats,
  });

  final Terminal terminal;
  final VoidCallback? onToggleFiles;
  final bool filesOpen;
  final Future<RemoteSystemStats> Function()? fetchSystemStats;

  @override
  State<SshTerminalPane> createState() => _SshTerminalPaneState();
}

class _SshTerminalPaneState extends State<SshTerminalPane> {
  late final TerminalController _controller;
  late final FocusNode _focusNode;
  final SessionStorage _storage = SessionStorage();
  var _fontSize = 13.0;
  var _themeMode = _TerminalThemeMode.morixterm;
  var _monitorEnabled = true;
  var _monitorLoading = false;
  RemoteSystemStats? _stats;
  RemoteSystemStats? _prevStats;
  String? _monitorError;
  Timer? _monitorTimer;
  var _polling = false;

  TerminalTheme get _theme {
    switch (_themeMode) {
      case _TerminalThemeMode.morixterm:
        return TerminalThemes.defaultTheme;
      case _TerminalThemeMode.black:
        return TerminalThemes.whiteOnBlack;
      case _TerminalThemeMode.amber:
        return const TerminalTheme(
          cursor: Color(0xFFE6B422),
          selection: Color(0x886B5B18),
          foreground: Color(0xFFF4D58D),
          background: Color(0xFF17130A),
          black: Color(0xFF17130A),
          white: Color(0xFFF4D58D),
          red: Color(0xFFD95D39),
          green: Color(0xFF8FBC55),
          yellow: Color(0xFFE6B422),
          blue: Color(0xFF6FA8DC),
          magenta: Color(0xFFC678DD),
          cyan: Color(0xFF56B6C2),
          brightBlack: Color(0xFF665C54),
          brightRed: Color(0xFFFF7B72),
          brightGreen: Color(0xFFA8D477),
          brightYellow: Color(0xFFFFD580),
          brightBlue: Color(0xFF8CC8FF),
          brightMagenta: Color(0xFFE2A6F5),
          brightCyan: Color(0xFF8BE9FD),
          brightWhite: Color(0xFFFFF4D6),
          searchHitBackground: Color(0xFFE6B422),
          searchHitBackgroundCurrent: Color(0xFFFFF4D6),
          searchHitForeground: Color(0xFF17130A),
        );
      case _TerminalThemeMode.dracula:
        return const TerminalTheme(
          cursor: Color(0xFFF8F8F2),
          selection: Color(0x665A4E7C),
          foreground: Color(0xFFF8F8F2),
          background: Color(0xFF282A36),
          black: Color(0xFF21222C),
          white: Color(0xFFF8F8F2),
          red: Color(0xFFFF5555),
          green: Color(0xFF50FA7B),
          yellow: Color(0xFFF1FA8C),
          blue: Color(0xFFBD93F9),
          magenta: Color(0xFFFF79C6),
          cyan: Color(0xFF8BE9FD),
          brightBlack: Color(0xFF6272A4),
          brightRed: Color(0xFFFF6E6E),
          brightGreen: Color(0xFF69FF94),
          brightYellow: Color(0xFFFFFFA5),
          brightBlue: Color(0xFFD6ACFF),
          brightMagenta: Color(0xFFFF92DF),
          brightCyan: Color(0xFFA4FFFF),
          brightWhite: Color(0xFFFFFFFF),
          searchHitBackground: Color(0xFFF1FA8C),
          searchHitBackgroundCurrent: Color(0xFFFF79C6),
          searchHitForeground: Color(0xFF282A36),
        );
      case _TerminalThemeMode.light:
        return const TerminalTheme(
          cursor: Color(0xFF243447),
          selection: Color(0x553B82F6),
          foreground: Color(0xFF243447),
          background: Color(0xFFF4F7FB),
          black: Color(0xFF243447),
          white: Color(0xFFFFFFFF),
          red: Color(0xFFB42318),
          green: Color(0xFF067647),
          yellow: Color(0xFF8A6100),
          blue: Color(0xFF175CD3),
          magenta: Color(0xFF9E2A8A),
          cyan: Color(0xFF087F8C),
          brightBlack: Color(0xFF667085),
          brightRed: Color(0xFFD92D20),
          brightGreen: Color(0xFF039855),
          brightYellow: Color(0xFFB54708),
          brightBlue: Color(0xFF2E90FA),
          brightMagenta: Color(0xFFD444B8),
          brightCyan: Color(0xFF0E9FAD),
          brightWhite: Color(0xFF101828),
          searchHitBackground: Color(0xFFFFE08A),
          searchHitBackgroundCurrent: Color(0xFFFDB022),
          searchHitForeground: Color(0xFF243447),
        );
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = TerminalController();
    _focusNode = FocusNode(debugLabel: 'ssh-terminal');
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusTerminal());
    unawaited(_loadMonitorPreference());
  }

  @override
  void didUpdateWidget(covariant SshTerminalPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.terminal != widget.terminal ||
        oldWidget.filesOpen != widget.filesOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusTerminal());
    }
    if (oldWidget.fetchSystemStats != widget.fetchSystemStats) {
      _syncMonitorTimer();
    }
  }

  Future<void> _loadMonitorPreference() async {
    final enabled = await _storage.loadSystemMonitorEnabled();
    if (!mounted) return;
    setState(() => _monitorEnabled = enabled);
    _syncMonitorTimer();
  }

  void _syncMonitorTimer() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
    if (!_monitorEnabled || widget.fetchSystemStats == null) return;
    unawaited(_pollMonitor());
    _monitorTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_pollMonitor()),
    );
  }

  Future<void> _pollMonitor() async {
    final fetch = widget.fetchSystemStats;
    if (!_monitorEnabled || fetch == null || _polling) return;
    _polling = true;
    try {
      final next = await fetch();
      if (!mounted || !_monitorEnabled) return;
      setState(() {
        _prevStats = _stats;
        _stats = next;
        _monitorError = null;
        _monitorLoading = false;
      });
    } catch (error) {
      if (!mounted || !_monitorEnabled) return;
      setState(() {
        _monitorError = '$error';
        _monitorLoading = false;
      });
    } finally {
      _polling = false;
    }
  }

  Future<void> _toggleMonitor() async {
    final next = !_monitorEnabled;
    setState(() {
      _monitorEnabled = next;
      if (!next) {
        _stats = null;
        _prevStats = null;
        _monitorError = null;
      } else {
        _monitorLoading = true;
      }
    });
    await _storage.saveSystemMonitorEnabled(next);
    _syncMonitorTimer();
  }

  void _focusTerminal() {
    if (!mounted) return;
    if (!_focusNode.hasFocus) _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _monitorTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _zoom(int direction) {
    setState(() {
      _fontSize = (_fontSize + direction).clamp(9.0, 28.0);
    });
  }

  Future<void> _copySelection() async {
    final selection = _controller.selection;
    if (selection == null) return;
    await Clipboard.setData(ClipboardData(text: widget.terminal.buffer.getText(selection)));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) widget.terminal.paste(data!.text!);
  }

  void _selectAll() {
    _controller.setSelection(
      widget.terminal.buffer.createAnchor(0, 0),
      widget.terminal.buffer.createAnchor(widget.terminal.viewWidth, widget.terminal.buffer.height - 1),
      mode: SelectionMode.line,
    );
  }

  Future<void> _showSearch() async {
    final query = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final needle = query.text.trim().toLowerCase();
          final lines = widget.terminal.buffer
              .getText()
              .split('\n')
              .where((line) => needle.isEmpty || line.toLowerCase().contains(needle))
              .toList(growable: false);
          return AlertDialog(
            title: const Text('Search terminal output'),
            content: SizedBox(
              width: 720,
              height: 480,
              child: Column(
                children: [
                  TextField(
                    controller: query,
                    autofocus: true,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search logs, errors, paths...'),
                    onChanged: (_) => setDialogState(() {}),
                    onSubmitted: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: Text('${needle.isEmpty ? 0 : lines.length} matches')),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SelectionArea(
                      child: ListView.builder(
                        itemCount: lines.length,
                        itemBuilder: (context, index) => Text(
                          lines[index],
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
          );
        },
      ),
    );
    query.dispose();
  }

  Future<void> _showContextMenu(TapUpDetails details) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(details.globalPosition.dx, details.globalPosition.dy, details.globalPosition.dx + 1, details.globalPosition.dy + 1),
      items: const [
        PopupMenuItem(value: 'copy', child: Text('Copy selection')),
        PopupMenuItem(value: 'paste', child: Text('Paste')),
        PopupMenuItem(value: 'select', child: Text('Select all')),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'copy':
        await _copySelection();
      case 'paste':
        await _paste();
      case 'select':
        _selectAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = TerminalStyle(
      fontSize: _fontSize,
      fontFamily: 'Cascadia Mono',
      fontFamilyFallback: const [
        'Cascadia Code',
        'JetBrains Mono',
        'Noto Sans Mono',
        'Segoe UI Emoji',
        'monospace'
      ],
    );
    final canMonitor = widget.fetchSystemStats != null;
    return Column(
      children: [
        _TerminalToolbar(
          fontSize: _fontSize,
          themeMode: _themeMode,
          onCopy: _copySelection,
          onPaste: _paste,
          onSelectAll: _selectAll,
          onSearch: _showSearch,
          onZoom: _zoom,
          onThemeChanged: (value) => setState(() => _themeMode = value),
          onToggleFiles: widget.onToggleFiles,
          filesOpen: widget.filesOpen,
          onToggleMonitor: canMonitor ? _toggleMonitor : null,
          monitorEnabled: _monitorEnabled,
        ),
        Expanded(
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent &&
                  HardwareKeyboard.instance.isControlPressed) {
                _zoom(event.scrollDelta.dy < 0 ? 1 : -1);
              }
            },
            child: TerminalView(
              widget.terminal,
              key: ValueKey(_themeMode),
              controller: _controller,
              focusNode: _focusNode,
              theme: _theme,
              textStyle: style,
              padding: const EdgeInsets.all(10),
              autofocus: true,
              hardwareKeyboardOnly: true,
              simulateScroll: true,
              onSecondaryTapUp: (details, _) => _showContextMenu(details),
            ),
          ),
        ),
        if (canMonitor && _monitorEnabled)
          _SystemMonitorBar(
            stats: _stats,
            previous: _prevStats,
            loading: _monitorLoading && _stats == null,
            error: _monitorError,
            onHide: _toggleMonitor,
          ),
      ],
    );
  }
}

enum _TerminalThemeMode { morixterm, black, amber, dracula, light }

String _themeLabel(_TerminalThemeMode mode) {
  switch (mode) {
    case _TerminalThemeMode.morixterm:
      return 'MoriXterm';
    case _TerminalThemeMode.black:
      return 'Black & white';
    case _TerminalThemeMode.amber:
      return 'Amber DevOps';
    case _TerminalThemeMode.dracula:
      return 'Dracula';
    case _TerminalThemeMode.light:
      return 'Light';
  }
}

class _TerminalToolbar extends StatelessWidget {
  const _TerminalToolbar({
    required this.fontSize,
    required this.themeMode,
    required this.onCopy,
    required this.onPaste,
    required this.onSelectAll,
    required this.onSearch,
    required this.onZoom,
    required this.onThemeChanged,
    this.onToggleFiles,
    this.filesOpen = false,
    this.onToggleMonitor,
    this.monitorEnabled = false,
  });

  final double fontSize;
  final _TerminalThemeMode themeMode;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onSelectAll;
  final VoidCallback onSearch;
  final void Function(int) onZoom;
  final ValueChanged<_TerminalThemeMode> onThemeChanged;
  final VoidCallback? onToggleFiles;
  final bool filesOpen;
  final VoidCallback? onToggleMonitor;
  final bool monitorEnabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      color: const Color(0xFF323232),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          _Tool(icon: Icons.copy, tooltip: 'Copy (Ctrl+Shift+C)', onPressed: onCopy),
          _Tool(icon: Icons.content_paste, tooltip: 'Paste (Ctrl+V)', onPressed: onPaste),
          _Tool(icon: Icons.select_all, tooltip: 'Select all (Ctrl+A)', onPressed: onSelectAll),
          _Tool(icon: Icons.search, tooltip: 'Search output', onPressed: onSearch),
          const VerticalDivider(width: 12),
          _Tool(icon: Icons.remove, tooltip: 'Zoom out', onPressed: () => onZoom(-1)),
          SizedBox(width: 34, child: Center(child: Text('${fontSize.round()}', style: const TextStyle(fontSize: 11)))),
          _Tool(icon: Icons.add, tooltip: 'Zoom in', onPressed: () => onZoom(1)),
          PopupMenuButton<_TerminalThemeMode>(
            tooltip: 'Terminal theme',
            icon: const Icon(Icons.palette_outlined, size: 17),
            initialValue: themeMode,
            onSelected: onThemeChanged,
            itemBuilder: (context) => const [
              PopupMenuItem(value: _TerminalThemeMode.morixterm, child: Text('MoriXterm dark')),
              PopupMenuItem(value: _TerminalThemeMode.black, child: Text('Black & white')),
              PopupMenuItem(value: _TerminalThemeMode.amber, child: Text('Amber DevOps')),
              PopupMenuItem(value: _TerminalThemeMode.dracula, child: Text('Dracula')),
              PopupMenuItem(value: _TerminalThemeMode.light, child: Text('Light')),
            ],
          ),
          if (onToggleFiles != null) ...[
            const VerticalDivider(width: 12),
            _Tool(
              icon: filesOpen ? Icons.folder_off_outlined : Icons.folder_open,
              tooltip: filesOpen ? 'Hide files sidebar' : 'Show files sidebar',
              onPressed: onToggleFiles!,
              color: filesOpen ? const Color(0xFF3D9970) : null,
            ),
          ],
          if (onToggleMonitor != null) ...[
            _Tool(
              icon: Icons.monitor_heart_outlined,
              tooltip: monitorEnabled
                  ? 'Hide system monitor'
                  : 'Show system monitor',
              onPressed: onToggleMonitor!,
              color: monitorEnabled ? const Color(0xFF3D9970) : null,
            ),
          ],
          const Spacer(),
          Text('SSH • ${_themeLabel(themeMode)}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 17),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      splashRadius: 16,
      color: color ?? Colors.white70,
    );
  }
}

class _SystemMonitorBar extends StatelessWidget {
  const _SystemMonitorBar({
    required this.stats,
    required this.previous,
    required this.loading,
    required this.error,
    required this.onHide,
  });

  final RemoteSystemStats? stats;
  final RemoteSystemStats? previous;
  final bool loading;
  final String? error;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final cpu = stats?.cpuPercentSince(previous);
    final memFrac = stats?.memFraction;
    final diskFrac = stats?.diskFraction;

    return Material(
      color: const Color(0xFF1A1D24),
      child: Container(
        height: 30,
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF2E333C))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            const Icon(Icons.monitor_heart_outlined,
                size: 14, color: Color(0xFF3D9970)),
            const SizedBox(width: 8),
            if (loading && stats == null)
              const Text(
                'Reading remote system…',
                style: TextStyle(fontSize: 11, color: Colors.white54),
              )
            else if (error != null && stats == null)
              Expanded(
                child: Text(
                  'Monitor unavailable: $error',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Color(0xFFFF8A80)),
                ),
              )
            else if (stats != null) ...[
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _MetricChip(
                        label: 'CPU',
                        value: cpu == null ? '…' : '${cpu.round()}%',
                        fraction: cpu == null ? null : cpu / 100,
                        color: const Color(0xFF5B9BD5),
                      ),
                      const SizedBox(width: 14),
                      _MetricChip(
                        label: 'RAM',
                        value: memFrac == null
                            ? '…'
                            : '${_fmtGiB(stats!.memUsedKb)} / ${_fmtGiB(stats!.memTotalKb)}',
                        fraction: memFrac,
                        color: const Color(0xFFE6B422),
                      ),
                      const SizedBox(width: 14),
                      _MetricChip(
                        label: 'DISK',
                        value: diskFrac == null
                            ? '…'
                            : '${_fmtGiB(stats!.diskUsedKb)} / ${_fmtGiB(stats!.diskTotalKb)}  ${stats!.diskMount}',
                        fraction: diskFrac,
                        color: const Color(0xFF3D9970),
                      ),
                    ],
                  ),
                ),
              ),
            ] else
              const Expanded(
                child: Text(
                  'Waiting for stats…',
                  style: TextStyle(fontSize: 11, color: Colors.white54),
                ),
              ),
            IconButton(
              tooltip: 'Hide monitor',
              onPressed: onHide,
              icon: const Icon(Icons.close, size: 14),
              color: Colors.white38,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 24, height: 24),
              splashRadius: 14,
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtGiB(int kb) {
    final gib = kb / (1024 * 1024);
    if (gib >= 10) return '${gib.round()}G';
    if (gib >= 1) return '${gib.toStringAsFixed(1)}G';
    final mib = kb / 1024;
    if (mib >= 10) return '${mib.round()}M';
    return '${mib.toStringAsFixed(1)}M';
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.fraction,
    required this.color,
  });

  final String label;
  final String value;
  final double? fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: color,
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 52,
          height: 6,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: fraction,
              backgroundColor: const Color(0xFF2A2F38),
              color: color,
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white70,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
