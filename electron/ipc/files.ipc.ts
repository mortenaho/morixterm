import { dialog, ipcMain } from 'electron';
import { z } from 'zod';
import { chmodFileSchema, chownFileSchema, copyFileSchema, listFilesSchema, remoteFileSchema, renameFileSchema, transferFileSchema } from '../contracts/files.js';
import { sshManager } from '../services/ssh/SSHConnectionManager.js';
import { permitted, senderWindow } from '../utils/ipcGuard.js';
import path from 'node:path';
import { logger } from '../utils/logger.js';

export function registerFilesIpc(): void {
  ipcMain.handle('files:list', async (event, input: unknown) => {
    if (!permitted(event)) return { ok: false, message: 'Access denied.' };
    try { const data = listFilesSchema.parse(input); return { ok: true, value: await sshManager.listFiles(data.id, data.path) }; }
    catch { return { ok: false, message: 'Could not list the remote directory.' }; }
  });
  ipcMain.handle('files:upload', async (event, input: unknown) => {
    if (!permitted(event)) return { ok: false, message: 'Access denied.' };
    try {
      const data = transferFileSchema.parse(input);
      const picked = await dialog.showOpenDialog(senderWindow(event), { properties: ['openFile'] });
      if (picked.canceled || !picked.filePaths[0]) return { ok: true, value: false };
      await sshManager.upload(data.id, picked.filePaths[0], data.remotePath, (transferred, total) => event.sender.send('files:progress', { id: data.id, direction: 'upload', transferred, total }));
      event.sender.send('files:progress', { id: data.id, direction: 'upload', transferred: 1, total: 1, complete: true });
      return { ok: true, value: true };
    } catch (error) {
      logger.warn(`SFTP upload failed: ${safeTransferError(error)}`);
      return { ok: false, message: safeTransferError(error, 'Could not upload the file.') };
    }
  });
  ipcMain.handle('files:copy', async (event, input: unknown) => {
    if (!permitted(event)) return { ok: false, message: 'Access denied.' };
    try { const data = copyFileSchema.parse(input); await sshManager.copyFile(data.id, data.source, data.target); return { ok: true, value: true }; }
    catch { return { ok: false, message: 'Could not copy the remote file.' }; }
  });
  ipcMain.handle('files:download', async (event, input: unknown) => {
    if (!permitted(event)) return { ok: false, message: 'Access denied.' };
    try {
      const data = transferFileSchema.parse(input);
      const picked = await dialog.showSaveDialog(senderWindow(event), { defaultPath: path.basename(data.remotePath) });
      if (picked.canceled || !picked.filePath) return { ok: true, value: false };
      await sshManager.download(data.id, data.remotePath, picked.filePath, (transferred, total) => event.sender.send('files:progress', { id: data.id, direction: 'download', transferred, total }));
      event.sender.send('files:progress', { id: data.id, direction: 'download', transferred: 1, total: 1, complete: true });
      return { ok: true, value: true };
    } catch (error) {
      logger.warn(`SFTP download failed: ${safeTransferError(error)}`);
      return { ok: false, message: safeTransferError(error, 'Could not download the file.') };
    }
  });
  ipcMain.handle('files:mkdir', async (event, input: unknown) => {
    if (!permitted(event)) return { ok: false, message: 'Access denied.' };
    try { const data = remoteFileSchema.parse(input); await sshManager.mkdir(data.id, data.path); return { ok: true, value: true }; }
    catch { return { ok: false, message: 'Could not create the directory.' }; }
  });
  ipcMain.handle('files:rename', async (event, input: unknown) => {
    if (!permitted(event)) return { ok: false, message: 'Access denied.' };
    try { const data = renameFileSchema.parse(input); await sshManager.renameFile(data.id, data.path, data.newPath); return { ok: true, value: true }; }
    catch { return { ok: false, message: 'Could not rename the remote item.' }; }
  });
  ipcMain.handle('files:delete', async (event, input: unknown) => {
    if (!permitted(event)) return { ok: false, message: 'Access denied.' };
    try { const data = remoteFileSchema.extend({ directory: z.boolean().default(false) }).parse(input); await sshManager.deleteFile(data.id, data.path, data.directory); return { ok: true, value: true }; }
    catch { return { ok: false, message: 'Could not delete the remote item.' }; }
  });
  ipcMain.handle('files:chmod', async (event, input: unknown) => {
    if (!permitted(event)) return { ok: false, message: 'Access denied.' };
    try { const data = chmodFileSchema.parse(input); await sshManager.chmod(data.id, data.path, data.mode); return { ok: true, value: true }; }
    catch (error) { logger.warn(`SFTP chmod failed: ${safeSftpError(error)}`); return { ok: false, message: safeSftpError(error, 'Could not change permissions.') }; }
  });
  ipcMain.handle('files:chown', async (event, input: unknown) => {
    if (!permitted(event)) return { ok: false, message: 'Access denied.' };
    try { const data = chownFileSchema.parse(input); await sshManager.chown(data.id, data.path, data.uid, data.gid); return { ok: true, value: true }; }
    catch (error) { logger.warn(`SFTP chown failed: ${safeSftpError(error)}`); return { ok: false, message: safeSftpError(error, 'Could not change owner.') }; }
  });
}

function safeSftpError(error: unknown, fallback = 'Remote file operation was rejected.'): string {
  const value = error as { code?: number; message?: string };
  if (value?.code === 3 || /permission denied|operation not permitted/i.test(value?.message ?? '')) return 'The SSH user does not have permission to change this item.';
  if (/not supported/i.test(value?.message ?? '')) return 'The remote SFTP server does not support this operation.';
  return fallback;
}

function safeTransferError(error: unknown, fallback = 'Remote file transfer failed.'): string {
  const value = error as { code?: number; message?: string };
  if (value?.code === 2 || /no such file|not found/i.test(value?.message ?? '')) return 'The selected remote path was not found.';
  if (value?.code === 3 || /permission denied|operation not permitted/i.test(value?.message ?? '')) return 'The SSH user cannot read or write this path.';
  if (value?.code === 4 || /failure/i.test(value?.message ?? '')) return 'The SFTP server rejected the upload. Check that this directory allows write access.';
  if (/failure|unable|error/i.test(value?.message ?? '')) return fallback;
  return fallback;
}
