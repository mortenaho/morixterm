import { z } from 'zod';

const remotePathSchema = z.string().min(1).max(4096)
  .refine(value => !value.includes('\0'), 'Remote paths cannot contain null bytes.');

export const listFilesSchema = z.object({
  id: z.string().min(1).max(100),
  path: remotePathSchema.default('.'),
}).strict();
export const remoteFileSchema = z.object({ id: z.string().min(1).max(100), path: remotePathSchema }).strict();
export const renameFileSchema = remoteFileSchema.extend({ newPath: remotePathSchema }).strict();
// Local/remote transfers carry the destination/source in `remotePath`.
// Keep this separate from remote item mutations, which use `path`.
export const transferFileSchema = z.object({
  id: z.string().min(1).max(100),
  remotePath: remotePathSchema,
}).strict();
export const copyFileSchema = z.object({ id: z.string().min(1).max(100), source: remotePathSchema, target: remotePathSchema }).strict();
export const chmodFileSchema = remoteFileSchema.extend({ mode: z.number().int().min(0).max(0o7777) }).strict();
export const chownFileSchema = remoteFileSchema.extend({ uid: z.number().int().min(0).max(0xffffffff), gid: z.number().int().min(0).max(0xffffffff) }).strict();

export type RemoteFile = {
  name: string;
  path: string;
  type: 'file' | 'directory' | 'link';
  size: number;
  permissions?: string;
  modifiedAt?: string;
  owner?: string;
};

export type FilesResult<T> = { ok: true; value: T } | { ok: false; message: string };
export interface FilesApi {
  list(input: { id: string; path?: string }): Promise<FilesResult<RemoteFile[]>>;
  upload(input: { id: string; remotePath: string }): Promise<FilesResult<boolean>>;
  download(input: { id: string; remotePath: string }): Promise<FilesResult<boolean>>;
  mkdir(input: { id: string; path: string }): Promise<FilesResult<boolean>>;
  rename(input: { id: string; path: string; newPath: string }): Promise<FilesResult<boolean>>;
  delete(input: { id: string; path: string; directory?: boolean }): Promise<FilesResult<boolean>>;
  chmod(input: { id: string; path: string; mode: number }): Promise<FilesResult<boolean>>;
  chown(input: { id: string; path: string; uid: number; gid: number }): Promise<FilesResult<boolean>>;
  copy(input: { id: string; source: string; target: string }): Promise<FilesResult<boolean>>;
  onProgress(callback: (value: { id: string; direction: 'upload' | 'download'; transferred: number; total: number; complete?: boolean }) => void): () => void;
}
