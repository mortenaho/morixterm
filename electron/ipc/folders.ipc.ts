import { ipcMain } from 'electron';
import { createFolderSchema, folderPathSchema, renameFolderSchema } from '../contracts/folders.js';
import { SessionRepository } from '../services/SessionRepository.js';
import { permitted } from '../utils/ipcGuard.js';

export function registerFoldersIpc(repository: SessionRepository): void {
  ipcMain.handle('folders:list', event => {
    if (!permitted(event)) return { ok: false, message: 'Access denied.' };
    try { return { ok: true, value: repository.listFolders() }; }
    catch { return { ok: false, message: 'Could not load folders.' }; }
  });
  ipcMain.handle('folders:create', (event, input: unknown) => {
    if (!permitted(event)) return { ok: false, message: 'Access denied.' };
    try { return { ok: true, value: repository.createFolder(createFolderSchema.parse(input).path) }; }
    catch { return { ok: false, message: 'Could not create the folder.' }; }
  });
  ipcMain.handle('folders:rename', (event, input: unknown) => {
    if (!permitted(event)) return { ok: false, message: 'Access denied.' };
    try { const data = renameFolderSchema.parse(input); return { ok: true, value: repository.renameFolder(data.path, data.name) }; }
    catch { return { ok: false, message: 'Could not rename the folder.' }; }
  });
  ipcMain.handle('folders:delete', (event, path: unknown) => {
    if (!permitted(event)) return { ok: false, message: 'Access denied.' };
    try { return { ok: true, value: repository.deleteFolder(folderPathSchema.parse(path)) }; }
    catch { return { ok: false, message: 'Could not delete the folder.' }; }
  });
}
