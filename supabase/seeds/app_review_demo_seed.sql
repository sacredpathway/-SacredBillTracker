-- app_review_demo_seed.sql
-- Seeds 5 sample bills for the App Review demo account.
--
-- PREREQ: Create the auth user FIRST in the Supabase Dashboard:
--   Authentication -> Users -> Add user -> Create new user
--   Email:    appreview@sacredbilltracker.com
--   Password: ReviewPass2026!
--   Auto Confirm User: ON
--
-- Then paste this whole file into the SQL Editor and Run.
-- Idempotent: re-running wipes the demo bills and reseeds them.

do $$
declare
  uid uuid;
begin
  -- Look up the demo account UID from auth.users
  select id into uid
  from auth.users
  where lower(email) = 'appreview@sacredbilltracker.com'
  limit 1;

  if uid is null then
    raise exception 'Demo user appreview@sacredbilltracker.com not found. Create it in Authentication -> Users first.';
  end if;

  -- Wipe any existing demo bills so this script is safe to re-run
  delete from public.bills where user_id = uid;

  -- Seed 5 representative bills (3 household, 2 business) covering due-today,
  -- due-this-week, upcoming, overdue, and auto-pay scenarios.
  insert into public.bills
    (id, user_id, name, amount, due_date, category, recurrence, type,
     auto_pay, notes, status, last_paid_date, created_at, updated_at)
  values
    (gen_random_uuid(), uid, 'Rent',              1850.00, (now() + interval '2 days'),  'rent',         'monthly', 'household', false, 'Apartment lease',           'unpaid', null, now(), now()),
    (gen_random_uuid(), uid, 'Electric Bill',      142.50, (now() + interval '5 days'),  'utilities',    'monthly', 'household', true,  'PG&E auto-pay',             'unpaid', null, now(), now()),
    (gen_random_uuid(), uid, 'Internet',            89.99, (now() - interval '3 days'),  'internet',     'monthly', 'household', false, 'Comcast - past due',        'overdue', null, now(), now()),
    (gen_random_uuid(), uid, 'Adobe Creative Cloud',54.99, (now() + interval '12 days'), 'software',     'monthly', 'business',  true,  'Design subscription',       'unpaid', null, now(), now()),
    (gen_random_uuid(), uid, 'Quarterly Taxes',   2400.00, (now() + interval '20 days'), 'taxes',        'quarterly','business', false, 'Q2 estimated payment',      'unpaid', null, now(), now());

  raise notice 'Seeded 5 demo bills for user %', uid;
end $$;

-- Verify
select name, amount, due_date::date, category, type, status
from public.bills
where user_id = (select id from auth.users where lower(email) = 'appreview@sacredbilltracker.com')
order by due_date;
