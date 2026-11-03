-- Step 1: schemas, extensions and least-privilege defaults.

-- Helper functions used by RLS policies live in "private".
-- This schema is not listed in [api].schemas (supabase/config.toml), so the
-- Data API never exposes anything inside it.
create schema if not exists private;
comment on schema private is
  'Internal helpers for RLS policies and triggers. Never exposed by the Data API.';

revoke all on schema private from public;
-- Policies are evaluated with the privileges of the calling role, so
-- "authenticated" needs USAGE to call private.is_admin() from a policy.
grant usage on schema private to authenticated;

-- btree_gist lets one exclusion constraint combine "=" on a uuid column with
-- "&&" on a date range (see the loan integrity migration).
create extension if not exists btree_gist with schema extensions;

-- Least privilege by default: tables, sequences and functions created later in
-- "public" are not reachable by the API roles until a migration grants access
-- explicitly. Every grant in this project is therefore written down.
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke execute on functions from anon, authenticated;
