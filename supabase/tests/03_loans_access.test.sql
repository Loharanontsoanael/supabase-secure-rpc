-- Row access on loans: visible only to the borrower, the tool owner and admins.
begin;
\ir helpers/setup.psql

select plan(12);

-- O owns the tool, B borrows it, S is an unrelated member, M is an admin.
select tests.create_user('00000000-0000-4000-8000-00000000000f', 'Olga');
select tests.create_user('00000000-0000-4000-8000-00000000000b', 'Ben');
select tests.create_user('00000000-0000-4000-8000-00000000000c', 'Sam');
select tests.create_user('00000000-0000-4000-8000-0000000000ad', 'Mia');
select tests.make_admin('00000000-0000-4000-8000-0000000000ad');

insert into public.tools (id, owner_id, name, category)
values ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-00000000000f', 'Olga drill', 'test');

insert into public.loans (id, tool_id, borrower_id, starts_on, ends_on)
values (
  '00000000-0000-4000-8000-000000000201',
  '00000000-0000-4000-8000-000000000101',
  '00000000-0000-4000-8000-00000000000b',
  current_date + 1,
  current_date + 2
);

-- Visibility -----------------------------------------------------------------
select tests.authenticate_as('00000000-0000-4000-8000-00000000000b');
select results_eq(
  $$ select id from public.loans where id = '00000000-0000-4000-8000-000000000201' $$,
  $$ values ('00000000-0000-4000-8000-000000000201'::uuid) $$,
  'the borrower sees the loan'
);

select tests.authenticate_as('00000000-0000-4000-8000-00000000000f');
select results_eq(
  $$ select id from public.loans where id = '00000000-0000-4000-8000-000000000201' $$,
  $$ values ('00000000-0000-4000-8000-000000000201'::uuid) $$,
  'the tool owner sees the loan'
);

select tests.authenticate_as('00000000-0000-4000-8000-0000000000ad');
select results_eq(
  $$ select id from public.loans where id = '00000000-0000-4000-8000-000000000201' $$,
  $$ values ('00000000-0000-4000-8000-000000000201'::uuid) $$,
  'an admin sees the loan'
);

select tests.authenticate_as('00000000-0000-4000-8000-00000000000c');
select is_empty(
  $$ select id from public.loans where id = '00000000-0000-4000-8000-000000000201' $$,
  'an unrelated member does not see the loan'
);

-- Modification ---------------------------------------------------------------
with changed as (
  update public.loans set status = 'approved'
  where id = '00000000-0000-4000-8000-000000000201'
  returning 1
)
select is(count(*)::int, 0, 'an unrelated member cannot change the loan') from changed;

select tests.authenticate_as('00000000-0000-4000-8000-00000000000b');
with changed as (
  update public.loans set status = 'approved'
  where id = '00000000-0000-4000-8000-000000000201'
  returning 1
)
select is(count(*)::int, 0, 'the borrower cannot approve their own request') from changed;

select throws_ok(
  $$ update public.loans set ends_on = current_date + 30
     where id = '00000000-0000-4000-8000-000000000201' $$,
  '42501', 'permission denied for table loans',
  'the borrower cannot change the loan dates'
);

select throws_ok(
  $$ delete from public.loans where id = '00000000-0000-4000-8000-000000000201' $$,
  '42501', 'permission denied for table loans',
  'the borrower cannot delete the loan'
);

select throws_ok(
  $$ insert into public.loans (tool_id, borrower_id, starts_on, ends_on)
     values ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-00000000000c',
             current_date + 5, current_date + 6) $$,
  '42501', 'permission denied for table loans',
  'a member cannot request a loan on behalf of someone else'
);

select tests.authenticate_as('00000000-0000-4000-8000-00000000000f');
select throws_ok(
  $$ delete from public.loans where id = '00000000-0000-4000-8000-000000000201' $$,
  '42501', 'permission denied for table loans',
  'the tool owner cannot delete the loan history'
);

select tests.clear_authentication();
select results_eq(
  $$ select status from public.loans where id = '00000000-0000-4000-8000-000000000201' $$,
  $$ values ('requested'::text) $$,
  'the loan is unchanged'
);

select tests.authenticate_as_anon();
select throws_ok(
  $$ select * from public.loans $$,
  '42501', 'permission denied for table loans',
  'anon cannot read loans'
);

select * from finish();
rollback;
