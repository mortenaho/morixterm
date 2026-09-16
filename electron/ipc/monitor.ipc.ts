import { ipcMain } from 'electron';
import { permitted } from '../utils/ipcGuard.js';
import { sshManager } from '../services/ssh/SSHConnectionManager.js';
import { ptyManager } from '../services/terminal/PtyManager.js';
import { z } from 'zod';
import type { MonitorStats } from '../contracts/monitor.js';

const targetSchema = z.object({ transport: z.enum(['pty', 'ssh']), id: z.string().min(1).max(100) });

export function registerMonitorIpc(): void {
  ipcMain.handle('monitor:stats', async (event, value: unknown) => {
    if (!permitted(event)) return { ok: false, message: 'Access denied.' };
    try {
      const target = targetSchema.parse(value);
      return { ok: true, value: await readStats(target) };
    } catch (error) {
      return { ok: false, message: error instanceof Error ? error.message : 'Monitoring unavailable.' };
    }
  });
}

async function readStats(target: z.infer<typeof targetSchema>): Promise<MonitorStats> {
  return target.transport === 'ssh' ? sshManager.stats(target.id) : ptyManager.stats(target.id);
}
