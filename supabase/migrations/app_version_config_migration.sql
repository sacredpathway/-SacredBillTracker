-- ============================================================
-- app_version_config — remote forced-update gate for the iOS app.
-- ============================================================
--
-- Purpose: control whether older builds are blocked from running
-- once a critical fix or required migration ships. The iOS app reads
-- the most-recent row on launch + on every foreground resume.
--
-- Read access: PUBLIC (no auth) so the gate works for signed-out
-- launches (sign-in screen still needs to be reachable / blockable).
-- Write access: locked to the service role only — manage from the
-- Supabase dashboard or via service-key migrations.
--
-- Run this in the SQL editor against project `zziauybwemoiqfpidiur`.

create table if not exists public.app_version_config (
    id                       bigserial primary key,
    minimum_supported_build  integer  not null,
    latest_build             integer  not null,
    update_required_message  text     not null default
        'A newer version of Sacred Bill Tracker is required to continue. Please update the app to keep using your account safely.',
    app_store_url            text     not null default
        'https://apps.apple.com/app/id6762890363',
    is_force_update_enabled  boolean  not null default false,
    updated_at               timestamptz not null default now()
);

-- Auto-update updated_at on every row change so iOS can sort
-- desc and grab the most recent config without timezone math.
create or replace function public.app_version_config_touch_updated_at()
returns trigger language plpgsql as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists trg_app_version_config_updated_at on public.app_version_config;
create trigger trg_app_version_config_updated_at
    before update on public.app_version_config
    for each row execute function public.app_version_config_touch_updated_at();

-- ============================================================
-- Row-level security
-- ============================================================
alter table public.app_version_config enable row level security;

-- Public read — anon role can SELECT.
drop policy if exists "app_version_config public read" on public.app_version_config;
create policy "app_version_config public read"
    on public.app_version_config
    for select
    using (true);

-- No INSERT / UPDATE / DELETE policies → only the service role can
-- write (it bypasses RLS), which is what we want.

-- ============================================================
-- Seed initial row (SAFE)
-- ============================================================
-- minimum_supported_build = 1   → nothing currently blocked
-- latest_build            = 18  → matches Build 18 release candidate
-- is_force_update_enabled = false → master switch off until needed
--
-- When you ship a future required update, do this in SQL editor:
--
--   update public.app_version_config
--      set minimum_supported_build = 25,
--          latest_build            = 25,
--          is_force_update_enabled = true
--    where id = (select id from public.app_version_config
--                order by updated_at desc limit 1);
--
-- Builds < 25 will then be hard-blocked on next launch / resume.

insert into public.app_version_config
    (minimum_supported_build, latest_build, is_force_update_enabled)
select 1, 18, false
where not exists (select 1 from public.app_version_config);
