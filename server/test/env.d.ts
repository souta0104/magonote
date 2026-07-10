declare namespace Cloudflare {
  interface Env {
    // Test-only binding populated in vitest.config.ts, applied in test/setup.ts.
    TEST_MIGRATIONS: import('cloudflare:test').D1Migration[];
  }
}
