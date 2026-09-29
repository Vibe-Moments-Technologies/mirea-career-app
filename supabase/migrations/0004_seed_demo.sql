-- 0004_seed_demo.sql — демо-организации и посты. Идемпотентно (фикс. UUID, on conflict).

-- ---------- Организации ----------
insert into public.organizations (id, name, type, description, logo_url) values
  ('11111111-1111-1111-1111-111111111101','Карьерный центр РТУ МИРЭА','university_dept',
   'Центр трудоустройства и практики студентов. Ярмарки вакансий, стажировки, дни карьеры.','https://placehold.co/128x128/png?text=CC'),
  ('11111111-1111-1111-1111-111111111102','Кафедра информационных технологий','university_dept',
   'Мероприятия, олимпиады и научные кружки кафедры ИТ.','https://placehold.co/128x128/png?text=IT'),
  ('11111111-1111-1111-1111-111111111103','Студенческий клуб','university_dept',
   'Творчество, спорт, волонтёрство и студенческая жизнь.','https://placehold.co/128x128/png?text=SC'),
  ('11111111-1111-1111-1111-111111111104','Яндекс','partner',
   'Технологическая компания: стажировки, вакансии, кейс-чемпионаты.','https://placehold.co/128x128/png?text=Y'),
  ('11111111-1111-1111-1111-111111111105','Сбер','partner',
   'Экосистема: ИТ-стажировки, аналитика, разработка.','https://placehold.co/128x128/png?text=S'),
  ('11111111-1111-1111-1111-111111111106','VK','partner',
   'Социальные технологии, продуктовые стажировки и олимпиады.','https://placehold.co/128x128/png?text=VK')
on conflict (id) do update set name = excluded.name, description = excluded.description, logo_url = excluded.logo_url;

-- ---------- Посты ----------
-- helper-синтаксис: значения вставляются, on conflict по id — update контента.
insert into public.posts
  (id, organization_id, author_id, title, description, type, format, external_link, image_url,
   event_date, campuses, institutes, directions, tags, is_featured, priority_weight, status, published_at)
values
 -- опубликованные, приоритетные
 ('22222222-2222-2222-2222-222222222201','11111111-1111-1111-1111-111111111101',null,
  'Осенняя ярмарка вакансий РТУ МИРЭА',
  'Более 80 компаний-партнёров, экспресс-собеседования и мастер-классы. Возьмите резюме!','event','offline',
  'https://mirea.ru/career-fair','https://placehold.co/800x450/png?text=Career+Fair',
  (current_date + 12),'{vernadsky78,vernadsky86}','{}','{any}','{карьера,ярмарка,стажировка}',true,100,'published', now() - interval '2 day'),

 ('22222222-2222-2222-2222-222222222202','11111111-1111-1111-1111-111111111104',null,
  'Стажировка в Яндексе: бэкенд-разработка',
  'Оплачиваемая стажировка для 3+ курса. Python/Go, реальная продуктовая команда, ментор.','internship','hybrid',
  'https://yandex.ru/internship','https://placehold.co/800x450/png?text=Yandex+Intern',
  (current_date + 30),'{}','{iit}','{bachelor,master}','{it,разработка,стажировка}',true,90,'published', now() - interval '1 day'),

 -- опубликованные обычные
 ('22222222-2222-2222-2222-222222222203','11111111-1111-1111-1111-111111111102',null,
  'Хакатон «Код Будущего»',
  '48 часов, командная разработка, призы от партнёров. Регистрация команд открыта.','event','offline',
  'https://mirea.ru/hackathon','https://placehold.co/800x450/png?text=Hackathon',
  (current_date + 20),'{vernadsky78}','{iit,iii}','{any}','{it,хакатон,разработка}',false,0,'published', now() - interval '3 day'),

 ('22222222-2222-2222-2222-222222222204','11111111-1111-1111-1111-111111111105',null,
  'Аналитик данных в Сбер (junior)',
  'Полная занятость, Москва. SQL, Python, основы статистики. Готовы рассматривать студентов старших курсов.','vacancy','offline',
  'https://sber.ru/jobs/analyst','https://placehold.co/800x450/png?text=Sber+Job',
  null,'{}','{}','{any}','{аналитика,работа,данные}',false,0,'published', now() - interval '4 day'),

 ('22222222-2222-2222-2222-222222222205','11111111-1111-1111-1111-111111111103',null,
  'Волонтёрская программа: помогать просто',
  'Набор волонтёров на социальные и экологические проекты. Гибкий график, сертификаты.','event','offline',
  'https://mirea.ru/volunteers','https://placehold.co/800x450/png?text=Volunteer',
  (current_date + 7),'{vernadsky78,vernadsky86,stromynka}','{}','{any}','{волонтёрство,общество}',false,0,'published', now() - interval '5 day'),

 ('22222222-2222-2222-2222-222222222206','11111111-1111-1111-1111-111111111106',null,
  'Олимпиада VK по алгоритмам',
  'Индивидуальное и командное участие, задачи разного уровня, призы и fast-track на стажировку.','event','online',
  'https://vk.com/olymp','https://placehold.co/800x450/png?text=VK+Olymp',
  (current_date + 15),'{}','{iit}','{bachelor}','{it,алгоритмы,олимпиада}',false,0,'published', now() - interval '6 day'),

 ('22222222-2222-2222-2222-222222222207','11111111-1111-1111-1111-111111111101',null,
  'Стипендия Президента РФ для IT-направлений',
  'Конкурс на назначение повышенной стипендии. Требуется портфолио достижений.','scholarship','online',
  'https://mirea.ru/scholarship','https://placehold.co/800x450/png?text=Scholarship',
  (current_date + 45),'{}','{iit,iii,itht}','{bachelor,master}','{стипендия,it,наука}',false,0,'published', now() - interval '7 day'),

 ('22222222-2222-2222-2222-222222222208','11111111-1111-1111-1111-111111111102',null,
  'Лекторий: как пройти собеседование в FAANG',
  'Открытая лекция от выпускников кафедры. Разбор реальных задач и поведенческих вопросов.','event','offline',
  'https://mirea.ru/lecture','https://placehold.co/800x450/png?text=Lecture',
  (current_date + 3),'{vernadsky78}','{iit}','{any}','{карьера,лекция,it}',false,0,'published', now() - interval '8 day'),

 -- неопубликованные (для демонстрации модерации)
 ('22222222-2222-2222-2222-222222222209','11111111-1111-1111-1111-111111111104',null,
  'День карьеры Яндекса в МИРЭА',
  'Экскурсия по технологиям, стенды команд, розыгрыш мерча. Ждём студентов всех курсов.','event','offline',
  'https://yandex.ru/career-day','https://placehold.co/800x450/png?text=Yandex+Day',
  (current_date + 25),'{vernadsky78}','{iit,iii}','{any}','{карьера,it,событие}',false,0,'pending_review', null),

 ('22222222-2222-2222-2222-22222222220a','11111111-1111-1111-1111-111111111105',null,
  'Продуктовая стажировка в Сбере',
  'Для студентов 3-4 курса направлений экономика и IT. Гибрид, наставник, реальные задачи.','internship','hybrid',
  'https://sber.ru/intern','https://placehold.co/800x450/png?text=Sber+Intern',
  (current_date + 40),'{}','{iit,itht}','{bachelor}','{стажировка,продукт,it}',false,0,'reviewed_ready', null),

 ('22222222-2222-2222-2222-22222222220b','11111111-1111-1111-1111-111111111103',null,
  'Черновик: весенний фестиваль',
  'Заготовка анонса весеннего фестиваля студенческих клубов.','event','offline',
  null,'https://placehold.co/800x450/png?text=Draft',
  (current_date + 90),'{stromynka}','{}','{any}','{событие}',false,0,'draft', null)
on conflict (id) do update set
  title = excluded.title, description = excluded.description, type = excluded.type,
  format = excluded.format, external_link = excluded.external_link, image_url = excluded.image_url,
  event_date = excluded.event_date, campuses = excluded.campuses, institutes = excluded.institutes,
  directions = excluded.directions, tags = excluded.tags;
-- намеренно НЕ трогаем status/published_at/is_featured/priority_weight при повторном seed:
-- guard_post_update трактует смену featured не-главным как нарушение, а демо-состояние
-- модерации должно переживать перезапуск seed.
