-- Step 3: index every column that an RLS policy filters on.
-- A policy is an extra WHERE clause on every query. Without these indexes,
-- each request from each user would scan the whole table.
--
-- Already covered by primary keys:
--   profiles.id                     (profiles primary key)
--   user_roles.user_id, role        (user_roles primary key, used by private.is_admin)
--   tools.id                        (tools primary key, used by the loans policies)

create index tools_owner_id_idx on public.tools (owner_id);
create index tools_is_available_idx on public.tools (is_available);

create index loans_borrower_id_idx on public.loans (borrower_id);
create index loans_tool_id_idx on public.loans (tool_id);
