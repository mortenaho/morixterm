import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_session.dart';

class SessionStorage {
  static const _key = 'saved_rdp_sessions';

  Future<List<SavedSession>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getStringList(_key) ?? <String>[];
    return raw.map((item) => SavedSession.fromJson(jsonDecode(item) as Map<String, dynamic>)).toList();
  }

  Future<void> saveAll(List<SavedSession> sessions) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_key, sessions.map((session) => jsonEncode(session.toJson())).toList());
  }
}
