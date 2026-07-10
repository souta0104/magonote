declare namespace Cloudflare {
  interface Env {
    // Test-only binding populated in vitest.config.ts, applied in test/setup.ts.
    TEST_SCHEMA_SQL: string;
  }
}
