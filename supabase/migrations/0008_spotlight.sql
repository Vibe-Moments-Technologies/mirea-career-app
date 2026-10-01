-- 0008_spotlight.sql
-- Витрина главной — отдельная сущность, а не выборка приоритетных постов.
--
-- Почему отдельная таблица: витрина это редакционный блок («новости и важная
-- информация»), его наполняет администратор в консоли. Раньше он собирался из
-- постов с is_featured, из-за чего был жёстко привязан к карточкам: чтобы
-- поставить баннер, модератору приходилось помечать приоритетным обычный пост,
-- и тот всплывал в ленте.
--
-- Теперь: spotlight_banners — самостоятельный список слайдов. Посты к нему
-- отношения не имеют, приоритет (is_featured) влияет только на порядок в ленте.

create table if not exists public.spotlight_banners (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  subtitle    text,
  image_url   text,
  link_url    text,
  sort_order  integer not null default 0,
  is_active   boolean not null default true,
  starts_at   timestamptz,
  ends_at     timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists spotlight_banners_active_idx
  on public.spotlight_banners (is_active, sort_order);

alter table public.spotlight_banners enable row level security;

-- Чтение: активные баннеры видны всем (приложение работает анонимно).
drop policy if exists spotlight_read on public.spotlight_banners;
create policy spotlight_read on public.spotlight_banners
  for select using (
    is_active
    and (starts_at is null or starts_at <= now())
    and (ends_at is null or ends_at >= now())
  );

-- Запись: только главный модератор. Роль берётся из profiles, как в остальных
-- таблицах (см. 0002_rls.sql); при отсутствии профиля — запрещено.
drop policy if exists spotlight_write on public.spotlight_banners;
create policy spotlight_write on public.spotlight_banners
  for all to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'main_moderator'
    )
  )
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'main_moderator'
    )
  );

grant select on public.spotlight_banners to anon, authenticated;

-- Демо-слайды: те же обложки, что были у приоритетных постов, но теперь это
-- самостоятельные записи витрины.
insert into public.spotlight_banners (title, subtitle, image_url, sort_order, is_active)
select * from (values
  (
    'Осенняя ярмарка вакансий',
    'Более 60 компаний на одной площадке',
    'https://rpmsjribjsrmnithqvap.supabase.co/storage/v1/object/public/media/images/career-fair.png',
    10, true
  ),
  (
    'Хакатон MIREA Tech',
    '48 часов на прототип, призовой фонд 500 000 ₽',
    'https://rpmsjribjsrmnithqvap.supabase.co/storage/v1/object/public/media/images/hackathon.png',
    20, true
  ),
  (
    'День открытых дверей',
    'Экскурсии по лабораториям и встречи с деканами',
    'https://rpmsjribjsrmnithqvap.supabase.co/storage/v1/object/public/media/images/open-day.png',
    30, true
  )
) as v(title, subtitle, image_url, sort_order, is_active)
where not exists (select 1 from public.spotlight_banners);
