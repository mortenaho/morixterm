import { ipcMain } from 'electron';
import { z } from 'zod';
import { SessionRepository } from '../services/SessionRepository.js';
import { rdpService } from '../services/rdp/RdpService.js';
import { getPassword } from '../services/credentials.js';
import { permitted, senderWindow } from '../utils/ipcGuard.js';

const idSchema = z.string().min(1).max(100);
const connectSchema = z.object({
  id: idSchema,
  sessionId: z.string().uuid().optional(),
  host: z.string().min(1).max(255).optional(),
  port: z.number().int().min(1).max(65535).optional(),
  username: z.string().min(1).max(128).optional(),
  password: z.string().max(1000).optional(),
  domain: z.string().max(128).optional(),
});

export function registerRdpIpc(repository: SessionRepository): void {
  ipcMain.handle('rdp:status', event => {
    if (!permitted(event)) throw new Error('Access denied.');
    return rdpService.status();
  });

  ipcMain.handle('rdp:connect', async (event, value: unknown) => {
    if (!permitted(event)) throw new Error('Access denied.');
    const data = connectSchema.parse(value);
    let host = data.host;
    let port = data.port ?? 3389;
    let username = data.username;
    let password = data.password;
    let domain = data.domain;

    if (data.sessionId) {
      const saved = repository.get(data.sessionId);
      if (!saved || saved.kind !== 'RDP') throw new Error('RDP session not found');
      host = saved.host;
      port = saved.port ?? 3389;
      username = saved.user;
      password = password || (await getPassword(saved.id)) || undefined;
    }

    if (!host || !username) throw new Error('RDP host and username are required');

    try {
      return await rdpService.connect(senderWindow(event), {
        id: data.id,
        host,
        port,
        username,
        password,
        domain,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'RDP connection failed';
      throw new Error(message);
    }
  });

  ipcMain.on('rdp:disconnect', (event, id: unknown) => {
    if (!permitted(event)) return;
    rdpService.disconnect(idSchema.parse(id));
  });
}
