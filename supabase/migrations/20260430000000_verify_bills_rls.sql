-- 20260430000000_verify_bills_rls.sql
--
-- Hotfix 1.0.1: idempotent guarantee that Row Level Security is ON for
-- public.bills and that the per-row policies are present. Re-running is
-- safe — drops/recreates the four policies. Run this in the Supabase
-- SQL editor BEFORE shipping the 1.0.1 client build.

-- 1) Make sure RLS is enabled on bills.
alter table public.bills enable row level security;

-- 2) Drop old copies (if any) so this script is idempotent.
drop policy if exists "Users can read own bills"   on public.bills;
drop policy if exists "Users can insert own bills" on public.bills;
drop policy if exists "Users can update own bills" on public.bills;
drop policy if exists "Users can delete own bills" on public.bills;

-- 3) Recreate them. auth.uid() returns the JWT-bound user; with no
-- JWT it returns NULL, which fails every comparison below — anon
-- traffic cannot read or write any row.
create policy "Users can read own bills"
  on public.bills for select
  using (auth.uid() = user_id);

create policy "Users can insert own bills"
  on public.bills for insert
  with check (auth.uid() = user_id);

create policy "Users can update own bills"
  on public.bills for update
  using (auth.uid() = user_id);

create policy "Users can delete own bills"
  on public.bills for delete
  using (auth.uid() = user_id);

-- 4) Verify (returns one row per policy + RLS state).
select 'rls enabled' as kind,
       (select relrowsecurity::text from pg_class where relname = 'bills' and relnamespace = 'public'::regnamespace) as detail
union all
select 'policy: ' || polname,
       'cmd=' || polcmd::text
  from pg_policy
  where polrelid = 'public.bills'::regclass
  order by 1;
