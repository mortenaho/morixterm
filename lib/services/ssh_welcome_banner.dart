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
  const greenSoft = '\x1b[38;5;72m';
  const gold = '\x1b[38;5;220m';
  const amber = '\x1b[38;5;178m';
  const white = '\x1b[38;5;255m';
  const soft = '\x1b[38;5;252m';
  const muted = '\x1b[38;5;245m';
  const faint = '\x1b[38;5;238m';
  const border = '\x1b[38;5;60m';
  const label = '\x1b[38;5;110m';
  const ice = '\x1b[38;5;117m';
  const panel = '\x1b[38;5;66m';

  const width = 74;

  String strip(String s) => s.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '');

  String row(String content) {
    final pad = (width - strip(content).length).clamp(0, width);
    return '$border|$reset$content${' ' * pad}$border|$reset';
  }

  String empty() => row('');

  String section(String title) {
    final mark = '-- $title ';
    final dash = (width - 4 - mark.length).clamp(2, width);
    return row('  $faint$mark${'-' * dash}$reset');
  }

  String padRight(String text, int cols) {
    final n = cols - strip(text).length;
    return n > 0 ? '$text${' ' * n}' : text;
  }

  String truncate(String text, int max) {
    if (text.length <= max) return text;
    if (max <= 1) return text.substring(0, max);
    return '${text.substring(0, max - 1)}.';
  }

  String panelRow(String content) {
    final innerWidth = width - 4; // between outer | |
    final body = '$panel|$reset$content';
    final pad = (innerWidth - 1 - strip(body).length).clamp(0, innerWidth);
    return row('  $body${' ' * pad}$panel|$reset');
  }

  final now = DateTime.now().toLocal();
  final stamp =
      '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')} '
      '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}';

  final userShort = truncate(username, 18);
  final hostShort = truncate(host, 30);
  final endpoint =
      '$green$bold$userShort$reset$white@$g3$hostShort$reset$muted:$ice$port$reset';

  // Standard FIGlet-style wordmark — spells MORIXTERM (I, not T).
  final logo = <String>[
    row('  $g1 __  __   ___   ____   ___ __  __ _____  _____  ____   __  __ $reset'),
    row('  $g2|  \\/  | / _ \\ |  _ \\ |_ _|\\ \\/ /|_   _|| ____||  _ \\ |  \\/  |$reset'),
    row('  $g3| |\\/| || | | || |_) | | |  \\  /   | |  |  _|  | |_) || |\\/| |$reset'),
    row('  $g4| |  | || |_| ||  _ <  | |  /  \\   | |  | |___ |  _ < | |  | |$reset'),
    row('  $g5|_|  |_| \\___/ |_| \\_\\|___|/_/\\_\\  |_|  |_____||_| \\_\\|_|  |_|$reset'),
  ];

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
    section('session'),
    empty(),
    row(
      '  $green$bold*$reset  $white$bold LIVE$reset'
      '   $greenSoft channel open$reset'
      '                   $muted SSH-2 encrypted$reset',
    ),
    empty(),
    row('  $panel+${'-' * (width - 4)}+$reset'),
    panelRow('  $label host $reset $endpoint'),
    panelRow('  $label when $reset $muted$stamp$reset'),
    row('  $panel+${'-' * (width - 4)}+$reset'),
    empty(),
    section('workspace'),
    empty(),
    row(
      '${padRight('  $g3$bold tools$reset', 36)}'
      '$gold$bold keys$reset',
    ),
    empty(),
    row(
      '${padRight('  $green+$reset shell    $green+$reset tabs    $green+$reset files', 36)}'
      '$amber>$reset Ctrl+Shift+C   $muted copy$reset',
    ),
    row(
      '${padRight('  $green+$reset upload   $green+$reset monitor $green+$reset theme', 36)}'
      '$amber>$reset Ctrl+Shift+V   $muted paste$reset',
    ),
    empty(),
    section('tip'),
    empty(),
    row(
      '  $gold*$reset  $soft Heart icon$reset$dim toggles CPU / RAM / Disk monitor.$reset',
    ),
    row(
      '     $dim Files sidebar can follow your shell working directory.$reset',
    ),
    row(
      '     $white$bold Ready$reset$dim — type a command to get started.$reset',
    ),
    empty(),
    '$border+${'=' * width}+$reset',
  ];

  return '${lines.join('\r\n')}\r\n\r\n';
}
