import { randomUUID } from 'node:crypto';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '../../src/database.types';

export type Client = SupabaseClient<Database>;

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing ${name}. Run "supabase start" then "npm run env:local".`);
  }
  return value;
}

export const supabaseUrl = requireEnv('SUPABASE_URL');
export const publishableKey = requireEnv('SUPABASE_PUBLISHABLE_KEY');

// LOCAL TEST CREDENTIALS ONLY. These accounts are created by supabase/seed.sql
// for the local stack and must never exist on a hosted project.
const LOCAL_TEST_PASSWORD = 'local-only-password';

export const seedUsers = {
  alice: { id: '11111111-1111-4111-8111-111111111111', email: 'alice@example.test' },
  bob: { id: '22222222-2222-4222-8222-222222222222', email: 'bob@example.test' },
  admin: { id: '99999999-9999-4999-8999-999999999999', email: 'admin@example.test' },
} as const;

export const seedTools = {
  aliceDrill: 'a0000000-0000-4000-8000-000000000001',
  bobPressureWasher: 'b0000000-0000-4000-8000-000000000001',
  bobHedgeTrimmer: 'b0000000-0000-4000-8000-000000000002',
  adminTileCutter: 'c0000000-0000-4000-8000-000000000001',
} as const;

function newClient(): Client {
  return createClient<Database>(supabaseUrl, publishableKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}

/** A visitor with the public key and no session (the "anon" role). */
export function anonClient(): Client {
  return newClient();
}

/** A client signed in through Supabase Auth, exactly like a real app user. */
export async function signIn(user: keyof typeof seedUsers): Promise<Client> {
  const client = newClient();
  const { error } = await client.auth.signInWithPassword({
    email: seedUsers[user].email,
    password: LOCAL_TEST_PASSWORD,
  });
  if (error) {
    throw error;
  }
  return client;
}

/**
 * Creates a tool owned by the signed-in user. Each test gets its own tool, so
 * the suite can run again without resetting the database.
 */
export async function createOwnTool(client: Client): Promise<string> {
  const { data, error } = await client
    .from('tools')
    .insert({ name: `Test tool ${randomUUID()}`, category: 'integration test' })
    .select('id')
    .single();
  if (error) {
    throw error;
  }
  return data.id;
}

/** A date as YYYY-MM-DD, n days from today in UTC (the database time zone). */
export function daysFromToday(n: number): string {
  const date = new Date();
  date.setUTCDate(date.getUTCDate() + n);
  return date.toISOString().slice(0, 10);
}
