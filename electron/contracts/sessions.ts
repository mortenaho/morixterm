import { z } from 'zod';

export const sessionFields = z.object({
  name: z.string().trim().min(1).max(128),
  host: z.string().trim().min(1).max(255),
  port: z.number().int().min(1).max(65535).optional(),
  user: z.string().trim().min(1).max(128),
  kind: z.enum(['SSH', 'RDP', 'LOCAL']),
  platform: z.enum(['LINUX', 'WINDOWS']).default('LINUX'),
  color: z.string().regex(/^#[0-9a-fA-F]{6}$/),
  group: z.string().trim().max(128),
  favorite: z.boolean().default(false),
}).strict();
export const saveSessionSchema = sessionFields.extend({
  id: z.string().uuid().optional(),
  // These are accepted when an existing row is round-tripped from the API.
  // New callers should omit them; persistence owns their values.
  createdAt: z.string().datetime().optional(),
  updatedAt: z.string().datetime().optional(),
  password: z.string().max(1000).optional(),
}).strict().superRefine((value, context) => {
  if (value.kind !== 'LOCAL' && value.port === undefined)
    context.addIssue({ code: 'custom', path: ['port'], message: 'Port is required.' });
  if (value.kind === 'LOCAL' && (value.port !== undefined || value.password))
    context.addIssue({ code: 'custom', message: 'Local sessions do not use remote credentials or ports.' });
});
export type Session = z.infer<typeof sessionFields> & {
  id: string;
  hasPassword: boolean;
  createdAt: string;
  updatedAt: string;
};
export type SaveSession = z.input<typeof saveSessionSchema>;
export const listSessionsSchema = z.object({
  query: z.string().max(255).default(''),
  page: z.number().int().min(1).max(1000000).default(1),
  pageSize: z.number().int().min(1).max(100).default(10),
  favoritesOnly: z.boolean().default(false),
}).strict();
export const duplicateSessionSchema = z.string().uuid();
export type SessionQuery = z.input<typeof listSessionsSchema>;
export type SessionPage = { items: Session[]; total: number; allTotal: number; page: number; pageSize: number };
export type Result<T> = { ok: true; value: T } | { ok: false; message: string };
export interface SessionsApi {
  list(input: SessionQuery): Promise<Result<SessionPage>>;
  save(input: SaveSession): Promise<Result<Session>>;
  duplicate(id: string): Promise<Result<Session>>;
  delete(id: string): Promise<Result<boolean>>;
}
