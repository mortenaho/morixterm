import { randomUUID } from 'node:crypto';
import { saveSessionSchema, type Session } from '../contracts/sessions.js';
import { SessionRepository } from './SessionRepository.js';

export interface PasswordStore {
  getPassword(id: string): Promise<string | null>;
  savePassword(id: string, password: string): Promise<void>;
  deletePassword(id: string): Promise<void>;
}

export class SessionService {
  private pending: Promise<unknown> = Promise.resolve();
  constructor(private readonly repository: SessionRepository, private readonly vault: PasswordStore) {}

  save(input: unknown): Promise<Session> {
    const task = this.pending.then(() => this.persist(input));
    this.pending = task.catch(() => undefined);
    return task;
  }

  private async persist(input: unknown): Promise<Session> {
    const { password, id: existingId, ...fields } = saveSessionSchema.parse(input);
    const previous = existingId ? this.repository.get(existingId) : undefined;
    if (existingId && !previous) throw new Error('Session no longer exists');
    const id = existingId ?? randomUUID();
    const secretChanged = Boolean(password) || (fields.kind === 'LOCAL' && Boolean(previous?.hasPassword));
    const oldPassword = secretChanged ? await this.vault.getPassword(id) : null;
    if (password) await this.vault.savePassword(id, password);
    else if (secretChanged) await this.vault.deletePassword(id);
    try {
      return this.repository.save({ ...fields, id,
        hasPassword: fields.kind !== 'LOCAL' && (Boolean(password) || Boolean(previous?.hasPassword)) }, Boolean(existingId));
    } catch (error) {
      if (secretChanged) {
        if (oldPassword !== null) await this.vault.savePassword(id, oldPassword);
        else await this.vault.deletePassword(id);
      }
      throw error;
    }
  }

  async delete(id: string): Promise<boolean> {
    const task = this.pending.then(async () => {
      const existing = this.repository.get(id);
      if (!existing) return false;
      const removed = this.repository.delete(id);
      if (removed) await this.vault.deletePassword(id);
      return removed;
    });
    this.pending = task.catch(() => undefined);
    return task;
  }

  async duplicate(id: string): Promise<Session> {
    const task = this.pending.then(async () => {
      const source = this.repository.get(id);
      if (!source) throw new Error('Session no longer exists');
      const password = source.hasPassword ? await this.vault.getPassword(id) : null;
      const copyId = randomUUID();
      const copy = this.repository.save({
        ...source,
        id: copyId,
        name: `${source.name} (copy)`,
        favorite: false,
        hasPassword: Boolean(password),
        createdAt: undefined,
        updatedAt: undefined,
      }, false);
      try {
        if (password) await this.vault.savePassword(copyId, password);
        return copy;
      } catch (error) {
        this.repository.delete(copyId);
        throw error;
      }
    });
    this.pending = task.catch(() => undefined);
    return task;
  }
}
