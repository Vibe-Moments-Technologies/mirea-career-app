-- 0015_profile_guard_roles.sql — роль и организацию меняет ответственный.
--
-- Проблема: guard_profile_update разрешал смену роли/организации только
-- super_admin, хотя по матрице (DATABASE.md §3) это право ответственного —
-- administrator и super_admin. Администратор не мог вести модераторов.
--
-- Правила:
--   1. Роль и организацию меняет только ответственный.
--   2. Роль super_admin назначает/снимает только супер; администратора
--      трогает только супер (назначить, снять, перевести).
--   3. Свою роль/организацию менять нельзя никому, кроме супера.
-- Остальные поля (права-флаги, активность, контакты) — как раньше, их решают
-- RLS-политики и остальные гварды.
create or replace function public.guard_profile_update() returns trigger
language plpgsql security definer set search_path = public as $$
declare me public.user_role := public.current_role();
begin
  if (new.role <> old.role or new.organization_id is distinct from old.organization_id)
     and not public.is_responsible() then
    raise exception 'Роль и организацию назначает только ответственный (администратор или супер-админ)';
  end if;

  if (new.role in ('super_admin', 'administrator') or old.role in ('super_admin', 'administrator'))
     and me <> 'super_admin' then
    raise exception 'Роль супер-админа и администратора меняет только супер-админ';
  end if;

  if (new.role <> old.role or new.organization_id is distinct from old.organization_id)
     and new.id = auth.uid() and me <> 'super_admin' then
    raise exception 'Свою роль и организацию менять нельзя';
  end if;

  return new;
end $$;

drop trigger if exists profiles_guard_update on public.profiles;
create trigger profiles_guard_update before update on public.profiles
  for each row execute function public.guard_profile_update();
