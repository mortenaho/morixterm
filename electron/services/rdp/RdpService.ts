import { spawn, type ChildProcess } from 'node:child_process';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { BrowserWindow } from 'electron';
import { logger } from '../../utils/logger.js';

export type RdpConnectInput = {
  id: string;
  host: string;
  port: number;
  username: string;
  password?: string;
  domain?: string;
};

export interface IRdpAdapter {
  isAvailable(): boolean;
  connect(window: BrowserWindow, input: RdpConnectInput): Promise<{ id: string; command: string }>;
  disconnect(id: string): void;
  disconnectAll(): void;
}

function which(command: string): string | undefined {
  if (command.includes('/') && existsSync(command)) return command;
  const pathEnv = process.env.PATH ?? '';
  for (const dir of pathEnv.split(path.delimiter)) {
    const candidate = path.join(dir, command);
    if (existsSync(candidate)) return candidate;
  }
  return undefined;
}

export class FreeRdpAdapter implements IRdpAdapter {
  private readonly processes = new Map<string, ChildProcess>();

  detectClient(): string | undefined {
    if (process.platform === 'win32') {
      return which('mstsc.exe') ?? which('mstsc') ?? which('wfreerdp.exe') ?? which('wfreerdp');
    }
    return (
      which('xfreerdp')
      ?? which('xfreerdp3')
      ?? which('wlfreerdp')
      ?? which('wlfreerdp3')
      ?? which('sdl-freerdp')
      ?? which('sdl-freerdp3')
    );
  }

  isAvailable(): boolean {
    return Boolean(this.detectClient());
  }

  installHint(): string {
    if (process.platform === 'win32') {
      return 'Install FreeRDP (wfreerdp) or use the built-in Remote Desktop client (mstsc).';
    }
    if (process.platform === 'darwin') {
      return 'Install FreeRDP (for example: brew install freerdp).';
    }
    return 'Install a FreeRDP client, e.g. `sudo apt install freerdp-x11` (provides xfreerdp).';
  }

  connect(window: BrowserWindow, input: RdpConnectInput): Promise<{ id: string; command: string }> {
    const command = this.detectClient();
    if (!command) {
      return Promise.reject(new Error(`RDP client not found. ${this.installHint()}`));
    }

    const args = this.buildArgs(command, input);
    logger.info(`RDP launch ${input.id} via ${command}`);

    return new Promise((resolve, reject) => {
      const child = spawn(command, args, {
        detached: false,
        stdio: [input.password && !/mstsc(?:\.exe)?$/i.test(command) ? 'pipe' : 'ignore', 'pipe', 'pipe'],
        env: { ...process.env },
      });

      let settled = false;
      const stderr: string[] = [];

      const fail = (message: string) => {
        if (settled) return;
        settled = true;
        this.processes.delete(input.id);
        try { child.kill(); } catch { /* ignore */ }
        reject(new Error(message));
      };

      const succeed = () => {
        if (settled) return;
        settled = true;
        this.processes.set(input.id, child);
        resolve({ id: input.id, command });
      };

      child.stderr?.on('data', chunk => {
        const text = String(chunk);
        stderr.push(text);
        logger.warn(`RDP client reported an error for ${input.id}`);
      });

      child.once('spawn', () => {
        if (input.password && child.stdin) {
          child.stdin.end(`${input.password}\n`);
        }
        succeed();
      });

      child.once('error', error => {
        const message = error.message.includes('ENOENT')
          ? `RDP client not found (${command}). ${this.installHint()}`
          : `Could not start RDP client: ${error.message}`;
        fail(message);
      });

      child.once('exit', (code, signal) => {
        this.processes.delete(input.id);
        if (!settled) {
          const detail = stderr.join('').trim() || `exit ${code ?? signal ?? 'unknown'}`;
          fail(`RDP client exited immediately (${detail}).`);
          return;
        }
        if (!window.isDestroyed()) {
          window.webContents.send('rdp:closed', { id: input.id, code: code ?? undefined });
        }
      });
    });
  }

  private buildArgs(command: string, input: RdpConnectInput): string[] {
    const base = command.toLowerCase();
    if (base.endsWith('mstsc') || base.endsWith('mstsc.exe')) {
      return [`/v:${input.host}:${input.port}`];
    }

    const args = [
      `/v:${input.host}:${input.port}`,
      `/u:${input.username}`,
      '/dynamic-resolution',
      '/cert:tofu',
      '+clipboard',
      '/network:auto',
    ];
    if (input.domain) args.push(`/d:${input.domain}`);
    if (input.password) args.push('/from-stdin');
    return args;
  }

  disconnect(id: string): void {
    const child = this.processes.get(id);
    if (!child) return;
    try { child.kill(); } catch { /* ignore */ }
    this.processes.delete(id);
  }

  disconnectAll(): void {
    for (const id of [...this.processes.keys()]) this.disconnect(id);
  }
}

export class RdpService {
  constructor(private readonly adapter: IRdpAdapter = new FreeRdpAdapter()) {}

  status(): { available: boolean; command?: string; hint: string } {
    const free = this.adapter instanceof FreeRdpAdapter ? this.adapter : undefined;
    return {
      available: this.adapter.isAvailable(),
      command: free?.detectClient(),
      hint: free?.installHint() ?? 'No RDP adapter configured.',
    };
  }

  connect(window: BrowserWindow, input: RdpConnectInput) {
    return this.adapter.connect(window, input);
  }

  disconnect(id: string) {
    this.adapter.disconnect(id);
  }

  disconnectAll() {
    this.adapter.disconnectAll();
  }
}

export const rdpService = new RdpService();
