-- 20260624230000_tier_enforcement_guards_and_unlimited_autotrack_grant.sql
-- Applied live to project zziauybwemoiqfpidiur on 2026-06-24 via MCP apply_migration
-- (migration name: tier_enforcement_guards_and_unlimited_autotrack_grant).
--
-- Purpose:
--   1) Fix: a new `unlimited` tier subscriber (feature_key='unlimited', rank 3) must also
--      receive the AutoTrack / bank-sync entitlement guarded by has_autotrack_premium().
--      The old definition matched feature_key='autotrack_premium' literally, so Unlimited
--      buyers were blocked from bank sync. Now grants to any active/in-grace subscription
--      whose subscription_tier_ranks.rank >= 3 (covers Unlimited AND legacy autotrack_premium),
--      preserving the period-end checks. Auto-propagates to the Plaid RLS policies that call it.
--      Non-breaking: no `unlimited` subscribers exist yet, so nothing current changes.
--   2) Add assert_essential()/assert_business()/assert_unlimited() guard functions (RAISE 42501)
--      as server-side enforcement primitives for edge functions / future RLS.
--
-- Intentionally NOT changed: core tables (bills, income_entries, budget_categories,
--   budget_goals, financial_profiles) remain owner-only and ungated by tier, because they are
--   used by free + all tiers; tier-gating them would lock out existing free/Essential users.

create or replace function public.has_autotrack_premium(p_uid uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (
    select 1
    from public.subscriptions s
    join public.subscription_tier_ranks r on r.feature_key = s.feature_key
    where s.owner_id = p_uid
      and r.rank >= 3
      and s.status in ('active','in_grace_period')
      and (
        s.current_period_end is null
        or s.current_period_end > now()
        or (s.grace_period_end is not null and s.grace_period_end > now())
      )
  );
$$;

create or replace function public.assert_essential()
returns void language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not public.has_essential() then
    raise exception 'essential_tier_required'
      using errcode = '42501', hint = 'Essential subscription (or higher) required.';
  end if;
end; $$;

create or replace function public.assert_business()
returns void language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not public.has_business() then
    raise exception 'business_tier_required'
      using errcode = '42501', hint = 'Business subscription (or higher) required.';
  end if;
end; $$;

create or replace function public.assert_unlimited()
returns void language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not public.has_unlimited() then
    raise exception 'unlimited_tier_required'
      using errcode = '42501', hint = 'Unlimited subscription required.';
  end if;
end; $$;
