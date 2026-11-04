# Схема БД — «Карьера РТУ МИРЭА»

> **Исторический документ.** Описанная ниже схема Supabase/Postgres больше не
> используется: проект переехал на PocketBase. Живая схема, правила доступа и
> все поля — в `.agent-docs/database-guide.md` (секреты, в git не входит).
> Этот файл оставлен как архив мотивации старой ролевой модели; миграции —
> в `supabase/migrations/` (к живой БД не применяются).

# Архив: старая схема (Supabase / PostgreSQL)

Исполняемые артефакты — `supabase/migrations/0001_init.sql … 0015_profile_guard_roles.sql`.
Ниже — контракт и обоснования на момент переезда.

## 1. Справочники (клиентские, не таблицы)

Перечисления MVP жили в коде клиента и в seed-данных — без БД-таблиц:
- **campuses**: `vernadsky78`, `vernadsky86`, `stromynka`
- **institutes**: `iit`, `iii`, `itht`, `irm`, `ionm` … (seed-список, расширяемый)
- **directions** (уровень): `bachelor`, `master`, `postgrad`, `any`

Типы и статусы — Postgres-enum'ы (`post_type`, `post_status`, `org_type`, `user_role`).

## 2. Таблицы

### organizations
| Колонка | Тип | Примечание |
|---|---|---|
| id | uuid pk default gen_random_uuid() | |
| name | text not null | «Кафедра ИТ», «Яндекс» |
| type | org_type (`university_dept` \| `partner`) | |
| description | text | |
| logo_url | text | |
| created_at | timestamptz default now() | |

### profiles (1:1 с auth.users)
| Колонка | Тип | Примечание |
|---|---|---|
| id | uuid pk references auth.users(id) on delete cascade | |
| role | user_role not null default `org_member` | |
| organization_id | uuid references organizations on delete set null | |
| full_name | text not null | |

### posts
| Колонка | Тип | Примечание |
|---|---|---|
| id | uuid pk | |
| organization_id | uuid not null | |
| author_id | uuid | |
| title / description | text | |
| type | post_type (`event` \| `vacancy` \| `internship` \| `scholarship` \| `project`) | |
| format | text (`online` \| `offline` \| `hybrid`) | |
| campuses / institutes / directions / tags | text[] | пусто = все |
| external_link / image_url | text | |
| event_date | date | |
| is_featured | boolean | |
| priority_weight | int | |
| status | post_status (`draft`…`published`, позже +`withdrawn`) | |
| views_count / favorites_count | bigint | только через RPC |
| published_at | timestamptz | |

### rejection_notes
Заметки ассистентов при отклонении/снятии: post_id, author_id, note, created_at.

## 3. Матрица прав (итоговая, перед переездом)

Роли после ренейма (0012/0013): `super_admin` · `administrator` (экс-главный
модератор) · `moderator` (экс-ассистент) · `org_admin` · `org_member`.
Модераторская служба — в системной организации «Администрация»
(`org_type = 'administration'`), над ней только супер-админ.

Публикация — автором (компанией); модерация штампует `reviewed_ready`,
снятие модерацией — `withdrawn`, оба с обязательным пояснением (проверял
триггер). Права сотрудника — три независимых флага `can_publish`,
`can_withdraw`, `can_delete_posts` + `is_active`, `must_change_password`.

Реализация: RLS-политики + триггеры `guard_post_update` / `guard_moderation_note`
/ `guard_profile_update` — не клиентская логика.

## 4. RPC (security definer)

`increment_post_views(uuid)` и `modify_post_favorites(uuid, int)` — анонимные
инкременты счётчиков только для `published`.

## 5. Почему уехали с этой схемы

RLS-матрица стала сложнее продукта: 15 миграций, три триггера-охранника,
колоночные гранты. PocketBase даёт правила доступа декларативно на коллекции,
а для MVP консоли хватило одного суперпользователя (решение 27.10.2026,
см. ARCHITECTURE.md §2). Старые миграции сохранены в `supabase/migrations/`
как история; к живой БД они не применяются.
