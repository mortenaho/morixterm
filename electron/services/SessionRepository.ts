import { DatabaseSync } from 'node:sqlite';
import { chmodSync, copyFileSync, existsSync, mkdirSync, readFileSync, unlinkSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { listSessionsSchema, sessionFields, type Session, type SessionPage } from '../contracts/sessions.js';
import type { Folder } from '../contracts/folders.js';
import { randomUUID } from 'node:crypto';

export class SessionRepository {
  private readonly db: DatabaseSync;
  private readonly filename: string;

  constructor(filename: string) {
    this.filename = filename;
    mkdirSync(dirname(filename), { recursive: true, mode: 0o700 });
    this.db = new DatabaseSync(filename);
    if (process.platform !== 'win32') chmodSync(filename, 0o600);
    this.db.exec('PRAGMA busy_timeout = 5000; PRAGMA journal_mode = WAL;');
    this.db.exec('PRAGMA foreign_keys = ON; PRAGMA trusted_schema = OFF;');
    if (process.platform !== 'win32') {
      for (const file of [filename, `${filename}-wal`, `${filename}-shm`]) {
        if (existsSync(file)) chmodSync(file, 0o600);
      }
    }
    const version = Number(this.db.prepare('PRAGMA user_version').get()?.user_version);
    if (version > 4) { this.db.close(); throw new Error('Unsupported database version'); }
    if (version > 0 && version < 4) backupBeforeMigration(this.db, filename, version);
    if (version === 0) {
      this.db.exec(`BEGIN IMMEDIATE;
        CREATE TABLE sessions (
          id TEXT PRIMARY KEY NOT NULL,
          name TEXT NOT NULL, host TEXT NOT NULL, port INTEGER,
          user TEXT NOT NULL, kind TEXT NOT NULL CHECK(kind IN ('SSH','RDP','LOCAL')),
          platform TEXT NOT NULL DEFAULT 'LINUX' CHECK(platform IN ('LINUX','WINDOWS')),
          color TEXT NOT NULL, group_name TEXT NOT NULL,
          favorite INTEGER NOT NULL CHECK(favorite IN (0,1)),
          has_password INTEGER NOT NULL CHECK(has_password IN (0,1)),
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          CHECK ((kind = 'LOCAL' AND port IS NULL) OR (kind != 'LOCAL' AND port BETWEEN 1 AND 65535))
        ) STRICT;
        CREATE TABLE folders (
          id TEXT PRIMARY KEY NOT NULL,
          path TEXT NOT NULL UNIQUE,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        ) STRICT;
        PRAGMA user_version = 4;
        COMMIT;`);
    } else if (version === 1) {
      const now = new Date().toISOString();
      this.db.exec('BEGIN IMMEDIATE;');
      try {
        this.db.prepare('ALTER TABLE sessions ADD COLUMN created_at TEXT').run();
        this.db.prepare('ALTER TABLE sessions ADD COLUMN updated_at TEXT').run();
        this.db.prepare("ALTER TABLE sessions ADD COLUMN platform TEXT NOT NULL DEFAULT 'LINUX' CHECK(platform IN ('LINUX','WINDOWS'))").run();
        this.db.prepare('UPDATE sessions SET created_at = ?, updated_at = ? WHERE created_at IS NULL OR updated_at IS NULL').run(now, now);
        this.db.exec(`CREATE TABLE folders (
          id TEXT PRIMARY KEY NOT NULL,
          path TEXT NOT NULL UNIQUE,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        ) STRICT;`);
        this.db.exec('PRAGMA user_version = 4; COMMIT;');
      } catch (error) {
        this.db.exec('ROLLBACK;');
        throw error;
      }
    } else if (version === 2) {
      this.db.exec(`BEGIN IMMEDIATE;
        ALTER TABLE sessions ADD COLUMN platform TEXT NOT NULL DEFAULT 'LINUX' CHECK(platform IN ('LINUX','WINDOWS'));
        CREATE TABLE folders (
          id TEXT PRIMARY KEY NOT NULL,
          path TEXT NOT NULL UNIQUE,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        ) STRICT;
        PRAGMA user_version = 4;
        COMMIT;`);
    } else if (version === 3) {
      this.db.exec(`BEGIN IMMEDIATE;
        ALTER TABLE sessions ADD COLUMN platform TEXT NOT NULL DEFAULT 'LINUX' CHECK(platform IN ('LINUX','WINDOWS'));
        PRAGMA user_version = 4;
        COMMIT;`);
    }
  }

  private decode(row: Record<string, unknown>): Session {
    const fields = sessionFields.parse({ name: row.name, host: row.host,
      port: row.port === null ? undefined : row.port, user: row.user, kind: row.kind,
      platform: row.platform === 'WINDOWS' ? 'WINDOWS' : 'LINUX',
      color: row.color, group: row.group_name, favorite: row.favorite === 1 });
    const createdAt = String(row.created_at ?? new Date(0).toISOString());
    const updatedAt = String(row.updated_at ?? createdAt);
    return { ...fields, id: String(row.id), hasPassword: row.has_password === 1, createdAt, updatedAt };
  }

  get(id: string): Session | undefined {
    const row = this.db.prepare('SELECT * FROM sessions WHERE id = ?').get(id);
    return row ? this.decode(row) : undefined;
  }

  list(input: unknown): SessionPage {
    const { query, pageSize, favoritesOnly, page: requestedPage } = listSessionsSchema.parse(input);
    // Literal substring matching, including apostrophes and LIKE wildcard characters.
    const where = `WHERE (? = 0 OR favorite = 1) AND
      (instr(lower(name), lower(?)) > 0 OR instr(lower(host), lower(?)) > 0 OR instr(lower(group_name), lower(?)) > 0)`;
    const parameters = [Number(favoritesOnly), query, query, query];
    const total = Number(this.db.prepare(`SELECT count(*) AS total FROM sessions ${where}`).get(...parameters)?.total);
    const allTotal = Number(this.db.prepare('SELECT count(*) AS total FROM sessions').get()?.total);
    const page = Math.min(requestedPage, Math.max(1, Math.ceil(total / pageSize)));
    const rows = this.db.prepare(`SELECT * FROM sessions ${where} ORDER BY rowid DESC LIMIT ? OFFSET ?`)
      .all(...parameters, pageSize, (page - 1) * pageSize);
    return { items: rows.map(row => this.decode(row)), total, allTotal, page, pageSize };
  }

  save(session: Omit<Session, 'createdAt' | 'updatedAt'> & Partial<Pick<Session, 'createdAt' | 'updatedAt'>>, update: boolean): Session {
    if (update && !this.get(session.id)) throw new Error('Session no longer exists');
    const now = new Date().toISOString();
    const createdAt = update ? this.get(session.id)?.createdAt ?? session.createdAt ?? now : session.createdAt ?? now;
    const updatedAt = session.updatedAt ?? now;
    const values = [session.name, session.host, session.port ?? null, session.user, session.kind,
      session.platform, session.color, session.group, Number(session.favorite), Number(session.hasPassword), createdAt,
      update ? now : updatedAt, session.id];
    if (update) {
      this.db.prepare(`UPDATE sessions SET name=?,host=?,port=?,user=?,kind=?,platform=?,color=?,group_name=?,favorite=?,has_password=?,created_at=?,updated_at=? WHERE id=?`).run(...values);
    } else {
      this.db.prepare(`INSERT INTO sessions (name,host,port,user,kind,platform,color,group_name,favorite,has_password,created_at,updated_at,id) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)`).run(...values);
    }
    return this.get(session.id)!;
  }

  delete(id: string): boolean {
    const result = this.db.prepare('DELETE FROM sessions WHERE id = ?').run(id);
    return Number(result.changes) > 0;
  }

  listFolders(): Folder[] {
    const rows = this.db.prepare('SELECT id, path, created_at, updated_at FROM folders ORDER BY path COLLATE NOCASE').all();
    return rows.map(row => ({ id: String(row.id), path: String(row.path), createdAt: String(row.created_at), updatedAt: String(row.updated_at) }));
  }

  createFolder(path: string): Folder {
    const normalized = normalizeFolderPath(path);
    const parts = normalized.split('/');
    let current = '';
    const now = new Date().toISOString();
    this.db.exec('BEGIN IMMEDIATE;');
    try {
      for (const part of parts) {
        current = current ? `${current}/${part}` : part;
        const existing = this.db.prepare('SELECT id, path, created_at, updated_at FROM folders WHERE path = ?').get(current);
        if (!existing) this.db.prepare('INSERT INTO folders (id,path,created_at,updated_at) VALUES (?,?,?,?)').run(randomUUID(), current, now, now);
      }
      this.db.exec('COMMIT;');
    } catch (error) {
      this.db.exec('ROLLBACK;');
      throw error;
    }
    return this.listFolders().find(folder => folder.path === normalized)!;
  }

  renameFolder(path: string, name: string): Folder {
    const oldPath = normalizeFolderPath(path);
    const parent = oldPath.includes('/') ? oldPath.slice(0, oldPath.lastIndexOf('/')) : '';
    const newPath = normalizeFolderPath(parent ? `${parent}/${name}` : name);
    if (oldPath === newPath) return this.listFolders().find(folder => folder.path === oldPath)!;
    const now = new Date().toISOString();
    this.db.exec('BEGIN IMMEDIATE;');
    try {
      const exists = this.db.prepare('SELECT id FROM folders WHERE path = ?').get(oldPath);
      if (!exists) throw new Error('Folder not found');
      if (this.db.prepare('SELECT id FROM folders WHERE path = ?').get(newPath)) throw new Error('Folder already exists');
      const descendants = this.db.prepare("SELECT id, path FROM folders WHERE path = ? OR path LIKE ? ORDER BY length(path) DESC").all(oldPath, `${oldPath}/%`);
      for (const row of descendants) {
        const current = String(row.path);
        const replacement = current === oldPath ? newPath : `${newPath}${current.slice(oldPath.length)}`;
        this.db.prepare('UPDATE folders SET path = ?, updated_at = ? WHERE id = ?').run(replacement, now, row.id);
      }
      this.db.prepare("UPDATE sessions SET group_name = CASE WHEN group_name = ? THEN ? ELSE ? || substr(group_name, ?) END, updated_at = ? WHERE group_name = ? OR group_name LIKE ?").run(oldPath, newPath, newPath, oldPath.length + 1, now, oldPath, `${oldPath}/%`);
      this.db.exec('COMMIT;');
    } catch (error) {
      this.db.exec('ROLLBACK;');
      throw error;
    }
    return this.listFolders().find(folder => folder.path === newPath)!;
  }

  deleteFolder(path: string): boolean {
    const normalized = normalizeFolderPath(path);
    this.db.exec('BEGIN IMMEDIATE;');
    try {
      const result = this.db.prepare('DELETE FROM folders WHERE path = ? OR path LIKE ?').run(normalized, `${normalized}/%`);
      this.db.prepare("UPDATE sessions SET group_name = '', updated_at = ? WHERE group_name = ? OR group_name LIKE ?").run(new Date().toISOString(), normalized, `${normalized}/%`);
      this.db.exec('COMMIT;');
      return Number(result.changes) > 0;
    } catch (error) {
      this.db.exec('ROLLBACK;');
      throw error;
    }
  }

  close(): void { this.db.close(); }

  backup(destination: string): void {
    if (resolve(destination) === resolve(this.filename)) throw new Error('Backup destination must differ from the database.');
    backupDatabase(this.db, this.filename, destination);
  }

  static applyPendingRestore(filename: string): void {
    const pending = `${filename}.restore-pending.sqlite`;
    if (!existsSync(pending)) return;
    if (!isSqliteFile(pending)) {
      unlinkSync(pending);
      throw new Error('The pending restore file is not a valid SQLite database.');
    }
    if (existsSync(filename)) {
      const safety = `${filename}.backup-before-restore-${new Date().toISOString().replace(/[:.]/g, '-')}.sqlite`;
      copyFileSync(filename, safety);
      if (process.platform !== 'win32') chmodSync(safety, 0o600);
    }
    copyFileSync(pending, filename);
    unlinkSync(pending);
    if (process.platform !== 'win32') chmodSync(filename, 0o600);
  }
}

function normalizeFolderPath(path: string): string {
  return path.trim().split('/').map(part => part.trim()).filter(Boolean).join('/');
}

function backupBeforeMigration(db: DatabaseSync, filename: string, version: number): void {
  // WAL can contain the newest committed records, so checkpoint before copying
  // the database. The backup is only created for an existing database that
  // actually needs migration; normal application updates reuse the same file.
  db.exec('PRAGMA wal_checkpoint(TRUNCATE);');
  const backup = `${filename}.backup-v${version}-${new Date().toISOString().replace(/[:.]/g, '-')}.sqlite`;
  backupDatabase(db, filename, backup);
}

function backupDatabase(db: DatabaseSync, filename: string, destination: string): void {
  db.exec('PRAGMA wal_checkpoint(TRUNCATE);');
  mkdirSync(dirname(destination), { recursive: true, mode: 0o700 });
  copyFileSync(filename, destination);
  if (process.platform !== 'win32') chmodSync(destination, 0o600);
}

export function isSqliteFile(filename: string): boolean {
  try { return readFileSync(filename).subarray(0, 16).toString() === 'SQLite format 3\0'; }
  catch { return false; }
}
