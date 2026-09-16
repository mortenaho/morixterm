import { z } from 'zod';

export const folderPathSchema = z.string().trim().min(1).max(512)
  .refine(value => !value.includes('\\'), 'Folder paths use / as separator.')
  .refine(value => value.split('/').every(part => part.trim().length > 0), 'Folder path contains an empty segment.');
export const createFolderSchema = z.object({ path: folderPathSchema }).strict();
export const renameFolderSchema = z.object({ path: folderPathSchema, name: z.string().trim().min(1).max(128) }).strict();

export type Folder = { id: string; path: string; createdAt: string; updatedAt: string };
export interface FoldersApi {
  list(): Promise<{ ok: true; value: Folder[] } | { ok: false; message: string }>;
  create(path: string): Promise<{ ok: true; value: Folder } | { ok: false; message: string }>;
  rename(path: string, name: string): Promise<{ ok: true; value: Folder } | { ok: false; message: string }>;
  delete(path: string): Promise<{ ok: true; value: boolean } | { ok: false; message: string }>;
}
