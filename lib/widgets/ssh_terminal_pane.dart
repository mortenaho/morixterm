import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

class SshTerminalPane extends StatefulWidget {
  const SshTerminalPane({
    super.key,
    required this.terminal,
    this.onToggleFiles,
    this.filesOpen = false,
  });

  final Terminal terminal;
  final VoidCallback? onToggleFiles;
  final bool filesOpen;

  @override
  State<SshTerminalPane> createState() => _SshTerminalPaneState();
}

class _SshTerminalPaneState extends State<SshTerminalPane> {
  late final TerminalController _controller;
  var _fontSize = 13.0;
  var _themeMode = _TerminalThemeMode.morixterm;

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
  }

  @override
  void dispose() {
    _controller.dispose();
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
      fontFamilyFallback: const ['Cascadia Code', 'JetBrains Mono', 'Noto Sans Mono', 'Segoe UI Emoji', 'monospace'],
    );
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
        ),
        Expanded(
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent && HardwareKeyboard.instance.isControlPressed) {
                _zoom(event.scrollDelta.dy < 0 ? 1 : -1);
              }
            },
            child: TerminalView(
              widget.terminal,
              key: ValueKey(_themeMode),
              controller: _controller,
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
