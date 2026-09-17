import * as pty from 'node-pty';
import { BrowserWindow } from 'electron';
import { existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import os from 'node:os';
import path from 'node:path';
import { readFile } from 'node:fs/promises';
import { logger } from '../../utils/logger.js';
import type { MonitorStats } from '../../contracts/monitor.js';

export type PtyStartOptions = {
  cols?: number;
  rows?: number;
  cwd?: string;
};

export function resolveShell(): string {
  if (process.platform === 'win32') {
    // Prefer a usable WSL distribution when available. `wsl.exe` alone can
    // exist on Windows without any installed distribution, so check the
    // distro list before selecting it as the default local terminal.
    if (hasWslDistribution()) return findOnPath('wsl.exe') ?? 'wsl.exe';
    const candidates = [
      process.env.ComSpec,
      'pwsh.exe',
      'powershell.exe',
      'cmd.exe',
    ].filter(Boolean) as string[];
    return candidates[0] ?? 'cmd.exe';
  }
  const fromEnv = process.env.SHELL;
  if (fromEnv && existsSync(fromEnv)) return fromEnv;
  for (const shell of ['/bin/zsh', '/bin/bash', '/bin/fish', '/bin/sh']) {
    if (existsSync(shell)) return shell;
  }
  return '/bin/sh';
}

function findOnPath(command: string): string | undefined {
  if (path.isAbsolute(command) && existsSync(command)) return command;
  for (const directory of (process.env.PATH ?? '').split(path.delimiter)) {
    if (!directory) continue;
    const candidate = path.join(directory, command);
    if (existsSync(candidate)) return candidate;
  }
  return undefined;
}

function hasWslDistribution(): boolean {
  if (process.platform !== 'win32') return false;
  const wsl = findOnPath('wsl.exe');
  if (!wsl) return false;
  try {
    const output = execFileSync(wsl, ['--list', '--quiet'], {
      encoding: 'utf8',
      timeout: 2000,
      windowsHide: true,
      stdio: ['ignore', 'pipe', 'ignore'],
    });
    return output.split(/\r?\n/).some(line => line.replace(/\0/g, '').trim().length > 0);
  } catch {
    return false;
  }
}

export class PtyManager {
  private readonly sessions = new Map<string, pty.IPty>();
  private readonly cpuSamples = new Map<string, { ticks: number; time: bigint }>();

  start(window: BrowserWindow, id: string, options: PtyStartOptions = {}): { id: string; shell: string } {
    const shell = resolveShell();
    const cols = options.cols ?? 120;
    const rows = options.rows ?? 32;
    const cwd = options.cwd && existsSync(options.cwd) ? options.cwd : os.homedir();
    const child = pty.spawn(shell, [], {
      name: 'xterm-256color',
      cols,
      rows,
      cwd,
      env: process.env as Record<string, string | undefined>,
    });
    this.sessions.set(id, child);
    child.onData(data => {
      if (!window.isDestroyed()) {
        window.webContents.send('pty:data', { id, data: Buffer.from(data).toString('base64') });
      }
    });
    child.onExit(({ exitCode }) => {
      this.sessions.delete(id);
      if (!window.isDestroyed()) {
        window.webContents.send('pty:closed', { id, code: exitCode });
      }
    });
    logger.info(`PTY started ${id} shell=${shell}`);
    return { id, shell };
  }

  write(id: string, data: string): void {
    this.sessions.get(id)?.write(data);
  }

  resize(id: string, cols: number, rows: number): void {
    this.sessions.get(id)?.resize(cols, rows);
  }

  stop(id: string): void {
    const session = this.sessions.get(id);
    if (!session) return;
    try { session.kill(); } catch { /* already exited */ }
    this.sessions.delete(id);
    this.cpuSamples.delete(id);
  }

  async stats(id: string): Promise<MonitorStats> {
    const session = this.sessions.get(id);
    if (!session) throw new Error('Local terminal is not running');
    let cpu: number | null = null;
    let memory: number | null = null;
    if (process.platform === 'linux') {
      try {
        const [stat, status] = await Promise.all([
          readFile(`/proc/${session.pid}/stat`, 'utf8'),
          readFile(`/proc/${session.pid}/status`, 'utf8'),
        ]);
        const fields = stat.slice(stat.lastIndexOf(')') + 2).trim().split(/\s+/);
        const ticks = Number(fields[11]) + Number(fields[12]);
        const time = process.hrtime.bigint();
        const previous = this.cpuSamples.get(id);
        if (previous) {
          const elapsedSeconds = Number(time - previous.time) / 1e9;
          cpu = elapsedSeconds > 0 ? (ticks - previous.ticks) / (elapsedSeconds * 100 * os.cpus().length) * 100 : null;
        }
        this.cpuSamples.set(id, { ticks, time });
        const residentKb = Number(status.match(/^VmRSS:\s+(\d+)/m)?.[1] ?? 0);
        memory = residentKb / (os.totalmem() / 1024) * 100;
      } catch { /* the process may exit between the two reads */ }
    }
    return {
      cpu: cpu === null ? null : Math.max(0, Math.min(100, Math.round(cpu))),
      memory: memory === null ? null : Math.max(0, Math.min(100, Math.round(memory))),
      disk: null,
      label: 'LOCAL SESSION',
    };
  }

  stopAll(): void {
    for (const id of [...this.sessions.keys()]) this.stop(id);
  }
}

export const ptyManager = new PtyManager();
