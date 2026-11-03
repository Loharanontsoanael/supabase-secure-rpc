-- Seed data for the LOCAL development stack only.
--
-- !!! LOCAL TEST CREDENTIALS ONLY !!!
-- These accounts and passwords exist only so the integration tests can sign
-- in against `supabase start`. They are public in this repository and must
-- never be used on a hosted project.
--
--   alice@example.test   local-only-password   role: user
--   bob@example.test     local-only-password   role: user
--   admin@example.test   local-only-password   role: admin

-- Users. The on_auth_user_created trigger creates each profile and gives
-- every account the "user" role.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  '00000000-0000-0000-0000-000000000000',
  u.id,
  'authenticated',
  'authenticated',
  u.email,
  extensions.crypt('local-only-password', extensions.gen_salt('bf')),
  now(),
  '{"provider": "email", "providers": ["email"]}'::jsonb,
  jsonb_build_object('display_name', u.display_name),
  now(),
  now(),
  '', '', '', ''
from (
  values
    ('11111111-1111-4111-8111-111111111111'::uuid, 'alice@example.test', 'Alice'),
    ('22222222-2222-4222-8222-222222222222'::uuid, 'bob@example.test', 'Bob'),
    ('99999999-9999-4999-8999-999999999999'::uuid, 'admin@example.test', 'Admin')
) as u (id, email, display_name);

-- Email identities, required by Supabase Auth for password sign-in.
insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at)
select
  u.id::text,
  u.id,
  jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
  'email',
  now(),
  now()
from auth.users as u
where u.email like '%@example.test';

-- Promote the admin account.
insert into public.user_roles (user_id, role)
values ('99999999-9999-4999-8999-999999999999', 'admin');

-- Tools.
insert into public.tools (id, owner_id, name, category, is_available)
values
  ('a0000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', 'Cordless drill', 'power tools', true),
  ('a0000000-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111', 'Extension ladder', 'ladders', false),
  ('b0000000-0000-4000-8000-000000000001', '22222222-2222-4222-8222-222222222222', 'Pressure washer', 'cleaning', true),
  ('b0000000-0000-4000-8000-000000000002', '22222222-2222-4222-8222-222222222222', 'Hedge trimmer', 'garden', false),
  ('c0000000-0000-4000-8000-000000000001', '99999999-9999-4999-8999-999999999999', 'Tile cutter', 'power tools', true);

-- Loans, with dates relative to today so the seed never goes stale.
insert into public.loans (tool_id, borrower_id, status, starts_on, ends_on)
values
  -- Bob asks to borrow Alice's drill.
  ('a0000000-0000-4000-8000-000000000001', '22222222-2222-4222-8222-222222222222', 'requested', current_date + 7, current_date + 9),
  -- Alice is borrowing Bob's pressure washer.
  ('b0000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', 'approved', current_date + 3, current_date + 5),
  -- Bob is borrowing the admin's tile cutter. Alice is not a party to this loan.
  ('c0000000-0000-4000-8000-000000000001', '22222222-2222-4222-8222-222222222222', 'approved', current_date + 1, current_date + 2);
