-- Function hardening: who can execute what, and how each function runs.
begin;
\ir helpers/setup.psql

select plan(17);

-- Catalog-wide rules for every function this project owns in public and private
-- (functions that belong to extensions are excluded).
create temporary view project_functions as
  select p.oid, p.oid::regprocedure::text as signature, p.prosecdef, p.proconfig, p.proacl, p.proowner
  from pg_proc as p
  join pg_namespace as n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private')
    and not exists (
      select 1 from pg_depend as d
      where d.objid = p.oid and d.deptype = 'e'
    );
grant select on project_functions to anon, authenticated;

select isnt_empty(
  'select 1 from project_functions',
  'the catalog query finds the project functions'
);

select is_empty(
  $$ select signature from project_functions where has_function_privilege('anon', oid, 'execute') $$,
  'anon cannot execute any function in public or private'
);

select is_empty(
  $$
    select f.signature
    from project_functions as f,
      aclexplode(coalesce(f.proacl, acldefault('f', f.proowner))) as acl
    where acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
  $$,
  'no function is executable by PUBLIC'
);

select is_empty(
  $$ select signature from project_functions where not coalesce(proconfig @> array['search_path=""'], false) $$,
  'every function pins search_path to an empty string'
);

select is_empty(
  $$ select signature from project_functions where obj_description(oid, 'pg_proc') is null $$,
  'every function has a comment explaining its security mode'
);

select is_definer('private', 'is_admin', array['uuid'], 'private.is_admin is SECURITY DEFINER');
select is_definer('public', 'admin_list_loans', array['integer', 'integer'], 'admin_list_loans is SECURITY DEFINER');
select isnt_definer('public', 'request_loan', array['uuid', 'date', 'date'], 'request_loan is SECURITY INVOKER');
select isnt_definer('public', 'decide_loan', array['uuid', 'text'], 'decide_loan is SECURITY INVOKER');

select function_privs_are(
  'public', 'request_loan', array['uuid', 'date', 'date'], 'authenticated', array['EXECUTE'],
  'authenticated can execute request_loan'
);
select function_privs_are(
  'public', 'decide_loan', array['uuid', 'text'], 'authenticated', array['EXECUTE'],
  'authenticated can execute decide_loan'
);
select function_privs_are(
  'public', 'admin_list_loans', array['integer', 'integer'], 'authenticated', array['EXECUTE'],
  'authenticated can execute admin_list_loans'
);
select function_privs_are(
  'private', 'handle_new_user', array[]::text[], 'authenticated', array[]::text[],
  'authenticated cannot call the signup trigger function directly'
);

-- The same rules seen from the outside: anon calls fail before any code runs.
select tests.authenticate_as_anon();

select throws_ok(
  $$ select public.request_loan(gen_random_uuid(), current_date, current_date) $$,
  '42501', 'permission denied for function request_loan',
  'anon cannot execute request_loan'
);
select throws_ok(
  $$ select public.decide_loan(gen_random_uuid(), 'approved') $$,
  '42501', 'permission denied for function decide_loan',
  'anon cannot execute decide_loan'
);
select throws_ok(
  $$ select * from public.admin_list_loans() $$,
  '42501', 'permission denied for function admin_list_loans',
  'anon cannot execute admin_list_loans'
);
select throws_ok(
  $$ select private.is_admin(gen_random_uuid()) $$,
  '42501', 'permission denied for schema private',
  'anon cannot reach the private schema'
);

select * from finish();
rollback;
