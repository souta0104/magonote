import { applyD1Migrations } from 'cloudflare:test';
import { env } from 'cloudflare:workers';

// Setup files run outside the per-test-file storage isolation, and may run multiple times.
// applyD1Migrations() only applies migrations that haven't already been applied, so it's
// safe to call unconditionally here (each test file still gets its own isolated storage).
await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
