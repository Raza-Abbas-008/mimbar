-- Mimbar cloud sync schema. Paste into Supabase → SQL Editor → Run.
-- Safe to run again: everything is "if not exists" / "or replace".
--
-- Each phone keeps its own SQLite copy and syncs rows by `uid`.
-- `updated_at` is the phone's clock (ms) at the time of the edit: the newer
-- edit wins. `server_ts` is stamped here and is what phones pull by.
-- Deletes are kept as rows with deleted = true so other phones see them.

create table if not exists public.hosts (
  uid        uuid primary key,
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name       text not null default '',
  phone      text not null default '',
  venue      text not null default '',
  deleted    boolean not null default false,
  updated_at bigint not null,
  server_ts  timestamptz not null default clock_timestamp()
);

create table if not exists public.events (
  uid           uuid primary key,
  user_id       uuid not null default auth.uid() references auth.users(id) on delete cascade,
  type          text not null default 'majlis',
  h_year        int  not null default 0,
  h_month       int  not null default 0,
  h_day         int  not null default 0,
  greg_override text,
  start_min     int  not null default 0,
  end_min       int  not null default 0,
  venue         text not null default '',
  host_uid      uuid,
  topic         text not null default '',
  status        text not null default 'confirmed',
  series_id     text,
  series_index  int,
  series_total  int,
  deleted       boolean not null default false,
  updated_at    bigint not null,
  server_ts     timestamptz not null default clock_timestamp()
);

create table if not exists public.settings (
  user_id    uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  data       jsonb not null default '{}',
  updated_at bigint not null,
  server_ts  timestamptz not null default clock_timestamp()
);

create index if not exists hosts_pull  on public.hosts  (user_id, server_ts);
create index if not exists events_pull on public.events (user_id, server_ts);

-- Last write wins: an upsert carrying an older edit than the stored row is
-- ignored. Also pins every row to the signed-in user.
create or replace function public.mimbar_lww() returns trigger
language plpgsql as $$
begin
  if tg_op = 'UPDATE' and new.updated_at < old.updated_at then
    return null;
  end if;
  new.user_id := auth.uid();
  new.server_ts := clock_timestamp();
  return new;
end $$;

drop trigger if exists hosts_lww on public.hosts;
create trigger hosts_lww before insert or update on public.hosts
  for each row execute function public.mimbar_lww();
drop trigger if exists events_lww on public.events;
create trigger events_lww before insert or update on public.events
  for each row execute function public.mimbar_lww();
drop trigger if exists settings_lww on public.settings;
create trigger settings_lww before insert or update on public.settings
  for each row execute function public.mimbar_lww();

-- Each account sees and writes only its own rows.
alter table public.hosts    enable row level security;
alter table public.events   enable row level security;
alter table public.settings enable row level security;

drop policy if exists own on public.hosts;
create policy own on public.hosts for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists own on public.events;
create policy own on public.events for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists own on public.settings;
create policy own on public.settings for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Live updates: the other phone is told to sync as soon as something changes.
do $$
declare t text;
begin
  foreach t in array array['hosts', 'events', 'settings'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public'
                     and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
