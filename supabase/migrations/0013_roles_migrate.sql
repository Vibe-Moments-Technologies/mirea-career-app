-- 0013_roles_migrate.sql — ЗАХОД 2: перенос людей на новые роли и переключение прав.
--
-- Предусловие: применён 0012 (значения enum созданы). Иначе будет ошибка
-- «unsafe use of new value of enum type» — это защита Postgres, а не поломка.

-- ---------- 1. Системная организация ----------
insert into public.organizations (id, name, type, description)
values ('00000000-0000-0000-0000-000000000001', 'Администрация', 'administration',
        'Модераторская служба вуза: проверка карточек, публикации, работа с организациями.')
on conflict (id) do update set name = excluded.name, type = excluded.type, description = excluded.description;

-- ---------- 2. Перенос ролей ----------
-- Модераторская служба целиком переезжает в «Администрацию»: и администратор,
-- и модераторы становятся её сотрудниками. Ответственный за неё — только супер-админ.
do $$
declare admin_org uuid := '00000000-0000-0000-0000-000000000001';
begin
  -- сначала роли, потом организация (порядок важен для понятности логов)
  update public.profiles set role = 'administrator' where role = 'main_moderator';
  update public.profiles set role = 'moderator'       where role = 'assistant_moderator';

  -- модераторская служба — сотрудники «Администрации»
  update public.profiles
     set organization_id = admin_org
   where role in ('administrator', 'moderator');

  -- у администратора организации быть не может: его сфера — вся система,
  -- а «Администрация» — это его рабочая площадка, как и у модераторов.
  -- (organization_id у administrator остаётся = admin_org: он её глава.)
  update public.profiles
     set organization_id = null
   where role = 'super_admin';
end $$;

-- ---------- 3. Хелперы под новые роли ----------
create or replace function public.is_moderator() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.current_role() in ('super_admin','administrator','moderator'), false)
$$;

-- «ответственный»: смена роли/организации, сброс пароля. Теперь это администратор и супер.
create or replace function public.is_responsible() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.current_role() in ('super_admin','administrator'), false)
$$;

-- проверяет очередь: администратор и модератор
create or replace function public.can_moderate() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.current_role() in ('super_admin','administrator','moderator'), false)
$$;

-- снимать с публикации и управлять приоритетом может администратор и супер
create or replace function public.is_chief() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.current_role() in ('super_admin','administrator'), false)
$$;

-- системная организация: её нельзя удалять и в ней особые правила
create or replace function public.admin_org_id() returns uuid
language sql immutable as $$
  select '00000000-0000-0000-0000-000000000001'::uuid
$$;

create or replace function public.is_admin_org(target uuid) returns boolean
language sql immutable as $$
  select target = '00000000-0000-0000-0000-000000000001'::uuid
$$;

revoke all on function public.can_moderate() from public;
revoke all on function public.admin_org_id() from public;
revoke all on function public.is_admin_org(uuid) from public;
grant execute on function public.can_moderate() to anon, authenticated;
grant execute on function public.admin_org_id() to authenticated;
grant execute on function public.is_admin_org(uuid) to authenticated;

-- ---------- 4. Гварды: новые роли в переходах ----------
create or replace function public.guard_post_update() returns trigger
language plpgsql security definer set search_path = public as $$
declare r public.user_role := public.current_role();
begin
  if new.status = old.status and new.is_featured = old.is_featured
     and new.priority_weight = old.priority_weight then
    return new;
  end if;

  if (new.is_featured <> old.is_featured or new.priority_weight <> old.priority_weight
        or new.campuses <> old.campuses or new.institutes <> old.institutes
        or new.directions <> old.directions) and not public.is_chief() then
    raise exception 'менять приоритет/аудиторию может только администратор';
  end if;

  if new.status <> old.status then
    if r = 'moderator' then
      if not (old.status = 'pending_review' and new.status in ('reviewed_ready','rejected')) then
        raise exception 'модератор проверяет только посты на модерации';
      end if;
    elsif r = 'administrator' then
      if new.status = 'published' then
        raise exception 'публикует автор поста, а не модератор';
      end if;
      if not ((old.status = 'pending_review' and new.status in ('reviewed_ready','rejected'))
           or (old.status = 'published' and new.status = 'withdrawn')) then
        raise exception 'администратор проверяет и снимает с публикации';
      end if;
    elsif r in ('org_admin','org_member') then
      if old.organization_id <> public.current_org_id() then
        raise exception 'нет доступа к чужой организации';
      end if;
      if r = 'org_member' and old.author_id is distinct from auth.uid() then
        raise exception 'сотрудник может менять только свои посты';
      end if;
      if not (
           (old.status = 'draft' and new.status = 'pending_review')
        or (old.status = 'rejected' and new.status in ('draft','pending_review'))
        or (old.status = 'withdrawn' and new.status in ('draft','pending_review'))
        or (old.status = 'pending_review' and new.status = 'draft')
        or (old.status = 'reviewed_ready' and new.status in ('published','draft'))
        or (old.status = 'published' and new.status = 'draft')) then
        raise exception 'недопустимый переход статуса';
      end if;
      if new.status = 'published' and not public.can_author_publish(old) then
        raise exception 'публиковать может глава организации или сотрудник с разрешением';
      end if;
      if old.status = 'published' and new.status = 'draft' and not public.can_author_withdraw(old) then
        raise exception 'отзывать публикацию может глава или сотрудник с разрешением';
      end if;
    elsif r = 'super_admin' then
      null;
    else
      raise exception 'недостаточно прав для смены статуса';
    end if;
  end if;

  if old.status = 'published' and new.status <> 'published' then
    new.is_featured := false;
  end if;
  if new.status = 'published' and old.status <> 'published' then
    new.published_at := now();
  end if;
  return new;
end $$;

-- ---------- 5. Организации: администратор управляет обычными ----------
-- Через org_write администратор получит право CRUD, кроме системной организации
-- (её трогает только супер-админ).
drop policy if exists org_write on public.organizations;
create policy org_write on public.organizations for all to authenticated
using (
  public.current_role() = 'super_admin'
  or (public.current_role() = 'administrator' and not public.is_admin_org(id))
  or (public.current_role() = 'org_admin' and id = public.current_org_id() and not public.is_admin_org(id))
)
with check (
  public.current_role() = 'super_admin'
  or (public.current_role() = 'administrator' and not public.is_admin_org(id))
  or (public.current_role() = 'org_admin' and id = public.current_org_id() and not public.is_admin_org(id))
);

-- ---------- 6. Профили: администратор управляет модераторами и главами организаций ----------
create or replace function public.manages_profile(target_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles p
     where p.id = target_id
       and not public.is_admin_org(p.organization_id)
       and public.current_role() = 'administrator'
  ) or exists (
    select 1 from public.profiles p
     where p.id = target_id
       and p.organization_id = public.current_org_id()
       and not public.is_admin_org(p.organization_id)
       and public.current_role() = 'org_admin'
  ) or exists (
    select 1 from public.profiles p
     where p.id = target_id
       and public.is_admin_org(p.organization_id)
       and public.current_role() = 'administrator'
       and p.role <> 'administrator'
  )
$$;

grant execute on function public.manages_profile(uuid) to authenticated;
