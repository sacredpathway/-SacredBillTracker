-- Managed Financial Profiles staging verification.
-- Run this against the STAGING Supabase database only after applying:
-- supabase/migrations/20260611090000_managed_financial_profiles.sql
--
-- Do not run against production project zziauybwemoiqfpidiur unless production
-- migration has been explicitly approved.

select
  'financial_profiles table exists' as check_name,
  to_regclass('public.financial_profiles') is not null as pass;

select
  'financial_profiles.archived_at exists' as check_name,
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'financial_profiles'
      and column_name = 'archived_at'
  ) as pass;

select
  'bills.profile_id exists' as check_name,
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'bills'
      and column_name = 'profile_id'
  ) as pass;

select
  'income_entries table exists' as check_name,
  to_regclass('public.income_entries') is not null as pass;

select
  'bills.profile_id fk restricts profile deletes' as check_name,
  exists (
    select 1
    from pg_constraint
    where conname = 'bills_profile_id_fkey'
      and contype = 'f'
      and confdeltype = 'r'
  ) as pass;

select
  'income_entries.profile_id fk restricts profile deletes' as check_name,
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.income_entries'::regclass
      and contype = 'f'
      and confdeltype = 'r'
  ) as pass;

select
  'rls enabled on managed tables' as check_name,
  bool_and(relrowsecurity) as pass
from pg_class
where oid in (
  'public.financial_profiles'::regclass,
  'public.bills'::regclass,
  'public.income_entries'::regclass
);

select
  'financial_profiles has no owner delete policy' as check_name,
  not exists (
    select 1
    from pg_policy
    where polrelid = 'public.financial_profiles'::regclass
      and polcmd = 'd'
  ) as pass;

select
  'profile policies are owner scoped' as check_name,
  exists (
    select 1
    from pg_policy
    where polrelid = 'public.financial_profiles'::regclass
      and polname = 'Owners can read profiles'
      and pg_get_expr(polqual, polrelid) like '%auth.uid() = owner_id%'
  )
  and exists (
    select 1
    from pg_policy
    where polrelid = 'public.financial_profiles'::regclass
      and polname = 'Owners can insert profiles'
      and pg_get_expr(polwithcheck, polrelid) like '%auth.uid() = owner_id%'
  )
  and exists (
    select 1
    from pg_policy
    where polrelid = 'public.financial_profiles'::regclass
      and polname = 'Owners can update profiles'
      and pg_get_expr(polqual, polrelid) like '%auth.uid() = owner_id%'
      and pg_get_expr(polwithcheck, polrelid) like '%auth.uid() = owner_id%'
  ) as pass;

select
  'bill policies are owner/profile scoped' as check_name,
  exists (
    select 1
    from pg_policy
    where polrelid = 'public.bills'::regclass
      and polname = 'Owners can read managed profile bills'
      and pg_get_expr(polqual, polrelid) like '%auth.uid() = owner_id%'
  )
  and exists (
    select 1
    from pg_policy
    where polrelid = 'public.bills'::regclass
      and polname = 'Owners can insert managed profile bills'
      and pg_get_expr(polwithcheck, polrelid) like '%fp.owner_id = auth.uid()%'
  ) as pass;

select
  'income policies are owner/profile scoped' as check_name,
  exists (
    select 1
    from pg_policy
    where polrelid = 'public.income_entries'::regclass
      and polname = 'Owners can read income entries'
      and pg_get_expr(polqual, polrelid) like '%auth.uid() = owner_id%'
  )
  and exists (
    select 1
    from pg_policy
    where polrelid = 'public.income_entries'::regclass
      and polname = 'Owners can insert income entries'
      and pg_get_expr(polwithcheck, polrelid) like '%fp.owner_id = auth.uid()%'
  ) as pass;

select
  'archived profile references are preserved' as check_name,
  not exists (
    select 1
    from public.bills b
    left join public.financial_profiles fp on fp.id = b.profile_id
    where fp.id is null
  ) as pass;

select
  'summary' as check_name,
  case
    when exists (
      select 1
      from public.financial_profiles
      where archived_at is not null
    ) then 'Archived profiles exist; verify historical bill/income totals manually.'
    else 'No archived profiles found yet; run archive QA with test data.'
  end as note;
