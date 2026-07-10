import { Hono } from 'hono';
import { authMiddleware, type TokenVerifier } from './auth';
import { ApiError } from './errors';
import { readerRoutes } from './tools/reader/routes';

export function createApp(makeVerifier: (env: Env) => TokenVerifier) {
  const app = new Hono<{ Bindings: Env; Variables: { uid: string } }>();

  app.get('/api/health', (c) => c.json({ ok: true }, 200));

  app.use('/api/*', authMiddleware(makeVerifier));

  app.route('/api/reader', readerRoutes);

  app.onError((err, c) => {
    if (err instanceof ApiError) {
      return c.json({ error: { code: err.code, message: err.message } }, err.status as 401 | 403 | 404 | 400 | 500);
    }
    console.error(err);
    return c.json({ error: { code: 'internal', message: 'internal server error' } }, 500);
  });

  app.notFound((c) => c.json({ error: { code: 'not_found', message: 'not found' } }, 404));

  return app;
}
