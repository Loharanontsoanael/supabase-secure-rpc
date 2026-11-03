-- decide_loan and status transitions.
begin;
\ir helpers/setup.psql

select plan(14);

-- O owns the tool, B and C request it, S is an unrelated member.
select tests.create_user('00000000-0000-4000-8000-00000000000f', 'Olga');
select tests.create_user('00000000-0000-4000-8000-00000000000b', 'Ben');
select tests.create_user('00000000-0000-4000-8000-00000000000c', 'Cleo');
select tests.create_user('00000000-0000-4000-8000-00000000000e', 'Sam');

insert into public.tools (id, owner_id, name, category)
values ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-00000000000f', 'Olga drill', 'test');

-- L1 (B) and L2 (C) overlap. L3 (B) is later.
insert into public.loans (id, tool_id, borrower_id, starts_on, ends_on)
values
  ('00000000-0000-4000-8000-000000000201', '00000000-0000-4000-8000-000000000101',
   '00000000-0000-4000-8000-00000000000b', current_date + 1, current_date + 3),
  ('00000000-0000-4000-8000-000000000202', '00000000-0000-4000-8000-000000000101',
   '00000000-0000-4000-8000-00000000000c', current_date + 2, current_date + 4),
  ('00000000-0000-4000-8000-000000000203', '00000000-0000-4000-8000-000000000101',
   '00000000-0000-4000-8000-00000000000b', current_date + 10, current_date + 11);

-- Who may decide -------------------------------------------------------------
select tests.authenticate_as('00000000-0000-4000-8000-00000000000b');
select throws_ok(
  $$ select public.decide_loan('00000000-0000-4000-8000-000000000201', 'approved') $$,
  '42501', 'only the tool owner can decide on this loan',
  'the borrower cannot approve their own request'
);

select tests.authenticate_as('00000000-0000-4000-8000-00000000000e');
select throws_ok(
  $$ select public.decide_loan('00000000-0000-4000-8000-000000000201', 'approved') $$,
  'P0002', 'loan not found',
  'an unrelated member cannot even see the loan'
);

-- Decisions by the owner -----------------------------------------------------
select tests.authenticate_as('00000000-0000-4000-8000-00000000000f');

select throws_ok(
  $$ select public.decide_loan('00000000-0000-4000-8000-000000000201', 'maybe') $$,
  '22023', 'decision must be "approved" or "declined"',
  'an unknown decision is rejected'
);

select results_eq(
  $$ select status from public.decide_loan('00000000-0000-4000-8000-000000000201', 'approved') $$,
  $$ values ('approved'::text) $$,
  'the owner approves a requested loan'
);

select throws_ok(
  $$ select public.decide_loan('00000000-0000-4000-8000-000000000201', 'declined') $$,
  '22023', 'only a requested loan can be decided (current status: approved)',
  'a decision cannot be changed afterwards'
);

select throws_ok(
  $$ select public.decide_loan('00000000-0000-4000-8000-000000000202', 'approved') $$,
  '23P01', 'the tool is already lent during these dates',
  'two overlapping loans cannot both be approved'
);

select results_eq(
  $$ select status from public.decide_loan('00000000-0000-4000-8000-000000000202', 'declined') $$,
  $$ values ('declined'::text) $$,
  'the owner declines the overlapping request'
);

-- Transitions through the table API (same trigger) ---------------------------
select throws_ok(
  $$ update public.loans set status = 'approved' where id = '00000000-0000-4000-8000-000000000202' $$,
  '23514', 'invalid loan status transition from declined to approved',
  'declined is final'
);

select throws_ok(
  $$ update public.loans set status = 'requested' where id = '00000000-0000-4000-8000-000000000201' $$,
  '23514', 'invalid loan status transition from approved to requested',
  'an approved loan cannot go back to requested'
);

select lives_ok(
  $$ update public.loans set status = 'returned' where id = '00000000-0000-4000-8000-000000000201' $$,
  'an approved loan can be marked as returned'
);

select throws_ok(
  $$ update public.loans set status = 'approved' where id = '00000000-0000-4000-8000-000000000201' $$,
  '23514', 'invalid loan status transition from returned to approved',
  'returned is final'
);

-- Rules that hold even for privileged connections ----------------------------
select tests.clear_authentication();

select throws_ok(
  $$ update public.loans set starts_on = current_date + 30, ends_on = current_date + 31
     where id = '00000000-0000-4000-8000-000000000203' $$,
  '23514', 'only the status of a loan can change',
  'loan dates are immutable, even for the table owner'
);

insert into public.loans (tool_id, borrower_id, status, starts_on, ends_on)
values ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-00000000000b',
        'approved', current_date + 40, current_date + 42);

select throws_ok(
  $$ insert into public.loans (tool_id, borrower_id, status, starts_on, ends_on)
     values ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-00000000000c',
             'approved', current_date + 42, current_date + 44) $$,
  '23P01', null,
  'the exclusion constraint blocks overlapping approved loans for every writer'
);

select lives_ok(
  $$ insert into public.loans (tool_id, borrower_id, status, starts_on, ends_on)
     values ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-00000000000c',
             'declined', current_date + 42, current_date + 44) $$,
  'overlapping loans that are not approved are allowed'
);

select * from finish();
rollback;
