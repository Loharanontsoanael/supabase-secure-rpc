-- request_loan: business rules, and proof that a direct INSERT cannot skip them.
begin;
\ir helpers/setup.psql

select plan(13);

-- O owns the tools, B and C are borrowers.
select tests.create_user('00000000-0000-4000-8000-00000000000f', 'Olga');
select tests.create_user('00000000-0000-4000-8000-00000000000b', 'Ben');
select tests.create_user('00000000-0000-4000-8000-00000000000c', 'Cleo');

insert into public.tools (id, owner_id, name, category, is_available)
values
  ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-00000000000f', 'Olga drill', 'test', true),
  ('00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-00000000000f', 'Olga saw', 'test', false);

-- C already has an approved loan on the drill, days +10 to +12.
insert into public.loans (tool_id, borrower_id, status, starts_on, ends_on)
values ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-00000000000c',
        'approved', current_date + 10, current_date + 12);

select tests.authenticate_as('00000000-0000-4000-8000-00000000000b');

select results_eq(
  $$ select borrower_id, status
     from public.request_loan('00000000-0000-4000-8000-000000000101', current_date + 1, current_date + 2) $$,
  $$ values ('00000000-0000-4000-8000-00000000000b'::uuid, 'requested'::text) $$,
  'a member can request someone else''s available tool'
);

select throws_ok(
  $$ select public.request_loan('00000000-0000-4000-8000-000000000101', current_date + 11, current_date + 13) $$,
  '23P01', 'the tool is already lent during these dates',
  'a request overlapping an approved loan is rejected'
);

select lives_ok(
  $$ select public.request_loan('00000000-0000-4000-8000-000000000101', current_date + 13, current_date + 14) $$,
  'a request right after an approved loan is accepted'
);

select lives_ok(
  $$ select public.request_loan('00000000-0000-4000-8000-000000000101', current_date + 1, current_date + 2) $$,
  'requests may overlap other requests: the owner chooses which one to approve'
);

select throws_ok(
  $$ select public.request_loan('00000000-0000-4000-8000-000000000101', current_date + 5, current_date + 4) $$,
  '22023', 'the end date must be on or after the start date',
  'an end date before the start date is rejected'
);

select throws_ok(
  $$ select public.request_loan('00000000-0000-4000-8000-000000000101', current_date - 1, current_date + 1) $$,
  '22023', 'a loan cannot start in the past',
  'a start date in the past is rejected'
);

select throws_ok(
  $$ select public.request_loan('00000000-0000-4000-8000-000000000101', null, current_date + 1) $$,
  '22004', 'tool, start date and end date are required',
  'missing arguments are rejected'
);

select throws_ok(
  $$ select public.request_loan('00000000-0000-4000-8000-000000000102', current_date + 1, current_date + 2) $$,
  'P0002', 'tool not found or not available',
  'an unavailable tool cannot be requested'
);

select throws_ok(
  $$ select public.request_loan(gen_random_uuid(), current_date + 1, current_date + 2) $$,
  'P0002', 'tool not found or not available',
  'an unknown tool cannot be requested'
);

select tests.authenticate_as('00000000-0000-4000-8000-00000000000f');

select throws_ok(
  $$ select public.request_loan('00000000-0000-4000-8000-000000000101', current_date + 1, current_date + 2) $$,
  '22023', 'you cannot borrow your own tool',
  'an owner cannot borrow their own tool'
);

-- The table API enforces the same rules: the RPC grants no extra power.
select throws_ok(
  $$ insert into public.loans (tool_id, starts_on, ends_on)
     values ('00000000-0000-4000-8000-000000000101', current_date + 1, current_date + 2) $$,
  '42501', 'new row violates row-level security policy for table "loans"',
  'a direct insert cannot borrow your own tool either'
);

select tests.authenticate_as('00000000-0000-4000-8000-00000000000b');

select throws_ok(
  $$ insert into public.loans (tool_id, starts_on, ends_on)
     values ('00000000-0000-4000-8000-000000000101', current_date + 11, current_date + 13) $$,
  '42501', 'new row violates row-level security policy for table "loans"',
  'a direct insert cannot overlap an approved loan either'
);

select lives_ok(
  $$ insert into public.loans (tool_id, starts_on, ends_on)
     values ('00000000-0000-4000-8000-000000000101', current_date + 20, current_date + 21) $$,
  'a valid direct insert is accepted, with the same rules as the RPC'
);

select * from finish();
rollback;
