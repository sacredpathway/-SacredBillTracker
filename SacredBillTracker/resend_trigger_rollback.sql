-- =====================================================================
-- Rollback for resend_trigger_install.sql
-- Use if Resend deploy goes wrong and you want partner_invites INSERT
-- to stop firing the Edge Function call.
-- =====================================================================

-- Removes the trigger but leaves pg_net + the function definition
-- in place so you can re-enable quickly.
drop trigger if exists trg_notify_partner_invite on public.partner_invites;

-- If you also want to remove the function:
-- drop function if exists public.notify_partner_invite();

-- Confirm
select tgname from pg_trigger where tgrelid = 'public.partner_invites'::regclass;
