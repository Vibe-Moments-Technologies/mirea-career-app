# Архитектура — «Карьера РТУ МИРЭА»

## 1. Стек

| Слой | Решение | Почему |
|---|---|---|
| Мобильное приложение | **Flutter 3.4x stable** (Dart ≥3.9), `supabase_flutter: ^2.17.2` | Один UI-код на iOS/Android, самый быстрый путь к «красивому» MVP, официальный SDK Supabase с realtime. 3.0.0-dev не берём — только stable. KMP/Compose отклонён: на iOS шероховатости анимаций, меньше готовых iOS-подобных компонентов. |
| Бэкенд | **Supabase** (Postgres + Auth + RLS + Realtime + Storage + RPC) | Не пишем свой сервер вообще: API, авторизация, права и файловое хранилище — из коробки. |
| Веб-админка | **Vite + TypeScript** (без фреймворка-гиганта; UI — на чистом TS + CSS, состояние — минимальное), `@supabase/supabase-js` | Презентационный инструмент на 3 экрана. React/Flutter Web — лишний вес для демо. |
| Локальное хранилище | `shared_preferences` (профиль-опрос, viewed ids, очередь счётчиков) + JSON-кэш ленты в том же SP | Не заводим Hive/Isar/Drift: данных мало (профиль + список UUID + кэш). `ponytail:` если кэш ленты вырастет или понадобится сложный офлайн — переход на Isar. |
| CI | Отсутствует на MVP | Сборки локальные / TestFlight-Internal по необходимости. |

Репозиторий — монорепо:

```
MIREA-Career/
├── docs/            # TZ, ARCHITECTURE, DATABASE, UI, ADMIN, ROADMAP
├── supabase/
│   ├── migrations/  # 0001_init.sql, 0002_rls.sql, 0003_rpc.sql, 0004_seed_demo.sql
│   └── config.toml
├── app/             # Flutter-приложение
└── admin/           # Vite+TS веб-админка
```

## 2. Структура Flutter-приложения

Feature-first, но без слоёной лазаньи — на MVP достаточно трёх уровней: `data` (Supabase + локальное хранилище) → `state` (Riverpod-провайдеры) → `screens` (виджеты).

```
app/lib/
├── main.dart
├── core/
│   ├── theme/          # design-tokens: цвета, радиусы, тени, типографика (docs/UI.md)
│   ├── widgets/        # GlassDock, HeroCarousel, PostCard, FilterSheet, Chip…
│   └── utils/          # debounce, formatters
├── data/
│   ├── supabase_client.dart
│   ├── posts_repo.dart       # fetch/filter/realtime-поток posts+organizations
│   ├── local_store.dart      # профиль, избранное, viewed ids, pending-счётчики
│   └── metrics.dart          # fire-and-forget RPC + локальная очередь повторов
├── state/
│   ├── feed_provider.dart    # лента, фильтры, «Для вас»-скоринг
│   ├── profile_provider.dart # результат опроса
│   └── favorites_provider.dart
└── screens/
    ├── onboarding/     # 4 шага опроса
    ├── home/           # Главная
    ├── catalog/        # Каталог (Вуз/Партнёры + фильтры)
    ├── favorites/
    ├── more/           # Другое + редактирование профиля
    └── post/           # Карточка
```

Состояние — **Riverpod** (единственная новая зависимость помимо supabase_flutter и url_launcher). Без bloc/getx: для четырёх вкладок достаточно.

## 3. Потоки данных

### Чтение ленты (аноним)
1. `anon`-ключ → Supabase REST: `posts?status=eq.published&select=*,organizations(name,logo_url,type)`, сортировка `priority_weight desc, published_at desc`, фильтр по `published_at <= now()`.
2. Ответ кэшируется в SP (JSON). Старт приложения рисует кэш мгновенно, сеть обновляет поверх.
3. Realtime-подписка на INSERT/UPDATE таблицы `posts` → новая опубликованная карточка появляется в ленте без pull-to-refresh (это же — магия для презентации).

### Фильтрация
Все фильтры MVP выполняются **на клиенте** по уже загруженной ленте: типы, кампус/институт — совпадение с `target_campuses`/`target_institutes` (пустой массив = для всех), теги — пересечение, компания — `organization_id`, формат — `format`, поиск — по `title` + теги. Серверный `select` применяется только когда строк станет > ~1000. `ponytail:` клиентская фильтрация; при росте каталога — перенести в RPC/View с пагинацией.

### Скоринг «Для вас» (полностью локальный)
```
score = 3·campus_match + 3·institute_match + 2·|tags ∩ profile.tags| + priority_weight
        (+1 если target_all)
```
Посты со score > 0 и не из избранного — в секцию «Для вас», отсортированные по score. Веса — константы в `feed_provider.dart`, калибруются на демо-данных.

### Счётчики (запись от анонима)
Аноним **не имеет** UPDATE на `posts` (закрыто RLS). Инкременты — только через `security definer` RPC:
- Открытие карточки: если `post_id ∉ viewed_ids` → `increment_post_views(id)`, id пишется в SP.
- Избранное ±: `modify_post_favorites(id, ±1)` немедленно; при офлайне — в локальную очередь, повторяется при старте/восстановлении сети.

### Публикация (автор → модерация → приложение)
Запись/смена статуса — прямыми UPDATE/INSERT в таблицы под RLS (см. DATABASE.md): право на переход статуса зашито в политику, а не в клиентский код. Клиент админки может попытаться поставить `published` — Postgres отклонит, если ты не main_moderator.

## 4. Медиа

Supabase Storage, bucket `media` (публичный на чтение). Загрузка — из админки (`supabase-js.storage.upload`), в БД хранится `image_url` (публичный URL). Ограничение на клиенте: ≤ 5 МБ, jpg/png/webp. `ponytail:` без серверной валидации и ресайза; CDN/ресайз — когда появятся реальные нагрузки.

## 5. Конфигурация и окружения

- Один проект Supabase на MVP. `SUPABASE_URL` + `SUPABASE_ANON_KEY` — во Flutter через `--dart-define`, в админке через `.env`.
- Секретные ключи (`service_role`) в клиентах не появляются никогда. Единственный носитель — Supabase SQL Editor для первичной настройки.

## 6. Ключевые риски и решения

| Риск | Решение |
|---|---|
| Накрутка счётчиков анонимами | RPC + дедупликация просмотров на устройстве; favorites — идемпотентный дельта-вызов с `greatest(0, …)`. Полноценный антифрод — после MVP. |
| Утечка неопубликованного через anon-ключ | RLS: `published` + дата публикации ≤ now(); всё остальное — только роли авторов/модераторов. Проверка отдельным smoke-тестом (запрос anon-ключом должен вернуть только published). |
| iOS-релиз без Mac/аккаунта на момент демо | Демонстрация через Android-эмулятор/устройство + админка в браузере; iOS-сборка — отдельным поздним этапом, код к этому готов. |
| Реальные данные МИРЭА (кампусы, институты) | На MVP — seed-скрипт с правдоподобным списком (Вернадского 78/86, Стромынка; ИИТ, ИИИ, ИТХТ…), заменяется справочниками позже. |
