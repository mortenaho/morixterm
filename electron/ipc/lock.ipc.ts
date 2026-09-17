import { ipcMain } from 'electron';
import { z } from 'zod';
import type { AppLockService } from '../services/AppLockService.js';
import { permitted } from '../utils/ipcGuard.js';

const passwordSchema = z.string().min(4).max(256);
const setPasswordSchema = z.object({
  currentPassword: z.string().max(256).optional(),
  newPassword: passwordSchema,
}).strict();

export function registerLockIpc(service: AppLockService): void {
  ipcMain.handle('lock:status', async event => {
    if (!permitted(event)) throw new Error('Access denied.');
    return service.status();
  });
  ipcMain.handle('lock:set-password', async (event, input: unknown) => {
    if (!permitted(event)) return { ok: false, message: 'Access denied.' };
    try {
      const value = setPasswordSchema.parse(input);
      await service.setPassword(value.currentPassword, value.newPassword);
      return { ok: true };
    } catch (error) {
      return { ok: false, message: error instanceof Error ? error.message : 'Could not set the lock password.' };
    }
  });
  ipcMain.handle('lock:lock', async event => {
    if (!permitted(event)) return { ok: false, message: 'Access denied.' };
    return await service.lock()
      ? { ok: true }
      : { ok: false, message: 'Set an application password in Settings first.' };
  });
  ipcMain.handle('lock:unlock', async (event, password: unknown) => {
    if (!permitted(event)) return { ok: false, message: 'Access denied.' };
    try {
      return await service.unlock(passwordSchema.parse(password))
        ? { ok: true }
        : { ok: false, message: 'Incorrect password.' };
    } catch {
      return { ok: false, message: 'Enter a valid password.' };
    }
  });
}
