-- Sacred Bill Tracker: managed financial profiles under one subscriber account.
-- Profiles are data scopes only. They do not create separate auth users,
-- emails, passwords, or subscriptions.

create extension if not exists "pgcrypto";

create table if not exists public.financial_profiles (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null references auth.users(id) on delete cascade,
  name             text not null check (char_length(trim(name)) between 1 and 80),
  kind             text not null default 'personal'
                   check (kind in ('personal', 'spouse', 'parent', 'child', 'business', 'rental_property', 'other')),
  icon_system_name text not null default 'person.crop.circle.fill',
  color_hex        text not null default '#2F7D5A'
                   check (color_hex ~ '^#[0-9A-Fa-f]{6}$'),
  is_default       boolean not null default false,
  archived_at      timestamptz,
  sort_order       integer not null default 0,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

alter table public.financial_profiles
  add column if not exists archived_at timestamptz;

drop index if exists public.financial_profiles_owner_sort_idx;
create index financial_profiles_owner_sort_idx
  on public.financial_profiles(owner_id, sort_order, name)
  where archived_at is null;

drop index if exists public.financial_profiles_one_default_per_owner_idx;
create unique index financial_profiles_one_default_per_owner_idx
  on public.financial_profiles(owner_id)
  where is_default and archived_at is null;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists financial_profiles_set_updated_at on public.financial_profiles;
create trigger financial_profiles_set_updated_at
  before update on public.financial_profiles
  for each row execute function public.set_updated_at();

alter table public.financial_profiles enable row level security;

drop policy if exists "Owners can read profiles" on public.financial_profiles;
drop policy if exists "Owners can insert profiles" on public.financial_profiles;
drop policy if exists "Owners can update profiles" on public.financial_profiles;
drop policy if exists "Owners can delete profiles" on public.financial_profiles;

create policy "Owners can read profiles"
  on public.financial_profiles for select
  using (auth.uid() = owner_id);

create policy "Owners can insert profiles"
  on public.financial_profiles for insert
  with check (auth.uid() = owner_id);

create policy "Owners can update profiles"
  on public.financial_profiles for update
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

create or replace function public.ensure_default_financial_profile(p_owner uuid)
returns uuid
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_profile_id uuid;
begin
  if p_owner is null then
    raise exception 'owner_id is required' using errcode = '23502';
  end if;

  if auth.uid() is not null and auth.uid() <> p_owner then
    raise exception 'cannot create a managed profile for another owner'
      using errcode = '42501';
  end if;

  select id
    into v_profile_id
    from public.financial_profiles
   where owner_id = p_owner
     and is_default = true
     and archived_at is null
   order by created_at asc
   limit 1;

  if v_profile_id is not null then
    return v_profile_id;
  end if;

  select id
    into v_profile_id
    from public.financial_profiles
   where owner_id = p_owner
     and archived_at is null
   order by sort_order asc, created_at asc
   limit 1;

  if v_profile_id is not null then
    update public.financial_profiles
       set is_default = true
     where id = v_profile_id;
    return v_profile_id;
  end if;

  insert into public.financial_profiles (
    owner_id, name, kind, icon_system_name, color_hex, is_default, sort_order
  )
  values (
    p_owner, 'My Bills', 'personal', 'person.crop.circle.fill', '#2F7D5A', true, 0
  )
  returning id into v_profile_id;

  return v_profile_id;
end;
$$;

revoke all on function public.ensure_default_financial_profile(uuid) from public;
revoke all on function public.ensure_default_financial_profile(uuid) from anon;
grant execute on function public.ensure_default_financial_profile(uuid) to authenticated;

-- Backfill profiles for every existing bills owner.
insert into public.financial_profiles (
  owner_id, name, kind, icon_system_name, color_hex, is_default, sort_order
)
select distinct b.user_id,
       'My Bills',
       'personal',
       'person.crop.circle.fill',
       '#2F7D5A',
       true,
       0
  from public.bills b
 where b.user_id is not null
   and not exists (
     select 1
       from public.financial_profiles fp
      where fp.owner_id = b.user_id
   );

alter table public.bills
  add column if not exists owner_id uuid,
  add column if not exists profile_id uuid;

update public.bills
   set owner_id = coalesce(owner_id, user_id)
 where owner_id is null;

update public.bills
   set profile_id = public.ensure_default_financial_profile(coalesce(owner_id, user_id))
 where profile_id is null
   and coalesce(owner_id, user_id) is not null;

alter table public.bills
  alter column owner_id set not null,
  alter column profile_id set not null;

alter table public.bills
  drop constraint if exists bills_owner_id_fkey,
  add constraint bills_owner_id_fkey
    foreign key (owner_id) references auth.users(id) on delete cascade;

alter table public.bills
  drop constraint if exists bills_profile_id_fkey,
  add constraint bills_profile_id_fkey
    foreign key (profile_id) references public.financial_profiles(id) on delete restrict;

create index if not exists bills_owner_profile_due_idx
  on public.bills(owner_id, profile_id, due_date);

create or replace function public.sync_bill_profile_owner()
returns trigger
language plpgsql
set search_path = public, auth, pg_temp
as $$
begin
  new.owner_id := coalesce(new.owner_id, new.user_id, auth.uid());

  if new.owner_id is null then
    raise exception 'owner_id is required' using errcode = '23502';
  end if;

  if new.user_id is null then
    new.user_id := new.owner_id;
  end if;

  if new.user_id <> new.owner_id then
    raise exception 'user_id must match owner_id for managed profile bills'
      using errcode = '23514';
  end if;

  if new.profile_id is null then
    new.profile_id := public.ensure_default_financial_profile(new.owner_id);
  end if;

  if not exists (
    select 1
      from public.financial_profiles fp
     where fp.id = new.profile_id
       and fp.owner_id = new.owner_id
  ) then
    raise exception 'profile_id does not belong to owner_id'
      using errcode = '23503';
  end if;

  return new;
end;
$$;

drop trigger if exists bills_sync_profile_owner on public.bills;
create trigger bills_sync_profile_owner
  before insert or update on public.bills
  for each row execute function public.sync_bill_profile_owner();

alter table public.bills enable row level security;

drop policy if exists "Users can read own bills" on public.bills;
drop policy if exists "Users can insert own bills" on public.bills;
drop policy if exists "Users can update own bills" on public.bills;
drop policy if exists "Users can delete own bills" on public.bills;
drop policy if exists "Owners can read managed profile bills" on public.bills;
drop policy if exists "Owners can insert managed profile bills" on public.bills;
drop policy if exists "Owners can update managed profile bills" on public.bills;
drop policy if exists "Owners can delete managed profile bills" on public.bills;
drop policy if exists "Connected partners can read shared bills" on public.bills;

create policy "Owners can read managed profile bills"
  on public.bills for select
  using (auth.uid() = owner_id);

create policy "Owners can insert managed profile bills"
  on public.bills for insert
  with check (
    auth.uid() = owner_id
    and user_id = owner_id
    and exists (
      select 1
        from public.financial_profiles fp
       where fp.id = profile_id
         and fp.owner_id = auth.uid()
    )
  );

create policy "Owners can update managed profile bills"
  on public.bills for update
  using (auth.uid() = owner_id)
  with check (
    auth.uid() = owner_id
    and user_id = owner_id
    and exists (
      select 1
        from public.financial_profiles fp
       where fp.id = profile_id
         and fp.owner_id = auth.uid()
    )
  );

create policy "Owners can delete managed profile bills"
  on public.bills for delete
  using (auth.uid() = owner_id);

-- Preserve partner read access when the optional partner_invites table is installed.
do $$
begin
  if to_regclass('public.partner_invites') is not null then
    execute $policy$
      create policy "Connected partners can read shared bills"
        on public.bills for select
        using (
          is_shared = true
          and exists (
            select 1
              from public.partner_invites pi
             where pi.status::text = 'connected'
               and (
                 (pi.inviter_id = owner_id and pi.invited_user_id = auth.uid())
                 or
                 (pi.inviter_id = auth.uid() and pi.invited_user_id = owner_id)
               )
          )
        )
    $policy$;
  end if;
end $$;

create table if not exists public.income_entries (
  id          uuid primary key,
  owner_id    uuid not null references auth.users(id) on delete cascade,
  profile_id  uuid not null references public.financial_profiles(id) on delete restrict,
  amount      numeric(14,2) not null check (amount > 0),
  week_start  timestamptz not null,
  week_end    timestamptz not null,
  type        text not null default 'business' check (type in ('business', 'personal')),
  source_name text not null default '',
  note        text not null default '',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  check (week_end >= week_start)
);

create index if not exists income_entries_owner_profile_week_idx
  on public.income_entries(owner_id, profile_id, week_start desc);

drop trigger if exists income_entries_set_updated_at on public.income_entries;
create trigger income_entries_set_updated_at
  before update on public.income_entries
  for each row execute function public.set_updated_at();

create or replace function public.sync_income_profile_owner()
returns trigger
language plpgsql
set search_path = public, auth, pg_temp
as $$
begin
  new.owner_id := coalesce(new.owner_id, auth.uid());

  if new.owner_id is null then
    raise exception 'owner_id is required' using errcode = '23502';
  end if;

  if new.profile_id is null then
    new.profile_id := public.ensure_default_financial_profile(new.owner_id);
  end if;

  if not exists (
    select 1
      from public.financial_profiles fp
     where fp.id = new.profile_id
       and fp.owner_id = new.owner_id
  ) then
    raise exception 'profile_id does not belong to owner_id'
      using errcode = '23503';
  end if;

  return new;
end;
$$;

drop trigger if exists income_entries_sync_profile_owner on public.income_entries;
create trigger income_entries_sync_profile_owner
  before insert or update on public.income_entries
  for each row execute function public.sync_income_profile_owner();

alter table public.income_entries enable row level security;

drop policy if exists "Owners can read income entries" on public.income_entries;
drop policy if exists "Owners can insert income entries" on public.income_entries;
drop policy if exists "Owners can update income entries" on public.income_entries;
drop policy if exists "Owners can delete income entries" on public.income_entries;

create policy "Owners can read income entries"
  on public.income_entries for select
  using (auth.uid() = owner_id);

create policy "Owners can insert income entries"
  on public.income_entries for insert
  with check (
    auth.uid() = owner_id
    and exists (
      select 1
        from public.financial_profiles fp
       where fp.id = profile_id
         and fp.owner_id = auth.uid()
    )
  );

create policy "Owners can update income entries"
  on public.income_entries for update
  using (auth.uid() = owner_id)
  with check (
    auth.uid() = owner_id
    and exists (
      select 1
        from public.financial_profiles fp
       where fp.id = profile_id
         and fp.owner_id = auth.uid()
    )
  );

create policy "Owners can delete income entries"
  on public.income_entries for delete
  using (auth.uid() = owner_id);

create or replace function public.delete_user_account()
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  delete from public.income_entries where owner_id = uid;
  delete from public.bills where owner_id = uid or user_id = uid;
  delete from public.financial_profiles where owner_id = uid;
  delete from auth.users where id = uid;

  return jsonb_build_object('success', true, 'user_id', uid);
end;
$$;

revoke all on function public.delete_user_account() from public;
revoke all on function public.delete_user_account() from anon;
grant execute on function public.delete_user_account() to authenticated;
