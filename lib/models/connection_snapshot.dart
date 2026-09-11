import 'saved_session.dart';

enum ConnectionPhase { idle, connecting, connected, failed }

class ConnectionSnapshot {
  const ConnectionSnapshot({
    required this.phase,
    this.protocol,
    this.host,
    this.port,
    this.username,
    this.title,
    this.error,
  });

  final ConnectionPhase phase;
  final SessionProtocol? protocol;
  final String? host;
  final int? port;
  final String? username;
  final String? title;
  final String? error;

  bool get isActive => phase == ConnectionPhase.connecting || phase == ConnectionPhase.connected;
  bool get isSsh => protocol == SessionProtocol.ssh;
}

({String host, int port}) parseEndpoint(String raw, int fallbackPort) {
  var host = raw.trim();
  var port = fallbackPort;
  if (host.startsWith('rdp://') ||
      host.startsWith('ssh://') ||
      host.startsWith('http://') ||
      host.startsWith('https://')) {
    final uri = Uri.parse(host);
    return (host: uri.host, port: uri.hasPort ? uri.port : fallbackPort);
  }
  final slash = host.indexOf('/');
  if (slash >= 0) host = host.substring(0, slash);
  if (host.startsWith('[') && host.contains(']')) {
    final end = host.indexOf(']');
    final inner = host.substring(1, end);
    final rest = host.substring(end + 1);
    if (rest.startsWith(':')) {
      port = int.tryParse(rest.substring(1)) ?? fallbackPort;
    }
    return (host: inner, port: port);
  }
  final colon = host.lastIndexOf(':');
  if (colon > 0) {
    final parsed = int.tryParse(host.substring(colon + 1));
    if (parsed != null) {
      port = parsed;
      host = host.substring(0, colon);
    }
  }
  return (host: host, port: port);
}
