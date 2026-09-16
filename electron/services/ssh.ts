import type { BrowserWindow } from 'electron';
import { sshManager, type SshConnectInput } from './ssh/SSHConnectionManager.js';

export { sshManager, SSHConnectionManager } from './ssh/SSHConnectionManager.js';
export type { SshConnectInput } from './ssh/SSHConnectionManager.js';

export const connectSsh = (window: BrowserWindow, input: SshConnectInput) => sshManager.connect(window, input);
export const writeSsh = (id: string, data: string) => sshManager.write(id, data);
export const resizeSsh = (id: string, cols: number, rows: number) => sshManager.resize(id, cols, rows);
export const disconnectSsh = (id: string) => sshManager.disconnect(id);
