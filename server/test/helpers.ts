import type { TokenVerifier } from '../src/auth';

/** Always resolves with the given uid, regardless of the JWT passed in. */
export class FixedUidVerifier implements TokenVerifier {
  constructor(private readonly uid: string) {}

  async verify(): Promise<{ uid: string }> {
    return { uid: this.uid };
  }
}

/** Always throws, simulating an invalid/expired/unverifiable token. */
export class AlwaysThrowsVerifier implements TokenVerifier {
  async verify(): Promise<{ uid: string }> {
    throw new Error('invalid token');
  }
}

export interface ErrorEnvelope {
  error: { code: string; message: string };
}

/** `Response#json()` is typed `unknown` in the Workers runtime types; this gives call sites a typed result. */
export async function readJson<T = unknown>(res: Response): Promise<T> {
  return (await res.json()) as T;
}
