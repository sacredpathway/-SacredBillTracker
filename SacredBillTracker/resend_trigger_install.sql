-- =====================================================================
-- Wire partner_invites INSERT → send-partner-invite Edge Function
-- Run AFTER `supabase functions deploy send-partner-invite --no-verify-jwt`
-- =====================================================================

-- 1. Enable pg_net (idempotent)
create extension if not exists pg_net;

-- 2. Trigger function: posts to the Edge Function async
create or replace function public.notify_partner_invite()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text := 'https://zziauybwemoiqfpidiur.supabase.co/functions/v1/send-partner-invite';
begin
  -- Fire-and-forget HTTP POST; Edge Function handles the Resend call.
  -- pg_net returns a request_id we ignore; failures end up in
  -- net._http_response (see monitoring SQL below).
  perform net.http_post(
    url     := v_url,
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body    := jsonb_build_object(
      'id',           new.id,
      'invited_email',new.invited_email,
      'inviter_id',   new.inviter_id
    ),
    timeout_milliseconds := 5000
  );
  return new;
exception when others then
  -- Don't block the INSERT if pg_net is misconfigured. Log and move on.
  raise warning 'notify_partner_invite failed: %', SQLERRM;
  return new;
end;
$$;

-- 3. Attach trigger (only on INSERT, not UPDATE — we don't want re-emails
--    when the partner accepts and updates the row)
drop trigger if exists trg_notify_partner_invite on public.partner_invites;
create trigger trg_notify_partner_invite
  after insert on public.partner_invites
  for each row execute function public.notify_partner_invite();

-- 4. Verify
select tgname, tgenabled
from pg_trigger
where tgrelid = 'public.partner_invites'::regclass;
