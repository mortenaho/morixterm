import { BrowserWindow, type IpcMainInvokeEvent, type IpcMainEvent } from 'electron';

let trustedRendererUrl: URL | undefined;

export function setTrustedRendererUrl(value: string): void {
  trustedRendererUrl = new URL(value);
}

export function isTrustedRendererUrl(value: string): boolean {
  if (!trustedRendererUrl) return false;
  try {
    const candidate = new URL(value);
    if (trustedRendererUrl.protocol === 'file:') {
      return candidate.protocol === 'file:' && candidate.pathname === trustedRendererUrl.pathname;
    }
    return candidate.origin === trustedRendererUrl.origin;
  } catch {
    return false;
  }
}

export function permitted(event: IpcMainInvokeEvent | IpcMainEvent): boolean {
  const window = BrowserWindow.fromWebContents(event.sender);
  const frame = event.senderFrame;
  return Boolean(window)
    && frame === event.sender.mainFrame
    && Boolean(frame?.url)
    && isTrustedRendererUrl(frame.url);
}

export function senderWindow(event: IpcMainInvokeEvent | IpcMainEvent): BrowserWindow {
  if (!permitted(event)) throw new Error('Untrusted IPC sender');
  const window = BrowserWindow.fromWebContents(event.sender);
  if (!window) throw new Error('No browser window for IPC sender');
  return window;
}
