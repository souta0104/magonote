import { Auth, WorkersKVStoreSingle } from 'firebase-auth-cloudflare-workers';
import type { MiddlewareHandler } from 'hono';
import { forbidden, unauthorized } from './errors';

export interface TokenVerifier {
  verify(jwt: string): Promise<{ uid: string }>;
}

export class FirebaseTokenVerifier implements TokenVerifier {
  constructor(private readonly env: Env) {}

  async verify(jwt: string): Promise<{ uid: string }> {
    const auth = Auth.getOrInitialize(
      this.env.FIREBASE_PROJECT_ID,
      WorkersKVStoreSingle.getOrInitialize('firebase-certs', this.env.FIREBASE_CERT_CACHE),
    );
    const decoded = await auth.verifyIdToken(jwt);
    return { uid: decoded.sub };
  }
}

type AuthVariables = {
  uid: string;
};

export function authMiddleware(
  makeVerifier: (env: Env) => TokenVerifier,
): MiddlewareHandler<{ Bindings: Env; Variables: AuthVariables }> {
  return async (c, next) => {
    const header = c.req.header('Authorization');
    if (!header || !header.startsWith('Bearer ')) {
      throw unauthorized('missing or malformed Authorization header');
    }
    const jwt = header.slice('Bearer '.length);

    let uid: string;
    try {
      const verified = await makeVerifier(c.env).verify(jwt);
      uid = verified.uid;
    } catch {
      throw unauthorized('invalid token');
    }

    if (uid !== c.env.ALLOWED_UID) {
      throw forbidden('uid not allowed');
    }

    c.set('uid', uid);
    await next();
  };
}
