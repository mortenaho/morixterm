import { ipcMain, type IpcMainInvokeEvent } from 'electron';
import { z } from 'zod';
import { duplicateSessionSchema, type Result } from '../contracts/sessions.js';
import { SessionRepository } from '../services/SessionRepository.js';
import { SessionService } from '../services/SessionService.js';
import * as vault from '../services/credentials.js';
import { permitted } from '../utils/ipcGuard.js';

export function registerSessions(repository: SessionRepository): void {
  const service = new SessionService(repository, vault);
  const idSchema = z.string().uuid();

  ipcMain.handle('sessions:list', (event, input): Result<ReturnType<SessionRepository['list']>> => {
    if (!permitted(event)) return { ok: false, message: 'Access denied.' };
    try { return { ok: true, value: repository.list(input) }; }
    catch { return { ok: false, message: 'Could not load sessions. Please retry.' }; }
  });

  ipcMain.handle('sessions:save', async (event, input) => {
    if (!permitted(event)) return { ok: false, message: 'Access denied.' };
    try { return { ok: true, value: await service.save(input) }; }
    catch { return { ok: false, message: 'Could not save the session. Check the fields and system credential store, then retry.' }; }
  });

  ipcMain.handle('sessions:delete', async (event: IpcMainInvokeEvent, id: unknown) => {
    if (!permitted(event)) return { ok: false, message: 'Access denied.' };
    try {
      const sessionId = idSchema.parse(id);
      return { ok: true, value: await service.delete(sessionId) };
    } catch {
      return { ok: false, message: 'Could not delete the session.' };
    }
  });

  ipcMain.handle('sessions:duplicate', async (event, id: unknown) => {
    if (!permitted(event)) return { ok: false, message: 'Access denied.' };
    try {
      return { ok: true, value: await service.duplicate(duplicateSessionSchema.parse(id)) };
    } catch {
      return { ok: false, message: 'Could not duplicate the session.' };
    }
  });
}
