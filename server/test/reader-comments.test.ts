import { env } from 'cloudflare:workers';
import { describe, expect, it } from 'vitest';
import { createApp } from '../src/app';
import { type ErrorEnvelope, FixedUidVerifier, readJson } from './helpers';

const app = createApp(() => new FixedUidVerifier('test-uid'));
const AUTH_HEADER = { Authorization: 'Bearer test-token' };
const JSON_HEADERS = { ...AUTH_HEADER, 'Content-Type': 'application/json' };

interface DocumentJson {
  id: string;
}

interface CommentJson {
  id: string;
  documentId: string;
  body: string;
  quote: string | null;
  createdAt: number;
  archivedAt: number | null;
}

interface CommentListJson {
  comments: CommentJson[];
}

async function createDocument(): Promise<DocumentJson> {
  const res = await app.request(
    '/api/reader/documents',
    {
      method: 'POST',
      headers: JSON_HEADERS,
      body: JSON.stringify({
        text: 'hello world',
        sourceAppName: 'Xcode',
        sourceMachineName: 'MacBook',
        capturedAt: Date.now(),
      }),
    },
    env,
  );
  return readJson<DocumentJson>(res);
}

async function createComment(
  documentId: string,
  body: { body: string; quote?: string },
) {
  return app.request(
    `/api/reader/documents/${documentId}/comments`,
    {
      method: 'POST',
      headers: JSON_HEADERS,
      body: JSON.stringify(body),
    },
    env,
  );
}

describe('POST /api/reader/documents/:id/comments', () => {
  it('creates a comment with a quote (201)', async () => {
    const doc = await createDocument();
    const res = await createComment(doc.id, { body: 'nice line', quote: 'the quoted text' });
    expect(res.status).toBe(201);
    const body = await readJson<CommentJson>(res);
    expect(body).toMatchObject({
      documentId: doc.id,
      body: 'nice line',
      quote: 'the quoted text',
      archivedAt: null,
    });
    expect(typeof body.id).toBe('string');
    expect(typeof body.createdAt).toBe('number');
  });

  it('creates a comment without a quote (201)', async () => {
    const doc = await createDocument();
    const res = await createComment(doc.id, { body: 'no quote here' });
    expect(res.status).toBe(201);
    const body = await readJson<CommentJson>(res);
    expect(body).toMatchObject({
      documentId: doc.id,
      body: 'no quote here',
      quote: null,
      archivedAt: null,
    });
  });

  it('returns 404 when the document does not exist', async () => {
    const missingId = crypto.randomUUID();
    const res = await createComment(missingId, { body: 'orphan comment' });
    expect(res.status).toBe(404);
    const body = await readJson<ErrorEnvelope>(res);
    expect(body.error.code).toBe('not_found');
  });

  it('rejects an empty body with 400', async () => {
    const doc = await createDocument();
    const res = await createComment(doc.id, { body: '' });
    expect(res.status).toBe(400);
    const body = await readJson<ErrorEnvelope>(res);
    expect(body.error.code).toBe('validation_error');
  });
});

describe('GET /api/reader/documents/:id/comments', () => {
  it('returns 404 when the document does not exist', async () => {
    const missingId = crypto.randomUUID();
    const res = await app.request(`/api/reader/documents/${missingId}/comments`, { headers: AUTH_HEADER }, env);
    expect(res.status).toBe(404);
    const body = await readJson<ErrorEnvelope>(res);
    expect(body.error.code).toBe('not_found');
  });

  it('lists comments oldest first', async () => {
    const doc = await createDocument();
    const c1 = await readJson<CommentJson>(await createComment(doc.id, { body: 'first' }));
    const c2 = await readJson<CommentJson>(await createComment(doc.id, { body: 'second' }));
    const c3 = await readJson<CommentJson>(await createComment(doc.id, { body: 'third' }));

    const res = await app.request(`/api/reader/documents/${doc.id}/comments`, { headers: AUTH_HEADER }, env);
    expect(res.status).toBe(200);
    const body = await readJson<CommentListJson>(res);

    const expectedOrder = [c1, c2, c3]
      .sort((x, y) => x.createdAt - y.createdAt || (x.id < y.id ? -1 : x.id > y.id ? 1 : 0))
      .map((c) => c.id);
    expect(body.comments.map((c) => c.id)).toEqual(expectedOrder);
  });

  it('excludes archived comments by default, includes them with includeArchived=true', async () => {
    const doc = await createDocument();
    const comment = await readJson<CommentJson>(await createComment(doc.id, { body: 'to archive' }));
    await app.request(`/api/reader/comments/${comment.id}/archive`, { method: 'POST', headers: AUTH_HEADER }, env);

    const defaultRes = await app.request(`/api/reader/documents/${doc.id}/comments`, { headers: AUTH_HEADER }, env);
    const defaultBody = await readJson<CommentListJson>(defaultRes);
    expect(defaultBody.comments.some((c) => c.id === comment.id)).toBe(false);

    const includeRes = await app.request(
      `/api/reader/documents/${doc.id}/comments?includeArchived=true`,
      { headers: AUTH_HEADER },
      env,
    );
    const includeBody = await readJson<CommentListJson>(includeRes);
    expect(includeBody.comments.some((c) => c.id === comment.id)).toBe(true);
  });
});

describe('POST /api/reader/comments/:id/archive, /unarchive', () => {
  it('archives and unarchives a comment', async () => {
    const doc = await createDocument();
    const comment = await readJson<CommentJson>(await createComment(doc.id, { body: 'toggle me' }));

    const archiveRes = await app.request(`/api/reader/comments/${comment.id}/archive`, { method: 'POST', headers: AUTH_HEADER }, env);
    expect(archiveRes.status).toBe(200);
    const archiveBody = await readJson<CommentJson>(archiveRes);
    expect(archiveBody.archivedAt).not.toBeNull();

    const unarchiveRes = await app.request(`/api/reader/comments/${comment.id}/unarchive`, { method: 'POST', headers: AUTH_HEADER }, env);
    expect(unarchiveRes.status).toBe(200);
    const unarchiveBody = await readJson<CommentJson>(unarchiveRes);
    expect(unarchiveBody.archivedAt).toBeNull();
  });

  it('returns 404 for a nonexistent comment id', async () => {
    const missingId = crypto.randomUUID();
    const res = await app.request(`/api/reader/comments/${missingId}/archive`, { method: 'POST', headers: AUTH_HEADER }, env);
    expect(res.status).toBe(404);
  });
});
