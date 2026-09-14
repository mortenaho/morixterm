import 'package:flutter/material.dart';

import '../services/app_lock.dart';
import '../services/app_version.dart';
import '../services/credential_vault.dart';

/// Full-screen gate shown when the app password is enabled.
class AppUnlockScreen extends StatefulWidget {
  const AppUnlockScreen({
    super.key,
    required this.appLock,
    required this.onUnlocked,
  });

  final AppLock appLock;
  final VoidCallback onUnlocked;

  @override
  State<AppUnlockScreen> createState() => _AppUnlockScreenState();
}

class _AppUnlockScreenState extends State<AppUnlockScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  var _obscure = true;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final password = _controller.text;
    if (password.isEmpty) {
      setState(() => _error = 'Enter your password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await widget.appLock.verify(password);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _busy = false;
          _error = 'Incorrect password';
        });
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
        return;
      }
      await CredentialVault.instance.unlockWithAppPassword(password);
      if (!mounted) return;
      widget.onUnlocked();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1D24),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFF263C58),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0x335B9BD5)),
                  ),
                  child: const Icon(Icons.lock_outline,
                      size: 32, color: Color(0xFF5B9BD5)),
                ),
                const SizedBox(height: 20),
                const Text(
                  'MoriXterm is locked',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter your app password to continue · ${AppVersion.label}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, height: 1.4),
                ),
                const SizedBox(height: 28),
                TextField(
                    controller: _controller,
                    focusNode: _focus,
                    obscureText: _obscure,
                    autofocus: true,
                    enabled: !_busy,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'App password',
                      filled: true,
                      fillColor: const Color(0xFF22262E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFFF8A80)),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Unlock'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dialog to enable, change, or disable the app password.
Future<bool?> showAppSecurityDialog(
  BuildContext context, {
  required AppLock appLock,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => _AppSecurityDialog(appLock: appLock),
  );
}

class _AppSecurityDialog extends StatefulWidget {
  const _AppSecurityDialog({required this.appLock});

  final AppLock appLock;

  @override
  State<_AppSecurityDialog> createState() => _AppSecurityDialogState();
}

class _AppSecurityDialogState extends State<_AppSecurityDialog> {
  var _loading = true;
  var _enabled = false;
  var _busy = false;
  var _obscure = true;
  var _idleMinutes = AppLock.defaultIdleMinutes;
  String? _error;
  String? _info;

  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final enabled = await widget.appLock.isEnabled();
    final idle = await widget.appLock.idleLockMinutes();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _idleMinutes = idle;
      _loading = false;
    });
  }

  Future<void> _enable() async {
    final next = _next.text;
    final confirm = _confirm.text;
    if (next.trim().length < 4) {
      setState(() => _error = 'Password must be at least 4 characters');
      return;
    }
    if (next != confirm) {
      setState(() => _error = 'New passwords do not match');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.appLock.enable(next);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  Future<void> _change() async {
    final next = _next.text;
    final confirm = _confirm.text;
    if (next.trim().length < 4) {
      setState(() => _error = 'Password must be at least 4 characters');
      return;
    }
    if (next != confirm) {
      setState(() => _error = 'New passwords do not match');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.appLock.changePassword(current: _current.text, next: next);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  Future<void> _disable() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.appLock.disable(_current.text);
      if (!mounted) return;
      Navigator.pop(context, false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
  }) {
    return TextField(
      controller: controller,
      obscureText: _obscure,
      enabled: !_busy,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFF22262E),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Show' : 'Hide',
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(
            _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: Row(
        children: [
          Icon(
            _enabled ? Icons.lock : Icons.lock_open_outlined,
            color: const Color(0xFF5B9BD5),
          ),
          const SizedBox(width: 10),
          const Text('App password'),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _enabled
                        ? 'App lock is on. Enter your current password to change or turn it off.'
                        : 'Protect MoriXterm with a password when the app starts.',
                    style: const TextStyle(color: Colors.white70, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  if (_enabled) ...[
                    _field(controller: _current, label: 'Current password'),
                    const SizedBox(height: 12),
                  ],
                  _field(
                    controller: _next,
                    label: _enabled ? 'New password' : 'Password',
                  ),
                  const SizedBox(height: 12),
                  _field(controller: _confirm, label: 'Confirm password'),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Auto-lock after idle',
                            style: TextStyle(color: Colors.white70)),
                      ),
                      DropdownButton<int>(
                        value: _idleMinutes,
                        dropdownColor: const Color(0xFF2A2A2A),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Off')),
                          DropdownMenuItem(value: 5, child: Text('5 min')),
                          DropdownMenuItem(value: 10, child: Text('10 min')),
                          DropdownMenuItem(value: 15, child: Text('15 min')),
                          DropdownMenuItem(value: 30, child: Text('30 min')),
                          DropdownMenuItem(value: 60, child: Text('60 min')),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) async {
                                if (value == null) return;
                                setState(() => _idleMinutes = value);
                                await widget.appLock.setIdleLockMinutes(value);
                              },
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: const TextStyle(color: Color(0xFFFF8A80))),
                  ],
                  if (_info != null) ...[
                    const SizedBox(height: 12),
                    Text(_info!, style: const TextStyle(color: Colors.white54)),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (_enabled)
          TextButton(
            onPressed: _busy ? null : _disable,
            child: const Text('Turn off',
                style: TextStyle(color: Color(0xFFFF8A80))),
          ),
        FilledButton(
          onPressed: _busy
              ? null
              : (_enabled ? _change : _enable),
          child: Text(_enabled ? 'Change password' : 'Turn on'),
        ),
      ],
    );
  }
}
