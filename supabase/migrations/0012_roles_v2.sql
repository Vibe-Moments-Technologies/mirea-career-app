-- 0012_roles_v2.sql — новая иерархия ролей и системная организация «Администрация».
--
-- ВАЖНО: применяется в ДВА захода. Postgres не даёт использовать новое значение
-- enum в той же транзакции, где оно создано, поэтому:
--   заход 1 (0012_roles_v2.sql)   — создать значения и организацию;
--   заход 2 (0013_roles_migrate.sql) — перенести людей и переключить права.
--
-- Ренейм:
--   main_moderator      → administrator  («Администратор»)
--   assistant_moderator → moderator      («Модератор»)
--   super_admin         — без изменений: доступ ко всему без исключений.

-- ---------- 1. Новые значения ролей ----------
alter type public.user_role add value if not exists 'administrator';
alter type public.user_role add value if not exists 'moderator';

-- ---------- 2. Особый тип организации ----------
alter type public.org_type add value if not exists 'administration';

-- ---------- 3. Системная организация «Администрация» ----------
insert into public.organizations (id, name, type, description)
values ('00000000-0000-0000-0000-000000000001', 'Администрация', 'administration',
        'Модераторская служба вуза: проверка карточек, публикации, работа с организациями.')
on conflict (id) do update set name = excluded.name, type = excluded.type, description = excluded.description;
