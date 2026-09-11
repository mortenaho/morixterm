enum SessionProtocol { rdp, ssh }

class SavedSession {
  const SavedSession({
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    this.protocol = SessionProtocol.rdp,
    this.password = '',
  });

  final String name;
  final String host;
  final int port;
  final String username;
  final SessionProtocol protocol;
  final String password;

  bool get isSsh => protocol == SessionProtocol.ssh;
  bool get hasSavedPassword => password.isNotEmpty;

  bool sameBookmark(SavedSession other) =>
      name == other.name && host == other.host && port == other.port && protocol == other.protocol;

  SavedSession copyWith({
    String? name,
    String? host,
    int? port,
    String? username,
    SessionProtocol? protocol,
    String? password,
  }) {
    return SavedSession(
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      protocol: protocol ?? this.protocol,
      password: password ?? this.password,
    );
  }

  Map<String, Object> toJson() => {
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'protocol': protocol.name,
        'password': password,
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
    );
  }
}
