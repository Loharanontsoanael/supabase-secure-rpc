import { describe, expect, it } from 'vitest';
import { anonClient, daysFromToday, publishableKey, signIn, supabaseUrl } from './support/supabase';

describe('function access through the API', () => {
  it('refuses every RPC to anonymous visitors', async () => {
    const anon = anonClient();
    const someId = '00000000-0000-4000-8000-000000000000';

    const results = await Promise.all([
      anon.rpc('request_loan', {
        p_tool_id: someId,
        p_starts_on: daysFromToday(1),
        p_ends_on: daysFromToday(2),
      }),
      anon.rpc('decide_loan', { p_loan_id: someId, p_decision: 'approved' }),
      anon.rpc('admin_list_loans', {}),
    ]);

    for (const { error } of results) {
      expect(error?.code).toBe('42501');
    }
  });

  it('refuses admin_list_loans to a normal member', async () => {
    const bob = await signIn('bob');
    const { data, error } = await bob.rpc('admin_list_loans', { p_limit: 10 });

    expect(data).toBeNull();
    expect(error?.code).toBe('42501');
  });

  it('lets an admin page through all loans with a server-side cap', async () => {
    const admin = await signIn('admin');

    const firstPage = await admin.rpc('admin_list_loans', { p_limit: 2, p_offset: 0 });
    expect(firstPage.error).toBeNull();
    expect(firstPage.data).toHaveLength(2);

    const huge = await admin.rpc('admin_list_loans', { p_limit: 10_000 });
    expect(huge.error).toBeNull();
    expect(huge.data?.length).toBeLessThanOrEqual(100);
  });

  it('does not expose the private schema through the Data API', async () => {
    const response = await fetch(`${supabaseUrl}/rest/v1/rpc/is_admin`, {
      method: 'POST',
      headers: {
        apikey: publishableKey,
        'Content-Profile': 'private',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ p_user_id: '00000000-0000-4000-8000-000000000000' }),
    });
    const body = (await response.json()) as { code?: string };

    expect(response.ok).toBe(false);
    expect(body.code).toBe('PGRST106');
  });
});
