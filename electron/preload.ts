import { contextBridge, ipcRenderer } from 'electron';

type Unsubscribe = () => void;

function subscribe(channel: string, callback: (value: unknown) => void): Unsubscribe {
  const listener = (_event: Electron.IpcRendererEvent, value: unknown) => callback(value);
  ipcRenderer.on(channel, listener);
  return () => ipcRenderer.removeListener(channel, listener);
}

contextBridge.exposeInMainWorld('mori', {
  appInfo: () => ipcRenderer.invoke('app:info'),
  monitor: { stats: (target: unknown) => ipcRenderer.invoke('monitor:stats', target) },
  validateConnection: (value: unknown) => ipcRenderer.invoke('connection:validate', value),
  settings: {
    get: () => ipcRenderer.invoke('settings:get'),
    set: (value: unknown) => ipcRenderer.invoke('settings:set', value),
  },
  database: {
    backup: () => ipcRenderer.invoke('database:backup'),
    restore: () => ipcRenderer.invoke('database:restore'),
  },
  lock: {
    status: () => ipcRenderer.invoke('lock:status'),
    setPassword: (value: unknown) => ipcRenderer.invoke('lock:set-password', value),
    lock: () => ipcRenderer.invoke('lock:lock'),
    unlock: (password: string) => ipcRenderer.invoke('lock:unlock', password),
  },
  sessions: {
    list: (value: unknown) => ipcRenderer.invoke('sessions:list', value),
    save: (value: unknown) => ipcRenderer.invoke('sessions:save', value),
    duplicate: (id: string) => ipcRenderer.invoke('sessions:duplicate', id),
    delete: (id: string) => ipcRenderer.invoke('sessions:delete', id),
  },
  folders: {
    list: () => ipcRenderer.invoke('folders:list'),
    create: (path: string) => ipcRenderer.invoke('folders:create', { path }),
    rename: (path: string, name: string) => ipcRenderer.invoke('folders:rename', { path, name }),
    delete: (path: string) => ipcRenderer.invoke('folders:delete', path),
  },
  files: {
    list: (value: unknown) => ipcRenderer.invoke('files:list', value),
    upload: (value: unknown) => ipcRenderer.invoke('files:upload', value),
    download: (value: unknown) => ipcRenderer.invoke('files:download', value),
    mkdir: (value: unknown) => ipcRenderer.invoke('files:mkdir', value),
    rename: (value: unknown) => ipcRenderer.invoke('files:rename', value),
    delete: (value: unknown) => ipcRenderer.invoke('files:delete', value),
    chmod: (value: unknown) => ipcRenderer.invoke('files:chmod', value),
    chown: (value: unknown) => ipcRenderer.invoke('files:chown', value),
    copy: (value: unknown) => ipcRenderer.invoke('files:copy', value),
    onProgress: (callback: (value: unknown) => void) => subscribe('files:progress', callback),
  },
  ssh: {
    connect: (value: unknown) => ipcRenderer.invoke('ssh:connect', value),
    write: (value: unknown) => ipcRenderer.send('ssh:write', value),
    resize: (value: unknown) => ipcRenderer.send('ssh:resize', value),
    disconnect: (id: string) => ipcRenderer.send('ssh:disconnect', id),
    onData: (callback: (value: unknown) => void) => subscribe('ssh:data', callback),
    onClosed: (callback: (value: unknown) => void) => subscribe('ssh:closed', callback),
    onState: (callback: (value: unknown) => void) => subscribe('ssh:state', callback),
  },
  rdp: {
    status: () => ipcRenderer.invoke('rdp:status'),
    connect: (value: unknown) => ipcRenderer.invoke('rdp:connect', value),
    disconnect: (id: string) => ipcRenderer.send('rdp:disconnect', id),
    onClosed: (callback: (value: unknown) => void) => subscribe('rdp:closed', callback),
    onError: (callback: (value: unknown) => void) => subscribe('rdp:error', callback),
  },
  pty: {
    start: (value?: unknown) => ipcRenderer.invoke('pty:start', value ?? {}),
    write: (value: unknown) => ipcRenderer.send('pty:write', value),
    resize: (value: unknown) => ipcRenderer.send('pty:resize', value),
    stop: (id: string) => ipcRenderer.send('pty:stop', id),
    onData: (callback: (value: unknown) => void) => subscribe('pty:data', callback),
    onClosed: (callback: (value: unknown) => void) => subscribe('pty:closed', callback),
  },
  onMenuCommand: (callback: (command: string) => void) =>
    subscribe('menu:command', value => callback(String(value))),
});
