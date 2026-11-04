# Архитектура — «Карьера РТУ МИРЭА»

## 1. Стек

| Слой | Решение | Почему |
|---|---|---|
| Мобильное приложение | **Flutter stable** (Dart), REST через `app_http_client.dart` | Один UI-код на iOS/Android. Supabase SDK выкинут при переезде на PocketBase: чтение — анонимный REST, SDK не нужен. |
| Бэкенд | **PocketBase v0.28+** на VDS `vmt-mireacareer.l1ratch.ru` (nginx → 127.0.0.1:8090, TLS на nginx) | Свой API, авторизация и права (API Rules) без своего сервера. Схема и правила доступа — в `.agent-docs/database-guide.md` (секреты, в git не входит). |
| Веб-консоль | **Vite + TypeScript**, чистый fetch к REST PocketBase | Без SDK и фреймворков: 14 файлов, один клиент `src/pb.ts`. |
| Локальное хранилище приложения | `shared_preferences`: профиль-опрос, viewed ids, очередь счётчиков, кэш ленты | Данных мало, ORM не нужен. |
| CI | Отсутствует на MVP | Сборки локальные. |

Репозиторий — монорепо:

```
MIREA-Career/
├── docs/            # TZ, ARCHITECTURE, DATABASE, UI, ADMIN, ROADMAP
├── .agent-docs/     # справка по живой БД PocketBase (секреты; в .gitignore)
├── supabase/        # архив миграций старой схемы (Postgres) — история, не применяется
├── app/             # Flutter-приложение студента
└── admin/           # Vite+TS веб-консоль (в git не входит)
```

## 2. Учётные записи и права (решение от 27.10.2026)

**Сейчас: один администратор.** Консоль работает под единственным суперпользователем
PocketBase (`_superusers`); ролевой модели нет — профилей, модерации и команд
новая схема не содержит. Публикация поста — напрямую администратором
(статусы `draft`/`published`), без цепочки согласований.

**Расширение (когда появятся реальные требования):** auth-коллекция
(например `editors`) с полями `role` + `organization`, права — через API Rules
PocketBase вида `post.organization = @request.auth.organization`. Это штатный
механизм, отдельный сервер не пишем. До этого момента ролевой код не заводим.

## 3. Потоки данных

### Чтение ленты (аноним)
1. Приложение → `GET /api/collections/posts/records?filter=status="published" && published_at<=@now && (end_date>@now||end_date="")&expand=organization`.
   Права на стороне PocketBase: аноним видит только опубликованное и наступившее; архив — `end_date<@now`.
2. Ответ кэшируется локально (SP): старт рисует кэш, сеть обновляет поверх.
3. Фильтры (вкладки, типы, поиск) — серверные filter-параметры (`@now` без кавычек; multi-value через OR, не через запятые).

### Витрина главной
`spotlight_banners` — отдельная таблица, к постам отношения не имеет. Анониму
отдаются только `is_active = true`; порядок — `sort_order`.

### Счётчики (решено)
`views_count`/`favorites_count` инкрементируются **серверно, из хука PocketBase**
(`pb_hooks/metrics.pb.js`, задеплоен на VDS): приложение анонимно вызывает
- `POST /api/metrics/view/{postId}` — просмотр; заголовок `X-Visitor-Id` (id
  устройства из SP) дедуплицирует: 1 просмотр на посетителя;
- `POST /api/metrics/favorite` с телом `{ post_id, delta }`, delta = ±1 —
  клэмп на нуле.

Дедупликация — служебная таблица `metric_events` (видна только хуку), чистка
старых строк — ночной cron. Прямой PATCH постов остаётся закрытым для анонима.
Стороне приложения остаётся дописать ~5 строк в TODO-заглушках
`posts_repo.dart` (incrementViews/modifyFavorites) — POST и fire-and-forget.
Внешние аналитики (Umami/Plausible) тут не нужны: они считают посещения
страниц сайта, а не показы конкретных карточек.

### Консоль
Вход суперпользователя (`auth-with-password`, токен в localStorage), дальше
CRUD через REST. Производные статусы считаются из дат: `published_at > now` =
отложен, `end_date < now` = архив. Счётчики консоль только читает и не
сбрасывает: PATCH шлёт лишь изменённые поля.

## 4. Медиа

Файлы — в самих записях PocketBase: `posts.image` (file), `spotlight_banners.image`
(file); URL — `/api/files/{collection}/{record_id}/{filename}`.
`organizations.logo_url` — **url-поле** (ссылка), файлом туда грузить нельзя.
Загрузка из консоли — multipart отдельным PATCH после сохранения JSON-полей.

## 5. Конфигурация

- `admin/.env`: `VITE_PB_URL=https://vmt-mireacareer.l1ratch.ru`.
- Приложение: базовый URL передаётся в `PostsRepo`.
- Пароль суперпользователя — только в `.agent-docs/database-guide.md` (gitignore), в коде и сборках его нет.

## 6. Ключевые риски

| Риск | Решение |
|---|---|
| Счётчики | Решено: хук `pb_hooks/metrics.pb.js` (см. §3), инкременты серверные. |
| Накрутка счётчиков | Дедупликация на устройстве; полноценный антифрод — после MVP. |
| Кириллица ломается при заливке данных через PowerShell/curl | Писать JSON в файл (UTF-8 без BOM) и `--data-binary @file` (guide §4.2); REST из браузера/Node безопасен. |
| Утечка неопубликованного | API Rules: list/view только `published` + `published_at <= @now`; черновики видны лишь суперпользователю. |
| iOS-релиз без Mac/аккаунта | Демо через Android + консоль в браузере. |
