-- 0008_role_model.sql — модель прав: публикует компания, модераторы проверяют.
-- Идемпотентно.
--
-- Что меняется против 0001–0007:
--   1) пост-статус `withdrawn` — «снят модерацией» (отзыв уже опубликованного),
--      в отличие от `rejected` («не прошёл проверку»). Пояснение обязательно в обоих.
--   2) права подчинённого — три раздельных флага, выдаёт и снимает начальник.
--   3) публикует компания (автор сам), а не главный модератор: `reviewed_ready`
--      теперь значит «одобрено модератором, ждёт публикации автором».
--   4) профиль: активация (деактивация начальником), принудительная смена пароля,
--      контакты, которые заполняет сам сотрудник при старте.
--
-- Роли остаются прежними (super_admin, main_moderator, assistant_moderator,
-- org_admin, org_member): «ответственный» = главный модератор и супер-админ,
-- проверяется функцией public.is_chief().

-- ---------- 1. Статус «снят модерацией» ----------
do $$ begin
  alter type public.post_status add value if not exists 'withdrawn';
exception when duplicate_object then null; end $$;

-- ---------- 2. Права подчинённых и поля профиля ----------
alter table public.profiles add column if not exists can_publish     boolean not null default false;
alter table public.profiles add column if not exists can_withdraw    boolean not null default false;
alter table public.profiles add column if not exists can_delete_posts boolean not null default false;

-- деактивация: начальник «приостанавливает» сотрудника, вход запрещён
alter table public.profiles add column if not exists is_active       boolean not null default true;
-- принудительная смена пароля после сброса супер-админом
alter table public.profiles add column if not exists must_change_password boolean not null default false;
-- стартовая настройка: сотрудник обязан заполнить профиль перед работой
alter table public.profiles add column if not exists profile_completed boolean not null default false;

-- контакты, которые заполняет сам сотрудник (начальник при создании даёт только ФИО и почту)
alter table public.profiles add column if not exists email        text;
alter table public.profiles add column if not exists phone        text;
alter table public.profiles add column if not exists position     text;
alter table public.profiles add column if not exists contact_note text;

-- ---------- 3. Хелперы прав ----------

-- начальник организации или ответственный (главный модератор / супер-админ)
create or replace function public.is_org_admin_of(target_org uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and (
    public.current_role() = 'super_admin'
    or (public.current_role() = 'org_admin' and public.current_org_id() = target_org)
  )
$$;

-- «ответственный»: меняет администратора организации и сбрасывает пароли
create or replace function public.is_responsible() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.current_role() in ('super_admin','main_moderator'), false)
$$;

-- начальник управляет этим профилем (свой сотрудник в его организации)
create or replace function public.manages_profile(target_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles p
     where p.id = target_id
       and public.is_org_admin_of(p.organization_id)
       and target_id <> auth.uid()
  )
$$;

-- право автора на публикацию: начальник — всегда, подчинённый — по флагу
create or replace function public.can_author_publish(p public.posts) returns boolean
language sql stable security definer set search_path = public as $$
  select case public.current_role()
    when 'super_admin' then true
    when 'org_admin'   then p.organization_id = public.current_org_id()
    when 'org_member'  then p.organization_id = public.current_org_id()
                            and coalesce((select can_publish from public.profiles where id = auth.uid()), false)
    else false
  end
$$;

create or replace function public.can_author_withdraw(p public.posts) returns boolean
language sql stable security definer set search_path = public as $$
  select case public.current_role()
    when 'super_admin' then true
    when 'org_admin'   then p.organization_id = public.current_org_id()
    when 'org_member'  then p.organization_id = public.current_org_id()
                            and coalesce((select can_withdraw from public.profiles where id = auth.uid()), false)
    else false
  end
$$;

create or replace function public.can_author_delete(p public.posts) returns boolean
language sql stable security definer set search_path = public as $$
  select case public.current_role()
    when 'super_admin' then true
    when 'org_admin'   then p.organization_id = public.current_org_id()
    when 'org_member'  then p.organization_id = public.current_org_id()
                            and coalesce((select can_delete_posts from public.profiles where id = auth.uid()), false)
    else false
  end
$$;

revoke all on function public.is_org_admin_of(uuid) from public;
revoke all on function public.is_responsible() from public;
revoke all on function public.manages_profile(uuid) from public;
revoke all on function public.can_author_publish(public.posts) from public;
revoke all on function public.can_author_withdraw(public.posts) from public;
revoke all on function public.can_author_delete(public.posts) from public;
grant execute on function public.is_org_admin_of(uuid)          to authenticated;
grant execute on function public.is_responsible()               to authenticated;
grant execute on function public.manages_profile(uuid)          to authenticated;
grant execute on function public.can_author_publish(public.posts)  to authenticated;
grant execute on function public.can_author_withdraw(public.posts) to authenticated;
grant execute on function public.can_author_delete(public.posts)   to authenticated;
