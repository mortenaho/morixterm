import { Client, type ClientChannel, type ConnectConfig, type Sftp } from 'ssh2';
import { BrowserWindow } from 'electron';
import { getPassword } from '../credentials.js';
import { logger } from '../../utils/logger.js';
import type { ConnectionState } from '../../contracts/terminal.js';
import type { RemoteFile } from '../../contracts/files.js';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import pathModule from 'node:path';
import type { MonitorStats } from '../../contracts/monitor.js';

export type SshConnectInput = {
  id: string;
  sessionId: string;
  host: string;
  port: number;
  username: string;
  password?: string;
  privateKey?: string;
  cols?: number;
  rows?: number;
};

type LiveSession = {
  client: Client;
  channel?: ClientChannel;
  window: BrowserWindow;
  state: ConnectionState;
};

export class SSHConnectionManager {
  private readonly sessions = new Map<string, LiveSession>();
  private readonly cpuSamples = new Map<string, { total: number; idle: number }>();

  private setState(id: string, state: ConnectionState, message?: string): void {
    const session = this.sessions.get(id);
    if (!session) return;
    session.state = state;
    if (!session.window.isDestroyed()) {
      session.window.webContents.send('ssh:state', { id, state, message });
    }
  }

  connect(window: BrowserWindow, input: SshConnectInput): Promise<{ id: string }> {
    return new Promise((resolve, reject) => {
      const existing = this.sessions.get(input.id);
      if (existing) {
        this.disconnect(input.id);
      }

      const client = new Client();
      const live: LiveSession = { client, window, state: 'Connecting' };
      this.sessions.set(input.id, live);
      this.setState(input.id, 'Connecting');

      (async () => {
        const config: ConnectConfig = {
          host: input.host,
          port: input.port,
          username: input.username,
          readyTimeout: 15000,
          keepaliveInterval: 10000,
          tryKeyboard: false,
        };
        const vaultPassword = await getPassword(input.sessionId);
        config.password = input.password || vaultPassword || undefined;
        if (input.privateKey) config.privateKey = input.privateKey;

        client
          .on('ready', () => {
            client.shell(
              { term: 'xterm-256color', cols: input.cols ?? 120, rows: input.rows ?? 32 },
              (error, channel) => {
                if (error) {
                  this.fail(input.id, error.message);
                  reject(error);
                  return;
                }
                live.channel = channel;
                this.setState(input.id, 'Connected');
                channel.on('data', (data: Buffer | string) => {
                  if (!window.isDestroyed()) {
                    window.webContents.send('ssh:data', {
                      id: input.id,
                      data: Buffer.from(data).toString('base64'),
                    });
                  }
                });
                channel.on('close', () => {
                  this.sessions.delete(input.id);
                  this.cpuSamples.delete(input.id);
                  if (!window.isDestroyed()) {
                    window.webContents.send('ssh:closed', { id: input.id });
                    window.webContents.send('ssh:state', { id: input.id, state: 'Disconnected' });
                  }
                });
                logger.info(`SSH connected ${input.id} ${input.username}@${input.host}:${input.port}`);
                resolve({ id: input.id });
              },
            );
          })
          .on('error', (error: Error) => {
            this.fail(input.id, error.message);
            reject(error);
          })
          .connect(config);
      })().catch(error => {
        this.fail(input.id, error instanceof Error ? error.message : 'SSH connection failed');
        reject(error);
      });
    });
  }

  private fail(id: string, message: string): void {
    this.setState(id, 'Failed', message);
    const session = this.sessions.get(id);
    try { session?.client.end(); } catch { /* ignore */ }
    this.sessions.delete(id);
    this.cpuSamples.delete(id);
    logger.warn(`SSH failed ${id}: ${message}`);
  }

  write(id: string, data: string): void {
    this.sessions.get(id)?.channel?.write(data);
  }

  resize(id: string, cols: number, rows: number): void {
    this.sessions.get(id)?.channel?.setWindow(rows, cols, 0, 0);
  }

  stats(id: string): Promise<MonitorStats> {
    const session = this.sessions.get(id);
    if (!session) return Promise.reject(new Error('SSH session is not connected'));
    return new Promise((resolve, reject) => {
      session.client.exec(
        "LC_ALL=C awk 'NR == 1 { total = 0; for (i = 2; i <= NF; i++) total += $i; idle = $5 + $6; printf \"cpu_total=%d\\ncpu_idle=%d\\n\", total, idle; exit }' /proc/stat 2>/dev/null; awk '/^MemTotal:/ { total = $2 } /^MemAvailable:/ { available = $2 } END { if (total > 0 && available >= 0) printf \"mem=%d\\n\", ((total - available) * 100 / total) }' /proc/meminfo 2>/dev/null; df -P / 2>/dev/null | awk 'NR == 2 { gsub(/%/, \"\", $5); printf \"disk=%s\\n\", $5 }'",
        (error, channel) => {
          if (error) { reject(error); return; }
          let output = '';
          channel.on('data', (chunk: Buffer | string) => { output += chunk.toString(); });
          channel.on('close', () => {
            const values = Object.fromEntries(output.trim().split(/\r?\n/).filter(Boolean).map(line => line.split('='))) as Record<string, string>;
            const total = Number.parseInt(values.cpu_total ?? '', 10);
            const idle = Number.parseInt(values.cpu_idle ?? '', 10);
            const previous = this.cpuSamples.get(id);
            const cpu = previous && Number.isFinite(total) && Number.isFinite(idle)
              ? percentFromCpuSample(total - previous.total, idle - previous.idle)
              : null;
            if (Number.isFinite(total) && Number.isFinite(idle)) this.cpuSamples.set(id, { total, idle });
            resolve({
              cpu,
              memory: boundedPercent(values.mem),
              disk: boundedPercent(values.disk),
              label: 'REMOTE SESSION',
            });
          });
          channel.on('error', reject);
        },
      );
    });
  }

  listFiles(id: string, path: string): Promise<RemoteFile[]> {
    return this.openSftp(id).then(sftp => new Promise((resolve, reject) => {
        sftp.readdir(path, (readError, entries) => {
          if (readError) { reject(readError); return; }
          resolve(entries.map(entry => {
            const attrs = entry.attrs;
            const mode = attrs.mode ?? 0;
            const type = (mode & 0o170000) === 0o040000 ? 'directory' : (mode & 0o170000) === 0o120000 ? 'link' : 'file';
            return {
              name: entry.filename,
              path: `${path.replace(/\/$/, '')}/${entry.filename}`,
              type,
              size: Number(attrs.size ?? 0),
              permissions: mode ? (mode & 0o777).toString(8).padStart(3, '0') : undefined,
              modifiedAt: attrs.mtime ? new Date(attrs.mtime * 1000).toISOString() : undefined,
              owner: attrs.uid !== undefined && attrs.gid !== undefined ? `${attrs.uid}:${attrs.gid}` : undefined,
            };
          }));
        });
      }));
  }

  async upload(id: string, localPath: string, remotePath: string, onProgress?: (transferred: number, total: number) => void): Promise<void> {
    const sftp = await this.openSftp(id);
    // Keep relative SFTP destinations explicitly relative. `path.posix.join`
    // removes the leading `./`, which several restricted/chrooted SFTP
    // servers reject even though they list the same directory successfully.
    const target = uploadTarget(remotePath, pathModule.basename(localPath));
    await new Promise<void>((resolve, reject) => {
      sftp.fastPut(localPath, target, { step: (transferred, _chunk, total) => onProgress?.(transferred, total) }, error => error ? reject(error) : resolve());
    });
  }

  async download(id: string, remotePath: string, localPath: string, onProgress?: (transferred: number, total: number) => void): Promise<void> {
    const sftp = await this.openSftp(id);
    await new Promise<void>((resolve, reject) => {
      sftp.fastGet(remotePath, localPath, { step: (transferred, _chunk, total) => onProgress?.(transferred, total) }, error => error ? reject(error) : resolve());
    });
  }

  mkdir(id: string, path: string): Promise<void> {
    return this.openSftp(id).then(sftp => new Promise((resolve, reject) => sftp.mkdir(path, error => error ? reject(error) : resolve())));
  }

  renameFile(id: string, path: string, newPath: string): Promise<void> {
    return this.openSftp(id).then(sftp => new Promise((resolve, reject) => sftp.rename(path, newPath, error => error ? reject(error) : resolve())));
  }

  deleteFile(id: string, path: string, directory: boolean): Promise<void> {
    return this.openSftp(id).then(sftp => directory ? removeTree(sftp, path) : new Promise((resolve, reject) => sftp.unlink(path, error => error ? reject(error) : resolve())));
  }

  chmod(id: string, path: string, mode: number): Promise<void> {
    return this.openSftp(id).then(sftp => new Promise((resolve, reject) => sftp.chmod(path, mode, error => error ? reject(error) : resolve())));
  }

  chown(id: string, path: string, uid: number, gid: number): Promise<void> {
    return this.openSftp(id).then(sftp => new Promise((resolve, reject) => sftp.chown(path, uid, gid, error => error ? reject(error) : resolve())));
  }

  async copyFile(id: string, source: string, target: string): Promise<void> {
    const sftp = await this.openSftp(id);
    const directory = await mkdtemp(pathModule.join(os.tmpdir(), 'morixterm-sftp-'));
    const local = pathModule.join(directory, 'transfer');
    try {
      await copyTree(sftp, source, target, local);
    } finally { await rm(directory, { recursive: true, force: true }); }
  }

  private openSftp(id: string): Promise<Sftp> {
    const session = this.sessions.get(id);
    if (!session) return Promise.reject(new Error('SSH session is not connected'));
    return new Promise((resolve, reject) => session.client.sftp((error, sftp) => error ? reject(error) : resolve(sftp)));
  }

  disconnect(id: string): void {
    const session = this.sessions.get(id);
    if (!session) return;
    try { session.channel?.end(); } catch { /* ignore */ }
    try { session.client.end(); } catch { /* ignore */ }
    this.sessions.delete(id);
    this.cpuSamples.delete(id);
    if (!session.window.isDestroyed()) {
      session.window.webContents.send('ssh:state', { id, state: 'Disconnected' });
    }
  }

  disconnectAll(): void {
    for (const id of [...this.sessions.keys()]) this.disconnect(id);
  }
}

function boundedPercent(value: string | undefined): number | null {
  if (value === undefined) return null;
  const number = Number.parseInt(value ?? '0', 10);
  return Number.isFinite(number) ? Math.max(0, Math.min(100, number)) : null;
}

function percentFromCpuSample(total: number, idle: number): number | null {
  if (!Number.isFinite(total) || !Number.isFinite(idle) || total <= 0) return null;
  return Math.max(0, Math.min(100, Math.round((total - idle) * 100 / total)));
}

export const sshManager = new SSHConnectionManager();

function uploadTarget(remoteDirectory: string, filename: string): string {
  const directory = remoteDirectory.replace(/\/+$/, '') || '/';
  if (directory === '.') return `./${filename}`;
  if (directory.startsWith('./')) return `${directory}/${filename}`;
  return `${directory}/${filename}`;
}

async function copyTree(sftp: Sftp, source: string, target: string, local: string): Promise<void> {
  const entries = await new Promise<import('ssh2').SftpFile[] | null>((resolve, reject) => sftp.readdir(source, (error, result) => error ? resolve(null) : resolve(result)));
  if (entries === null) {
    await new Promise<void>((resolve, reject) => sftp.fastGet(source, local, {}, (error?: Error) => error ? reject(error) : resolve()));
    await new Promise<void>((resolve, reject) => sftp.fastPut(local, target, {}, (error?: Error) => error ? reject(error) : resolve()));
    return;
  }
  await new Promise<void>((resolve, reject) => sftp.mkdir(target, error => error && !/exist/i.test(error.message) ? reject(error) : resolve()));
  for (const entry of entries) await copyTree(sftp, `${source.replace(/\/$/, '')}/${entry.filename}`, `${target.replace(/\/$/, '')}/${entry.filename}`, `${local}-${entry.filename}`);
}

async function removeTree(sftp: Sftp, target: string): Promise<void> {
  const entries = await new Promise<import('ssh2').SftpFile[] | null>((resolve) => sftp.readdir(target, (error, result) => error ? resolve(null) : resolve(result)));
  if (entries === null) {
    await new Promise<void>((resolve, reject) => sftp.unlink(target, error => error ? reject(error) : resolve()));
    return;
  }
  for (const entry of entries) await removeTree(sftp, `${target.replace(/\/$/, '')}/${entry.filename}`);
  await new Promise<void>((resolve, reject) => sftp.rmdir(target, error => error ? reject(error) : resolve()));
}
