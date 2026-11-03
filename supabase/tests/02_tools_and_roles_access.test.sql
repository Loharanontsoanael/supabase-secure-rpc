-- Row access on tools, profiles and user_roles.
begin;
\ir helpers/setup.psql

select plan(16);

-- Users: A and B are members, M is an admin.
select tests.create_user('00000000-0000-4000-8000-00000000000a', 'Ana');
select tests.create_user('00000000-0000-4000-8000-00000000000b', 'Ben');
select tests.create_user('00000000-0000-4000-8000-0000000000ad', 'Mia');
select tests.make_admin('00000000-0000-4000-8000-0000000000ad');

insert into public.tools (id, owner_id, name, category, is_available)
values
  ('00000000-0000-4000-8000-0000000001a1', '00000000-0000-4000-8000-00000000000a', 'A available', 'test', true),
  ('00000000-0000-4000-8000-0000000001a2', '00000000-0000-4000-8000-00000000000a', 'A hidden', 'test', false),
  ('00000000-0000-4000-8000-0000000001b1', '00000000-0000-4000-8000-00000000000b', 'B available', 'test', true),
  ('00000000-0000-4000-8000-0000000001b2', '00000000-0000-4000-8000-00000000000b', 'B hidden', 'test', false);

-- As user A ------------------------------------------------------------------
select tests.authenticate_as('00000000-0000-4000-8000-00000000000a');

select results_eq(
  $$ select name from public.tools where category = 'test' order by name $$,
  $$ values ('A available'), ('A hidden'), ('B available') $$,
  'a member sees available tools and their own, but not other members'' unavailable tools'
);

with changed as (
  update public.tools set name = 'hijacked'
  where id = '00000000-0000-4000-8000-0000000001b1'
  returning 1
)
select is(count(*)::int, 0, 'a member cannot update another member''s tool') from changed;

with removed as (
  delete from public.tools
  where id = '00000000-0000-4000-8000-0000000001b1'
  returning 1
)
select is(count(*)::int, 0, 'a member cannot delete another member''s tool') from removed;

with changed as (
  update public.tools set name = 'A renamed'
  where id = '00000000-0000-4000-8000-0000000001a1'
  returning 1
)
select is(count(*)::int, 1, 'a member can update their own tool') from changed;

select throws_ok(
  $$ insert into public.tools (owner_id, name, category)
     values ('00000000-0000-4000-8000-00000000000b', 'planted', 'test') $$,
  '42501', 'permission denied for table tools',
  'a member cannot create a tool on behalf of someone else'
);

select throws_ok(
  $$ update public.tools set owner_id = '00000000-0000-4000-8000-00000000000a'
     where id = '00000000-0000-4000-8000-0000000001b1' $$,
  '42501', 'permission denied for table tools',
  'a member cannot take ownership of a tool'
);

select results_eq(
  $$ insert into public.tools (name, category) values ('A new', 'test') returning owner_id $$,
  $$ values ('00000000-0000-4000-8000-00000000000a'::uuid) $$,
  'a new tool always belongs to its creator'
);

with changed as (
  update public.profiles set display_name = 'hijacked'
  where id = '00000000-0000-4000-8000-00000000000b'
  returning 1
)
select is(count(*)::int, 0, 'a member cannot rename another member') from changed;

select results_eq(
  $$ select user_id, role from public.user_roles order by role $$,
  $$ values ('00000000-0000-4000-8000-00000000000a'::uuid, 'user'::text) $$,
  'a member only sees their own roles'
);

select throws_ok(
  $$ insert into public.user_roles (user_id, role)
     values ('00000000-0000-4000-8000-00000000000a', 'admin') $$,
  '42501', 'permission denied for table user_roles',
  'a member cannot grant themselves the admin role'
);

-- Data must be untouched -----------------------------------------------------
select tests.clear_authentication();

select results_eq(
  $$ select name from public.tools where id = '00000000-0000-4000-8000-0000000001b1' $$,
  $$ values ('B available') $$,
  'the other member''s tool still exists, unchanged'
);

-- As the admin ---------------------------------------------------------------
select tests.authenticate_as('00000000-0000-4000-8000-0000000000ad');

select results_eq(
  $$ select name from public.tools where category = 'test' order by name $$,
  $$ values ('A hidden'), ('A new'), ('A renamed'), ('B available'), ('B hidden') $$,
  'an admin reads every tool, including unavailable ones'
);

with changed as (
  update public.tools set name = 'admin edit'
  where id = '00000000-0000-4000-8000-0000000001b1'
  returning 1
)
select is(count(*)::int, 0, 'admin access is read-only: an admin cannot edit someone else''s tool') from changed;

-- The user_roles policy calls private.is_admin, which reads user_roles. Its
-- SECURITY DEFINER mode, which breaks that cycle, is asserted in
-- 01_function_security; this checks the behavior end to end.
select lives_ok(
  $$ select count(*) from public.user_roles $$,
  'an admin can read user_roles even though its policy reads user_roles'
);

select results_eq(
  $$ select count(*)::int from public.user_roles
     where user_id in ('00000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-00000000000b') $$,
  $$ values (2) $$,
  'an admin reads every member''s roles'
);

-- As anon --------------------------------------------------------------------
select tests.authenticate_as_anon();

select throws_ok(
  $$ select * from public.tools $$,
  '42501', 'permission denied for table tools',
  'anon cannot read tools'
);

select * from finish();
rollback;
