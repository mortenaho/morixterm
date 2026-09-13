/// Local ANSI welcome board drawn into the xterm buffer after SSH is ready.
///
/// Plain ASCII only — wide Unicode / box-drawing can break xterm cell width.
String sshWelcomeBanner({
  required String username,
  required String host,
  required int port,
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

  const width = 74;

  String strip(String s) => s.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '');

  String row(String content) {
    final pad = (width - strip(content).length).clamp(0, width);
    return '$border|$reset$content${' ' * pad}$border|$reset';
  }

  String empty() => row('');
  String rule() => row('  $faint${'-' * (width - 4)}$reset');

  String padRight(String text, int cols) {
    final n = cols - strip(text).length;
    return n > 0 ? '$text${' ' * n}' : text;
  }

  String truncate(String text, int max) {
    if (text.length <= max) return text;
    if (max <= 1) return text.substring(0, max);
    return '${text.substring(0, max - 1)}.';
  }

  final now = DateTime.now().toLocal();
  final stamp =
      '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')} '
      '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}:'
      '${now.second.toString().padLeft(2, '0')}';

  final userShort = truncate(username, 20);
  final hostShort = truncate(host, 36);
  final endpoint =
      '$green$bold$userShort$reset$white@$g3$hostShort$reset$muted:$port$reset';

  // Standard FIGlet-style wordmark — spells MORIXTERM (I, not T).
  final logo = <String>[
    row('  $g1 __  __   ___   ____   ___ __  __ _____  _____  ____   __  __ $reset'),
    row('  $g2|  \\/  | / _ \\ |  _ \\ |_ _|\\ \\/ /|_   _|| ____||  _ \\ |  \\/  |$reset'),
    row('  $g3| |\\/| || | | || |_) | | |  \\  /   | |  |  _|  | |_) || |\\/| |$reset'),
    row('  $g4| |  | || |_| ||  _ <  | |  /  \\   | |  | |___ |  _ < | |  | |$reset'),
    row('  $g5|_|  |_| \\___/ |_| \\_\\|___|/_/\\_\\  |_|  |_____||_| \\_\\|_|  |_|$reset'),
  ];

  final leftFeatures = [
    '$green+$reset Interactive shell',
    '$green+$reset Multi-session tabs',
    '$green+$reset Side file browser',
    '$green+$reset SCP / SFTP upload',
  ];
  final rightFeatures = [
    '$amber>$reset Ctrl+Shift+C   copy',
    '$amber>$reset Ctrl+Shift+V   paste',
    '$amber>$reset Toolbar         theme',
    '$amber>$reset Monitor         stats',
  ];

  String featureRow(int i) =>
      row('${padRight('  ${leftFeatures[i]}', 36)}${rightFeatures[i]}');

  final lines = <String>[
    '$border+${'=' * width}+$reset',
    empty(),
    ...logo,
    empty(),
    row(
      '           $dim Connect · Manage · Explore$reset'
      '                 $faint SSH client$reset',
    ),
    empty(),
    rule(),
    empty(),
    row(
      '  $green$bold*$reset  $white$bold CONNECTED$reset'
      '   $greenSoft[ SSH CHANNEL OPEN ]$reset'
      '              $ice v1.0.0$reset',
    ),
    empty(),
    row('  $label TARGET$reset    $endpoint'),
    row('  $label PROTO$reset     $soft SSH-2$reset   $muted· encrypted session$reset'),
    row('  $label WHEN$reset      $muted$stamp$reset'),
    empty(),
    rule(),
    empty(),
    row(
      '  $g3$bold WORKSPACE$reset'
      '                             $gold$bold SHORTCUTS$reset',
    ),
    empty(),
    featureRow(0),
    featureRow(1),
    featureRow(2),
    featureRow(3),
    empty(),
    rule(),
    empty(),
    row(
      '  $gold TIP$reset  Use the toolbar heart icon to toggle CPU / RAM / Disk.',
    ),
    row(
      '       $dim Files sidebar can follow your shell working directory.$reset',
    ),
    row(
      '       $dim Prompt is ready — type a command to get started.$reset',
    ),
    empty(),
    '$border+${'=' * width}+$reset',
  ];

  return '${lines.join('\r\n')}\r\n\r\n';
}
