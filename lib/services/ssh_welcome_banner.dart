/// The small, ANSI-coloured introduction shown when an SSH shell is ready.
///
/// Keeping this separate from the transport code makes the terminal artwork
/// easy to change without touching authentication or stream handling.
String sshWelcomeBanner({
  required String username,
  required String host,
  required int port,
}) {
  const reset = '\x1b[0m';
  const dim = '\x1b[2m';
  const cyan = '\x1b[38;5;45m';
  const blue = '\x1b[38;5;39m';
  const violet = '\x1b[38;5;135m';
  const green = '\x1b[38;5;82m';
  const yellow = '\x1b[38;5;220m';
  const white = '\x1b[38;5;255m';

  return '''
${cyan}        Welcome to Morixtrem!${reset}
${blue}        Morixtrem ${white}v1.0.0${reset}
${dim}        (Your Remote Workspace, Simplified)${reset}

${blue}   /\\        ${violet}/\\${reset}       ${white}>  SSH client       ${green}✓${reset}
${blue}  /  \\      ${violet}/  \\${reset}      ${white}>  X11-forwarding   ${green}✓${reset}
${blue} /    \\    ${violet}/    \\${reset}     ${white}>  Port forwarding   ${green}✓${reset}
${blue}/      \\  ${violet}/      \\${reset}    ${white}>  SFTP browser      ${green}✓${reset}
${blue}\\      /  ${violet}\\      /${reset}    ${white}>  Multi-execution   ${green}✓${reset}
${blue} \\    /    ${violet}\\    /${reset}     ${white}>  Tabbed sessions   ${green}✓${reset}
${blue}  \\  /      ${violet}\\  /${reset}
${blue}   \\/        ${violet}\\/${reset}

${white}  Morixtrem terminal ready.${reset}
${dim}  Session: ${username}@${host}:${port}${reset}
${yellow}  Tip: use the toolbar above for copy, paste, search, and themes.${reset}
${dim}  ------------------------------------------------------------------------${reset}
''';
}
