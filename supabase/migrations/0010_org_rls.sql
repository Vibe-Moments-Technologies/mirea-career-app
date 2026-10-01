-- 0010_org_rls.sql — видимость и управление внутри организации. Идемпотентно.
--
-- Что даёт:
--   1) начальник видит посты подчинённых (все статусы), сотрудник — только свои;
--   2) начальник правит профили своих сотрудников;
--   3) роль и организацию меняет только «ответственный» — это триггер 0002;
--   4) удаление постов — по разрешению can_delete_posts (или начальник/ответственный).

-- ---------- posts: SELECT ----------
drop policy if exists posts_select on public.posts;
create policy posts_select on public.posts for select
using (
  -- все, включая anon: только опубликованное
  (status = 'published' and published_at <= now())
  -- модераторы (в т.ч. ассистент) видят всё — очередь работает по всем организациям
  or public.is_moderator()
  or (auth.role() = 'authenticated' and (
        -- начальник: вся своя организация, посты подчинённых в любом статусе
        (public.current_role() = 'org_admin' and organization_id = public.current_org_id())
        -- сотрудник: только собственные посты
        or (public.current_role() = 'org_member'
            and organization_id = public.current_org_id()
            and author_id = auth.uid())
        or public.is_responsible()
     ))
);

-- ---------- posts: UPDATE ----------
-- Смена статуса сторожится триггером guard_post_update; политика лишь отсекает чужое.
drop policy if exists posts_update on public.posts;
create policy posts_update on public.posts for update to authenticated
using (
  public.is_moderator()
  or (public.current_role() = 'org_admin' and organization_id = public.current_org_id())
  or (public.current_role() = 'org_member' and organization_id = public.current_org_id()
      and author_id = auth.uid())
)
with check (
  public.is_moderator()
  or (public.current_role() = 'org_admin' and organization_id = public.current_org_id())
  or (public.current_role() = 'org_member' and organization_id = public.current_org_id()
      and author_id = auth.uid())
);

-- ---------- posts: DELETE — по разрешению ----------
-- Предикат по строке: RLS не даёт вызывать функцию над строкой по-другому.
create or replace function public.can_author_delete_row(target uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.can_author_delete(p), false)
    from public.posts p where p.id = target
$$;
revoke all on function public.can_author_delete_row(uuid) from public;
grant execute on function public.can_author_delete_row(uuid) to authenticated;

drop policy if exists posts_delete on public.posts;
create policy posts_delete on public.posts for delete to authenticated
using (public.is_chief() or public.can_author_delete_row(id));

-- ---------- profiles: SELECT ----------
-- Коллеги своей организации видны (экран «Команда»), правит каждый только себя
-- или начальник своих сотрудников — это UPDATE-политика ниже.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
using (true);

-- ---------- profiles: UPDATE ----------
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated
using (
  id = auth.uid()
  or public.manages_profile(id)
  or public.is_responsible()
)
with check (
  id = auth.uid()
  or public.manages_profile(id)
  or public.is_responsible()
);

-- ---------- profiles: DELETE ----------
-- Начальник удаляет сотрудника своей организации; себя и ответственного — нет
-- (manages_profile исключает самого себя).
drop policy if exists profiles_delete on public.profiles;
create policy profiles_delete on public.profiles for delete to authenticated
using (public.manages_profile(id));

-- ---------- rejection_notes: авторы видят пояснения по своим постам ----------
drop policy if exists rn_select on public.rejection_notes;
create policy rn_select on public.rejection_notes for select to authenticated
using (
  public.is_moderator()
  or exists (
    select 1 from public.posts p
     where p.id = post_id
       and (
         (public.current_role() = 'org_admin' and p.organization_id = public.current_org_id())
         or (public.current_role() = 'org_member' and p.author_id = auth.uid())
       )
  )
);

-- ---------- rejection_notes: пишут модераторы, читают все причастные ----------
drop policy if exists rn_insert on public.rejection_notes;
create policy rn_insert on public.rejection_notes for insert to authenticated
with check (public.is_moderator());
