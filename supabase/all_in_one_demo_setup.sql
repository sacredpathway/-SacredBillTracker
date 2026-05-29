-- =====================================================================
-- Sacred Bill Tracker — App Review Demo Setup (single-shot SQL)
-- Run this once in Supabase SQL Editor. Idempotent: safe to re-run.
-- Creates: demo user, 5 seed bills, delete_user_account RPC.
-- =====================================================================

-- 1) Create demo user if it doesn't exist
do $$
declare
  uid uuid;
  existing_uid uuid;
begin
  select id into existing_uid
    from auth.users
    where lower(email) = 'appreview@sacredbilltracker.com'
    limit 1;

  if existing_uid is null then
    uid := gen_random_uuid();

    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data,
      is_super_admin, is_sso_user, is_anonymous
    )
    values (
      '00000000-0000-0000-0000-000000000000',
      uid,
      'authenticated',
      'authenticated',
      'appreview@sacredbilltracker.com',
      crypt('ReviewPass2026!', gen_salt('bf')),
      now(), now(), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{}'::jsonb,
      false, false, false
    );

    insert into auth.identities (
      id, user_id, identity_data, provider, provider_id,
      last_sign_in_at, created_at, updated_at
    )
    values (
      gen_random_uuid(),
      uid,
      jsonb_build_object('sub', uid::text, 'email', 'appreview@sacredbilltracker.com', 'email_verified', true),
      'email',
      uid::text,
      now(), now(), now()
    );

    raise notice 'Created demo user %', uid;
  else
    raise notice 'Demo user already exists: %', existing_uid;
  end if;
end $$;

-- 2) Seed 5 bills for the demo user (wipes existing demo bills first)
do $$
declare
  uid uuid;
begin
  select id into uid
    from auth.users
    where lower(email) = 'appreview@sacredbilltracker.com'
    limit 1;

  if uid is null then
    raise exception 'Demo user not found after creation step.';
  end if;

  delete from public.bills where user_id = uid;

  insert into public.bills
    (id, user_id, name, amount, due_date, category, recurrence, type,
     auto_pay, notes, status, last_paid_date, created_at, updated_at)
  values
    (gen_random_uuid(), uid, 'Rent',                1850.00, (now() + interval '2 days'),  'rent',      'monthly',   'household', false, 'Apartment lease',     'unpaid',  null, now(), now()),
    (gen_random_uuid(), uid, 'Electric Bill',        142.50, (now() + interval '5 days'),  'utilities', 'monthly',   'household', true,  'PG&E auto-pay',       'unpaid',  null, now(), now()),
    (gen_random_uuid(), uid, 'Internet',              89.99, (now() - interval '3 days'),  'internet',  'monthly',   'household', false, 'Comcast - past due',  'overdue', null, now(), now()),
    (gen_random_uuid(), uid, 'Adobe Creative Cloud',  54.99, (now() + interval '12 days'), 'software',  'monthly',   'business',  true,  'Design subscription', 'unpaid',  null, now(), now()),
    (gen_random_uuid(), uid, 'Quarterly Taxes',     2400.00, (now() + interval '20 days'), 'taxes',     'quarterly', 'business',  false, 'Q2 estimated payment','unpaid',  null, now(), now());

  raise notice 'Seeded 5 demo bills for user %', uid;
end $$;

-- 3) Deploy delete_user_account RPC (App Store guideline 5.1.1(v))
create or replace function public.delete_user_account()
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  delete from public.bills where user_id = uid;
  delete from auth.users where id = uid;

  return jsonb_build_object('success', true, 'user_id', uid);
end;
$$;

revoke all on function public.delete_user_account() from public;
revoke all on function public.delete_user_account() from anon;
grant  execute on function public.delete_user_account() to authenticated;

alter table public.bills
  drop constraint if exists bills_user_id_fkey,
  add  constraint bills_user_id_fkey
    foreign key (user_id) references auth.users(id) on delete cascade;

-- 4) Verify
select 'demo user' as kind, id::text as detail from auth.users where lower(email) = 'appreview@sacredbilltracker.com'
union all
select 'bills count', count(*)::text from public.bills where user_id = (select id from auth.users where lower(email) = 'appreview@sacredbilltracker.com')
union all
select 'rpc deployed', case when exists (select 1 from pg_proc where proname = 'delete_user_account') then 'yes' else 'no' end;
