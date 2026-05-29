-- ============================================================
-- Sacred Pathway Driver Hub — Device Tokens (P5 — future remote push)
-- Run in Supabase SQL Editor.
--
-- P5 ships local notifications only. This table lays the groundwork
-- for future remote push (carrier/team features, server-side events).
-- ============================================================

create table if not exists public.device_tokens (
    id              uuid primary key default gen_random_uuid(),
    user_id         uuid not null references auth.users(id) on delete cascade,
    apns_token      text not null,                  -- hex-encoded APNs device token
    bundle_id       text not null,
    device_model    text,                           -- e.g. "iPhone15,3"
    os_version      text,                           -- e.g. "iOS 17.5.1"
    app_version     text,                           -- e.g. "1.0.0 (24)"
    environment     text not null default 'production', -- 'sandbox' | 'production'
    last_seen_at    timestamptz not null default now(),
    created_at      timestamptz not null default now(),
    unique (user_id, apns_token)
);

create index if not exists idx_device_tokens_user      on public.device_tokens(user_id);
create index if not exists idx_device_tokens_lastseen  on public.device_tokens(last_seen_at desc);

-- RLS — user can only manage their own tokens
alter table public.device_tokens enable row level security;

drop policy if exists "select_own_device_tokens" on public.device_tokens;
create policy "select_own_device_tokens"
    on public.device_tokens for select using (auth.uid() = user_id);

drop policy if exists "insert_own_device_tokens" on public.device_tokens;
create policy "insert_own_device_tokens"
    on public.device_tokens for insert with check (auth.uid() = user_id);

drop policy if exists "update_own_device_tokens" on public.device_tokens;
create policy "update_own_device_tokens"
    on public.device_tokens for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "delete_own_device_tokens" on public.device_tokens;
create policy "delete_own_device_tokens"
    on public.device_tokens for delete using (auth.uid() = user_id);
