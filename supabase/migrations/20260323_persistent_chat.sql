create extension if not exists pgcrypto;

create table if not exists public.chat_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default 'New Chat',
  last_message_preview text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.chat_sessions
  add column if not exists user_id uuid references auth.users(id) on delete cascade,
  add column if not exists title text,
  add column if not exists last_message_preview text,
  add column if not exists created_at timestamptz default now(),
  add column if not exists updated_at timestamptz default now();

update public.chat_sessions
set title = 'New Chat'
where title is null or btrim(title) = '';

alter table public.chat_sessions
  alter column title set default 'New Chat';

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.chat_sessions(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  role text not null,
  message text not null,
  created_at timestamptz not null default now()
);

alter table public.chat_messages
  add column if not exists session_id uuid references public.chat_sessions(id) on delete cascade,
  add column if not exists user_id uuid references auth.users(id) on delete cascade,
  add column if not exists role text,
  add column if not exists message text,
  add column if not exists created_at timestamptz default now();

update public.chat_messages as messages
set user_id = sessions.user_id
from public.chat_sessions as sessions
where messages.session_id = sessions.id
  and messages.user_id is null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'chat_sessions_user_id_fkey'
      and conrelid = 'public.chat_sessions'::regclass
  ) then
    alter table public.chat_sessions
      add constraint chat_sessions_user_id_fkey
      foreign key (user_id) references auth.users(id) on delete cascade;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'chat_messages_session_id_fkey'
      and conrelid = 'public.chat_messages'::regclass
  ) then
    alter table public.chat_messages
      add constraint chat_messages_session_id_fkey
      foreign key (session_id) references public.chat_sessions(id) on delete cascade;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'chat_messages_user_id_fkey'
      and conrelid = 'public.chat_messages'::regclass
  ) then
    alter table public.chat_messages
      add constraint chat_messages_user_id_fkey
      foreign key (user_id) references auth.users(id) on delete cascade;
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'chat_messages_role_check'
      and conrelid = 'public.chat_messages'::regclass
  ) then
    alter table public.chat_messages
      add constraint chat_messages_role_check
      check (role in ('user', 'assistant', 'system'));
  end if;
end
$$;

do $$
begin
  if not exists (select 1 from public.chat_sessions where user_id is null) then
    alter table public.chat_sessions alter column user_id set not null;
  end if;

  if not exists (select 1 from public.chat_messages where session_id is null) then
    alter table public.chat_messages alter column session_id set not null;
  end if;

  if not exists (select 1 from public.chat_messages where user_id is null) then
    alter table public.chat_messages alter column user_id set not null;
  end if;

  if not exists (select 1 from public.chat_messages where role is null) then
    alter table public.chat_messages alter column role set not null;
  end if;

  if not exists (select 1 from public.chat_messages where message is null) then
    alter table public.chat_messages alter column message set not null;
  end if;
end
$$;

update public.chat_sessions as sessions
set last_message_preview = latest.message,
    updated_at = greatest(coalesce(sessions.updated_at, latest.created_at), latest.created_at)
from (
  select distinct on (session_id)
    session_id,
    message,
    created_at
  from public.chat_messages
  order by session_id, created_at desc, id desc
) as latest
where latest.session_id = sessions.id;

alter table public.chat_sessions enable row level security;
alter table public.chat_messages enable row level security;
alter table public.chat_sessions replica identity full;
alter table public.chat_messages replica identity full;

drop policy if exists "Users can view own chat sessions" on public.chat_sessions;
create policy "Users can view own chat sessions"
on public.chat_sessions
for select
using (auth.uid() = user_id);

drop policy if exists "Users can insert own chat sessions" on public.chat_sessions;
create policy "Users can insert own chat sessions"
on public.chat_sessions
for insert
with check (auth.uid() = user_id);

drop policy if exists "Users can update own chat sessions" on public.chat_sessions;
create policy "Users can update own chat sessions"
on public.chat_sessions
for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete own chat sessions" on public.chat_sessions;
create policy "Users can delete own chat sessions"
on public.chat_sessions
for delete
using (auth.uid() = user_id);

drop policy if exists "Users can view own chat messages" on public.chat_messages;
create policy "Users can view own chat messages"
on public.chat_messages
for select
using (auth.uid() = user_id);

drop policy if exists "Users can insert own chat messages" on public.chat_messages;
create policy "Users can insert own chat messages"
on public.chat_messages
for insert
with check (
  auth.uid() = user_id
  and exists (
    select 1
    from public.chat_sessions as sessions
    where sessions.id = session_id
      and sessions.user_id = auth.uid()
  )
);

drop policy if exists "Users can update own chat messages" on public.chat_messages;
create policy "Users can update own chat messages"
on public.chat_messages
for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete own chat messages" on public.chat_messages;
create policy "Users can delete own chat messages"
on public.chat_messages
for delete
using (auth.uid() = user_id);

create or replace function public.set_chat_session_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.apply_chat_message_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  session_owner uuid;
begin
  select user_id
  into session_owner
  from public.chat_sessions
  where id = new.session_id;

  if session_owner is null then
    raise exception 'Chat session % does not exist', new.session_id;
  end if;

  new.user_id = session_owner;
  return new;
end;
$$;

create or replace function public.sync_chat_session_metadata()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_session_id uuid := coalesce(new.session_id, old.session_id);
  latest_message text;
begin
  select message
  into latest_message
  from public.chat_messages
  where session_id = target_session_id
  order by created_at desc, id desc
  limit 1;

  update public.chat_sessions
  set last_message_preview = latest_message,
      updated_at = now()
  where id = target_session_id;

  return coalesce(new, old);
end;
$$;

drop trigger if exists set_chat_sessions_updated_at on public.chat_sessions;
create trigger set_chat_sessions_updated_at
before update on public.chat_sessions
for each row
execute function public.set_chat_session_updated_at();

drop trigger if exists apply_chat_message_owner_before_write on public.chat_messages;
create trigger apply_chat_message_owner_before_write
before insert or update on public.chat_messages
for each row
execute function public.apply_chat_message_owner();

drop trigger if exists sync_chat_session_metadata_after_write on public.chat_messages;
create trigger sync_chat_session_metadata_after_write
after insert or update or delete on public.chat_messages
for each row
execute function public.sync_chat_session_metadata();

create index if not exists chat_sessions_user_updated_at_idx
  on public.chat_sessions (user_id, updated_at desc);

create index if not exists chat_messages_session_created_at_idx
  on public.chat_messages (session_id, created_at asc);

create index if not exists chat_messages_user_session_created_at_idx
  on public.chat_messages (user_id, session_id, created_at asc);

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
        and tablename = 'chat_sessions'
    ) then
      alter publication supabase_realtime add table public.chat_sessions;
    end if;

    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'chat_messages'
    ) then
      alter publication supabase_realtime add table public.chat_messages;
    end if;
  end if;
end
$$;
