-- 20260423120000_delete_user_account.sql
--
-- Adds public.delete_user_account() so the iOS client can self-serve
-- account deletion from the Settings screen. Apple App Store Guideline
-- 5.1.1(v) requires in-app account deletion for any app that creates
-- accounts; the client calls this RPC with the user's JWT and we
-- cascade-delete all of their data, then the auth record itself.
--
-- No extensions required beyond what Supabase ships with.

create or replace function public.delete_user_account()
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  uid uuid := auth.uid();
begin
  -- Reject unauthenticated callers. auth.uid() is NULL when the
  -- request carries no valid JWT; that is the safety gate against
  -- anon / service traffic wiping arbitrary accounts.
  if uid is null then
    raise exception 'not authenticated'
      using errcode = '42501';   -- insufficient_privilege
  end if;

  -- Delete every row the user owns in app tables first. Bills has
  -- ON DELETE CASCADE on auth.users, but doing this explicitly keeps
  -- the order deterministic and makes it obvious where to add new
  -- tables as the schema grows.
  delete from public.bills where user_id = uid;

  -- Delete the auth record. This invalidates every refresh token and
  -- makes the JWT the caller is holding useless immediately.
  delete from auth.users where id = uid;

  return jsonb_build_object(
    'success', true,
    'user_id', uid
  );
end;
$$;

-- Lock it down: no PUBLIC / anon access, only logged-in users.
revoke all on function public.delete_user_account() from public;
revoke all on function public.delete_user_account() from anon;
grant  execute on function public.delete_user_account() to authenticated;

-- Defensive: ensure the FK from bills to auth.users cascades so the
-- final `delete from auth.users` in the function never fails on a
-- dangling reference.
alter table public.bills
  drop constraint if exists bills_user_id_fkey,
  add  constraint bills_user_id_fkey
    foreign key (user_id) references auth.users(id) on delete cascade;
