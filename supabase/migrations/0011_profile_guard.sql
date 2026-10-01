-- 0011_profile_guard.sql — охранник профиля: кто что меняет. Идемпотентно.
--
-- Правила:
--   * роль и организацию меняет ТОЛЬКО ответственный (главный модератор / супер-админ);
--   * права подчинённого (can_publish/can_withdraw/can_delete_posts) и активность
--     меняет начальник своей организации — или ответственный;
--   * сам сотрудник правит личные поля (ФИО, контакты) и НЕ может выдать себе права
--     или «оживить» себя после деактивации;
--   * деактивированный сотрудник не работает в админке: RLS не пустит его к данным,
--     но свой профиль он видеть может (чтобы экран сказал «доступ приостановлен»).

create or replace function public.guard_profile_update() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  me public.user_role := public.current_role();
  is_self boolean := (old.id = auth.uid());
  is_boss boolean := public.manages_profile(old.id);
  is_resp boolean := public.is_responsible();
begin
  -- 1) Роль и организация — только ответственный.
  if (new.role <> old.role or new.organization_id is distinct from old.organization_id)
     and not is_resp then
    raise exception 'роль и организацию назначает только ответственный';
  end if;

  -- 2) «Обезопасить» роль: не-ответственный не может выдать роль выше своей ступени.
  if new.role <> old.role and is_resp then
    if new.role in ('super_admin') and me <> 'super_admin' then
      raise exception 'супер-админа назначает только супер-админ';
    end if;
  end if;

  -- 3) Разрешения и активность — начальник или ответственный (не сам сотрудник).
  if (new.can_publish <> old.can_publish
      or new.can_withdraw <> old.can_withdraw
      or new.can_delete_posts <> old.can_delete_posts
      or new.is_active <> old.is_active
      or new.must_change_password <> old.must_change_password)
     and not (is_boss or is_resp) then
    raise exception 'разрешения и активность сотрудника меняет начальник';
  end if;

  -- 4) Свой профиль: только личные поля, никаких самовыданных прав.
  if is_self then
    if new.role <> old.role
       or new.organization_id is distinct from old.organization_id then
      raise exception 'свою роль и организацию менять нельзя';
    end if;
    if new.is_active <> old.is_active then
      raise exception 'активность меняет начальник';
    end if;
  end if;

  -- 5) Проставляем completed-флаг автоматически: заполнены ФИО и контакт.
  --    Сотрудник не может «отменить» заполненность профиля.
  if old.profile_completed and not new.profile_completed and not (is_boss or is_resp) then
    new.profile_completed := true;
  end if;

  return new;
end $$;

drop trigger if exists profiles_guard_update on public.profiles;
create trigger profiles_guard_update before update on public.profiles
  for each row execute function public.guard_profile_update();

-- ---------- Гранты: колонки, которые вообще разрешено писать ----------
-- Раньше грант был UPDATE на всю таблицу; сузим до реально нужных колонок.
revoke update on public.profiles from authenticated;
grant update (full_name, email, phone, position, contact_note, profile_completed)
  on public.profiles to authenticated;
grant update (can_publish, can_withdraw, can_delete_posts, is_active, must_change_password)
  on public.profiles to authenticated;
grant update (role, organization_id) on public.profiles to authenticated;

-- ---------- Деактивированный не читает данные (кроме своего профиля) ----------
-- ponytail: простое и надёжное правило — все «рабочие» политики требуют is_active.
create or replace function public.me_active() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_active from public.profiles where id = auth.uid()), false)
$$;
revoke all on function public.me_active() from public;
grant execute on function public.me_active() to authenticated;

drop policy if exists posts_select on public.posts;
create policy posts_select on public.posts for select
using (
  (status = 'published' and published_at <= now())
  or public.is_moderator()
  or (auth.role() = 'authenticated' and public.me_active() and (
        (public.current_role() = 'org_admin' and organization_id = public.current_org_id())
        or (public.current_role() = 'org_member'
            and organization_id = public.current_org_id()
            and author_id = auth.uid())
        or public.is_responsible()
     ))
);

drop policy if exists posts_update on public.posts;
create policy posts_update on public.posts for update to authenticated
using (
  public.me_active() and (
    public.is_moderator()
    or (public.current_role() = 'org_admin' and organization_id = public.current_org_id())
    or (public.current_role() = 'org_member' and organization_id = public.current_org_id()
        and author_id = auth.uid())
  )
)
with check (
  public.me_active() and (
    public.is_moderator()
    or (public.current_role() = 'org_admin' and organization_id = public.current_org_id())
    or (public.current_role() = 'org_member' and organization_id = public.current_org_id()
        and author_id = auth.uid())
  )
);

drop policy if exists posts_delete on public.posts;
create policy posts_delete on public.posts for delete to authenticated
using (public.me_active() and (public.is_chief() or public.can_author_delete_row(id)));

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
using (id = auth.uid() or public.me_active());
