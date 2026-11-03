-- Structural checks: they fail as soon as someone adds a table, policy or
-- grant that breaks the project's security conventions.
begin;
\ir helpers/setup.psql

select plan(10);

select is_empty(
  $$
    select c.relname
    from pg_class as c
    join pg_namespace as n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and not c.relrowsecurity
  $$,
  'RLS is enabled on every table in public'
);

select is_empty(
  $$
    select c.relname
    from pg_class as c
    join pg_namespace as n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and not exists (
        select 1 from pg_policies as p
        where p.schemaname = 'public' and p.tablename = c.relname
      )
  $$,
  'every table in public has at least one policy'
);

select is_empty(
  $$
    select tablename || '.' || policyname
    from pg_policies
    where schemaname = 'public'
      and roles <> array['authenticated']::name[]
  $$,
  'every policy is scoped to authenticated only'
);

select is_empty(
  $$
    select tablename || '.' || policyname
    from pg_policies
    where schemaname = 'public'
      and concat_ws(' ', qual, with_check) ~ '(?<!SELECT )auth\.uid\(\)'
  $$,
  'policies call auth.uid() through a scalar subquery (evaluated once per statement)'
);

select has_index('public', 'tools', 'tools_owner_id_idx', 'owner_id', 'tools.owner_id is indexed');
select has_index('public', 'tools', 'tools_is_available_idx', 'is_available', 'tools.is_available is indexed');
select has_index('public', 'loans', 'loans_borrower_id_idx', 'borrower_id', 'loans.borrower_id is indexed');
select has_index('public', 'loans', 'loans_tool_id_idx', 'tool_id', 'loans.tool_id is indexed');

select ok(
  not has_schema_privilege('anon', 'private', 'usage'),
  'anon cannot use the private schema'
);

select is_empty(
  $$
    select c.relname
    from pg_class as c
    join pg_namespace as n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p', 'v', 'm')
      and has_table_privilege('anon', c.oid, 'select, insert, update, delete, truncate, references, trigger')
  $$,
  'anon has no privilege on any table or view in public'
);

select * from finish();
rollback;
