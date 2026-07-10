import { env } from 'cloudflare:workers';

// Setup files run outside the per-test-file storage isolation, and may run multiple times.
// There's no migrations bookkeeping table anymore (schema.sql is applied declaratively via
// sqlite3def outside of tests), so guard manually: only apply the schema if it hasn't been
// applied yet (each test file still gets its own isolated storage).
const alreadyApplied = await env.DB.prepare(
  `SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'reader_documents'`,
).first();

if (!alreadyApplied) {
  const statements = env.TEST_SCHEMA_SQL.split(';')
    .map((statement) => statement.trim())
    .filter((statement) => statement.length > 0);

  for (const statement of statements) {
    await env.DB.prepare(statement).run();
  }
}
