-- =====================================================================
-- Resend / pg_net monitoring + failure-recovery queries
-- Run any of these in Supabase SQL editor after the trigger is live.
-- =====================================================================

-- 1. Last 20 outbound HTTP responses (pg_net writes to net._http_response)
select id,
       status_code,
       content_type,
       error_msg,
       created
from net._http_response
order by id desc
limit 20;

-- 2. Failed sends in the last 24h
select id,
       status_code,
       error_msg,
       created
from net._http_response
where created > now() - interval '24 hours'
  and (status_code is null or status_code >= 400 or error_msg is not null)
order by created desc;

-- 3. Per-day send volume / failure rate
select date_trunc('day', created) as day,
       count(*) as total,
       count(*) filter (where status_code between 200 and 299) as ok,
       count(*) filter (where status_code is null or status_code >= 400) as failed
from net._http_response
where created > now() - interval '14 days'
group by 1
order by 1 desc;

-- 4. Manual re-fire for one invite (use when an email failed to deliver and
--    you want to retry the send without inserting a duplicate row)
-- Replace :invite_id with the partner_invites.id you want to resend.
-- select net.http_post(
--   url     := 'https://zziauybwemoiqfpidiur.supabase.co/functions/v1/send-partner-invite',
--   headers := jsonb_build_object('Content-Type','application/json'),
--   body    := (
--     select jsonb_build_object('id', id, 'invited_email', invited_email, 'inviter_id', inviter_id)
--     from public.partner_invites where id = :invite_id
--   ),
--   timeout_milliseconds := 5000
-- );

-- 5. Burst-protection: count invites a single user has sent in the last hour
--    (use to add a check constraint or trigger later if abuse appears)
select inviter_id,
       count(*) as last_hour
from public.partner_invites
where created_at > now() - interval '1 hour'
group by inviter_id
order by last_hour desc;
