import { z } from 'zod';

export const appSettingsSchema = z.object({
  appearance: z.enum(['dark', 'light', 'system']).default('dark'),
  terminal: z.object({
    fontFamily: z.string().min(1).max(120).default("'JetBrains Mono', 'Cascadia Code', Menlo, monospace"),
    fontSize: z.number().int().min(10).max(28).default(13),
    lineHeight: z.number().min(1).max(2).default(1.2),
    scrollback: z.number().int().min(10000).max(50000).default(10000),
    cursorBlink: z.boolean().default(true),
  }).default({}),
  security: z.object({
    autoLockMinutes: z.number().int().min(0).max(240).default(15),
  }).default({}),
}).default({});

export type AppSettings = z.infer<typeof appSettingsSchema>;

export const defaultSettings: AppSettings = appSettingsSchema.parse({});
