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
  const dim = '\x1b[2m';
  const cyan = '\x1b[38;5;51m';
  const blue = '\x1b[38;5;75m';
  const violet = '\x1b[38;5;141m';
  const green = '\x1b[38;5;82m';
  const yellow = '\x1b[38;5;220m';
  const white = '\x1b[38;5;255m';
  const muted = '\x1b[38;5;245m';
  const border = '\x1b[38;5;60m';

  return '''
${border}╭────────────────────────────────────────────────────────────────────────╮${reset}
${border}│${reset} ${cyan}◆${reset} ${white}MORI${cyan}XTREM${reset}                                      ${green}● CONNECTED${reset} ${border}│${reset}
${border}│${reset}   ${dim}Remote workspace · SSH terminal${reset}                         ${muted}v1.0.0${reset} ${border}│${reset}
${border}├────────────────────────────────────────────────────────────────────────┤${reset}
${border}│${reset}  ${muted}SESSION${reset}                                                            ${border}│${reset}
${border}│${reset}  ${white}${username}@${host}${reset} ${dim}on port ${port}${reset}                                  ${border}│${reset}
${border}│${reset}  ${green}✓${reset} ${muted}Authenticated and ready for commands${reset}                      ${border}│${reset}
${border}├────────────────────────────────────────────────────────────────────────┤${reset}
${border}│${reset}  ${blue}WORKSPACE${reset}                  ${violet}TOOLS${reset}                         ${border}│${reset}
${border}│${reset}  ${green}✓${reset} Interactive shell              ${green}✓${reset} Copy / paste                  ${border}│${reset}
${border}│${reset}  ${green}✓${reset} Multi-session tabs             ${green}✓${reset} Search terminal output         ${border}│${reset}
${border}│${reset}  ${green}✓${reset} SFTP file browser              ${green}✓${reset} Adjustable font & themes       ${border}│${reset}
${border}│${reset}  ${green}✓${reset} Port forwarding                ${green}✓${reset} Clear terminal                 ${border}│${reset}
${border}├────────────────────────────────────────────────────────────────────────┤${reset}
${border}│${reset}  ${yellow}TIP${reset}  Use the toolbar above for terminal tools.                  ${border}│${reset}
${border}│${reset}       Your shell is ready — type a command to get started.     ${border}│${reset}
${border}╰────────────────────────────────────────────────────────────────────────╯${reset}
''';
}
