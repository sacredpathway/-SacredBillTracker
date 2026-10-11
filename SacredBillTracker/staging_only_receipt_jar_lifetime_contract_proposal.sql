-- Sacred Bill Tracker 1.0.20 (56)
-- STAGING-ONLY PROPOSAL. DO NOT APPLY WITHOUT EXPLICIT APPROVAL.
--
-- Purpose:
--   Add the smallest lifetime-safe server contract needed for the Apple
--   Receipt Jar non-consumable:
--     com.sacredbilltracker.app.receiptjar.lifetime
--
-- Scope:
--   - additive only
--   - no changes to subscriptions, subscription_products, or
--     record_verified_subscription
--   - no Receipt Jar verifier wiring
--   - no production target

begin;

do $$
begin
  if current_setting('sbt.staging_project_ref', true) is distinct from 'thwjnpofhrpxfuvwkfgd' then
    raise exception 'Verified Sacred Bill Tracker staging target required';
  end if;
end $$;

create extension if not exists "pgcrypto";

create table if not exists public.sbt_store_purchases (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references auth.users(id) on delete cascade,
  provider text not null check (provider in ('apple', 'google_play')),
  environment text not null check (environment in ('production', 'sandbox')),
  product_id text not null,
  entitlement_kind text not null check (entitlement_kind in ('receipt_jar_lifetime')),
  provider_original_id text not null,
  provider_latest_id text not null,
  status text not null check (status in ('active', 'revoked', 'refunded', 'quarantined')),
  ownership_state text not null default 'bound'
    check (ownership_state in ('bound', 'conflict', 'quarantined')),
  revoked_at timestamptz,
  refunded_at timestamptz,
  last_provider_event_time timestamptz not null,
  last_verified_at timestamptz not null,
  raw_payload_hash text not null check (length(raw_payload_hash) between 16 and 128),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    entitlement_kind <> 'receipt_jar_lifetime'
    or (
      product_id = 'com.sacredbilltracker.app.receiptjar.lifetime'
      and status in ('active', 'revoked', 'refunded', 'quarantined')
    )
  ),
  check (
    provider <> 'apple'
    or (
      provider_original_id ~ '^[0-9]{1,64}$'
      and provider_latest_id ~ '^[0-9]{1,64}$'
    )
  ),
  unique (provider, environment, provider_original_id)
);

create index if not exists sbt_store_purchases_account_idx
  on public.sbt_store_purchases(account_id, entitlement_kind, status);

create index if not exists sbt_store_purchases_provider_latest_idx
  on public.sbt_store_purchases(provider, environment, provider_latest_id);

alter table public.sbt_store_purchases enable row level security;

create table if not exists public.sbt_store_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null check (provider in ('apple', 'google_play')),
  environment text not null check (environment in ('production', 'sandbox')),
  event_id text not null check (length(event_id) between 1 and 160),
  provider_original_id text,
  provider_latest_id text,
  product_id text,
  event_type text not null,
  event_time timestamptz not null,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  processing_state text not null default 'received'
    check (processing_state in ('received', 'processed', 'duplicate', 'ignored_out_of_order', 'quarantined', 'failed_verification')),
  raw_payload_hash text not null check (length(raw_payload_hash) between 16 and 128),
  failure_reason text,
  unique (provider, environment, event_id)
);

create index if not exists sbt_store_events_purchase_idx
  on public.sbt_store_events(provider, environment, provider_original_id, event_time desc);

alter table public.sbt_store_events enable row level security;

create table if not exists public.sbt_effective_entitlements (
  account_id uuid primary key references auth.users(id) on delete cascade,
  effective_plan_tier text not null default 'free'
    check (effective_plan_tier in ('free', 'essential', 'business', 'unlimited')),
  receipt_jar_lifetime boolean not null default false,
  calculated_at timestamptz not null default now(),
  source_purchase_ids uuid[] not null default '{}',
  has_conflict boolean not null default false
);

alter table public.sbt_effective_entitlements enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'sbt_effective_entitlements'
      and policyname = 'sbt effective entitlements owner select'
  ) then
    create policy "sbt effective entitlements owner select"
      on public.sbt_effective_entitlements for select
      using (auth.uid() = account_id);
  end if;
end $$;

revoke all on public.sbt_store_purchases from public, anon, authenticated, service_role;
revoke all on public.sbt_store_events from public, anon, authenticated, service_role;
revoke all on public.sbt_effective_entitlements from public, anon, authenticated, service_role;

grant select, insert, update on public.sbt_store_purchases to service_role;
grant select, insert, update on public.sbt_store_events to service_role;
grant select, insert, update on public.sbt_effective_entitlements to service_role;
grant select on public.sbt_effective_entitlements to authenticated;

create or replace function public.sbt_recalculate_effective_entitlements(p_account_id uuid)
returns public.sbt_effective_entitlements
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan text := 'free';
  v_receipt_jar boolean := false;
  v_source_purchase_ids uuid[] := '{}';
  v_has_conflict boolean := false;
  v_result public.sbt_effective_entitlements;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_account_id is null then
    raise exception 'account required';
  end if;

  select coalesce((
    select r.tier
    from public.subscriptions s
    join public.subscription_tier_ranks r on r.feature_key = s.feature_key
    where s.owner_id = p_account_id
      and s.status in ('active', 'in_grace_period', 'canceled')
      and coalesce(s.grace_period_end, s.current_period_end) > now()
    order by r.rank desc
    limit 1
  ), coalesce((
    select r.tier
    from public.reward_entitlements e
    join public.subscription_tier_ranks r on r.tier = e.tier
    where e.owner_id = p_account_id
      and e.revoked_at is null
      and e.expires_at > now()
    order by r.rank desc
    limit 1
  ), 'free')) into v_plan;

  select coalesce(bool_or(status = 'active' and ownership_state = 'bound'), false),
         coalesce(array_agg(id order by last_verified_at desc)
                  filter (where status = 'active' and ownership_state = 'bound'), '{}'),
         coalesce(bool_or(ownership_state in ('conflict', 'quarantined')), false)
    into v_receipt_jar, v_source_purchase_ids, v_has_conflict
  from public.sbt_store_purchases
  where account_id = p_account_id
    and provider = 'apple'
    and product_id = 'com.sacredbilltracker.app.receiptjar.lifetime'
    and entitlement_kind = 'receipt_jar_lifetime';

  insert into public.sbt_effective_entitlements as ee(
    account_id,
    effective_plan_tier,
    receipt_jar_lifetime,
    calculated_at,
    source_purchase_ids,
    has_conflict
  )
  values (
    p_account_id,
    v_plan,
    v_receipt_jar,
    now(),
    v_source_purchase_ids,
    v_has_conflict
  )
  on conflict (account_id) do update set
    effective_plan_tier = excluded.effective_plan_tier,
    receipt_jar_lifetime = excluded.receipt_jar_lifetime,
    calculated_at = excluded.calculated_at,
    source_purchase_ids = excluded.source_purchase_ids,
    has_conflict = excluded.has_conflict
  returning * into v_result;

  return v_result;
end;
$$;

create or replace function public.sbt_record_verified_receipt_jar_purchase(
  p_account_id uuid,
  p_provider text,
  p_environment text,
  p_product_id text,
  p_provider_original_id text,
  p_provider_latest_id text,
  p_status text,
  p_event_id text,
  p_event_type text,
  p_event_time timestamptz,
  p_verified_at timestamptz,
  p_raw_payload_hash text,
  p_account_token uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing public.sbt_store_purchases;
  v_event_inserted integer := 0;
  v_purchase public.sbt_store_purchases;
  v_effective public.sbt_effective_entitlements;
  v_processing_state text := 'processed';
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_account_id is null
     or p_provider <> 'apple'
     or p_environment not in ('production', 'sandbox')
     or p_product_id <> 'com.sacredbilltracker.app.receiptjar.lifetime'
     or p_provider_original_id !~ '^[0-9]{1,64}$'
     or p_provider_latest_id !~ '^[0-9]{1,64}$'
     or p_status not in ('active', 'revoked', 'refunded', 'quarantined')
     or p_event_id is null
     or length(p_event_id) < 1
     or p_event_time is null
     or p_verified_at is null
     or p_raw_payload_hash is null
     or length(p_raw_payload_hash) < 16 then
    return jsonb_build_object('state', 'verification_rejected');
  end if;
  if p_account_token is not null and p_account_token <> p_account_id then
    v_processing_state := 'quarantined';
    insert into public.sbt_store_events(provider, environment, event_id, provider_original_id, provider_latest_id, product_id,
      event_type, event_time, processed_at, processing_state, raw_payload_hash, failure_reason)
    values (p_provider, p_environment, p_event_id, p_provider_original_id, p_provider_latest_id, p_product_id,
      p_event_type, p_event_time, now(), v_processing_state, p_raw_payload_hash, 'account_token_mismatch')
    on conflict (provider, environment, event_id) do nothing;
    return jsonb_build_object('state', 'owner_conflict');
  end if;

  perform 1 from auth.users where id = p_account_id for key share;
  if not found then
    return jsonb_build_object('state', 'verification_rejected');
  end if;

  insert into public.sbt_store_events(provider, environment, event_id, provider_original_id, provider_latest_id, product_id,
    event_type, event_time, processed_at, processing_state, raw_payload_hash)
  values (p_provider, p_environment, p_event_id, p_provider_original_id, p_provider_latest_id, p_product_id,
    p_event_type, p_event_time, now(), 'received', p_raw_payload_hash)
  on conflict (provider, environment, event_id) do nothing;
  get diagnostics v_event_inserted = row_count;

  if v_event_inserted = 0 then
    update public.sbt_store_events
      set processed_at = coalesce(processed_at, now()),
          processing_state = case when processing_state = 'received' then 'duplicate' else processing_state end
    where provider = p_provider and environment = p_environment and event_id = p_event_id;
    v_effective := public.sbt_recalculate_effective_entitlements(p_account_id);
    return jsonb_build_object('state', 'duplicate', 'effective', to_jsonb(v_effective));
  end if;

  select * into v_existing
  from public.sbt_store_purchases
  where provider = p_provider
    and environment = p_environment
    and provider_original_id = p_provider_original_id
  for update;

  if found and v_existing.account_id <> p_account_id then
    update public.sbt_store_events
      set processing_state = 'quarantined',
          failure_reason = 'purchase_owned_by_another_account',
          processed_at = now()
    where provider = p_provider and environment = p_environment and event_id = p_event_id;
    return jsonb_build_object('state', 'owner_conflict');
  end if;

  if found and v_existing.last_provider_event_time > p_event_time then
    update public.sbt_store_events
      set processing_state = 'ignored_out_of_order',
          failure_reason = 'stale_event',
          processed_at = now()
    where provider = p_provider and environment = p_environment and event_id = p_event_id;
    v_effective := public.sbt_recalculate_effective_entitlements(p_account_id);
    return jsonb_build_object('state', 'ignored_out_of_order', 'effective', to_jsonb(v_effective));
  end if;

  insert into public.sbt_store_purchases as sp(
    account_id,
    provider,
    environment,
    product_id,
    entitlement_kind,
    provider_original_id,
    provider_latest_id,
    status,
    ownership_state,
    revoked_at,
    refunded_at,
    last_provider_event_time,
    last_verified_at,
    raw_payload_hash
  )
  values (
    p_account_id,
    p_provider,
    p_environment,
    p_product_id,
    'receipt_jar_lifetime',
    p_provider_original_id,
    p_provider_latest_id,
    p_status,
    case when p_status = 'quarantined' then 'quarantined' else 'bound' end,
    case when p_status = 'revoked' then p_event_time else null end,
    case when p_status = 'refunded' then p_event_time else null end,
    p_event_time,
    p_verified_at,
    p_raw_payload_hash
  )
  on conflict (provider, environment, provider_original_id) do update set
    provider_latest_id = excluded.provider_latest_id,
    status = excluded.status,
    ownership_state = excluded.ownership_state,
    revoked_at = excluded.revoked_at,
    refunded_at = excluded.refunded_at,
    last_provider_event_time = excluded.last_provider_event_time,
    last_verified_at = excluded.last_verified_at,
    raw_payload_hash = excluded.raw_payload_hash,
    updated_at = now()
  where sp.account_id = excluded.account_id
    and sp.last_provider_event_time <= excluded.last_provider_event_time
  returning * into v_purchase;

  if v_purchase.id is null then
    update public.sbt_store_events
      set processing_state = 'ignored_out_of_order',
          failure_reason = 'stale_or_conflicting_upsert',
          processed_at = now()
    where provider = p_provider and environment = p_environment and event_id = p_event_id;
    v_effective := public.sbt_recalculate_effective_entitlements(p_account_id);
    return jsonb_build_object('state', 'ignored_out_of_order', 'effective', to_jsonb(v_effective));
  end if;

  update public.sbt_store_events
    set processing_state = v_processing_state,
        processed_at = now()
  where provider = p_provider and environment = p_environment and event_id = p_event_id;

  v_effective := public.sbt_recalculate_effective_entitlements(p_account_id);
  return jsonb_build_object('state', 'securely_bound', 'purchase_id', v_purchase.id, 'effective', to_jsonb(v_effective));
end;
$$;

revoke all on function public.sbt_recalculate_effective_entitlements(uuid) from public, anon, authenticated;
revoke all on function public.sbt_record_verified_receipt_jar_purchase(uuid,text,text,text,text,text,text,text,text,timestamptz,timestamptz,text,uuid) from public, anon, authenticated;
grant execute on function public.sbt_recalculate_effective_entitlements(uuid) to service_role;
grant execute on function public.sbt_record_verified_receipt_jar_purchase(uuid,text,text,text,text,text,text,text,text,timestamptz,timestamptz,text,uuid) to service_role;

commit;
