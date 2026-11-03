-- Step 7: request_loan RPC.

create function public.request_loan(
  p_tool_id uuid,
  p_starts_on date,
  p_ends_on date
)
returns public.loans
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_owner_id uuid;
  v_loan public.loans;
begin
  if v_user_id is null then
    raise exception 'authentication required'
      using errcode = 'insufficient_privilege';
  end if;

  if p_tool_id is null or p_starts_on is null or p_ends_on is null then
    raise exception 'tool, start date and end date are required'
      using errcode = 'null_value_not_allowed';
  end if;

  if p_ends_on < p_starts_on then
    raise exception 'the end date must be on or after the start date'
      using errcode = 'invalid_parameter_value';
  end if;

  if p_starts_on < current_date then
    raise exception 'a loan cannot start in the past'
      using errcode = 'invalid_parameter_value';
  end if;

  -- RLS applies here: the caller only sees available tools and their own.
  select t.owner_id
  into v_owner_id
  from public.tools as t
  where t.id = p_tool_id
    and t.is_available;

  if not found then
    raise exception 'tool not found or not available'
      using errcode = 'no_data_found';
  end if;

  if v_owner_id = v_user_id then
    raise exception 'you cannot borrow your own tool'
      using errcode = 'invalid_parameter_value';
  end if;

  if private.tool_has_approved_overlap(p_tool_id, p_starts_on, p_ends_on) then
    raise exception 'the tool is already lent during these dates'
      using errcode = 'exclusion_violation';
  end if;

  -- borrower_id and status take their defaults: auth.uid() and 'requested'.
  -- The loans INSERT policy checks the same rules again.
  insert into public.loans (tool_id, starts_on, ends_on)
  values (p_tool_id, p_starts_on, p_ends_on)
  returning * into v_loan;

  return v_loan;
end;
$$;

comment on function public.request_loan(uuid, date, date) is
  'SECURITY INVOKER: RLS on tools and loans already says who may request a loan, so the function runs with the caller''s rights '
  'and can never do more than a direct insert. It adds clear error messages; the one check RLS cannot express (overlap with '
  'other members'' approved loans) goes through the narrow private.tool_has_approved_overlap helper.';

revoke all on function public.request_loan(uuid, date, date) from public, anon;
grant execute on function public.request_loan(uuid, date, date) to authenticated;
