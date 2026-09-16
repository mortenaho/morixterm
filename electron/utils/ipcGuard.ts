import { BrowserWindow, type IpcMainInvokeEvent, type IpcMainEvent } from 'electron';

export function permitted(event: IpcMainInvokeEvent | IpcMainEvent): boolean {
  const window = BrowserWindow.fromWebContents(event.sender);
  return Boolean(window) && event.senderFrame === event.sender.mainFrame;
}

export function senderWindow(event: IpcMainInvokeEvent | IpcMainEvent): BrowserWindow {
  const window = BrowserWindow.fromWebContents(event.sender);
  if (!window) throw new Error('No browser window for IPC sender');
  return window;
}
