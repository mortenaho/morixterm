import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_session.dart';

class SessionStorage {
  static const _key = 'saved_rdp_sessions';
  static const _foldersKey = 'saved_rdp_session_folders';
  static const _monitorKey = 'terminal_system_monitor';

  Future<List<SavedSession>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getStringList(_key) ?? <String>[];
    return raw.map((item) => SavedSession.fromJson(jsonDecode(item) as Map<String, dynamic>)).toList();
  }

  Future<void> saveAll(List<SavedSession> sessions) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_key, sessions.map((session) => jsonEncode(session.toJson())).toList());
  }

  Future<List<String>> loadFolders() async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getStringList(_foldersKey) ?? <String>[]).where((item) => item.trim().isNotEmpty).toList();
  }

  Future<void> saveFolders(Iterable<String> folders) async {
    final preferences = await SharedPreferences.getInstance();
    final values = folders.map((item) => item.trim()).where((item) => item.isNotEmpty).toSet().toList()..sort();
    await preferences.setStringList(_foldersKey, values);
  }

  Future<bool> loadSystemMonitorEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_monitorKey) ?? false;
  }

  Future<void> saveSystemMonitorEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_monitorKey, enabled);
  }
}
