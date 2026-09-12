class RemoteEntry {
  const RemoteEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
  });

  final String name;
  final String path;
  final bool isDirectory;

  static String join(String dir, String name) {
    if (dir == '/') return '/$name';
    return '${dir.endsWith('/') ? dir.substring(0, dir.length - 1) : dir}/$name';
  }

  static String parent(String path) {
    if (path.isEmpty || path == '/') return '/';
    final trimmed = path.endsWith('/') && path != '/' ? path.substring(0, path.length - 1) : path;
    final index = trimmed.lastIndexOf('/');
    if (index <= 0) return '/';
    return trimmed.substring(0, index);
  }

  static String displayPath(String path) {
    if (path == '/') return '/';
    return path.endsWith('/') ? path : '$path/';
  }

  /// Breadcrumb crumbs for an absolute Unix-style path.
  /// Each entry is `(label, absolutePath)`.
  static List<({String label, String path})> breadcrumbs(String path) {
    final normalized = path.trim().isEmpty ? '/' : path.trim();
    final crumbs = <({String label, String path})>[
      (label: '/', path: '/'),
    ];
    if (normalized == '/') return crumbs;
    final parts = normalized
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    var current = '';
    for (final part in parts) {
      current = '$current/$part';
      crumbs.add((label: part, path: current));
    }
    return crumbs;
  }
}

class FileClipboard {
  const FileClipboard({required this.paths, required this.cut, required this.sourceDir});

  final List<String> paths;
  final bool cut;
  final String sourceDir;

  bool get isEmpty => paths.isEmpty;
}
