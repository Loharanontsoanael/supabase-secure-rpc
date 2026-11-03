-- Step 9: admin_list_loans RPC.

-- Supports the report's ORDER BY so each page is an index scan.
create index loans_created_at_id_idx on public.loans (created_at desc, id desc);

create function public.admin_list_loans(
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  loan_id uuid,
  tool_id uuid,
  tool_name text,
  owner_id uuid,
  borrower_id uuid,
  status text,
  starts_on date,
  ends_on date,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  c_max_limit constant integer := 100;
begin
  -- First statement, before any data is read: this function bypasses RLS,
  -- so this check is the only gate.
  if not private.is_admin((select auth.uid())) then
    raise exception 'admin role required'
      using errcode = 'insufficient_privilege';
  end if;

  if p_limit is null or p_limit < 1 then
    raise exception 'p_limit must be a positive integer'
      using errcode = 'invalid_parameter_value';
  end if;

  if p_offset is null or p_offset < 0 then
    raise exception 'p_offset must be zero or positive'
      using errcode = 'invalid_parameter_value';
  end if;

  return query
    select
      l.id,
      l.tool_id,
      t.name,
      t.owner_id,
      l.borrower_id,
      l.status,
      l.starts_on,
      l.ends_on,
      l.created_at
    from public.loans as l
    join public.tools as t on t.id = l.tool_id
    order by l.created_at desc, l.id desc
    limit least(p_limit, c_max_limit)
    offset p_offset;
end;
$$;

comment on function public.admin_list_loans(integer, integer) is
  'SECURITY DEFINER: an admin report over all loans and tools, gated by one explicit private.is_admin check as its first '
  'statement instead of per-row policy checks on every joined table. Because it bypasses RLS, EXECUTE is granted to '
  'authenticated only, non-admins get errcode 42501, and the page size is capped server side at 100 rows.';

revoke all on function public.admin_list_loans(integer, integer) from public, anon;
grant execute on function public.admin_list_loans(integer, integer) to authenticated;
