import { chmodSync, readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname } from 'node:path';
import { appSettingsSchema, defaultSettings, type AppSettings } from '../../contracts/settings.js';

export class SettingsStore {
  private cache: AppSettings;

  constructor(private readonly filename: string) {
    mkdirSync(dirname(filename), { recursive: true, mode: 0o700 });
    if (process.platform !== 'win32' && existsSync(filename)) chmodSync(filename, 0o600);
    this.cache = this.load();
  }

  private load(): AppSettings {
    if (!existsSync(this.filename)) return structuredClone(defaultSettings);
    try {
      return appSettingsSchema.parse(JSON.parse(readFileSync(this.filename, 'utf8')));
    } catch {
      return structuredClone(defaultSettings);
    }
  }

  get(): AppSettings {
    return structuredClone(this.cache);
  }

  set(input: unknown): AppSettings {
    this.cache = appSettingsSchema.parse(input);
    writeFileSync(this.filename, JSON.stringify(this.cache, null, 2), { mode: 0o600 });
    return this.get();
  }
}
