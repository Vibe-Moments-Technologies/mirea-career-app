-- 0001_init.sql — схема «Карьера РТУ МИРЭА»
-- enum'ы, таблицы, триггеры, индексы, realtime. Идемпотентно.

create extension if not exists pgcrypto;

-- ---------- Enum'ы ----------
do $$ begin
  create type public.org_type as enum ('university_dept', 'partner');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.user_role as enum
    ('super_admin', 'main_moderator', 'assistant_moderator', 'org_admin', 'org_member');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.post_type as enum
    ('event', 'vacancy', 'internship', 'scholarship', 'project');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.post_status as enum
    ('draft', 'pending_review', 'reviewed_ready', 'published', 'rejected');
exception when duplicate_object then null; end $$;

-- ---------- organizations ----------
create table if not exists public.organizations (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  type        public.org_type not null,
  description text,
  logo_url    text,
  created_at  timestamptz not null default now()
);

-- ---------- profiles (1:1 auth.users) ----------
create table if not exists public.profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  role            public.user_role not null default 'org_member',
  organization_id uuid references public.organizations(id) on delete set null,
  full_name       text not null default 'Пользователь',
  created_at      timestamptz not null default now()
);
create index if not exists profiles_org_idx on public.profiles(organization_id);

-- ---------- posts ----------
create table if not exists public.posts (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  author_id       uuid references public.profiles(id) on delete set null,

  title           text not null,
  description     text not null default '',
  type            public.post_type not null,
  format          text not null default 'offline' check (format in ('online','offline','hybrid')),
  external_link   text,
  image_url       text,
  event_date      date,

  campuses        text[] not null default '{}',
  institutes      text[] not null default '{}',
  directions      text[] not null default '{}',
  tags            text[] not null default '{}',

  is_featured     boolean not null default false,
  priority_weight integer not null default 0,
  status          public.post_status not null default 'draft',

  views_count     bigint not null default 0,
  favorites_count bigint not null default 0,

  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  published_at    timestamptz
);
create index if not exists posts_status_pub_idx on public.posts(status, published_at desc);
create index if not exists posts_org_idx        on public.posts(organization_id);
create index if not exists posts_tags_gin       on public.posts using gin(tags);
create index if not exists posts_campuses_gin   on public.posts using gin(campuses);
create index if not exists posts_institutes_gin on public.posts using gin(institutes);

-- ---------- rejection_notes ----------
create table if not exists public.rejection_notes (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid not null references public.posts(id) on delete cascade,
  author_id  uuid references public.profiles(id) on delete set null,
  note       text not null,
  created_at timestamptz not null default now()
);
create index if not exists rejection_post_idx on public.rejection_notes(post_id);

-- ---------- updated_at ----------
create or replace function public.set_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at = now(); return new; end $$;

drop trigger if exists posts_set_updated_at on public.posts;
create trigger posts_set_updated_at before update on public.posts
  for each row execute function public.set_updated_at();

-- ---------- профиль при регистрации ----------
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', 'Пользователь'), 'org_member')
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Realtime ----------
do $$ begin
  alter publication supabase_realtime add table public.posts;
exception when duplicate_object then null; end $$;
