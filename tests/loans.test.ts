import { beforeAll, describe, expect, it } from 'vitest';
import {
  createOwnTool,
  daysFromToday,
  seedTools,
  seedUsers,
  signIn,
  type Client,
} from './support/supabase';

describe('loans through the RPC functions', () => {
  let alice: Client;
  let bob: Client;
  let admin: Client;
  let toolId: string;

  beforeAll(async () => {
    [alice, bob, admin] = await Promise.all([signIn('alice'), signIn('bob'), signIn('admin')]);
    toolId = await createOwnTool(alice);
  });

  it('runs the full request, decision and overlap flow', async () => {
    // Bob requests Alice's tool.
    const requested = await bob.rpc('request_loan', {
      p_tool_id: toolId,
      p_starts_on: daysFromToday(3),
      p_ends_on: daysFromToday(5),
    });
    expect(requested.error).toBeNull();
    expect(requested.data).toMatchObject({ borrower_id: seedUsers.bob.id, status: 'requested' });
    const loanId = requested.data?.id;
    if (!loanId) throw new Error('request_loan returned no loan');

    // Bob cannot approve his own request.
    const selfApproval = await bob.rpc('decide_loan', {
      p_loan_id: loanId,
      p_decision: 'approved',
    });
    expect(selfApproval.error?.code).toBe('42501');

    // Alice, the owner, approves it.
    const approved = await alice.rpc('decide_loan', {
      p_loan_id: loanId,
      p_decision: 'approved',
    });
    expect(approved.error).toBeNull();
    expect(approved.data?.status).toBe('approved');

    // A decision cannot be changed afterwards.
    const changedMind = await alice.rpc('decide_loan', {
      p_loan_id: loanId,
      p_decision: 'declined',
    });
    expect(changedMind.error?.code).toBe('22023');

    // The dates are now taken.
    const overlapping = await bob.rpc('request_loan', {
      p_tool_id: toolId,
      p_starts_on: daysFromToday(4),
      p_ends_on: daysFromToday(6),
    });
    expect(overlapping.error?.code).toBe('23P01');

    // The admin sees the loan, as do both parties.
    for (const client of [alice, bob, admin]) {
      const { data } = await client.from('loans').select('id').eq('id', loanId);
      expect(data).toHaveLength(1);
    }
  });

  it('rejects borrowing your own tool', async () => {
    const { error } = await alice.rpc('request_loan', {
      p_tool_id: toolId,
      p_starts_on: daysFromToday(10),
      p_ends_on: daysFromToday(11),
    });

    expect(error?.code).toBe('22023');
  });

  it('hides a loan from members who are not part of it', async () => {
    // Seed: Bob borrows the admin's tile cutter. Alice is not involved.
    const asAlice = await alice.from('loans').select('id').eq('tool_id', seedTools.adminTileCutter);
    const asBob = await bob.from('loans').select('id').eq('tool_id', seedTools.adminTileCutter);

    expect(asAlice.error).toBeNull();
    expect(asAlice.data).toEqual([]);
    expect(asBob.data?.length).toBeGreaterThan(0);
  });
});
