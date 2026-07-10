import { zValidator } from '@hono/zod-validator';
import { Hono } from 'hono';
import type { ZodType } from 'zod';
import {
  getDocument,
  insertComment,
  insertDocument,
  listComments,
  listDocuments,
  setCommentArchived,
  setDocumentArchived,
} from '../../db';
import { notFound, validationError } from '../../errors';
import {
  createCommentSchema,
  createDocumentSchema,
  decodeCursor,
  listCommentsQuerySchema,
  listDocumentsQuerySchema,
} from './schemas';

// Thin wrapper around zValidator so failures throw ApiError and land in app.ts's onError,
// producing the shared { error: { code, message } } envelope instead of the library's default shape.
function zv<T extends ZodType>(target: 'json' | 'query', schema: T) {
  return zValidator(target, schema, (result) => {
    if (!result.success) {
      const message = result.error.issues
        .map((issue) => `${issue.path.join('.') || '(root)'}: ${issue.message}`)
        .join(', ');
      throw validationError(message || 'invalid request');
    }
  });
}

export const readerRoutes = new Hono<{ Bindings: Env }>()
  .post('/documents', zv('json', createDocumentSchema), async (c) => {
    const input = c.req.valid('json');
    const document = await insertDocument(c.env.DB, input);
    return c.json(document, 201);
  })
  .get('/documents', zv('query', listDocumentsQuerySchema), async (c) => {
    const { filter, limit, cursor } = c.req.valid('query');
    const decodedCursor = cursor ? decodeCursor(cursor) : undefined;
    const result = await listDocuments(c.env.DB, { filter, limit, cursor: decodedCursor });
    return c.json(result, 200);
  })
  .get('/documents/:id', async (c) => {
    const document = await getDocument(c.env.DB, c.req.param('id'));
    if (!document) {
      throw notFound('document');
    }
    return c.json(document, 200);
  })
  .post('/documents/:id/archive', async (c) => {
    const document = await setDocumentArchived(c.env.DB, c.req.param('id'), Date.now());
    if (!document) {
      throw notFound('document');
    }
    return c.json(document, 200);
  })
  .post('/documents/:id/unarchive', async (c) => {
    const document = await setDocumentArchived(c.env.DB, c.req.param('id'), null);
    if (!document) {
      throw notFound('document');
    }
    return c.json(document, 200);
  })
  .get('/documents/:id/comments', zv('query', listCommentsQuerySchema), async (c) => {
    const { includeArchived } = c.req.valid('query');
    const comments = await listComments(c.env.DB, c.req.param('id'), includeArchived);
    return c.json({ comments }, 200);
  })
  .post('/documents/:id/comments', zv('json', createCommentSchema), async (c) => {
    const input = c.req.valid('json');
    const comment = await insertComment(c.env.DB, c.req.param('id'), input);
    if (!comment) {
      throw notFound('document');
    }
    return c.json(comment, 201);
  })
  .post('/comments/:id/archive', async (c) => {
    const comment = await setCommentArchived(c.env.DB, c.req.param('id'), Date.now());
    if (!comment) {
      throw notFound('comment');
    }
    return c.json(comment, 200);
  })
  .post('/comments/:id/unarchive', async (c) => {
    const comment = await setCommentArchived(c.env.DB, c.req.param('id'), null);
    if (!comment) {
      throw notFound('comment');
    }
    return c.json(comment, 200);
  });
