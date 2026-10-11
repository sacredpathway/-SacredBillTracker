-- Sacred Bill Tracker 1.0.20 (56)
-- Unified account / entitlement / Receipt Jar backend migration draft.
--
-- DRAFT ONLY. Do not run in production until:
--   1. a production backup exists,
--   2. this has been applied and rolled back in staging,
--   3. Apple and Google verifier functions are deployed in staging,
--   4. RLS/storage policies are audited,
--   5. existing-user ownership backfill has been dry-run,
--   6. the owner explicitly approves production migration.
--
-- Canonical account key:
--   public.sbt_accounts.id == auth.users.id
--
-- Provider identities, provider emails, purchase tokens, original transaction
-- IDs, and local device IDs are attributes of that account. They are not row
-- ownership keys and must not be used to merge accounts by themselves.

begin;

create extension if not exists "pgcrypto";

create table if not exists public.sbt_accounts (
    id uuid primary key references auth.users(id) on delete cascade,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    migration_state text not null default 'canonical'
        check (migration_state in ('canonical', 'needs_review', 'quarantined', 'merged_by_support')),
    support_note text,
    deleted_at timestamptz
);

alter table public.sbt_accounts enable row level security;

drop policy if exists "accounts owner select" on public.sbt_accounts;
create policy "accounts owner select"
    on public.sbt_accounts for select
    using (auth.uid() = id);

drop policy if exists "accounts owner insert" on public.sbt_accounts;
create policy "accounts owner insert"
    on public.sbt_accounts for insert
    with check (auth.uid() = id);

-- Server-side support/admin functions may update migration_state with a
-- service-role key after human review. Clients cannot self-transfer accounts.

create table if not exists public.sbt_account_identity_links (
    id uuid primary key default gen_random_uuid(),
    account_id uuid not null references public.sbt_accounts(id) on delete cascade,
    provider text not null check (provider in ('apple', 'google', 'email_password')),
    provider_subject text not null,
    verified_email text,
    normalized_verified_email text generated always as (lower(nullif(trim(verified_email), ''))) stored,
    is_private_relay_email boolean not null default false,
    proof_level text not null default 'provider_asserted'
        check (proof_level in ('provider_asserted', 'reauthenticated_same_session', 'support_verified')),
    link_state text not null default 'active'
        check (link_state in ('active', 'quarantined', 'revoked')),
    linked_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (provider, provider_subject)
);

create index if not exists sbt_account_identity_links_account_idx
    on public.sbt_account_identity_links(account_id, link_state);

create index if not exists sbt_account_identity_links_email_idx
    on public.sbt_account_identity_links(normalized_verified_email)
    where normalized_verified_email is not null;

alter table public.sbt_account_identity_links enable row level security;

drop policy if exists "identity links owner select" on public.sbt_account_identity_links;
create policy "identity links owner select"
    on public.sbt_account_identity_links for select
    using (auth.uid() = account_id);

-- Insert/update/delete for identity links must go through a reviewed server
-- function that proves provider control. Matching email, including Apple
-- private relay, is advisory only and never an automatic merge rule.

create table if not exists public.sbt_devices (
    id uuid primary key default gen_random_uuid(),
    account_id uuid not null references public.sbt_accounts(id) on delete cascade,
    platform text not null check (platform in ('ios', 'android')),
    install_id text not null,
    push_token_hash text,
    app_version text,
    build_number text,
    last_seen_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    unique (platform, install_id)
);

create index if not exists sbt_devices_account_idx
    on public.sbt_devices(account_id, platform, last_seen_at desc);

alter table public.sbt_devices enable row level security;

drop policy if exists "devices owner select" on public.sbt_devices;
create policy "devices owner select"
    on public.sbt_devices for select
    using (auth.uid() = account_id);

drop policy if exists "devices owner upsert" on public.sbt_devices;
create policy "devices owner upsert"
    on public.sbt_devices for insert
    with check (auth.uid() = account_id);

drop policy if exists "devices owner update" on public.sbt_devices;
create policy "devices owner update"
    on public.sbt_devices for update
    using (auth.uid() = account_id)
    with check (auth.uid() = account_id);

create table if not exists public.sbt_store_purchases (
    id uuid primary key default gen_random_uuid(),
    account_id uuid not null references public.sbt_accounts(id) on delete cascade,
    provider text not null check (provider in ('apple', 'google_play', 'legacy')),
    environment text not null check (environment in ('production', 'sandbox', 'xcode', 'test')),
    product_id text not null,
    entitlement_kind text not null check (entitlement_kind in ('plan', 'receipt_jar_lifetime', 'legacy_grant')),
    plan_tier text check (plan_tier in ('free', 'essential', 'business', 'unlimited')),
    provider_original_id text not null,
    provider_latest_id text not null,
    purchase_token_hash text,
    status text not null check (status in (
        'active',
        'trial',
        'grace',
        'billing_retry',
        'account_hold',
        'cancelled_active',
        'expired',
        'revoked',
        'refunded',
        'quarantined',
        'superseded'
    )),
    provider_reason text,
    expires_at timestamptz,
    revoked_at timestamptz,
    refunded_at timestamptz,
    last_verified_at timestamptz not null,
    provider_event_time timestamptz,
    ownership_state text not null default 'bound'
        check (ownership_state in ('bound', 'conflict', 'quarantined', 'support_transfer_pending', 'support_transferred')),
    ownership_note text,
    raw_payload_hash text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (
        entitlement_kind <> 'plan'
        or plan_tier in ('essential', 'business', 'unlimited')
    ),
    unique (provider, environment, provider_original_id)
);

create index if not exists sbt_store_purchases_account_idx
    on public.sbt_store_purchases(account_id, status, expires_at);

create index if not exists sbt_store_purchases_token_idx
    on public.sbt_store_purchases(provider, purchase_token_hash)
    where purchase_token_hash is not null;

alter table public.sbt_store_purchases enable row level security;

drop policy if exists "store purchases owner select" on public.sbt_store_purchases;
create policy "store purchases owner select"
    on public.sbt_store_purchases for select
    using (auth.uid() = account_id);

-- Writes belong only in service-role verifier functions. The unique
-- (provider, environment, provider_original_id) constraint prevents one Apple
-- original transaction ID or Play purchase token lineage from being silently
-- claimed by multiple accounts. Conflicts must be written as quarantined by
-- support/admin tooling, not reassigned by clients.

create table if not exists public.sbt_store_events (
    id uuid primary key default gen_random_uuid(),
    provider text not null check (provider in ('apple', 'google_play')),
    environment text not null check (environment in ('production', 'sandbox', 'xcode', 'test')),
    event_id text not null,
    provider_original_id text,
    provider_latest_id text,
    product_id text,
    event_type text not null,
    event_subtype text,
    event_time timestamptz not null,
    received_at timestamptz not null default now(),
    processed_at timestamptz,
    processing_state text not null default 'received'
        check (processing_state in ('received', 'processed', 'duplicate', 'ignored_out_of_order', 'failed_signature', 'failed_verification', 'quarantined')),
    raw_payload_hash text not null,
    failure_reason text,
    unique (provider, environment, event_id)
);

create index if not exists sbt_store_events_purchase_idx
    on public.sbt_store_events(provider, environment, provider_original_id, event_time desc);

alter table public.sbt_store_events enable row level security;

-- No client RLS policies: users do not need raw store events. Auditing is
-- service-role/admin only.

create table if not exists public.sbt_effective_entitlements (
    account_id uuid primary key references public.sbt_accounts(id) on delete cascade,
    effective_plan_tier text not null default 'free'
        check (effective_plan_tier in ('free', 'essential', 'business', 'unlimited')),
    receipt_jar_lifetime boolean not null default false,
    source_purchase_ids uuid[] not null default '{}',
    calculated_at timestamptz not null default now(),
    expires_at timestamptz,
    has_conflict boolean not null default false,
    conflict_note text
);

alter table public.sbt_effective_entitlements enable row level security;

drop policy if exists "effective entitlements owner select" on public.sbt_effective_entitlements;
create policy "effective entitlements owner select"
    on public.sbt_effective_entitlements for select
    using (auth.uid() = account_id);

create table if not exists public.receipt_jar_receipts (
    id uuid primary key default gen_random_uuid(),
    owner_user_id uuid not null references public.sbt_accounts(id) on delete cascade,
    merchant text not null,
    purchased_at date not null,
    total numeric(12, 2) not null default 0,
    tax numeric(12, 2),
    source text not null check (source in ('camera', 'photoLibrary', 'pdf', 'manual', 'gmail')),
    original_filename text,
    stored_filename text,
    recognized_text_redacted text not null default '',
    notes text not null default '',
    associated_bill_id uuid,
    fingerprint text not null,
    client_updated_at timestamptz not null default now(),
    record_version bigint not null default 1,
    deleted_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (owner_user_id, fingerprint)
);

create index if not exists receipt_jar_receipts_owner_updated_idx
    on public.receipt_jar_receipts(owner_user_id, updated_at desc);

alter table public.receipt_jar_receipts enable row level security;

drop policy if exists "receipt jar owner select" on public.receipt_jar_receipts;
create policy "receipt jar owner select"
    on public.receipt_jar_receipts for select
    using (auth.uid() = owner_user_id);

drop policy if exists "receipt jar owner insert" on public.receipt_jar_receipts;
create policy "receipt jar owner insert"
    on public.receipt_jar_receipts for insert
    with check (auth.uid() = owner_user_id);

drop policy if exists "receipt jar owner update" on public.receipt_jar_receipts;
create policy "receipt jar owner update"
    on public.receipt_jar_receipts for update
    using (auth.uid() = owner_user_id)
    with check (auth.uid() = owner_user_id);

drop policy if exists "receipt jar owner delete" on public.receipt_jar_receipts;
create policy "receipt jar owner delete"
    on public.receipt_jar_receipts for delete
    using (auth.uid() = owner_user_id);

create table if not exists public.receipt_jar_documents (
    id uuid primary key default gen_random_uuid(),
    receipt_id uuid not null references public.receipt_jar_receipts(id) on delete cascade,
    owner_user_id uuid not null references public.sbt_accounts(id) on delete cascade,
    bucket text not null default 'receipt-jar-originals',
    object_path text not null,
    content_type text,
    byte_size bigint,
    sha256 text,
    created_at timestamptz not null default now(),
    deleted_at timestamptz,
    unique (bucket, object_path),
    check (object_path like owner_user_id::text || '/%')
);

create index if not exists receipt_jar_documents_owner_idx
    on public.receipt_jar_documents(owner_user_id, receipt_id);

alter table public.receipt_jar_documents enable row level security;

drop policy if exists "receipt document owner select" on public.receipt_jar_documents;
create policy "receipt document owner select"
    on public.receipt_jar_documents for select
    using (auth.uid() = owner_user_id);

drop policy if exists "receipt document owner insert" on public.receipt_jar_documents;
create policy "receipt document owner insert"
    on public.receipt_jar_documents for insert
    with check (auth.uid() = owner_user_id and object_path like auth.uid()::text || '/%');

drop policy if exists "receipt document owner update" on public.receipt_jar_documents;
create policy "receipt document owner update"
    on public.receipt_jar_documents for update
    using (auth.uid() = owner_user_id)
    with check (auth.uid() = owner_user_id and object_path like auth.uid()::text || '/%');

drop policy if exists "receipt document owner delete" on public.receipt_jar_documents;
create policy "receipt document owner delete"
    on public.receipt_jar_documents for delete
    using (auth.uid() = owner_user_id);

-- Supabase Storage companion policies for bucket receipt-jar-originals.
-- These are safe only if object names are {owner_uuid}/{receipt_uuid}/{file}.
drop policy if exists "receipt originals owner select" on storage.objects;
create policy "receipt originals owner select"
    on storage.objects for select
    using (
        bucket_id = 'receipt-jar-originals'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

drop policy if exists "receipt originals owner insert" on storage.objects;
create policy "receipt originals owner insert"
    on storage.objects for insert
    with check (
        bucket_id = 'receipt-jar-originals'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

drop policy if exists "receipt originals owner update" on storage.objects;
create policy "receipt originals owner update"
    on storage.objects for update
    using (
        bucket_id = 'receipt-jar-originals'
        and (storage.foldername(name))[1] = auth.uid()::text
    )
    with check (
        bucket_id = 'receipt-jar-originals'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

drop policy if exists "receipt originals owner delete" on storage.objects;
create policy "receipt originals owner delete"
    on storage.objects for delete
    using (
        bucket_id = 'receipt-jar-originals'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

create table if not exists public.financial_education_progress (
    owner_user_id uuid not null references public.sbt_accounts(id) on delete cascade,
    lesson_id text not null,
    status text not null check (status in ('seen', 'completed', 'favorite')),
    client_updated_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (owner_user_id, lesson_id, status)
);

alter table public.financial_education_progress enable row level security;

drop policy if exists "education progress owner all" on public.financial_education_progress;
create policy "education progress owner all"
    on public.financial_education_progress for all
    using (auth.uid() = owner_user_id)
    with check (auth.uid() = owner_user_id);

create table if not exists public.sbt_account_settings (
    owner_user_id uuid primary key references public.sbt_accounts(id) on delete cascade,
    settings jsonb not null default '{}'::jsonb,
    client_updated_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.sbt_account_settings enable row level security;

drop policy if exists "account settings owner all" on public.sbt_account_settings;
create policy "account settings owner all"
    on public.sbt_account_settings for all
    using (auth.uid() = owner_user_id)
    with check (auth.uid() = owner_user_id);

-- Existing bills table hardening. Keep this idempotent because production may
-- already have some columns/policies.
alter table if exists public.bills
    add column if not exists owner_id uuid,
    add column if not exists client_updated_at timestamptz not null default now(),
    add column if not exists record_version bigint not null default 1;

update public.bills
set owner_id = coalesce(owner_id, user_id)
where owner_id is null;

alter table if exists public.bills
    alter column owner_id set not null;

create index if not exists bills_owner_updated_idx
    on public.bills(owner_id, updated_at desc);

-- Production should replace older user_id-only RLS policies with owner_id
-- policies only after verifying partner/shared-bill policies still work.

commit;
