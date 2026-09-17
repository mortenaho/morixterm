import type { Terminal } from '@xterm/xterm';

const C = {
  reset: '\x1b[0m', bold: '\x1b[1m', border: '\x1b[38;2;52;72;82m',
  cyan: '\x1b[38;2;45;209;214m', green: '\x1b[38;2;67;201;139m',
  blue: '\x1b[38;2;75;151;255m', text: '\x1b[38;2;222;230;236m',
  muted: '\x1b[38;2;118;132;145m',
};

export type WelcomeContext = {
  version: string; platform: string; transport: 'pty' | 'ssh';
  sessionName?: string; host?: string; user?: string; port?: number;
};

type Segment = { text: string; color?: string; bold?: boolean };

function paint({ text, color = C.text, bold = false }: Segment): string {
  return `${color}${bold ? C.bold : ''}${text}${C.reset}`;
}

function panelRow(width: number, left: Segment[], right: Segment[] = []): string {
  const leftLength = left.reduce((sum, part) => sum + part.text.length, 0);
  const rightLength = right.reduce((sum, part) => sum + part.text.length, 0);
  const available = Math.max(0, width - 4);
  const visibleLeft = leftLength + rightLength > available
    ? left.map((part, index) => index === left.length - 1
      ? { ...part, text: part.text.slice(0, Math.max(0, available - rightLength - (leftLength - part.text.length))) }
      : part)
    : left;
  const visibleLeftLength = visibleLeft.reduce((sum, part) => sum + part.text.length, 0);
  const gap = Math.max(1, width - 2 - visibleLeftLength - rightLength);
  return `${C.border}│${C.reset} ${visibleLeft.map(paint).join('')}${' '.repeat(gap)}${right.map(paint).join('')} ${C.border}│${C.reset}`;
}

function border(width: number, top: boolean): string {
  return `${C.border}${top ? '╭' : '╰'}${'─'.repeat(width)}${top ? '╮' : '╯'}${C.reset}`;
}

export function writeWelcomeBanner(term: Terminal, context: WelcomeContext): void {
  const width = Math.max(1, Math.min(74, term.cols - 2));
  const isSsh = context.transport === 'ssh';
  const user = context.user ?? (isSsh ? 'remote' : 'local');
  const host = context.host ?? (isSsh ? 'remote-host' : 'localhost');
  const port = context.port ? `:${context.port}` : '';
  const version = context.version.startsWith('v') ? context.version : `v${context.version}`;
  const target = `${user}@${host}${port}`;
  const status = isSsh ? 'CONNECTED' : 'READY';
  const transport = isSsh ? 'SSH-2 · encrypted' : `${context.platform} · local PTY`;
  const session = context.sessionName?.trim() || (isSsh ? 'Remote session' : 'Local terminal');

  term.writeln('');
  if (width < 32) {
    term.writeln(`${paint({ text: 'MORIXTERM', color: C.cyan, bold: true })} ${paint({ text: status, color: C.green })}`);
    term.writeln(paint({ text: target.slice(0, Math.max(1, term.cols - 1)), color: C.muted }));
    term.writeln('');
    return;
  }
  term.writeln(border(width, true));
  term.writeln(panelRow(width, [
    { text: 'MORI', color: C.cyan, bold: true },
    { text: 'XTERM', color: C.blue, bold: true },
  ], [{ text: version, color: C.muted }]));
  term.writeln(panelRow(width, [
    { text: '● ', color: C.green },
    { text: status, color: C.green, bold: true },
  ], width >= 46 ? [{ text: transport, color: C.muted }] : []));
  term.writeln(`${C.border}│${C.reset} ${C.border}${'─'.repeat(Math.max(0, width - 2))}${C.reset} ${C.border}│${C.reset}`);
  term.writeln(panelRow(width, [
    { text: 'TARGET  ', color: C.muted },
    { text: target, color: C.text, bold: true },
  ]));
  term.writeln(panelRow(width, [
    { text: 'SESSION ', color: C.muted },
    { text: session, color: C.cyan },
  ], width >= 64 ? [{ text: 'Connect · Manage · Explore', color: C.muted }] : []));
  term.writeln(border(width, false));
  term.writeln('');
}
