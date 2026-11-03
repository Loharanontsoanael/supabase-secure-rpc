-- admin_list_loans: admin gate and server-side pagination.
begin;
\ir helpers/setup.psql

select plan(8);

select tests.create_user('00000000-0000-4000-8000-00000000000f', 'Olga');
select tests.create_user('00000000-0000-4000-8000-00000000000b', 'Ben');
select tests.create_user('00000000-0000-4000-8000-0000000000ad', 'Mia');
select tests.make_admin('00000000-0000-4000-8000-0000000000ad');

insert into public.tools (id, owner_id, name, category)
values ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-00000000000f', 'Olga drill', 'test');

-- 120 loan requests, more than the hard page limit of 100.
insert into public.loans (tool_id, borrower_id, starts_on, ends_on)
select '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-00000000000b',
       current_date + i, current_date + i
from generate_series(1, 120) as i;

select tests.authenticate_as('00000000-0000-4000-8000-00000000000b');
select throws_ok(
  $$ select * from public.admin_list_loans() $$,
  '42501', 'admin role required',
  'a normal user gets 42501'
);

select tests.authenticate_as('00000000-0000-4000-8000-0000000000ad');

select results_eq(
  $$ select count(*)::int from public.admin_list_loans() $$,
  $$ values (20) $$,
  'the default page size is 20'
);

select results_eq(
  $$ select count(*)::int from public.admin_list_loans(1000, 0) $$,
  $$ values (100) $$,
  'the page size is capped at 100, whatever the client asks'
);

select results_eq(
  $$ select count(*)::int from public.admin_list_loans(100, 0)
     where borrower_id = '00000000-0000-4000-8000-00000000000b' $$,
  $$ values (100) $$,
  'an admin sees loans of other members, newest first'
);

select results_eq(
  $$ select loan_id from public.admin_list_loans(5, 0)
     union all
     select loan_id from public.admin_list_loans(5, 5) $$,
  $$ select loan_id from public.admin_list_loans(10, 0) $$,
  'pages are stable and contiguous'
);

select throws_ok(
  $$ select * from public.admin_list_loans(0, 0) $$,
  '22023', 'p_limit must be a positive integer',
  'a page size of 0 is rejected'
);

select throws_ok(
  $$ select * from public.admin_list_loans(10, -1) $$,
  '22023', 'p_offset must be zero or positive',
  'a negative offset is rejected'
);

select throws_ok(
  $$ select * from public.admin_list_loans(null, 0) $$,
  '22023', 'p_limit must be a positive integer',
  'a null page size is rejected'
);

select * from finish();
rollback;
