-- =====================================================================
-- SacredBillTracker — partner_invites
-- Run in Supabase SQL Editor (project: zziauybwemoiqfpidiur)
-- =====================================================================

-- 1. ENUM for invite status
do $$ begin
  create type partner_status as enum ('none','pending','connected');
exception when duplicate_object then null; end $$;

-- 2. Table
create table if not exists public.partner_invites (
    id              uuid primary key default gen_random_uuid(),
    inviter_id      uuid not null references auth.users(id) on delete cascade,
    invited_email   text not null,
    invited_user_id uuid references auth.users(id) on delete set null,
    status          partner_status not null default 'pending',
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now()
);

create index if not exists partner_invites_inviter_idx
  on public.partner_invites (inviter_id);
create index if not exists partner_invites_invited_user_idx
  on public.partner_invites (invited_user_id);
create index if not exists partner_invites_invited_email_idx
  on public.partner_invites (lower(invited_email));

-- 3. updated_at trigger
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;

drop trigger if exists partner_invites_set_updated_at on public.partner_invites;
create trigger partner_invites_set_updated_at
  before update on public.partner_invites
  for each row execute function public.set_updated_at();

-- 4. Row Level Security
alter table public.partner_invites enable row level security;

drop policy if exists "select own invites" on public.partner_invites;
create policy "select own invites" on public.partner_invites
  for select using (
    auth.uid() = inviter_id
    or auth.uid() = invited_user_id
    or lower(invited_email) = lower((auth.jwt() ->> 'email'))
  );

drop policy if exists "insert own invites" on public.partner_invites;
create policy "insert own invites" on public.partner_invites
  for insert with check (auth.uid() = inviter_id);

drop policy if exists "update own invites" on public.partner_invites;
create policy "update own invites" on public.partner_invites
  for update using (
    auth.uid() = inviter_id
    or auth.uid() = invited_user_id
  );

drop policy if exists "delete own invites" on public.partner_invites;
create policy "delete own invites" on public.partner_invites
  for delete using (auth.uid() = inviter_id);

-- 5. RPC: accept_partner_invite — invitee links themselves to a pending invite
create or replace function public.accept_partner_invite(p_invite_id uuid)
returns public.partner_invites
language plpgsql security definer set search_path = public as $$
declare
  v_user_email text;
  v_row public.partner_invites;
begin
  select (auth.jwt() ->> 'email') into v_user_email;

  update public.partner_invites
     set invited_user_id = auth.uid(),
         status          = 'connected'
   where id = p_invite_id
     and status = 'pending'
     and lower(invited_email) = lower(v_user_email)
  returning * into v_row;

  if v_row.id is null then
     raise exception 'Invite not found, already accepted, or email mismatch';
  end if;

  return v_row;
end $$;

grant execute on function public.accept_partner_invite(uuid) to authenticated;

-- 6. Smoke test (uncomment after running):
-- select * from public.partner_invites limit 1;
