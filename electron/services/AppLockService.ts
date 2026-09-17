import { timingSafeEqual } from 'node:crypto';

export interface AppLockVault {
  getPassword(): Promise<string | null>;
  savePassword(password: string): Promise<void>;
}

export class AppLockService {
  private locked = false;
  private initialized = false;

  constructor(private readonly vault: AppLockVault) {}

  async status(): Promise<{ configured: boolean; locked: boolean }> {
    const configured = Boolean(await this.vault.getPassword());
    if (!this.initialized) {
      this.locked = configured;
      this.initialized = true;
    }
    return { configured, locked: configured && this.locked };
  }

  async setPassword(currentPassword: string | undefined, newPassword: string): Promise<void> {
    const existing = await this.vault.getPassword();
    if (existing && !safeEqual(existing, currentPassword ?? '')) throw new Error('Current password is incorrect.');
    await this.vault.savePassword(newPassword);
    this.initialized = true;
  }

  async lock(): Promise<boolean> {
    if (!await this.vault.getPassword()) return false;
    this.locked = true;
    this.initialized = true;
    return true;
  }

  async unlock(password: string): Promise<boolean> {
    const existing = await this.vault.getPassword();
    if (!existing || !safeEqual(existing, password)) return false;
    this.locked = false;
    this.initialized = true;
    return true;
  }
}

function safeEqual(left: string, right: string): boolean {
  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);
  return leftBuffer.length === rightBuffer.length && timingSafeEqual(leftBuffer, rightBuffer);
}
