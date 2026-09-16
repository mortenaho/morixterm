import type { Terminal } from '@xterm/xterm';

const C = {
  reset: '\x1b[0m',
  bold: '\x1b[1m',
  line: '\x1b[38;2;104;112;163m',
  cyan: '\x1b[38;2;28;221;224m',
  green: '\x1b[38;2;102;214;115m',
  blue: '\x1b[38;2;91;178;255m',
  text: '\x1b[38;2;222;222;222m',
  muted: '\x1b[38;2;142;142;142m',
};

export type WelcomeContext = {
  version: string;
  platform: string;
  transport: 'pty' | 'ssh';
  sessionName?: string;
  host?: string;
  user?: string;
  port?: number;
};

type Segment = { text: string; color?: string; bold?: boolean };

function row(width: number, parts: Segment[] = []): string {
  let remaining = width;
  const clipped = parts
    .map(part => {
      const text = part.text.slice(0, Math.max(0, remaining));
      remaining -= text.length;
      return { ...part, text };
    })
    .filter(part => part.text.length > 0);
  const visible = width - remaining;
  const content = clipped.map(part => `${part.color ?? C.text}${part.bold ? C.bold : ''}${part.text}${C.reset}`).join('');
  return `${C.line}|${C.reset}${content}${' '.repeat(Math.max(0, width - visible))}${C.line}|${C.reset}`;
}

function divider(width: number, char = '='): string {
  return `${C.line}+${char.repeat(width)}+${C.reset}`;
}

function infoRow(width: number, leftLabel: string, leftValue: string, rightLabel: string, rightValue: string): string {
  const left = `  ${leftLabel.padEnd(7)} ${leftValue}`;
  const gap = Math.max(2, Math.floor(width * .6) - left.length);
  return row(width, [
    { text: leftLabel ? `  ${leftLabel.padEnd(7)} ` : '', color: C.muted },
    { text: leftValue, color: C.green, bold: true },
    { text: ' '.repeat(gap) },
    { text: `${rightLabel.padEnd(7)} `, color: C.muted },
    { text: rightValue, color: C.blue, bold: true },
  ]);
}

function centered(text: string, width: number): string {
  const indent = Math.max(0, Math.floor((width - text.length) / 2));
  return `${' '.repeat(indent)}${text}`;
}

const glyphs: Record<string, string[]> = {
  M: ['█   █', '██ ██', '█ █ █', '█   █', '█   █'],
  O: [' ███ ', '█   █', '█   █', '█   █', ' ███ '],
  R: ['████ ', '█   █', '████ ', '█ █  ', '█  ██'],
  I: ['█████', '  █  ', '  █  ', '  █  ', '█████'],
  X: ['█   █', ' █ █ ', '  █  ', ' █ █ ', '█   █'],
  T: ['█████', '  █  ', '  █  ', '  █  ', '  █  '],
  E: ['█████', '█    ', '████ ', '█    ', '█████'],
};

function productWordmark(): string[] {
  const name = 'MORIXTERM';
  return Array.from({ length: 5 }, (_, rowIndex) => name
    .split('')
    .map(letter => glyphs[letter][rowIndex])
    .join(' '));
}

export function writeWelcomeBanner(term: Terminal, context: WelcomeContext): void {
  const insideWidth = Math.max(1, Math.min(82, term.cols - 2));
  const isSsh = context.transport === 'ssh';
  const user = context.user ?? (isSsh ? 'remote' : 'local');
  const host = context.host ?? (isSsh ? 'remote-host' : 'localhost');
  const port = context.port ? String(context.port) : 'local';
  const now = new Intl.DateTimeFormat('en-CA', { dateStyle: 'medium', timeStyle: 'short', hour12: false }).format(new Date());
  const version = context.version.startsWith('v') ? context.version : `v${context.version}`;
  const wordmark = productWordmark();
  const status = isSsh ? 'SSH channel open' : 'Local shell open';
  const security = isSsh ? 'SSH-2  ·  encrypted' : `${context.platform}  ·  local PTY`;

  term.writeln('');
  term.writeln(divider(insideWidth));
  term.writeln(row(insideWidth));
  for (const line of wordmark) term.writeln(row(insideWidth, [{ text: centered(line, insideWidth), color: C.cyan }]));
  term.writeln(row(insideWidth));
  const workspace = '   SSH workspace';
  const tagline = 'Connect · Manage · Explore';
  term.writeln(row(insideWidth, [
    { text: workspace, color: C.muted },
    { text: ' '.repeat(Math.max(3, insideWidth - workspace.length - tagline.length - version.length)) },
    { text: tagline, color: C.text },
    { text: '   ' },
    { text: version, color: C.blue },
  ]));
  term.writeln(divider(insideWidth));
  const livePrefix = `     [ LIVE ]    ${status}`;
  term.writeln(row(insideWidth, [
    { text: '     [ ', color: C.muted },
    { text: 'LIVE', color: C.green, bold: true },
    { text: ' ]    ', color: C.muted },
    { text: status, color: C.text },
    { text: ' '.repeat(Math.max(3, insideWidth - livePrefix.length - security.length - 3)) },
    { text: security, color: C.muted },
  ]));
  term.writeln(`${C.line}|${C.reset}  ${C.muted}${'-'.repeat(Math.max(0, insideWidth - 2))}${C.reset}${C.line}|${C.reset}`);
  term.writeln(infoRow(insideWidth, 'user', user, 'port', port));
  term.writeln(infoRow(insideWidth, 'host', host, 'time', now));
  term.writeln(divider(insideWidth));
  term.writeln('');
}
