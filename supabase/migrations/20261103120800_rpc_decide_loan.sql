-- Step 8: decide_loan RPC.

create function public.decide_loan(
  p_loan_id uuid,
  p_decision text
)
returns public.loans
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_tool_id uuid;
  v_status text;
  v_owner_id uuid;
  v_loan public.loans;
begin
  if v_user_id is null then
    raise exception 'authentication required'
      using errcode = 'insufficient_privilege';
  end if;

  if p_decision is null or p_decision not in ('approved', 'declined') then
    raise exception 'decision must be "approved" or "declined"'
      using errcode = 'invalid_parameter_value';
  end if;

  -- RLS applies: only the borrower, the tool owner and admins see the loan.
  select l.tool_id, l.status
  into v_tool_id, v_status
  from public.loans as l
  where l.id = p_loan_id;

  if not found then
    raise exception 'loan not found'
      using errcode = 'no_data_found';
  end if;

  select t.owner_id
  into v_owner_id
  from public.tools as t
  where t.id = v_tool_id;

  if v_owner_id is distinct from v_user_id then
    raise exception 'only the tool owner can decide on this loan'
      using errcode = 'insufficient_privilege';
  end if;

  if v_status <> 'requested' then
    raise exception 'only a requested loan can be decided (current status: %)', v_status
      using errcode = 'invalid_parameter_value';
  end if;

  begin
    -- The status filter makes the check and the update atomic: if another
    -- session decided first, no row matches.
    update public.loans as l
    set status = p_decision
    where l.id = p_loan_id
      and l.status = 'requested'
    returning l.* into v_loan;
  exception
    when exclusion_violation then
      raise exception 'the tool is already lent during these dates'
        using errcode = 'exclusion_violation';
  end;

  if v_loan.id is null then
    raise exception 'the loan was changed by another request, please retry'
      using errcode = 'serialization_failure';
  end if;

  return v_loan;
end;
$$;

comment on function public.decide_loan(uuid, text) is
  'SECURITY INVOKER: the loans UPDATE policy already limits changes to the tool owner, the column grant limits them to status, '
  'and a trigger enforces valid transitions. Running with the caller''s rights keeps all three layers in force; the function '
  'only adds clear errors and an atomic check-and-update.';

revoke all on function public.decide_loan(uuid, text) from public, anon;
grant execute on function public.decide_loan(uuid, text) to authenticated;
