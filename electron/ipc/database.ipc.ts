import { app, dialog, ipcMain } from 'electron';
import path from 'node:path';
import { isSqliteFile, type SessionRepository } from '../services/SessionRepository.js';
import { permitted, senderWindow } from '../utils/ipcGuard.js';

export function registerDatabaseIpc(repository: SessionRepository, filename: string): void {
  ipcMain.handle('database:backup', async event => {
    if (!permitted(event)) throw new Error('Access denied.');
    const defaultPath = path.join(path.dirname(filename), `morixterm-backup-${new Date().toISOString().replace(/[:.]/g, '-')}.sqlite`);
    const result = await dialog.showSaveDialog(senderWindow(event), {
      title: 'Backup MoriXterm database',
      defaultPath,
      filters: [{ name: 'SQLite database', extensions: ['sqlite'] }],
    });
    if (result.canceled || !result.filePath) return { ok: false, message: 'Backup canceled.' };
    try {
      repository.backup(result.filePath);
      return { ok: true, path: result.filePath };
    } catch {
      return { ok: false, message: 'Could not create the database backup.' };
    }
  });
  ipcMain.handle('database:restore', async event => {
    if (!permitted(event)) throw new Error('Access denied.');
    const result = await dialog.showOpenDialog(senderWindow(event), {
      title: 'Restore MoriXterm database',
      properties: ['openFile'],
      filters: [{ name: 'SQLite database', extensions: ['sqlite', 'db'] }],
    });
    if (result.canceled || !result.filePaths[0]) return { ok: false, message: 'Restore canceled.' };
    const source = result.filePaths[0];
    if (path.resolve(source) === path.resolve(filename) || !isSqliteFile(source)) {
      return { ok: false, message: 'Selected file is not a valid SQLite backup.' };
    }
    try {
      repository.backup(`${filename}.backup-before-restore-${new Date().toISOString().replace(/[:.]/g, '-')}.sqlite`);
      const { copyFileSync, chmodSync } = await import('node:fs');
      copyFileSync(source, `${filename}.restore-pending.sqlite`);
      if (process.platform !== 'win32') chmodSync(`${filename}.restore-pending.sqlite`, 0o600);
      app.relaunch();
      app.exit(0);
      return { ok: true };
    } catch {
      return { ok: false, message: 'Could not prepare the database restore.' };
    }
  });
}
