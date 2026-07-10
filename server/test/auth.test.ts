import { env } from 'cloudflare:workers';
import { describe, expect, it } from 'vitest';
import { createApp } from '../src/app';
import { AlwaysThrowsVerifier, type ErrorEnvelope, FixedUidVerifier, readJson } from './helpers';

describe('authMiddleware', () => {
  it('GET /api/health requires no auth', async () => {
    const app = createApp(() => new AlwaysThrowsVerifier());
    const res = await app.request('/api/health', {}, env);
    expect(res.status).toBe(200);
    expect(await readJson(res)).toEqual({ ok: true });
  });

  it('rejects requests with no Authorization header (401)', async () => {
    const app = createApp(() => new FixedUidVerifier('test-uid'));
    const res = await app.request('/api/reader/documents', {}, env);
    expect(res.status).toBe(401);
    const body = await readJson<ErrorEnvelope>(res);
    expect(body.error.code).toBe('unauthorized');
  });

  it('rejects a malformed Authorization header (401)', async () => {
    const app = createApp(() => new FixedUidVerifier('test-uid'));
    const res = await app.request(
      '/api/reader/documents',
      { headers: { Authorization: 'Token abc' } },
      env,
    );
    expect(res.status).toBe(401);
  });

  it('rejects when the verifier throws (401)', async () => {
    const app = createApp(() => new AlwaysThrowsVerifier());
    const res = await app.request(
      '/api/reader/documents',
      { headers: { Authorization: 'Bearer bad-token' } },
      env,
    );
    expect(res.status).toBe(401);
  });

  it('rejects a verified uid that does not match ALLOWED_UID (403)', async () => {
    const app = createApp(() => new FixedUidVerifier('someone-else'));
    const res = await app.request(
      '/api/reader/documents',
      { headers: { Authorization: 'Bearer token' } },
      env,
    );
    expect(res.status).toBe(403);
    const body = await readJson<ErrorEnvelope>(res);
    expect(body.error.code).toBe('forbidden');
  });

  it('allows a verified uid that matches ALLOWED_UID (200)', async () => {
    const app = createApp(() => new FixedUidVerifier('test-uid'));
    const res = await app.request(
      '/api/reader/documents',
      { headers: { Authorization: 'Bearer token' } },
      env,
    );
    expect(res.status).toBe(200);
  });
});
