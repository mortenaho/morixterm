/// Local ANSI welcome board drawn into the xterm buffer after SSH is ready.
///
/// Plain ASCII only — wide Unicode / box-drawing can break xterm cell width.
String sshWelcomeBanner({
  required String username,
  required String host,
  required int port,
  String version = 'v0.1.0',
}) {
  const reset = '\x1b[0m';
  const bold = '\x1b[1m';
  const dim = '\x1b[2m';

  // Cyan → violet brand gradient
  const g1 = '\x1b[38;5;51m';
  const g2 = '\x1b[38;5;45m';
  const g3 = '\x1b[38;5;39m';
  const g4 = '\x1b[38;5;33m';
  const g5 = '\x1b[38;5;69m';

  const green = '\x1b[38;5;82m';
  const greenDim = '\x1b[38;5;65m';
  const white = '\x1b[38;5;255m';
  const soft = '\x1b[38;5;252m';
  const muted = '\x1b[38;5;245m';
  const faint = '\x1b[38;5;238m';
  const border = '\x1b[38;5;60m';
  const label = '\x1b[38;5;110m';
  const ice = '\x1b[38;5;117m';
  const card = '\x1b[38;5;67m';

  const width = 74;

  String strip(String s) => s.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '');

  String row(String content) {
    final pad = (width - strip(content).length).clamp(0, width);
    return '$border|$reset$content${' ' * pad}$border|$reset';
  }

  String empty() => row('');

  String padRight(String text, int cols) {
    final n = cols - strip(text).length;
    return n > 0 ? '$text${' ' * n}' : text;
  }

  String truncate(String text, int max) {
    if (text.length <= max) return text;
    if (max <= 1) return text.substring(0, max);
    return '${text.substring(0, max - 1)}.';
  }

  /// Inner card line: `| content |` padded to outer width.
  String cardRow(String content) {
    const side = 2; // "  " before left |
    const inner = width - side - 2; // between the two card | chars
    final pad = (inner - strip(content).length).clamp(0, inner);
    return row('  $card|$reset$content${' ' * pad}$card|$reset');
  }

  final now = DateTime.now().toLocal();
  final stamp =
      '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')} '
      '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}';

  final userShort = truncate(username, 22);
  final hostShort = truncate(host, 36);
  final portText = '$port';

  // Standard FIGlet-style wordmark — spells MORIXTERM (I, not T).
  final logo = <String>[
    row('  $g1 __  __   ___   ____   ___ __  __ _____  _____  ____   __  __ $reset'),
    row('  $g2|  \\/  | / _ \\ |  _ \\ |_ _|\\ \\/ /|_   _|| ____||  _ \\ |  \\/  |$reset'),
    row('  $g3| |\\/| || | | || |_) | | |  \\  /   | |  |  _|  | |_) || |\\/| |$reset'),
    row('  $g4| |  | || |_| ||  _ <  | |  /  \\   | |  | |___ |  _ < | |  | |$reset'),
    row('  $g5|_|  |_| \\___/ |_| \\_\\|___|/_/\\_\\  |_|  |_____||_| \\_\\|_|  |_|$reset'),
  ];

  const leftCol = 40;
  final userCell = padRight(
    '  $label user $reset $green$bold$userShort$reset',
    leftCol,
  );
  final hostCell = padRight(
    '  $label host $reset $g3$hostShort$reset',
    leftCol,
  );

  final lines = <String>[
    '$border+${'=' * width}+$reset',
    empty(),
    ...logo,
    empty(),
    row(
      '  $dim SSH workspace$reset'
      '  $faint·$reset  $soft Connect · Manage · Explore$reset'
      '            $ice$version$reset',
    ),
    empty(),
    row('  $card+${'=' * (width - 4)}+$reset'),
    cardRow(
      '  $greenDim[$reset$white$bold LIVE $reset$greenDim]$reset'
      '  $soft SSH channel open$reset'
      '          $muted SSH-2  ·  encrypted$reset',
    ),
    cardRow('  $faint${'-' * (width - 8)}$reset'),
    cardRow(
      '$userCell'
      '$label port$reset  $ice$bold$portText$reset',
    ),
    cardRow(
      '$hostCell'
      '$label time$reset  $muted$stamp$reset',
    ),
    row('  $card+${'=' * (width - 4)}+$reset'),
    empty(),
    '$border+${'=' * width}+$reset',
  ];

  return '${lines.join('\r\n')}\r\n\r\n';
}
