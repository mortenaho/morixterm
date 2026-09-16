import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { z } from 'zod';

const entrySchema = z.object({
  endpoint: z.string().min(1).max(512),
  fingerprint: z.string().regex(/^SHA256:[A-Za-z0-9+/]+$/),
  firstSeen: z.string().datetime(),
  lastSeen: z.string().datetime(),
}).strict();

const fileSchema = z.object({
  version: z.literal(1),
  hosts: z.array(entrySchema).max(5000),
}).strict();

type KnownHostsFile = z.infer<typeof fileSchema>;

export class KnownHostsStore {
  private pending: Promise<unknown> = Promise.resolve();

  constructor(private readonly filePath: string) {}

  lookup(endpoint: string): Promise<string | undefined> {
    return this.pending.then(async () => {
      const file = await this.read();
      return file.hosts.find(item => item.endpoint === endpoint)?.fingerprint;
    });
  }

  remember(endpoint: string, fingerprint: string): Promise<void> {
    const task = this.pending.then(async () => {
      const file = await this.read();
      const now = new Date().toISOString();
      const existing = file.hosts.find(item => item.endpoint === endpoint);
      if (existing) {
        existing.fingerprint = fingerprint;
        existing.lastSeen = now;
      } else {
        file.hosts.push({ endpoint, fingerprint, firstSeen: now, lastSeen: now });
      }
      await this.write(file);
    });
    this.pending = task.catch(() => undefined);
    return task;
  }

  private async read(): Promise<KnownHostsFile> {
    try {
      return fileSchema.parse(JSON.parse(await readFile(this.filePath, 'utf8')));
    } catch (error) {
      const code = (error as NodeJS.ErrnoException).code;
      if (code === 'ENOENT') return { version: 1, hosts: [] };
      throw new Error('The trusted-host database is invalid or unreadable.');
    }
  }

  private async write(value: KnownHostsFile): Promise<void> {
    const directory = path.dirname(this.filePath);
    const temporary = `${this.filePath}.tmp`;
    await mkdir(directory, { recursive: true, mode: 0o700 });
    await writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`, { encoding: 'utf8', mode: 0o600 });
    await rename(temporary, this.filePath);
  }
}
