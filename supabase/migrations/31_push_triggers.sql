-- ============================================================================
-- Sacred Pathway Driver Hub — P5 (Notifications)
-- Postgres triggers that invoke the send-push edge function automatically.
--
-- Run AFTER 20_supabase_device_tokens_schema.sql.
-- Required: pg_net extension (Supabase has this enabled by default).
-- ============================================================================

create extension if not exists pg_net;

-- Stored function: posts to the send-push edge function with a JSON body.
-- The service role key + project ref are read from the supabase Vault
-- (set via:  select vault.create_secret('edge_url', 'https://<ref>.supabase.co/functions/v1/send-push');
--            select vault.create_secret('service_role_key', '<key>');
-- ).

create or replace function private.invoke_send_push(payload jsonb)
returns void
language plpgsql
security definer
as $$
declare
  edge_url   text;
  svc_key    text;
begin
  select decrypted_secret into edge_url from vault.decrypted_secrets where name = 'edge_url'         limit 1;
  select decrypted_secret into svc_key  from vault.decrypted_secrets where name = 'service_role_key' limit 1;

  if edge_url is null or svc_key is null then
    raise warning 'send-push secrets missing — skipping';
    return;
  end if;

  perform net.http_post(
    url     := edge_url,
    headers := jsonb_build_object(
                 'Authorization', 'Bearer ' || svc_key,
                 'Content-Type',  'application/json'
               ),
    body    := payload
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- 1. New settlement → notify all of this user's OTHER devices
-- ----------------------------------------------------------------------------
create or replace function public.notify_on_settlement_insert()
returns trigger
language plpgsql
security definer
as $$
begin
  perform private.invoke_send_push(jsonb_build_object(
    'user_id',      NEW.user_id::text,
    'event',        'settlement.synced',
    'title',        'Settlements Updated',
    'body',         'A new settlement is available on your other device.',
    'settlementId', NEW.id::text,
    'silent',       false
  ));
  return NEW;
end;
$$;

drop trigger if exists trg_settlement_insert_push on public.settlements;
create trigger trg_settlement_insert_push
  after insert on public.settlements
  for each row
  execute function public.notify_on_settlement_insert();

-- ----------------------------------------------------------------------------
-- 2. Share link revoked or expired → notify owner
-- ----------------------------------------------------------------------------
create or replace function public.notify_on_share_link_state_change()
returns trigger
language plpgsql
security definer
as $$
begin
  -- Revoked manually
  if NEW.revoked_at is not null and OLD.revoked_at is null then
    perform private.invoke_send_push(jsonb_build_object(
      'user_id', NEW.user_id::text,
      'event',   'share.expired',
      'title',   'Share Link Revoked',
      'body',    'Your lender share link has been revoked.',
      'shareId', NEW.id::text,
      'silent',  false
    ));
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_share_link_state on public.share_links;
create trigger trg_share_link_state
  after update on public.share_links
  for each row
  execute function public.notify_on_share_link_state_change();

-- ----------------------------------------------------------------------------
-- 3. Cron: nightly sweep for shares expiring in next 24h → "expiring soon"
--    Uses pg_cron (also Supabase-default).
-- ----------------------------------------------------------------------------
create extension if not exists pg_cron;

create or replace function public.notify_share_links_expiring()
returns void
language plpgsql
security definer
as $$
declare
  r record;
begin
  for r in
    select id, user_id
    from public.share_links
    where revoked_at is null
      and expires_at between now() and now() + interval '24 hours'
      and (last_warned_at is null or last_warned_at < now() - interval '20 hours')
  loop
    perform private.invoke_send_push(jsonb_build_object(
      'user_id', r.user_id::text,
      'event',   'share.expiring_soon',
      'title',   'Share Link Expiring',
      'body',    'A lender share link expires in less than 24 hours.',
      'shareId', r.id::text,
      'silent',  false
    ));
    update public.share_links set last_warned_at = now() where id = r.id;
  end loop;
end;
$$;

-- Add the column the cron uses to dedupe.
alter table public.share_links
  add column if not exists last_warned_at timestamptz;

-- Schedule: every hour at :07 (offset off the top of the hour to spread load).
select cron.unschedule('share_links_expiring_sweep')
  where exists (select 1 from cron.job where jobname = 'share_links_expiring_sweep');

select cron.schedule(
  'share_links_expiring_sweep',
  '7 * * * *',
  $$ select public.notify_share_links_expiring(); $$
);

-- ----------------------------------------------------------------------------
-- 4. Permissions — only service role can call invoke_send_push directly.
-- ----------------------------------------------------------------------------
revoke all on function private.invoke_send_push(jsonb) from public;
grant  execute on function private.invoke_send_push(jsonb) to service_role;
