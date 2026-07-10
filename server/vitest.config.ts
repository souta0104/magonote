import { readFileSync } from 'node:fs';
import { cloudflareTest } from '@cloudflare/vitest-pool-workers';
import { defineConfig } from 'vitest/config';

export default defineConfig(() => {
  const schemaPath = new URL('./schema.sql', import.meta.url);
  const schemaSql = readFileSync(schemaPath, 'utf-8');

  return {
    plugins: [
      cloudflareTest({
        wrangler: { configPath: './wrangler.jsonc' },
        miniflare: {
          bindings: {
            ALLOWED_UID: 'test-uid',
            // Test-only binding: schema is applied per test file in test/setup.ts.
            TEST_SCHEMA_SQL: schemaSql,
          },
        },
      }),
    ],
    test: {
      setupFiles: ['./test/setup.ts'],
    },
  };
});
