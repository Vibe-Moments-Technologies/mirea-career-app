-- 0002_rls.sql — роли, RLS-политики, охранники, storage. Идемпотентно.

-- ---------- Хелперы (security definer, чтобы читать profiles без рекурсии RLS) ----------
create or replace function public.current_role() returns public.user_role
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.current_org_id() returns uuid
language sql stable security definer set search_path = public as $$
  select organization_id from public.profiles where id = auth.uid()
$$;

create or replace function public.is_moderator() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.current_role() in
    ('super_admin','main_moderator','assistant_moderator'), false)
$$;

create or replace function public.is_chief() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.current_role() in ('super_admin','main_moderator'), false)
$$;

revoke all on function public.current_role() from public;
revoke all on function public.current_org_id() from public;
revoke all on function public.is_moderator() from public;
revoke all on function public.is_chief() from public;
grant execute on function public.current_role() to anon, authenticated;
grant execute on function public.current_org_id() to anon, authenticated;
grant execute on function public.is_moderator() to anon, authenticated;
grant execute on function public.is_chief() to anon, authenticated;

-- ---------- Охранник переходов статуса posts (матрица DATABASE.md §3) ----------
create or replace function public.guard_post_update() returns trigger
language plpgsql security definer set search_path = public as $$
declare r public.user_role := public.current_role();
begin
  -- RPC-инкремент счётчиков: статус и приоритет не меняются — пропускаем
  if new.status = old.status
     and new.is_featured = old.is_featured
     and new.priority_weight = old.priority_weight then
    return new;
  end if;

  -- приоритет и целевая аудитория — только главный/супер
  if (new.is_featured <> old.is_featured
        or new.priority_weight <> old.priority_weight
        or new.campuses <> old.campuses
        or new.institutes <> old.institutes
        or new.directions <> old.directions)
     and not public.is_chief() then
    raise exception 'менять приоритет/аудиторию может только главный модератор';
  end if;

  if new.status <> old.status then
    if public.is_chief() then
      -- главный/супер: любой переход; при публикации ставим published_at
      if new.status = 'published' and old.status <> 'published' then
        new.published_at := now();
      end if;
    elsif r = 'assistant_moderator' then
      if not (old.status = 'pending_review'
              and new.status in ('reviewed_ready','rejected')) then
        raise exception 'ассистент проверяет только pending_review';
      end if;
    elsif r in ('org_admin','org_member') then
      if old.organization_id <> public.current_org_id() then
        raise exception 'нет доступа к чужой организации';
      end if;
      if not ((old.status = 'draft'    and new.status = 'pending_review')
           or (old.status = 'rejected' and new.status = 'draft')) then
        raise exception 'автор может только отправить на модерацию или вернуть в черновик';
      end if;
    else
      raise exception 'недостаточно прав для смены статуса';
    end if;
  end if;

  return new;
end $$;

drop trigger if exists posts_guard_update on public.posts;
create trigger posts_guard_update before update on public.posts
  for each row execute function public.guard_post_update();

-- ---------- Охранник INSERT: автор — в свою org, author_id = текущий ----------
create or replace function public.guard_post_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_moderator() then
    if new.organization_id <> public.current_org_id() then
      raise exception 'пост можно создавать только в своей организации';
    end if;
    new.author_id := auth.uid();
  elsif new.author_id is null then
    new.author_id := auth.uid();
  end if;
  return new;
end $$;

drop trigger if exists posts_guard_insert on public.posts;
create trigger posts_guard_insert before insert on public.posts
  for each row execute function public.guard_post_insert();

-- ---------- Охранник profiles: роль/организацию меняет только супер-админ ----------
create or replace function public.guard_profile_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.current_role() <> 'super_admin'
     and (new.role <> old.role or new.organization_id is distinct from old.organization_id) then
    raise exception 'роль и организацию назначает только супер-админ';
  end if;
  return new;
end $$;

drop trigger if exists profiles_guard_update on public.profiles;
create trigger profiles_guard_update before update on public.profiles
  for each row execute function public.guard_profile_update();

-- ================= RLS =================
alter table public.organizations  enable row level security;
alter table public.profiles       enable row level security;
alter table public.posts          enable row level security;
alter table public.rejection_notes enable row level security;

-- ---- posts ----
drop policy if exists posts_select on public.posts;
create policy posts_select on public.posts for select
using (
  (status = 'published' and published_at <= now())          -- все, включая anon
  or public.is_moderator()                                    -- модераторы видят всё
  or (auth.role() = 'authenticated'                           -- авторы — своё неопубликованное
      and organization_id = public.current_org_id())
);

drop policy if exists posts_insert on public.posts;
create policy posts_insert on public.posts for insert to authenticated
with check (
  public.current_role() in ('super_admin','main_moderator')
  or organization_id = public.current_org_id()
);

drop policy if exists posts_update on public.posts;
create policy posts_update on public.posts for update to authenticated
using (
  public.is_moderator() or organization_id = public.current_org_id()
)
with check (
  public.is_moderator() or organization_id = public.current_org_id()
);

drop policy if exists posts_delete on public.posts;
create policy posts_delete on public.posts for delete to authenticated
using (
  public.is_chief()
  or (public.current_role() in ('org_admin','org_member')
      and organization_id = public.current_org_id()
      and status in ('draft','rejected'))
);

-- ---- organizations ----
drop policy if exists org_select on public.organizations;
create policy org_select on public.organizations for select using (true);

drop policy if exists org_write on public.organizations;
create policy org_write on public.organizations for all to authenticated
using (
  public.current_role() = 'super_admin'
  or (public.current_role() = 'org_admin' and id = public.current_org_id())
)
with check (
  public.current_role() = 'super_admin'
  or (public.current_role() = 'org_admin' and id = public.current_org_id())
);

-- ---- profiles ----
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated using (true);

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated
using (id = auth.uid() or public.current_role() = 'super_admin')
with check (id = auth.uid() or public.current_role() = 'super_admin');

-- вставка профилей — только триггером handle_new_user (definer) / сервис-ролью
drop policy if exists profiles_insert on public.profiles;

-- ---- rejection_notes ----
drop policy if exists rn_select on public.rejection_notes;
create policy rn_select on public.rejection_notes for select to authenticated
using (
  public.is_moderator()
  or exists (select 1 from public.posts p
             where p.id = post_id and p.organization_id = public.current_org_id())
);

drop policy if exists rn_insert on public.rejection_notes;
create policy rn_insert on public.rejection_notes for insert to authenticated
with check (public.is_moderator());

-- ================= Гранты (в т.ч. колоночные: счётчики недоступны напрямую) =================
revoke all on public.posts from anon, authenticated;
grant select on public.posts to anon, authenticated;
grant insert (organization_id, title, description, type, format, external_link,
              image_url, event_date, campuses, institutes, directions, tags, status)
  on public.posts to authenticated;
grant update (title, description, type, format, external_link, image_url, event_date,
              campuses, institutes, directions, tags, status, is_featured, priority_weight)
  on public.posts to authenticated;
grant delete on public.posts to authenticated;
-- views_count / favorites_count / published_at / created_at / updated_at — НЕ выдаются:
-- их пишут только RPC (owner) и триггеры.

revoke all on public.organizations from anon, authenticated;
grant select on public.organizations to anon, authenticated;
grant insert, update, delete on public.organizations to authenticated;

revoke all on public.profiles from anon, authenticated;
grant select, update on public.profiles to authenticated;
grant insert (id, role, organization_id, full_name) on public.profiles to authenticated;

revoke all on public.rejection_notes from anon, authenticated;
grant select, insert on public.rejection_notes to authenticated;

-- ================= Storage: публичный bucket media =================
insert into storage.buckets (id, name, public)
values ('media', 'media', true)
on conflict (id) do update set public = true;

drop policy if exists media_public_read on storage.objects;
create policy media_public_read on storage.objects for select
using (bucket_id = 'media');

drop policy if exists media_auth_upload on storage.objects;
create policy media_auth_upload on storage.objects for insert to authenticated
with check (bucket_id = 'media');

drop policy if exists media_auth_update on storage.objects;
create policy media_auth_update on storage.objects for update to authenticated
using (bucket_id = 'media');

drop policy if exists media_auth_delete on storage.objects;
create policy media_auth_delete on storage.objects for delete to authenticated
using (bucket_id = 'media' and (owner::text = auth.uid()::text or public.is_moderator()));
