import 'package:flutter/material.dart';

enum SessionProtocol { rdp, ssh }

class SavedSession {
  static const _unset = Object();

  /// Preset accent colors for session tabs.
  static const List<Color> tabPalette = [
    Color(0xFF3D9970), // green
    Color(0xFF5B9BD5), // blue
    Color(0xFFE6B422), // gold
    Color(0xFFE06C75), // red
    Color(0xFFC678DD), // purple
    Color(0xFF56B6C2), // cyan
    Color(0xFFD19A66), // orange
    Color(0xFF98C379), // lime
    Color(0xFF61AFEF), // sky
    Color(0xFFE5C07B), // sand
  ];

  const SavedSession({
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    this.protocol = SessionProtocol.rdp,
    this.password = '',
    this.folder,
    this.tabColor,
  });

  final String name;
  final String host;
  final int port;
  final String username;
  final SessionProtocol protocol;
  final String password;
  final String? folder;
  /// ARGB color value for the session tab accent. Null = protocol default.
  final int? tabColor;

  bool get isSsh => protocol == SessionProtocol.ssh;
  bool get hasSavedPassword => password.isNotEmpty;

  Color get accentColor {
    if (tabColor != null) return Color(tabColor!);
    return isSsh ? const Color(0xFFE6B422) : const Color(0xFF5B9BD5);
  }

  Color get tabBackground => accentColor.withValues(alpha: 0.35);

  bool sameBookmark(SavedSession other) =>
      name == other.name &&
      host == other.host &&
      port == other.port &&
      username == other.username &&
      protocol == other.protocol;

  SavedSession copyWith({
    String? name,
    String? host,
    int? port,
    String? username,
    SessionProtocol? protocol,
    String? password,
    Object? folder = _unset,
    Object? tabColor = _unset,
  }) {
    return SavedSession(
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      protocol: protocol ?? this.protocol,
      password: password ?? this.password,
      folder: identical(folder, _unset) ? this.folder : folder as String?,
      tabColor: identical(tabColor, _unset) ? this.tabColor : tabColor as int?,
    );
  }

  Map<String, Object?> toJson() => {
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'protocol': protocol.name,
        'password': password,
        'folder': folder,
        'tabColor': tabColor,
      };

  factory SavedSession.fromJson(Map<String, dynamic> json) {
    final protocolName = json['protocol'] as String?;
    return SavedSession(
      name: json['name'] as String? ?? 'جلسه بدون نام',
      host: json['host'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? (protocolName == 'ssh' ? 22 : 3389),
      username: json['username'] as String? ?? '',
      protocol: protocolName == 'ssh' ? SessionProtocol.ssh : SessionProtocol.rdp,
      password: json['password'] as String? ?? '',
      folder: (json['folder'] as String?)?.trim().isEmpty == true
          ? null
          : json['folder'] as String?,
      tabColor: (json['tabColor'] as num?)?.toInt(),
    );
  }
}
