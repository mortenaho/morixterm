/// The ANSI-coloured dashboard shown when an SSH shell is ready.
///
/// Keeping this separate from the transport code makes the terminal artwork
/// easy to change without touching authentication or stream handling.
String sshWelcomeBanner({
  required String username,
  required String host,
  required int port,
}) {
  const reset = '\x1b[0m';
  const bold = '\x1b[1m';
  const dim = '\x1b[2m';
  const c1 = '\x1b[38;5;51m';
  const c2 = '\x1b[38;5;75m';
  const c3 = '\x1b[38;5;69m';
  const c4 = '\x1b[38;5;105m';
  const c5 = '\x1b[38;5;141m';
  const c6 = '\x1b[38;5;171m';
  const green = '\x1b[38;5;82m';
  const brightGreen = '\x1b[1;32m';
  const yellow = '\x1b[38;5;220m';
  const white = '\x1b[38;5;255m';
  const muted = '\x1b[38;5;245m';
  const soft = '\x1b[38;5;240m';
  const border = '\x1b[38;5;67m';

  // Plain ASCII only — wide Unicode glyphs break xterm cell alignment.
  const width = 68;

  String row(String content) {
    final plain = content.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '');
    final pad = (width - plain.length).clamp(0, width);
    return '$border|${reset}$content${' ' * pad}$border|$reset';
  }

  String empty() => row('');
  String rule() => row('  $soft${'-' * 62}$reset');

  final brand =
      '$white$bold MORI$reset${c2}X${reset}${c3}T${reset}${c4}E${reset}${c5}R${reset}${c6}M$reset';
  final session = '$brightGreen$username$reset$white@$c2$host$reset  $dim·$reset  $muted$port$reset';
  final time = DateTime.now().toLocal().toString().split('.').first;

  // Compact gradient mark — single-width ASCII only.
  final mark = '$c1*$reset$c2*$reset$c3*$reset$c4*$reset$c5*$reset$c6*$reset';

  final lines = <String>[
    '$border+${'-' * width}+$reset',
    empty(),
    row('  $mark  $brand'),
    row('         $dim Connect · Manage · Explore$reset'),
    empty(),
    row('  $green*$reset $white$bold CONNECTED$reset  $dim· SSH ready$reset               $muted v1.0.0$reset'),
    empty(),
    rule(),
    empty(),
    row('  $muted SESSION$reset   $session'),
    row('  $muted WHEN$reset      $soft$time$reset'),
    empty(),
    row('  $c2 WORKSPACE$reset                            $c5 TOOLS$reset'),
    row('  $green+$reset Interactive shell                    $green+$reset Copy / paste'),
    row('  $green+$reset Multi-session tabs                   $green+$reset Search output'),
    row('  $green+$reset SCP file browser                     $green+$reset Themes & font'),
    row('  $green+$reset Port forwarding                      $green+$reset Clear terminal'),
    empty(),
    rule(),
    row('  $yellow TIP$reset  Toolbar -> themes · search · clear'),
    row('       $dim Type a command below to get started.$reset'),
    empty(),
    '$border+${'-' * width}+$reset',
  ];

  return '${lines.join('\r\n')}\r\n';
}
