-- Step 6: loan integrity rules that hold for every access path.

-- Two approved loans of the same tool can never overlap, even when two
-- approvals run at the same time. Checks in application code cannot give
-- that guarantee; an exclusion constraint can.
alter table public.loans
  add constraint loans_no_overlapping_approved
  exclude using gist (
    tool_id with =,
    daterange(starts_on, ends_on, '[]') with &&
  )
  where (status = 'approved');


-- Valid status transitions:
--   requested -> approved | declined
--   approved  -> returned
-- Every other column is immutable after creation.
create function private.enforce_loan_update()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.tool_id is distinct from old.tool_id
    or new.borrower_id is distinct from old.borrower_id
    or new.starts_on is distinct from old.starts_on
    or new.ends_on is distinct from old.ends_on
    or new.created_at is distinct from old.created_at
  then
    raise exception 'only the status of a loan can change'
      using errcode = 'check_violation';
  end if;

  if new.status is distinct from old.status
    and not (
      (old.status = 'requested' and new.status in ('approved', 'declined'))
      or (old.status = 'approved' and new.status = 'returned')
    )
  then
    raise exception 'invalid loan status transition from % to %', old.status, new.status
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

comment on function private.enforce_loan_update() is
  'SECURITY INVOKER: it only compares OLD and NEW and reads no table, so it needs no extra privileges. '
  'Runs as a BEFORE UPDATE trigger, which also covers the service role and direct API updates.';

revoke all on function private.enforce_loan_update() from public, anon, authenticated;

create trigger loans_enforce_update
  before update on public.loans
  for each row execute function private.enforce_loan_update();
