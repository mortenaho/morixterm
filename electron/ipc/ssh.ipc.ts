import { ipcMain } from 'electron';
import { z } from 'zod';
import { SessionRepository } from '../services/SessionRepository.js';
import { sshManager } from '../services/ssh/SSHConnectionManager.js';
import { permitted, senderWindow } from '../utils/ipcGuard.js';

const idSchema = z.string().min(1).max(100);
const dataSchema = z.object({ id: idSchema, data: z.string().max(100000) }).strict();
const resizeSchema = z.object({ id: idSchema, cols: z.number().int().min(1).max(500), rows: z.number().int().min(1).max(200) }).strict();
const connectSchema = z.object({
  id: idSchema,
  sessionId: z.string().uuid(),
  cols: z.number().int().min(1).max(500).optional(),
  rows: z.number().int().min(1).max(200).optional(),
  password: z.string().max(1000).optional(),
  privateKey: z.string().max(100000).optional(),
}).strict();

export function registerSshIpc(repository: SessionRepository): void {
  ipcMain.handle('ssh:connect', async (event, value: unknown) => {
    if (!permitted(event)) throw new Error('Access denied.');
    const data = connectSchema.parse(value);
    const saved = repository.get(data.sessionId);
    if (!saved || saved.kind !== 'SSH') throw new Error('SSH session not found');
    if (!saved.port) throw new Error('SSH session is missing a port');
    return sshManager.connect(senderWindow(event), {
      id: data.id,
      sessionId: saved.id,
      host: saved.host,
      port: saved.port,
      username: saved.user,
      password: data.password,
      privateKey: data.privateKey,
      cols: data.cols,
      rows: data.rows,
    });
  });

  ipcMain.on('ssh:write', (event, value: unknown) => {
    if (!permitted(event)) return;
    const data = dataSchema.parse(value);
    sshManager.write(data.id, data.data);
  });

  ipcMain.on('ssh:resize', (event, value: unknown) => {
    if (!permitted(event)) return;
    const data = resizeSchema.parse(value);
    sshManager.resize(data.id, data.cols, data.rows);
  });

  ipcMain.on('ssh:disconnect', (event, id: unknown) => {
    if (!permitted(event)) return;
    sshManager.disconnect(idSchema.parse(id));
  });
}
