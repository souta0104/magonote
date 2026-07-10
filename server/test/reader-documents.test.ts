import { env } from 'cloudflare:workers';
import { beforeEach, describe, expect, it } from 'vitest';
import { createApp } from '../src/app';
import { type ErrorEnvelope, FixedUidVerifier, readJson } from './helpers';

const app = createApp(() => new FixedUidVerifier('test-uid'));
const AUTH_HEADER = { Authorization: 'Bearer test-token' };
const JSON_HEADERS = { ...AUTH_HEADER, 'Content-Type': 'application/json' };

interface DocumentJson {
  id: string;
  text?: string;
  preview?: string;
  sourceAppName: string;
  sourceMachineName: string;
  capturedAt: number;
  createdAt: number;
  archivedAt: number | null;
}

interface DocumentListJson {
  documents: DocumentJson[];
  nextCursor: string | null;
}

async function createDocument(
  overrides: Partial<{
    text: string;
    sourceAppName: string;
    sourceMachineName: string;
    capturedAt: number;
  }> = {},
): Promise<DocumentJson> {
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
        ...overrides,
      }),
    },
    env,
  );
  return readJson<DocumentJson>(res);
}

// Vitest-pool-workers now isolates storage per test *file*, not per test case, so we reset
// the reader tables before every test to keep list/pagination assertions deterministic.
beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare('DELETE FROM reader_comments'),
    env.DB.prepare('DELETE FROM reader_documents'),
  ]);
});

describe('POST /api/reader/documents', () => {
  it('creates a document and echoes the input (201)', async () => {
    const res = await app.request(
      '/api/reader/documents',
      {
        method: 'POST',
        headers: JSON_HEADERS,
        body: JSON.stringify({
          text: 'hello',
          sourceAppName: 'Xcode',
          sourceMachineName: 'MacBook',
          capturedAt: 1_700_000_000_000,
        }),
      },
      env,
    );
    expect(res.status).toBe(201);
    const body = await readJson<DocumentJson>(res);
    expect(body).toMatchObject({
      text: 'hello',
      sourceAppName: 'Xcode',
      sourceMachineName: 'MacBook',
      capturedAt: 1_700_000_000_000,
      archivedAt: null,
    });
    expect(typeof body.id).toBe('string');
    expect(typeof body.createdAt).toBe('number');
  });

  it('rejects empty text with 400', async () => {
    const res = await app.request(
      '/api/reader/documents',
      {
        method: 'POST',
        headers: JSON_HEADERS,
        body: JSON.stringify({
          text: '',
          sourceAppName: 'Xcode',
          sourceMachineName: 'MacBook',
          capturedAt: Date.now(),
        }),
      },
      env,
    );
    expect(res.status).toBe(400);
    const body = await readJson<ErrorEnvelope>(res);
    expect(body.error.code).toBe('validation_error');
  });

  it('rejects missing required fields with 400', async () => {
    const res = await app.request(
      '/api/reader/documents',
      {
        method: 'POST',
        headers: JSON_HEADERS,
        body: JSON.stringify({ text: 'hello' }),
      },
      env,
    );
    expect(res.status).toBe(400);
  });
});

describe('GET /api/reader/documents', () => {
  it('lists documents newest first', async () => {
    const a = await createDocument({ text: 'a' });
    const b = await createDocument({ text: 'b' });
    const c = await createDocument({ text: 'c' });

    const res = await app.request('/api/reader/documents', { headers: AUTH_HEADER }, env);
    expect(res.status).toBe(200);
    const body = await readJson<DocumentListJson>(res);

    const expectedOrder = [a, b, c]
      .sort((x, y) => y.createdAt - x.createdAt || (y.id > x.id ? 1 : y.id < x.id ? -1 : 0))
      .map((d) => d.id);
    expect(body.documents.map((d: DocumentJson) => d.id)).toEqual(expectedOrder);
  });

  it('truncates preview to 300 chars and omits the full text', async () => {
    const longText = 'a'.repeat(400);
    const created = await createDocument({ text: longText });

    const res = await app.request('/api/reader/documents', { headers: AUTH_HEADER }, env);
    const body = await readJson<DocumentListJson>(res);
    const summary = body.documents.find((d) => d.id === created.id);

    expect(summary).toBeDefined();
    expect(summary?.preview).toBe('a'.repeat(300));
    expect(summary?.preview?.length).toBe(300);
    expect(summary?.text).toBeUndefined();
  });

  it('paginates via keyset cursor, covering all documents exactly once', async () => {
    const created: DocumentJson[] = [];
    for (let i = 0; i < 7; i += 1) {
      created.push(await createDocument({ text: `doc-${i}` }));
    }
    const createdIds = created.map((d) => d.id).sort();

    const seen: string[] = [];
    let cursor: string | undefined;
    let pageCount = 0;

    do {
      const qs = new URLSearchParams({ limit: '3' });
      if (cursor) qs.set('cursor', cursor);
      const res = await app.request(`/api/reader/documents?${qs}`, { headers: AUTH_HEADER }, env);
      expect(res.status).toBe(200);
      const body = await readJson<DocumentListJson>(res);
      seen.push(...body.documents.map((d) => d.id));
      cursor = body.nextCursor ?? undefined;
      pageCount += 1;
    } while (cursor);

    expect(pageCount).toBe(3);
    expect(new Set(seen).size).toBe(seen.length);
    expect(seen.sort()).toEqual(createdIds);
  });

  it('rejects a malformed cursor with 400 validation_error', async () => {
    const res = await app.request(
      '/api/reader/documents?cursor=not-a-valid-cursor!!',
      { headers: AUTH_HEADER },
      env,
    );
    expect(res.status).toBe(400);
    const body = await readJson<ErrorEnvelope>(res);
    expect(body.error.code).toBe('validation_error');
  });

  it('excludes archived documents from the active (default) list', async () => {
    const doc = await createDocument();
    await app.request(`/api/reader/documents/${doc.id}/archive`, { method: 'POST', headers: AUTH_HEADER }, env);

    const res = await app.request('/api/reader/documents?filter=active', { headers: AUTH_HEADER }, env);
    const body = await readJson<DocumentListJson>(res);
    expect(body.documents.some((d) => d.id === doc.id)).toBe(false);
  });

  it('includes archived documents when filter=archived', async () => {
    const doc = await createDocument();
    await app.request(`/api/reader/documents/${doc.id}/archive`, { method: 'POST', headers: AUTH_HEADER }, env);

    const res = await app.request('/api/reader/documents?filter=archived', { headers: AUTH_HEADER }, env);
    const body = await readJson<DocumentListJson>(res);
    expect(body.documents.some((d) => d.id === doc.id)).toBe(true);
  });
});

describe('GET /api/reader/documents/:id', () => {
  it('returns 404 for a nonexistent document id', async () => {
    const missingId = crypto.randomUUID();
    const res = await app.request(`/api/reader/documents/${missingId}`, { headers: AUTH_HEADER }, env);
    expect(res.status).toBe(404);
  });
});

describe('POST /api/reader/documents/:id/archive, /unarchive', () => {
  it('archiving an already-archived document returns 200 (idempotent)', async () => {
    const doc = await createDocument();
    const first = await app.request(`/api/reader/documents/${doc.id}/archive`, { method: 'POST', headers: AUTH_HEADER }, env);
    expect(first.status).toBe(200);

    const second = await app.request(`/api/reader/documents/${doc.id}/archive`, { method: 'POST', headers: AUTH_HEADER }, env);
    expect(second.status).toBe(200);
    const secondBody = await readJson<DocumentJson>(second);
    expect(secondBody.archivedAt).not.toBeNull();
  });

  it('unarchive restores the document to the active list', async () => {
    const doc = await createDocument();
    await app.request(`/api/reader/documents/${doc.id}/archive`, { method: 'POST', headers: AUTH_HEADER }, env);

    const res = await app.request(`/api/reader/documents/${doc.id}/unarchive`, { method: 'POST', headers: AUTH_HEADER }, env);
    expect(res.status).toBe(200);
    const body = await readJson<DocumentJson>(res);
    expect(body.archivedAt).toBeNull();

    const activeRes = await app.request('/api/reader/documents?filter=active', { headers: AUTH_HEADER }, env);
    const activeBody = await readJson<DocumentListJson>(activeRes);
    expect(activeBody.documents.some((d) => d.id === doc.id)).toBe(true);
  });

  it('returns 404 for archive/unarchive of a nonexistent document id', async () => {
    const missingId = crypto.randomUUID();
    const archiveRes = await app.request(`/api/reader/documents/${missingId}/archive`, { method: 'POST', headers: AUTH_HEADER }, env);
    expect(archiveRes.status).toBe(404);

    const unarchiveRes = await app.request(`/api/reader/documents/${missingId}/unarchive`, { method: 'POST', headers: AUTH_HEADER }, env);
    expect(unarchiveRes.status).toBe(404);
  });
});
