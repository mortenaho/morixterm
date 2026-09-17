import { Client, type ClientChannel, type ConnectConfig, type Sftp } from 'ssh2';
import { BrowserWindow, dialog } from 'electron';
import { getPassword } from '../credentials.js';
import { logger } from '../../utils/logger.js';
import type { ConnectionState } from '../../contracts/terminal.js';
import type { RemoteFile } from '../../contracts/files.js';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import pathModule from 'node:path';
import type { MonitorStats } from '../../contracts/monitor.js';
import { KnownHostsStore } from './KnownHostsStore.js';

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

export const compatibleSshAlgorithms: NonNullable<ConnectConfig['algorithms']> = {
  // ssh2 applies `append` after its modern runtime defaults. The regular
  // expression only visits algorithms supported by the current Electron
  // crypto build, so unavailable algorithms can never abort connection setup.
  // Legacy KEX/ciphers/MACs and ssh-dss remain last-resort options for old
  // appliances while modern peers continue to negotiate modern defaults.
  kex: { append: [/.*/] },
  cipher: { append: [/.*/] },
  serverHostKey: { append: [/.*/] },
  hmac: { append: [/.*/] },
};

export class SSHConnectionManager {
  private readonly sessions = new Map<string, LiveSession>();
  private readonly cpuSamples = new Map<string, { total: number; idle: number }>();
  private readonly monitorPlatforms = new Map<string, 'linux' | 'windows'>();
  private knownHosts?: KnownHostsStore;

  configureKnownHosts(filePath: string): void {
    this.knownHosts = new KnownHostsStore(filePath);
  }

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
        if (!this.knownHosts) throw new Error('SSH host verification is not initialized');
        const config: ConnectConfig = {
          host: input.host,
          port: input.port,
          username: input.username,
          readyTimeout: 15000,
          keepaliveInterval: 10000,
          tryKeyboard: false,
          hostHash: 'sha256',
          hostVerifier: (hash, callback) => {
            void this.verifyHostKey(window, input.host, input.port, hash)
              .then(callback)
              .catch(() => callback(false));
          },
          algorithms: compatibleSshAlgorithms,
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
                  this.monitorPlatforms.delete(input.id);
                  if (!window.isDestroyed()) {
                    window.webContents.send('ssh:closed', { id: input.id });
                    window.webContents.send('ssh:state', { id: input.id, state: 'Disconnected' });
                  }
                });
                logger.info(`SSH connected ${input.id}`);
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

  private async verifyHostKey(window: BrowserWindow, host: string, port: number, hash: string): Promise<boolean> {
    if (!this.knownHosts) return false;
    const endpoint = `${host.trim().toLowerCase()}:${port}`;
    const fingerprint = formatHostFingerprint(hash);
    const trusted = await this.knownHosts.lookup(endpoint);
    if (trusted === fingerprint) return true;

    const changed = trusted !== undefined;
    const response = await dialog.showMessageBox(window, {
      type: 'warning',
      title: changed ? 'SSH host key changed' : 'Unknown SSH host',
      message: changed
        ? 'The SSH host key has changed. This can indicate a man-in-the-middle attack.'
        : 'This SSH host has not been trusted yet.',
      detail: changed
        ? `Host: ${endpoint}\nTrusted: ${trusted}\nReceived: ${fingerprint}\n\nVerify the new fingerprint with the server administrator before continuing.`
        : `Host: ${endpoint}\nFingerprint: ${fingerprint}\n\nVerify this fingerprint with the server administrator before trusting it.`,
      buttons: changed ? ['Cancel', 'Replace key and connect'] : ['Cancel', 'Trust and connect'],
      defaultId: 0,
      cancelId: 0,
      noLink: true,
    });
    if (response.response !== 1) return false;
    await this.knownHosts.remember(endpoint, fingerprint);
    return true;
  }

  private fail(id: string, message: string): void {
    this.setState(id, 'Failed', message);
    const session = this.sessions.get(id);
    try { session?.client.end(); } catch { /* ignore */ }
    this.sessions.delete(id);
    this.cpuSamples.delete(id);
    this.monitorPlatforms.delete(id);
    logger.warn(`SSH failed ${id}: ${message}`);
  }

  write(id: string, data: string): void {
    this.sessions.get(id)?.channel?.write(data);
  }

  resize(id: string, cols: number, rows: number): void {
    this.sessions.get(id)?.channel?.setWindow(rows, cols, 0, 0);
  }

  async stats(id: string): Promise<MonitorStats> {
    const session = this.sessions.get(id);
    if (!session) throw new Error('SSH session is not connected');
    if (this.monitorPlatforms.get(id) === 'windows') return this.readWindowsStats(session);

    const linux = await this.readLinuxStats(session, id);
    if (linux) {
      this.monitorPlatforms.set(id, 'linux');
      return linux;
    }

    const windows = await this.readWindowsStats(session);
    this.monitorPlatforms.set(id, 'windows');
    return windows;
  }

  private async readLinuxStats(session: LiveSession, id: string): Promise<MonitorStats | null> {
    const values = parseMonitorValues(await this.executeMonitorCommand(session, LINUX_MONITOR_COMMAND));
    const total = Number.parseInt(values.cpu_total ?? '', 10);
    const idle = Number.parseInt(values.cpu_idle ?? '', 10);
    if (!Number.isFinite(total) || !Number.isFinite(idle)) return null;
    const previous = this.cpuSamples.get(id);
    const cpu = previous ? percentFromCpuSample(total - previous.total, idle - previous.idle) : null;
    this.cpuSamples.set(id, { total, idle });
    return { cpu, memory: boundedPercent(values.mem), disk: boundedPercent(values.disk), label: 'LINUX SSH' };
  }

  private async readWindowsStats(session: LiveSession): Promise<MonitorStats> {
    const values = parseMonitorValues(await this.executeMonitorCommand(session, WINDOWS_MONITOR_COMMAND));
    if (values.cpu === undefined && values.mem === undefined && values.disk === undefined) {
      throw new Error('The SSH host does not provide Linux or Windows monitoring commands.');
    }
    return { cpu: boundedPercent(values.cpu), memory: boundedPercent(values.mem), disk: boundedPercent(values.disk), label: 'WINDOWS SSH' };
  }

  private executeMonitorCommand(session: LiveSession, command: string): Promise<string> {
    return new Promise((resolve, reject) => {
      session.client.exec(
        command,
        (error, channel) => {
          if (error) { reject(error); return; }
          let output = '';
          channel.on('data', (chunk: Buffer | string) => { output += chunk.toString(); });
          channel.on('close', () => resolve(output));
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
    this.monitorPlatforms.delete(id);
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

function formatHostFingerprint(hexHash: string): string {
  if (!/^[0-9a-f]+$/i.test(hexHash) || hexHash.length % 2 !== 0) {
    throw new Error('The SSH server returned an invalid host-key fingerprint.');
  }
  return `SHA256:${Buffer.from(hexHash, 'hex').toString('base64').replace(/=+$/, '')}`;
}

function parseMonitorValues(output: string): Record<string, string> {
  return Object.fromEntries(
    output.trim().split(/\r?\n/).flatMap(line => {
      const separator = line.indexOf('=');
      return separator > 0 ? [[line.slice(0, separator).trim(), line.slice(separator + 1).trim()]] : [];
    }),
  );
}

const LINUX_MONITOR_COMMAND = "LC_ALL=C awk 'NR == 1 { total = 0; for (i = 2; i <= NF; i++) total += $i; idle = $5 + $6; printf \"cpu_total=%d\\ncpu_idle=%d\\n\", total, idle; exit }' /proc/stat 2>/dev/null; awk '/^MemTotal:/ { total = $2 } /^MemAvailable:/ { available = $2 } END { if (total > 0 && available >= 0) printf \"mem=%d\\n\", ((total - available) * 100 / total) }' /proc/meminfo 2>/dev/null; df -P / 2>/dev/null | awk 'NR == 2 { gsub(/%/, \"\", $5); printf \"disk=%s\\n\", $5 }'";

const WINDOWS_MONITOR_COMMAND = `powershell.exe -NoProfile -NonInteractive -EncodedCommand ${Buffer.from(`
$cpu = [math]::Round((Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average)
$os = Get-CimInstance Win32_OperatingSystem
$mem = if ($os.TotalVisibleMemorySize -gt 0) { [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) * 100) / $os.TotalVisibleMemorySize) }
$drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$disk = if ($drive -and $drive.Size -gt 0) { [math]::Round((($drive.Size - $drive.FreeSpace) * 100) / $drive.Size) }
Write-Output "cpu=$cpu"
Write-Output "mem=$mem"
Write-Output "disk=$disk"
`, 'utf16le').toString('base64')}`;

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
