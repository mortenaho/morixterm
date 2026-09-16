import { ipcMain } from 'electron';
import type { SettingsStore } from '../services/settings/SettingsStore.js';
import { permitted } from '../utils/ipcGuard.js';

export function registerSettingsIpc(store: SettingsStore): void {
  ipcMain.handle('settings:get', event => {
    if (!permitted(event)) throw new Error('Access denied.');
    return store.get();
  });

  ipcMain.handle('settings:set', (event, value: unknown) => {
    if (!permitted(event)) throw new Error('Access denied.');
    return store.set(value);
  });
}
