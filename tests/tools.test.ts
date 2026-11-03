import { beforeAll, describe, expect, it } from 'vitest';
import { anonClient, seedTools, seedUsers, signIn, type Client } from './support/supabase';

describe('tools through the Data API', () => {
  let alice: Client;
  let bob: Client;
  let admin: Client;

  beforeAll(async () => {
    [alice, bob, admin] = await Promise.all([signIn('alice'), signIn('bob'), signIn('admin')]);
  });

  it('refuses anonymous reads', async () => {
    const { data, error } = await anonClient().from('tools').select('id');

    expect(data).toBeNull();
    expect(error?.code).toBe('42501');
  });

  it("shows other members' available tools but not their unavailable ones", async () => {
    const { data, error } = await alice
      .from('tools')
      .select('id')
      .in('id', [seedTools.bobPressureWasher, seedTools.bobHedgeTrimmer]);

    expect(error).toBeNull();
    expect(data?.map((tool) => tool.id)).toEqual([seedTools.bobPressureWasher]);
  });

  it("does not let a member update another member's tool", async () => {
    const { data, error } = await alice
      .from('tools')
      .update({ name: 'hijacked' })
      .eq('id', seedTools.bobPressureWasher)
      .select('id');

    // RLS hides the row from the UPDATE, so nothing matches and nothing changes.
    expect(error).toBeNull();
    expect(data).toEqual([]);

    const { data: tool } = await bob
      .from('tools')
      .select('name')
      .eq('id', seedTools.bobPressureWasher)
      .single();
    expect(tool?.name).toBe('Pressure washer');
  });

  it("does not let a member delete another member's tool", async () => {
    const { data, error } = await alice
      .from('tools')
      .delete()
      .eq('id', seedTools.bobPressureWasher)
      .select('id');

    expect(error).toBeNull();
    expect(data).toEqual([]);
  });

  it('does not let a member take ownership of a tool', async () => {
    const { error } = await alice
      .from('tools')
      .update({ owner_id: seedUsers.alice.id })
      .eq('id', seedTools.bobPressureWasher);

    // owner_id has no UPDATE grant: rejected before RLS is even consulted.
    expect(error?.code).toBe('42501');
  });

  it('lets an admin read unavailable tools of any member', async () => {
    const { data, error } = await admin
      .from('tools')
      .select('id')
      .eq('id', seedTools.bobHedgeTrimmer);

    expect(error).toBeNull();
    expect(data).toHaveLength(1);
  });
});
