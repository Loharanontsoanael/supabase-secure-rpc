# supabase-secure-rpc

A small, fully tested example of how to secure a Supabase/PostgreSQL backend with
row-level security (RLS), column grants and carefully scoped `SECURITY DEFINER` functions.

## What this repo shows

The domain is deliberately tiny: a neighborhood tool-lending app where members list tools,
request loans and approve requests for their own tools. The point is not the app. The point is
the access rules around it, and the proof that those rules hold.

With Supabase, the database is the API. Any table in an exposed schema can be queried directly
by a browser with the public key, so authorization must live in Postgres itself, not in client
code. This repo shows the patterns I use for that: least privilege by default, RLS on every
table, column-level grants, integrity rules that hold for every caller, and RPC functions that
never give a caller more power than the table API already does.

Every rule is backed by a test. 90 pgTAP assertions check the rules inside the database, and a
Vitest suite checks the same rules through the real Supabase API, with real signed-in users.
CI runs all of it on every push.

## Run it locally

Prerequisites:

- Docker, or any compatible runtime such as OrbStack or Colima
- Supabase CLI 3.x (`brew install supabase/tap/supabase`)
- Node.js 22 or later

```bash
git clone https://github.com/<you>/supabase-secure-rpc.git
cd supabase-secure-rpc
npm ci

supabase start                                     # starts Postgres, Auth and the REST API, applies migrations and seed
supabase db lint --level warning --fail-on warning # static checks of every function
supabase test db                                   # pgTAP tests

npm run env:local                                  # writes .env with the local URL and publishable key
npm run typecheck
npm test                                           # Vitest integration tests against the local API
```

To start again from a clean database: `supabase db reset`.

The seed creates three local accounts (`alice@example.test`, `bob@example.test`,
`admin@example.test`) with the password `local-only-password`. They exist only on your local
stack.

## Project layout

```
supabase/
  config.toml           only the public schema is exposed, unused services are off
  migrations/           one migration per logical step, applied in order
  seed.sql              local-only users, tools and loans
  tests/                pgTAP tests (run with supabase test db)
src/database.types.ts   generated with supabase gen types, checked for drift in CI
tests/                  Vitest integration tests through @supabase/supabase-js
.github/workflows/      CI pipeline
```

## Security decisions

### 1. RLS on every table, with policies that scale

RLS is enabled on every table in `public`. Every policy is scoped `to authenticated`, so the
`anon` role matches no policy at all. On top of that, `anon` has no table privileges, so an
anonymous request fails with `permission denied` before RLS is even consulted.

Policies call `(select auth.uid())` instead of `auth.uid()`. Wrapped in a scalar subquery, the
function runs once per statement instead of once per row. Every column a policy filters on is
indexed, because a policy is an extra `WHERE` clause on every query.

**Risk prevented:** data exposed by a forgotten policy, anonymous access by accident, and policies
that turn every request into a full table scan as data grows.

Tests check this structurally: if someone adds a table without RLS, a policy for another role,
or a bare `auth.uid()` call, `supabase test db` fails.

### 2. Who can see and change what

| Table        | Read                                                 | Write                                                     |
| ------------ | ---------------------------------------------------- | --------------------------------------------------------- |
| `tools`      | available tools, your own tools; admins read all     | owner only: insert, update, delete                        |
| `loans`      | the borrower, the tool owner; admins read all        | borrower creates a request; tool owner changes the status |
| `profiles`   | every member (display names are shown next to tools) | your own display name                                     |
| `user_roles` | your own roles; admins read all                      | nobody through the API                                    |

Policies decide which rows a statement sees. Grants decide which columns it may touch. Both are
used:

- `tools.owner_id` and `loans.borrower_id` cannot be written through the API. They default to
  `auth.uid()`, so you cannot create a tool or a loan in someone else's name.
- On `loans`, only `status` is updatable. A trigger rejects invalid transitions
  (`requested -> approved | declined`, `approved -> returned`) and any change to other columns,
  even from the service role.
- Two approved loans of the same tool can never overlap. This is an exclusion constraint, so it
  also holds when two approvals run at the same time.
- Admin access is read only. Admins cannot edit other members' data.

**Risk prevented:** horizontal privilege escalation (user A acting on user B's data), forged
ownership, tampered loan history and double booking under concurrency.

### 3. The admin check: `private.is_admin(uuid)`

The admin check is a `SECURITY DEFINER` function with `set search_path = ''`, in a `private`
schema that the Data API does not expose.

Running as its owner, it reads `user_roles` without RLS. That matters because the policy on
`user_roles` itself asks whether the caller is an admin. Without definer rights, the lookup
would re-enter the same policy, and whether that ends in `infinite recursion detected in policy`
would depend on the query plan.

Roles live in their own table and are never derived from `raw_user_meta_data`, which users can
edit themselves. New accounts always get the `user` role.

**Risk prevented:** recursive policies, self-promotion to admin, and a helper callable over HTTP.

### 4. RPC functions: invoker by default, definer only when needed

| Function                                    | Mode               | Why                                                                                                                               |
| ------------------------------------------- | ------------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| `request_loan(tool_id, starts_on, ends_on)` | `SECURITY INVOKER` | RLS already says who may request a loan. The function adds clear errors and cannot do more than a direct insert.                  |
| `decide_loan(loan_id, decision)`            | `SECURITY INVOKER` | The update policy, the column grant and the trigger stay in force. The function adds clear errors and an atomic check-and-update. |
| `admin_list_loans(p_limit, p_offset)`       | `SECURITY DEFINER` | One explicit admin check, run first, gates a report over all loans and tools. The page size is capped at 100 server side.         |

`request_loan` needs one fact RLS cannot give it: whether another member already has an
approved loan on those dates. That check lives in `private.tool_has_approved_overlap`, a narrow
definer helper that returns a boolean and nothing else. The loans INSERT policy calls it too, so
a direct `POST /rest/v1/loans` follows exactly the same rules as the RPC. A test proves it.

Every function, definer or not: `set search_path = ''`, every object schema-qualified, `EXECUTE`
revoked from `PUBLIC` and `anon`, granted only to `authenticated`. Tests check all of this for
every function in `public` and `private`.

**Risk prevented:** RPCs used as a back door around RLS, search_path hijacking, and unbounded
queries from a client asking for a million rows.

### 5. Every function explains itself

Each function carries a SQL `COMMENT` that says why it is `SECURITY DEFINER` or
`SECURITY INVOKER`. The reason is visible in the database, in Studio and in code review, not
only in a README. A test fails if a function has no comment.

### Error codes

The API returns standard Postgres error codes, so clients can react without parsing messages.

| Code    | Meaning here                                                               |
| ------- | -------------------------------------------------------------------------- |
| `42501` | not allowed: anonymous call, not the tool owner, not an admin              |
| `22023` | invalid input: bad dates, own tool, unknown decision, loan already decided |
| `22004` | a required argument is missing                                             |
| `P0002` | the tool or loan does not exist, or the caller cannot see it               |
| `23P01` | the tool is already lent during these dates                                |
| `23514` | invalid status transition, or an attempt to change an immutable column     |
| `40001` | the loan was changed concurrently; retry                                   |

## Review checklist for SECURITY DEFINER functions

- [ ] Is definer really needed? Could RLS plus `SECURITY INVOKER` do the job?
- [ ] `set search_path = ''` is set, and every table, function and type is schema-qualified.
- [ ] Authorization is checked first, before any data is read or written.
- [ ] `EXECUTE` is revoked from `PUBLIC` and `anon`, and granted only to the roles that need it.
- [ ] Helpers that should not be callable over HTTP live in a schema the Data API does not expose.
- [ ] The function returns only what the caller needs (a boolean, a page, not a whole table).
- [ ] Inputs are validated: nulls, ranges, and a hard limit on result size.
- [ ] Errors use clear `errcode`s and leak nothing about rows the caller cannot see.
- [ ] A `COMMENT` explains why the function is `SECURITY DEFINER`.
- [ ] Tests cover the allowed caller, a forbidden caller and `anon`.

## What I would add for production

- **Rate limiting** on the RPC endpoints, for example with an API gateway or a per-user counter,
  so one account cannot flood `request_loan`.
- **Audit log**: an append-only `audit.loan_events` table filled by a trigger (who, what, when,
  old and new status), readable by admins only.
- **Monitoring**: `pg_stat_statements` to watch slow queries, Supabase advisors in CI, and alerts
  on spikes of `42501` errors, which usually mean someone is probing the API.
- **Keyset pagination** for the admin report (`where (created_at, id) < (...)`), which stays
  fast on deep pages where `OFFSET` does not.
- **Account deletion flow**: loans block the deletion of a tool by design, so a real app needs a
  defined process for closing an account that still has loan history.
- **Migration review**: run `supabase db diff` on every pull request so schema changes are
  reviewed like code.

## Notes

- Supabase CLI 3 generates types from the local stack by default and deprecates the `--local`
  flag, so the scripts call `supabase gen types typescript` without it.
- Local runs use the new publishable API key (`SUPABASE_PUBLISHABLE_KEY`), the successor of the
  legacy `anon` key.

## License

MIT
