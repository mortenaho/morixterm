import { ipcMain } from 'electron';
import { z } from 'zod';
import { randomUUID } from 'node:crypto';
import { ptyManager } from '../services/terminal/PtyManager.js';
import { permitted, senderWindow } from '../utils/ipcGuard.js';

const idSchema = z.string().min(1).max(100);
const dataSchema = z.object({ id: idSchema, data: z.string().max(100000) });
const resizeSchema = z.object({ id: idSchema, cols: z.number().int().min(1).max(500), rows: z.number().int().min(1).max(200) });
const startSchema = z.object({
  cols: z.number().int().min(1).max(500).optional(),
  rows: z.number().int().min(1).max(200).optional(),
  cwd: z.string().max(1024).optional(),
}).default({});

export function registerTerminalIpc(): void {
  ipcMain.handle('pty:start', (event, value: unknown = {}) => {
    if (!permitted(event)) throw new Error('Access denied.');
    const options = startSchema.parse(value ?? {});
    return ptyManager.start(senderWindow(event), randomUUID(), options);
  });

  ipcMain.on('pty:write', (event, value: unknown) => {
    if (!permitted(event)) return;
    const data = dataSchema.parse(value);
    ptyManager.write(data.id, data.data);
  });

  ipcMain.on('pty:resize', (event, value: unknown) => {
    if (!permitted(event)) return;
    const data = resizeSchema.parse(value);
    ptyManager.resize(data.id, data.cols, data.rows);
  });

  ipcMain.on('pty:stop', (event, id: unknown) => {
    if (!permitted(event)) return;
    ptyManager.stop(idSchema.parse(id));
  });
}
