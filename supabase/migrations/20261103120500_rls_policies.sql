-- Step 5: privileges and row-level security.
-- Two layers, both required:
--   GRANTs decide which statements and columns a role may use at all.
--   Policies decide which rows those statements can see or change.
-- Every policy targets "authenticated" only and calls auth.uid() inside a
-- scalar subquery, so Postgres evaluates it once per statement, not per row.

alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.tools enable row level security;
alter table public.loans enable row level security;

-- Start from zero for the API roles, then grant only what is needed.
revoke all on public.profiles, public.user_roles, public.tools, public.loans from anon, authenticated;

grant select on public.profiles to authenticated;
grant update (display_name) on public.profiles to authenticated;

grant select on public.user_roles to authenticated;

grant select, delete on public.tools to authenticated;
-- owner_id is not grantable: it always takes its default, auth.uid().
grant insert (name, category, is_available) on public.tools to authenticated;
grant update (name, category, is_available) on public.tools to authenticated;

grant select on public.loans to authenticated;
-- borrower_id and status are not grantable on insert: they default to the
-- caller and to "requested". Only status can be updated, and a trigger
-- checks the transition.
grant insert (tool_id, starts_on, ends_on) on public.loans to authenticated;
grant update (status) on public.loans to authenticated;


-- profiles -------------------------------------------------------------------

-- Display names are shown next to tools, so members can read all profiles.
create policy profiles_select_members
  on public.profiles for select
  to authenticated
  using (true);

create policy profiles_update_own
  on public.profiles for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));


-- user_roles -----------------------------------------------------------------
-- No insert, update or delete policy: roles change only through migrations
-- or the service role, never through the public API.

create policy user_roles_select_own_or_admin
  on public.user_roles for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.is_admin((select auth.uid())))
  );


-- tools ----------------------------------------------------------------------

create policy tools_select_available_own_or_admin
  on public.tools for select
  to authenticated
  using (
    is_available
    or owner_id = (select auth.uid())
    or (select private.is_admin((select auth.uid())))
  );

create policy tools_insert_own
  on public.tools for insert
  to authenticated
  with check (owner_id = (select auth.uid()));

create policy tools_update_own
  on public.tools for update
  to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy tools_delete_own
  on public.tools for delete
  to authenticated
  using (owner_id = (select auth.uid()));


-- loans ----------------------------------------------------------------------

create policy loans_select_parties_or_admin
  on public.loans for select
  to authenticated
  using (
    borrower_id = (select auth.uid())
    or exists (
      select 1
      from public.tools as t
      where t.id = loans.tool_id
        and t.owner_id = (select auth.uid())
    )
    or (select private.is_admin((select auth.uid())))
  );

-- The same rules as request_loan, so a direct INSERT through the API cannot
-- skip them: own request only, someone else's available tool, dates not in
-- the past and not overlapping an approved loan.
create policy loans_insert_request
  on public.loans for insert
  to authenticated
  with check (
    borrower_id = (select auth.uid())
    and status = 'requested'
    and starts_on >= current_date
    and exists (
      select 1
      from public.tools as t
      where t.id = loans.tool_id
        and t.is_available
        and t.owner_id <> (select auth.uid())
    )
    and not private.tool_has_approved_overlap(tool_id, starts_on, ends_on)
  );

-- Only the tool owner can change a loan, and only its status (see grants).
create policy loans_update_tool_owner
  on public.loans for update
  to authenticated
  using (
    exists (
      select 1
      from public.tools as t
      where t.id = loans.tool_id
        and t.owner_id = (select auth.uid())
    )
  )
  with check (
    exists (
      select 1
      from public.tools as t
      where t.id = loans.tool_id
        and t.owner_id = (select auth.uid())
    )
  );
-- No delete policy on loans: the history is kept.
