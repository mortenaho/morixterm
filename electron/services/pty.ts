import type { BrowserWindow } from 'electron';
import { ptyManager } from './terminal/PtyManager.js';

export { ptyManager, PtyManager } from './terminal/PtyManager.js';

export const startPty = (window: BrowserWindow, id: string) => ptyManager.start(window, id);
export const writePty = (id: string, data: string) => ptyManager.write(id, data);
export const resizePty = (id: string, cols: number, rows: number) => ptyManager.resize(id, cols, rows);
export const stopPty = (id: string) => ptyManager.stop(id);
