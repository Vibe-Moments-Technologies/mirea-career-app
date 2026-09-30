-- 0004_seed_demo.sql — демо-организации и посты. Идемпотентно (фикс. UUID, on conflict).
--
-- Картинки постов сгенерированы моделью (buytokens/qwen-image) и лежат
-- в Supabase Storage (bucket media, images/). Это реальные фото, а не
-- placehold.co — лента выглядит живой. У постов без картинки image_url = null:
-- карточка рисует буквенную заглушку (core/widgets/post_image.dart).

-- ---------- Картинки (публичные URL из Storage) ----------
-- \set не работает в этом контексте, поэтому URL подставляются напрямую.
-- При пересоздании проекта картинки нужно загрузить заново (scripts/upload-images.js).

-- ---------- Организации ----------
-- logo_url = null: placehold.co отдаёт 403 из мобильного клиента, и вместо
-- логотипа мигал серый квадрат. Интерфейс рисует букву организации
-- (core/widgets/post_image.dart) — битая ссылка в данных не нужна.
insert into public.organizations (id, name, type, description, logo_url) values
  ('11111111-1111-1111-1111-111111111101','Карьерный центр РТУ МИРЭА','university_dept',
   'Центр трудоустройства и практики студентов. Ярмарки вакансий, стажировки, дни карьеры.',null),
  ('11111111-1111-1111-1111-111111111102','Кафедра информационных технологий','university_dept',
   'Мероприятия, олимпиады и научные кружки кафедры ИТ.',null),
  ('11111111-1111-1111-1111-111111111103','Студенческий клуб','university_dept',
   'Творчество, спорт, волонтёрство и студенческая жизнь.',null),
  ('11111111-1111-1111-1111-111111111104','Яндекс','partner',
   'Технологическая компания: стажировки, вакансии, кейс-чемпионаты.',null),
  ('11111111-1111-1111-1111-111111111105','Сбер','partner',
   'Экосистема: ИТ-стажировки, аналитика, разработка.',null),
  ('11111111-1111-1111-1111-111111111106','VK','partner',
   'Социальные технологии, продуктовые стажировки и олимпиады.',null)
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
  'https://mirea.ru/career-fair','https://rpmsjribjsrmnithqvap.supabase.co/storage/v1/object/public/media/images/career-fair.png',
  (current_date + 12),'{vernadsky78,vernadsky86}','{}','{any}','{карьера,ярмарка,стажировка}',true,100,'published', now() - interval '2 day'),

 ('22222222-2222-2222-2222-222222222202','11111111-1111-1111-1111-111111111104',null,
  'Стажировка в Яндексе: бэкенд-разработка',
  'Оплачиваемая стажировка для 3+ курса. Python/Go, реальная продуктовая команда, ментор.','internship','hybrid',
  'https://yandex.ru/internship','https://rpmsjribjsrmnithqvap.supabase.co/storage/v1/object/public/media/images/internship.png',
  (current_date + 30),'{}','{iit}','{bachelor,master}','{it,разработка,стажировка}',true,90,'published', now() - interval '1 day'),

 -- опубликованные обычные
 ('22222222-2222-2222-2222-222222222203','11111111-1111-1111-1111-111111111102',null,
  'Хакатон «Код Будущего»',
  '48 часов, командная разработка, призы от партнёров. Регистрация команд открыта.','event','offline',
  'https://mirea.ru/hackathon','https://rpmsjribjsrmnithqvap.supabase.co/storage/v1/object/public/media/images/hackathon.png',
  (current_date + 20),'{vernadsky78}','{iit,iii}','{any}','{it,хакатон,разработка}',false,0,'published', now() - interval '3 day'),

 ('22222222-2222-2222-2222-222222222204','11111111-1111-1111-1111-111111111105',null,
  'Аналитик данных в Сбер (junior)',
  'Полная занятость, Москва. SQL, Python, основы статистики. Готовы рассматривать студентов старших курсов.','vacancy','offline',
  'https://sber.ru/jobs/analyst','https://rpmsjribjsrmnithqvap.supabase.co/storage/v1/object/public/media/images/lecture.png',
  null,'{}','{}','{any}','{аналитика,работа,данные}',false,0,'published', now() - interval '4 day'),

 ('22222222-2222-2222-2222-222222222205','11111111-1111-1111-1111-111111111103',null,
  'Волонтёрская программа: помогать просто',
  'Набор волонтёров на социальные и экологические проекты. Гибкий график, сертификаты.','event','offline',
  'https://mirea.ru/volunteers','https://rpmsjribjsrmnithqvap.supabase.co/storage/v1/object/public/media/images/career-fair.png',
  (current_date + 7),'{vernadsky78,vernadsky86,stromynka}','{}','{any}','{волонтёрство,общество}',false,0,'published', now() - interval '5 day'),

 ('22222222-2222-2222-2222-222222222206','11111111-1111-1111-1111-111111111106',null,
  'Олимпиада VK по алгоритмам',
  'Индивидуальное и командное участие, задачи разного уровня, призы и fast-track на стажировку.','event','online',
  'https://vk.com/olymp','https://rpmsjribjsrmnithqvap.supabase.co/storage/v1/object/public/media/images/hackathon.png',
  (current_date + 15),'{}','{iit}','{bachelor}','{it,алгоритмы,олимпиада}',false,0,'published', now() - interval '6 day'),

 ('22222222-2222-2222-2222-222222222207','11111111-1111-1111-1111-111111111101',null,
  'Стипендия Президента РФ для IT-направлений',
  'Конкурс на назначение повышенной стипендии. Требуется портфолио достижений.','scholarship','online',
  'https://mirea.ru/scholarship','https://rpmsjribjsrmnithqvap.supabase.co/storage/v1/object/public/media/images/chemistry-lab.png',
  (current_date + 45),'{}','{iit,iii,itht}','{bachelor,master}','{стипендия,it,наука}',false,0,'published', now() - interval '7 day'),

 ('22222222-2222-2222-2222-222222222208','11111111-1111-1111-1111-111111111102',null,
  'Лекторий: как пройти собеседование в FAANG',
  'Открытая лекция от выпускников кафедры. Разбор реальных задач и поведенческих вопросов.','event','offline',
  'https://mirea.ru/lecture','https://rpmsjribjsrmnithqvap.supabase.co/storage/v1/object/public/media/images/lecture.png',
  (current_date + 3),'{vernadsky78}','{iit}','{any}','{карьера,лекция,it}',false,0,'published', now() - interval '8 day'),

 -- неопубликованные (для демонстрации модерации)
 ('22222222-2222-2222-2222-222222222209','11111111-1111-1111-1111-111111111104',null,
  'День карьеры Яндекса в РТУ МИРЭА',
  'Экскурсия по технологиям, стенды команд, розыгрыш мерча. Ждём студентов всех курсов.','event','offline',
  'https://yandex.ru/career-day','https://rpmsjribjsrmnithqvap.supabase.co/storage/v1/object/public/media/images/career-fair.png',
  (current_date + 25),'{vernadsky78}','{iit,iii}','{any}','{карьера,it,событие}',false,0,'pending_review', null),

 ('22222222-2222-2222-2222-22222222220a','11111111-1111-1111-1111-111111111105',null,
  'Продуктовая стажировка в Сбере',
  'Для студентов 3-4 курса направлений экономика и IT. Гибрид, наставник, реальные задачи.','internship','hybrid',
  'https://sber.ru/intern','https://rpmsjribjsrmnithqvap.supabase.co/storage/v1/object/public/media/images/internship.png',
  (current_date + 40),'{}','{iit,itht}','{bachelor}','{стажировка,продукт,it}',false,0,'reviewed_ready', null),

 ('22222222-2222-2222-2222-22222222220b','11111111-1111-1111-1111-111111111103',null,
  'Черновик: весенний фестиваль',
  'Заготовка анонса весеннего фестиваля студенческих клубов.','event','offline',
  null,null,
  (current_date + 90),'{stromynka}','{}','{any}','{событие}',false,0,'draft', null),

 -- ---------- дополнительные опубликованные: чтобы проверить подгрузку ----------
 ('22222222-2222-2222-2222-22222222220c','11111111-1111-1111-1111-111111111101',null,
  'День карьеры ИКБ и ИИИ',
  'Стенды компаний в области кибербезопасности и машинного обучения, разбор вакансий и стажировок.','event','offline',
  'https://mirea.ru/career-day-ikb','https://rpmsjribjsrmnithqvap.supabase.co/storage/v1/object/public/media/images/hackathon.png',
  (current_date + 9),'{vernadsky78}','{ikb,iii}','{bachelor,specialist,master}','{карьера,безопасность,it}',false,20,'published', now() - interval '9 hour'),

 ('22222222-2222-2222-2222-22222222220d','11111111-1111-1111-1111-111111111104',null,
  'Стажировка: инженер данных',
  'Работа с потоковыми данными, Python и SQL. Гибрид, ментор, возможен оффер для выпускников.','internship','hybrid',
  'https://yandex.ru/jobs/data','https://rpmsjribjsrmnithqvap.supabase.co/storage/v1/object/public/media/images/internship.png',
  (current_date + 21),'{}','{iit,iptip}','{bachelor,master,graduate}','{it,данные,стажировка}',false,10,'published', now() - interval '8 hour'),

 ('22222222-2222-2222-2222-22222222220e','11111111-1111-1111-1111-111111111102',null,
  'Лекторий ИТУ: управление проектами',
  'Открытая лекция для студентов ИТУ и всех желающих. Разбираем реальные кейсы управления командами.','event','offline',
  'https://mirea.ru/pm-lecture','https://rpmsjribjsrmnithqvap.supabase.co/storage/v1/object/public/media/images/lecture.png',
  (current_date + 5),'{vernadsky86}','{itu}','{bachelor,specialist,master}','{карьера,менеджмент,лекция}',false,0,'published', now() - interval '7 hour'),

 ('22222222-2222-2222-2222-22222222220f','11111111-1111-1111-1111-111111111105',null,
  'Абитуриентам: день открытых дверей ИПТИП',
  'Знакомство с направлениями института, лабораториями и правилами приёма. Ответы на вопросы.','event','offline',
  'https://mirea.ru/open-day','https://rpmsjribjsrmnithqvap.supabase.co/storage/v1/object/public/media/images/open-day.png',
  (current_date + 14),'{vernadsky78}','{iptip}','{applicant}','{абитуриент,поступление,событие}',false,15,'published', now() - interval '6 hour'),

 ('22222222-2222-2222-2222-222222222210','11111111-1111-1111-1111-111111111106',null,
  'Вакансия: инженер-электроник',
  'Разработка и отладка радиоэлектронных модулей. Для выпускников ИРИ и ИТХТ.','vacancy','offline',
  'https://vk.com/jobs/electronics','https://rpmsjribjsrmnithqvap.supabase.co/storage/v1/object/public/media/images/internship.png',
  null,'{}','{iri,itht}','{specialist,master,graduate}','{работа,электроника,инженерия}',false,0,'published', now() - interval '5 hour'),

 ('22222222-2222-2222-2222-222222222211','11111111-1111-1111-1111-111111111103',null,
  'Научный кружок ИТХТ: химия полимеров',
  'Набор студентов в научную группу. Работа в лаборатории, публикации, поддержка на конкурсах.','project','offline',
  'https://mirea.ru/polymer','https://rpmsjribjsrmnithqvap.supabase.co/storage/v1/object/public/media/images/chemistry-lab.png',
  (current_date + 18),'{vernadsky86}','{itht}','{bachelor,specialist}','{наука,химия,проект}',false,0,'published', now() - interval '4 hour'),

 ('22222222-2222-2222-2222-222222222212','11111111-1111-1111-1111-111111111101',null,
  'Стажировка в карьерном центре',
  'Помощь в организации ярмарок вакансий, работа с компаниями-партнёрами. Для всех институтов.','internship','offline',
  'https://mirea.ru/career-intern','https://rpmsjribjsrmnithqvap.supabase.co/storage/v1/object/public/media/images/career-fair.png',
  (current_date + 10),'{vernadsky78,vernadsky86}','{}','{bachelor,specialist,master}','{стажировка,карьера,организация}',false,0,'published', now() - interval '3 hour'),

 ('22222222-2222-2222-2222-222222222213','11111111-1111-1111-1111-111111111102',null,
  'Курс для преподавателей: цифровые инструменты',
  'Повышение квалификации для преподавателей всех институтов. Практика работы с современными платформами.','event','online',
  'https://mirea.ru/teacher-course','https://rpmsjribjsrmnithqvap.supabase.co/storage/v1/object/public/media/images/lecture.png',
  (current_date + 30),'{}','{}','{teacher}','{образование,курс,цифровые}',false,0,'published', now() - interval '2 hour'),

 ('22222222-2222-2222-2222-222222222214','11111111-1111-1111-1111-111111111104',null,
  'Стипендия для выпускников ИКБ',
  'Программа поддержки выпускников по направлению кибербезопасности при поступлении в магистратуру.','scholarship','online',
  'https://mirea.ru/scholarship-ikb','https://rpmsjribjsrmnithqvap.supabase.co/storage/v1/object/public/media/images/chemistry-lab.png',
  (current_date + 50),'{}','{ikb}','{graduate,master}','{стипендия,безопасность,магистратура}',false,0,'published', now() - interval '1 hour'),

 ('22222222-2222-2222-2222-222222222215','11111111-1111-1111-1111-111111111106',null,
  'Кейс-чемпионат КПК: защита данных',
  'Командный чемпионат для студентов колледжа. Практические задачи по защите информации, призы от партнёров.','event','hybrid',
  'https://vk.com/case-cup','https://rpmsjribjsrmnithqvap.supabase.co/storage/v1/object/public/media/images/hackathon.png',
  (current_date + 11),'{stromynka}','{kpk}','{specialist}','{кейс,безопасность,чемпионат}',false,0,'published', now() - interval '30 minute'),

 ('22222222-2222-2222-2222-222222222216','11111111-1111-1111-1111-111111111101',null,
  'Передовая инженерная школа: набор в проекты',
  'ПИШ приглашает студентов в инженерные проекты с индустриальными партнёрами. Есть оплата и наставники.','project','offline',
  'https://mirea.ru/pish','https://rpmsjribjsrmnithqvap.supabase.co/storage/v1/object/public/media/images/open-day.png',
  (current_date + 25),'{vernadsky78}','{pish,iptip}','{bachelor,specialist,master}','{инженерия,проект,наука}',false,0,'published', now() - interval '20 minute'),

 ('22222222-2222-2222-2222-222222222217','11111111-1111-1111-1111-111111111103',null,
  'Мероприятия филиала во Фрязино',
  'Встреча студентов филиала с работодателями наукограда. Экскурсии на предприятия и стажировки.','event','offline',
  'https://mirea.ru/fryazino','https://rpmsjribjsrmnithqvap.supabase.co/storage/v1/object/public/media/images/career-fair.png',
  (current_date + 16),'{fryazino}','{fryazino}','{bachelor,specialist,master}','{карьера,стажировка,событие}',false,0,'published', now() - interval '10 minute')
on conflict (id) do update set
  title = excluded.title, description = excluded.description, type = excluded.type,
  format = excluded.format, external_link = excluded.external_link, image_url = excluded.image_url,
  event_date = excluded.event_date, campuses = excluded.campuses, institutes = excluded.institutes,
  directions = excluded.directions, tags = excluded.tags;
-- намеренно НЕ трогаем status/published_at/is_featured/priority_weight при повторном seed:
-- guard_post_update трактует смену featured не-главным как нарушение, а демо-состояние
-- модерации должно переживать перезапуск seed.
