import { existsSync } from 'node:fs';
import { defineConfig } from 'vitest/config';

// Local runs read SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY from .env
// (created by `npm run env:local`). CI writes the same file.
if (existsSync('.env')) {
  process.loadEnvFile('.env');
}

export default defineConfig({
  test: {
    include: ['tests/**/*.test.ts'],
    testTimeout: 15_000,
  },
});
