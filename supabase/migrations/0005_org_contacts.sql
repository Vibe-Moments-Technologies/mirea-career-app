-- 0005_org_contacts.sql — контакты организаций для профиля организатора.
--
-- Зачем: студент видит предложение, но не понимает, кто за ним стоит.
-- Профиль организации даёт описание, контакты и все её публикации.
-- Идемпотентно.

alter table public.organizations add column if not exists website text;
alter table public.organizations add column if not exists contact_email text;
alter table public.organizations add column if not exists contact_phone text;
alter table public.organizations add column if not exists contact_name text;

-- Контакты читает кто угодно (анонимный просмотр) — это публичные данные
-- подразделения/компании, а не персональные данные сотрудника.
grant select on public.organizations to anon, authenticated;

-- placehold.co отдаёт 403 из мобильного клиента, и на месте логотипа мигал
-- серый квадрат. Логотипы убраны совсем: интерфейс рисует букву организации
-- (core/widgets/post_image.dart), а битый URL в данных не нужен.
update public.organizations set logo_url = null where logo_url like '%placehold.co%';

-- ---------- Картинки постов ----------
-- Часть постов осталась с placehold.co (seed применялся до того, как ссылки
-- заменили на Storage), и такие карточки показывали серую заглушку вместо
-- фото — «то есть картинка, то нет». Раздаём шесть реальных изображений
-- по смыслу типа поста. Идемпотентно: берём только битые ссылки.
with base as (
  select 'https://rpmsjribjsrmnithqvap.supabase.co/storage/v1/object/public/media/images/' as u
),
pick as (
  select id, type,
    case type
      when 'event'       then (array['career-fair','open-day','lecture'])[1 + (row_number() over (partition by type order by id) - 1) % 3]
      when 'vacancy'     then (array['internship','lecture'])[1 + (row_number() over (partition by type order by id) - 1) % 2]
      when 'internship'  then (array['internship','chemistry-lab'])[1 + (row_number() over (partition by type order by id) - 1) % 2]
      when 'project'     then (array['hackathon','chemistry-lab'])[1 + (row_number() over (partition by type order by id) - 1) % 2]
      when 'scholarship' then 'lecture'
      else 'career-fair'
    end as img
  from public.posts
  where image_url like '%placehold.co%'
)
update public.posts p
set image_url = base.u || pick.img || '.png'
from pick, base
where p.id = pick.id;

-- ---------- Демо-контакты ----------
update public.organizations set
  website = 'https://mirea.ru/career',
  contact_email = 'career@mirea.ru',
  contact_phone = '+7 (499) 215-65-65',
  contact_name = 'Карьерный центр'
where id = '11111111-1111-1111-1111-111111111101';

update public.organizations set
  website = 'https://mirea.ru',
  contact_email = 'it@mirea.ru',
  contact_name = 'Учебный офис кафедры'
where id = '11111111-1111-1111-1111-111111111102';

update public.organizations set
  website = 'https://mirea.ru/studlife',
  contact_email = 'club@mirea.ru',
  contact_name = 'Студенческий клуб'
where id = '11111111-1111-1111-1111-111111111103';

update public.organizations set
  website = 'https://yandex.ru/yaintern',
  contact_email = 'interns@yandex-team.ru',
  contact_name = 'Рекрутинг-команда'
where id = '11111111-1111-1111-1111-111111111104';

update public.organizations set
  website = 'https://sber.ru/careers',
  contact_email = 'graduates@sberbank.ru',
  contact_name = 'Молодёжные программы'
where id = '11111111-1111-1111-1111-111111111105';

update public.organizations set
  website = 'https://team.vk.company',
  contact_email = 'intern@vk.team',
  contact_name = 'Early Careers'
where id = '11111111-1111-1111-1111-111111111106';