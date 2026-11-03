-- Step 2: domain tables for a neighborhood tool-lending app.
-- Integrity rules that never depend on who the caller is live here as
-- constraints, so they hold for every access path (API, RPC, service role).

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null
    constraint profiles_display_name_length check (char_length(display_name) between 1 and 80)
);
comment on table public.profiles is
  'Public profile of a member. Created by a trigger when an auth user signs up.';

create table public.user_roles (
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null
    constraint user_roles_role_valid check (role in ('admin', 'user')),
  primary key (user_id, role)
);
comment on table public.user_roles is
  'Application roles. Never derived from user-editable metadata. Writable only by migrations or the service role.';

create table public.tools (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid()
    references public.profiles (id) on delete cascade,
  name text not null
    constraint tools_name_length check (char_length(btrim(name)) between 1 and 100),
  category text not null
    constraint tools_category_length check (char_length(btrim(category)) between 1 and 50),
  is_available boolean not null default true,
  created_at timestamptz not null default now()
);
comment on table public.tools is
  'Tools that members offer to lend. owner_id defaults to the caller and cannot be set through the API.';

create table public.loans (
  id uuid primary key default gen_random_uuid(),
  -- A tool with loan history cannot be deleted: owners mark it unavailable instead.
  tool_id uuid not null references public.tools (id) on delete restrict,
  borrower_id uuid not null default auth.uid()
    references public.profiles (id) on delete cascade,
  status text not null default 'requested'
    constraint loans_status_valid check (status in ('requested', 'approved', 'declined', 'returned')),
  starts_on date not null,
  ends_on date not null,
  created_at timestamptz not null default now(),
  constraint loans_dates_ordered check (ends_on >= starts_on)
);
comment on table public.loans is
  'Loan requests. borrower_id defaults to the caller; only status can change after creation.';
