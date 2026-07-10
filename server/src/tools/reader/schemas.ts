import { z } from 'zod';
import { validationError } from '../../errors';

export const createDocumentSchema = z.object({
  text: z.string().min(1).max(500_000),
  sourceAppName: z.string().min(1).max(200),
  sourceMachineName: z.string().min(1).max(200),
  capturedAt: z.number().int().positive(),
});

export const listDocumentsQuerySchema = z.object({
  filter: z.enum(['active', 'archived']).default('active'),
  limit: z.coerce.number().int().min(1).max(100).default(30),
  cursor: z.string().optional(),
});

export const createCommentSchema = z.object({
  body: z.string().min(1).max(10_000),
  quote: z.string().min(1).max(10_000).optional(),
});

export const listCommentsQuerySchema = z.object({
  includeArchived: z
    .enum(['true', 'false'])
    .default('false')
    .transform((v) => v === 'true'),
});

export interface Cursor {
  createdAt: number;
  id: string;
}

export function encodeCursor(cursor: Cursor): string {
  const json = JSON.stringify(cursor);
  const bytes = new TextEncoder().encode(json);
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function decodeCursor(value: string): Cursor {
  try {
    const padded = value.replace(/-/g, '+').replace(/_/g, '/');
    const padding = padded.length % 4 === 0 ? '' : '='.repeat(4 - (padded.length % 4));
    const binary = atob(padded + padding);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) {
      bytes[i] = binary.charCodeAt(i);
    }
    const json = new TextDecoder().decode(bytes);
    const parsed: unknown = JSON.parse(json);

    if (
      typeof parsed !== 'object' ||
      parsed === null ||
      typeof (parsed as Cursor).createdAt !== 'number' ||
      typeof (parsed as Cursor).id !== 'string'
    ) {
      throw new Error('malformed cursor payload');
    }

    return parsed as Cursor;
  } catch {
    throw validationError('invalid cursor');
  }
}
