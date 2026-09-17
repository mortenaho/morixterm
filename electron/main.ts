import { app, BrowserWindow, Menu, nativeImage, session, shell } from 'electron';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { z } from 'zod';
import { SessionRepository } from './services/SessionRepository.js';
import { SettingsStore } from './services/settings/SettingsStore.js';
import { registerSessions } from './ipc/sessions.js';
import { registerTerminalIpc } from './ipc/terminal.ipc.js';
import { registerSshIpc } from './ipc/ssh.ipc.js';
import { registerRdpIpc } from './ipc/rdp.ipc.js';
import { registerSettingsIpc } from './ipc/settings.ipc.js';
import { registerFoldersIpc } from './ipc/folders.ipc.js';
import { registerFilesIpc } from './ipc/files.ipc.js';
import { registerMonitorIpc } from './ipc/monitor.ipc.js';
import { registerDatabaseIpc } from './ipc/database.ipc.js';
import { registerLockIpc } from './ipc/lock.ipc.js';
import { ptyManager } from './services/terminal/PtyManager.js';
import { sshManager } from './services/ssh/SSHConnectionManager.js';
import { rdpService } from './services/rdp/RdpService.js';
import { logger } from './utils/logger.js';
import { ipcMain } from 'electron';
import { isTrustedRendererUrl, permitted, setTrustedRendererUrl } from './utils/ipcGuard.js';
import { AppLockService } from './services/AppLockService.js';
import { getAppLockPassword, saveAppLockPassword } from './services/credentials.js';

const connectionSchema = z.object({
  host: z.string().min(1).max(255),
  port: z.number().int().min(1).max(65535),
  username: z.string().min(1).max(128),
}).strict();

let mainWindow: BrowserWindow | null = null;
let repository: SessionRepository | undefined;
let settingsStore: SettingsStore | undefined;
let databaseFilename: string | undefined;

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (!mainWindow) return;
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.focus();
  });
}

function brandingIcon(): Electron.NativeImage | undefined {
  const candidates = [
    path.join(__dirname, '../assets/branding/morixterm-icon.png'),
    path.join(__dirname, '../assets/branding/morixterm-logo.png'),
    path.join(__dirname, '../assets/branding/morixterm-logo.svg'),
  ];
  for (const file of candidates) {
    const image = nativeImage.createFromPath(file);
    if (!image.isEmpty()) return image;
  }
  return undefined;
}

function buildMenu(window: BrowserWindow): void {
  const template: Electron.MenuItemConstructorOptions[] = [
    {
      label: 'File',
      submenu: [
        { label: 'New Terminal', accelerator: 'CmdOrCtrl+Shift+T', click: () => window.webContents.send('menu:command', 'new-terminal') },
        { label: 'New SSH Session', click: () => window.webContents.send('menu:command', 'new-ssh') },
        { label: 'New RDP Session', click: () => window.webContents.send('menu:command', 'new-rdp') },
        { type: 'separator' },
        { role: process.platform === 'darwin' ? 'close' : 'quit' },
      ],
    },
    {
      label: 'Terminal',
      submenu: [
        { label: 'Clear', click: () => window.webContents.send('menu:command', 'clear-terminal') },
        { label: 'Search', accelerator: 'CmdOrCtrl+Shift+F', click: () => window.webContents.send('menu:command', 'search-terminal') },
      ],
    },
    {
      label: 'View',
      submenu: [
        { label: 'Toggle Sidebar', accelerator: 'CmdOrCtrl+B', click: () => window.webContents.send('menu:command', 'toggle-sidebar') },
        { role: 'togglefullscreen' },
        { type: 'separator' },
        { role: 'reload' },
        { role: 'toggleDevTools' },
      ],
    },
    {
      label: 'Help',
      submenu: [
        { label: 'About MoriXterm', click: () => window.webContents.send('menu:command', 'about') },
        { label: 'View Logs', click: () => shell.openPath(app.getPath('logs')) },
      ],
    },
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

function createWindow(): void {
  const icon = brandingIcon();
  const rendererUrl = app.isPackaged
    ? pathToFileURL(path.join(__dirname, '../dist/index.html')).toString()
    : process.env.MORIXTERM_DEV_SERVER_URL ?? 'http://localhost:5173';
  setTrustedRendererUrl(rendererUrl);
  mainWindow = new BrowserWindow({
    width: 1440,
    height: 920,
    minWidth: 1100,
    minHeight: 700,
    backgroundColor: '#080e18',
    title: '',
    show: false,
    icon,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      webSecurity: true,
      allowRunningInsecureContent: false,
      webviewTag: false,
      safeDialogs: true,
      spellcheck: false,
    },
  });

  buildMenu(mainWindow);
  mainWindow.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  mainWindow.webContents.on('will-navigate', (event, url) => {
    if (!isTrustedRendererUrl(url)) event.preventDefault();
  });
  mainWindow.webContents.on('will-attach-webview', event => event.preventDefault());
  mainWindow.once('ready-to-show', () => mainWindow?.show());
  void mainWindow.loadURL(rendererUrl);

  mainWindow.on('closed', () => { mainWindow = null; });
}

ipcMain.handle('app:info', event => permitted(event) ? ({
  version: app.getVersion(),
  platform: process.platform,
  electron: process.versions.electron,
  node: process.versions.node,
  name: 'MoriXterm',
}) : Promise.reject(new Error('Access denied.')));
ipcMain.handle('connection:validate', (event, value: unknown) => permitted(event)
  ? connectionSchema.safeParse(value)
  : { success: false, error: { message: 'Access denied.' } });

if (gotLock) {
  app.whenReady().then(() => {
    app.setName('MoriXterm');
    if (process.platform !== 'win32') process.umask(0o077);
    const clipboardPermissions = new Set(['clipboard-read', 'clipboard-sanitized-write']);
    session.defaultSession.setPermissionRequestHandler((webContents, permission, callback) => {
      callback(clipboardPermissions.has(permission) && isTrustedRendererUrl(webContents.getURL()));
    });
    session.defaultSession.setPermissionCheckHandler((webContents, permission) =>
      Boolean(webContents) && clipboardPermissions.has(permission) && isTrustedRendererUrl(webContents!.getURL()));
    databaseFilename = path.join(app.getPath('userData'), 'morixterm.sqlite');
    SessionRepository.applyPendingRestore(databaseFilename);
    repository = new SessionRepository(databaseFilename);
    settingsStore = new SettingsStore(path.join(app.getPath('userData'), 'settings.json'));
    sshManager.configureKnownHosts(path.join(app.getPath('userData'), 'known-hosts.json'));
    registerSessions(repository);
    registerTerminalIpc();
    registerSshIpc(repository);
    registerRdpIpc(repository);
    registerSettingsIpc(settingsStore);
    registerFoldersIpc(repository);
  registerFilesIpc();
    registerMonitorIpc();
    registerDatabaseIpc(repository, databaseFilename);
    registerLockIpc(new AppLockService({ getPassword: getAppLockPassword, savePassword: saveAppLockPassword }));
    createWindow();
    logger.info('MoriXterm ready');
    app.on('activate', () => {
      if (BrowserWindow.getAllWindows().length === 0) createWindow();
    });
  });

  app.on('will-quit', () => {
    ptyManager.stopAll();
    sshManager.disconnectAll();
    rdpService.disconnectAll();
    repository?.close();
  });

  app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') app.quit();
  });
}
