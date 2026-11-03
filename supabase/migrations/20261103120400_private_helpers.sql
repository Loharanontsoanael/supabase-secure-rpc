-- Step 4: private helper functions.
-- Every SECURITY DEFINER function follows the same checklist:
--   set search_path = '', schema-qualify every object, revoke EXECUTE from
--   public and anon, grant it only to the roles that need it.

-- Admin check used by RLS policies.
create function private.is_admin(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_roles as ur
    where ur.user_id = p_user_id
      and ur.role = 'admin'
  );
$$;

comment on function private.is_admin(uuid) is
  'SECURITY DEFINER: reads public.user_roles as the function owner, so RLS on user_roles is not applied inside it. '
  'The user_roles policy calls this function; as SECURITY INVOKER the lookup would re-enter that same policy, and whether '
  'that ends in "infinite recursion detected in policy" would depend on the query plan. Definer rights remove the cycle. '
  'Returns a boolean only and lives in the unexposed private schema.';

revoke all on function private.is_admin(uuid) from public, anon;
grant execute on function private.is_admin(uuid) to authenticated;


-- Availability check used by request_loan and by the loans INSERT policy.
-- A borrower cannot see other members' loans through RLS, yet must not book
-- dates that are already taken. This function answers that one question.
create function private.tool_has_approved_overlap(
  p_tool_id uuid,
  p_starts_on date,
  p_ends_on date
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.loans as l
    where l.tool_id = p_tool_id
      and l.status = 'approved'
      and daterange(l.starts_on, l.ends_on, '[]') && daterange(p_starts_on, p_ends_on, '[]')
  );
$$;

comment on function private.tool_has_approved_overlap(uuid, date, date) is
  'SECURITY DEFINER: must see approved loans of every member, which RLS hides from the caller. '
  'It returns a single boolean and never exposes who borrowed the tool or when.';

revoke all on function private.tool_has_approved_overlap(uuid, date, date) from public, anon;
grant execute on function private.tool_has_approved_overlap(uuid, date, date) to authenticated;


-- Creates the profile and the default role of every new auth user.
create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      nullif(left(btrim(new.raw_user_meta_data ->> 'display_name'), 80), ''),
      nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
      'member'
    )
  );

  -- The role is always "user". User metadata is editable by the user, so it
  -- is never trusted for authorization.
  insert into public.user_roles (user_id, role)
  values (new.id, 'user');

  return new;
end;
$$;

comment on function private.handle_new_user() is
  'SECURITY DEFINER: runs as the auth service inserts into auth.users, a role that has no rights on public tables. '
  'Only callable as a trigger: EXECUTE is revoked from every API role.';

revoke all on function private.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();
