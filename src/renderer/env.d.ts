import type { SessionsApi, Session } from '../../electron/contracts/sessions';
import type { FoldersApi } from '../../electron/contracts/folders';
import type { FilesApi } from '../../electron/contracts/files';
import type { AppSettings } from '../../electron/contracts/settings';
import type { ConnectionStatePayload, TerminalClosedPayload, TerminalPayload } from '../../electron/contracts/terminal';
import type { MonitorStats, MonitorTarget } from '../../electron/contracts/monitor';

export {};

type Unsubscribe = () => void;

declare global {
  interface Window {
    mori: {
      appInfo: () => Promise<{ version: string; platform: string; electron: string; node: string; name: string }>;
      monitor: { stats: (target: MonitorTarget) => Promise<{ ok: boolean; value?: MonitorStats; message?: string }> };
      validateConnection: (value: unknown) => Promise<{ success: boolean; error?: unknown }>;
      settings: {
        get: () => Promise<AppSettings>;
        set: (value: unknown) => Promise<AppSettings>;
      };
      sessions: SessionsApi;
      folders: FoldersApi;
      files: FilesApi;
      ssh: {
        connect: (value: unknown) => Promise<{ id: string }>;
        write: (value: unknown) => void;
        resize: (value: unknown) => void;
        disconnect: (id: string) => void;
        onData: (callback: (value: TerminalPayload) => void) => Unsubscribe;
        onClosed: (callback: (value: TerminalClosedPayload) => void) => Unsubscribe;
        onState: (callback: (value: ConnectionStatePayload) => void) => Unsubscribe;
      };
      rdp: {
        status: () => Promise<{ available: boolean; command?: string; hint: string }>;
        connect: (value: unknown) => Promise<{ id: string; command: string }>;
        disconnect: (id: string) => void;
        onClosed: (callback: (value: { id: string; code?: number }) => void) => Unsubscribe;
        onError: (callback: (value: { id: string; message: string }) => void) => Unsubscribe;
      };
      pty: {
        start: (value?: unknown) => Promise<{ id: string; shell: string }>;
        write: (value: unknown) => void;
        resize: (value: unknown) => void;
        stop: (id: string) => void;
        onData: (callback: (value: TerminalPayload) => void) => Unsubscribe;
        onClosed: (callback: (value: TerminalClosedPayload) => void) => Unsubscribe;
      };
      onMenuCommand: (callback: (command: string) => void) => Unsubscribe;
    };
  }
}

export type WorkspaceTab = {
  id: string;
  title: string;
  kind: 'home' | 'sessions' | 'settings' | 'about' | 'terminal' | 'ssh' | 'rdp' | 'files' | 'snippets';
  sessionId?: string;
  transportId?: string;
  session?: Session;
  status?: string;
};
