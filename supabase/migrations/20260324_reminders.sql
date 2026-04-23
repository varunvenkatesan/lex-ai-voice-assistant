create extension if not exists pgcrypto;

create table if not exists public.reminders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  details text,
  scheduled_at timestamptz not null,
  source text not null default 'talk',
  status text not null default 'scheduled',
  delivered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.reminders
  add column if not exists user_id uuid references auth.users(id) on delete cascade,
  add column if not exists title text,
  add column if not exists details text,
  add column if not exists scheduled_at timestamptz,
  add column if not exists source text default 'talk',
  add column if not exists status text default 'scheduled',
  add column if not exists delivered_at timestamptz,
  add column if not exists created_at timestamptz default now(),
  add column if not exists updated_at timestamptz default now();

update public.reminders
set title = 'Reminder'
where title is null or btrim(title) = '';

update public.reminders
set source = 'talk'
where source is null or btrim(source) = '';

update public.reminders
set status = 'scheduled'
where status is null or btrim(status) = '';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'reminders_source_check'
      and conrelid = 'public.reminders'::regclass
  ) then
    alter table public.reminders
      add constraint reminders_source_check
      check (source in ('chat', 'talk'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'reminders_status_check'
      and conrelid = 'public.reminders'::regclass
  ) then
    alter table public.reminders
      add constraint reminders_status_check
      check (status in ('scheduled', 'triggered'));
  end if;
end
$$;

do $$
begin
  if not exists (select 1 from public.reminders where user_id is null) then
    alter table public.reminders alter column user_id set not null;
  end if;

  if not exists (select 1 from public.reminders where title is null) then
    alter table public.reminders alter column title set not null;
  end if;

  if not exists (select 1 from public.reminders where scheduled_at is null) then
    alter table public.reminders alter column scheduled_at set not null;
  end if;

  if not exists (select 1 from public.reminders where source is null) then
    alter table public.reminders alter column source set not null;
  end if;

  if not exists (select 1 from public.reminders where status is null) then
    alter table public.reminders alter column status set not null;
  end if;
end
$$;

alter table public.reminders
  alter column source set default 'talk',
  alter column status set default 'scheduled',
  alter column created_at set default now(),
  alter column updated_at set default now();

alter table public.reminders enable row level security;
alter table public.reminders replica identity full;

drop policy if exists "Users can view own reminders" on public.reminders;
create policy "Users can view own reminders"
on public.reminders
for select
using (auth.uid() = user_id);

drop policy if exists "Users can insert own reminders" on public.reminders;
create policy "Users can insert own reminders"
on public.reminders
for insert
with check (auth.uid() = user_id);

drop policy if exists "Users can update own reminders" on public.reminders;
create policy "Users can update own reminders"
on public.reminders
for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete own reminders" on public.reminders;
create policy "Users can delete own reminders"
on public.reminders
for delete
using (auth.uid() = user_id);

create or replace function public.set_reminders_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_reminders_updated_at on public.reminders;
create trigger set_reminders_updated_at
before update on public.reminders
for each row
execute function public.set_reminders_updated_at();

create index if not exists reminders_user_scheduled_at_idx
  on public.reminders (user_id, scheduled_at asc);

create index if not exists reminders_user_created_at_idx
  on public.reminders (user_id, created_at desc);

create index if not exists reminders_user_status_scheduled_at_idx
  on public.reminders (user_id, status, scheduled_at asc);

do $$
begin
  if exists (
    select 1
    from pg_publication
    where pubname = 'supabase_realtime'
  ) then
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'reminders'
    ) then
      alter publication supabase_realtime add table public.reminders;
    end if;
  end if;
end
$$;
