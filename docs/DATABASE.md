# Схема БД и RLS — «Карьера РТУ МИРЭА» (Supabase / PostgreSQL)

Исполняемые артефакты — `supabase/migrations/0001_init.sql … 0004_seed_demo.sql`. Здесь — контракт и обоснования.

## 1. Справочники (клиентские, не таблицы)

Перечисления MVP живёт в коде клиента и в seed-данных — без БД-таблиц:
- **campuses**: `vernadsky78`, `vernadsky86`, `stromynka`
- **institutes**: `iit`, `iii`, `itht`, `irm`, `ionm` … (seed-список, расширяемый)
- **directions** (уровень): `bachelor`, `master`, `postgrad`, `any`

`ponytail:` когда справочники станут редактируемыми из админки — завести таблицы `campuses`/`institutes` и FK; пока это статические enum-подобные строки.

Типы и статусы — Postgres-enum'ы (`post_type`, `post_status`, `org_type`, `user_role`).

## 2. Таблицы

### organizations
| Колонка | Тип | Примечание |
|---|---|---|
| id | uuid pk default gen_random_uuid() | |
| name | text not null | «Кафедра ИТ», «Яндекс» |
| type | org_type (`university_dept` \| `partner`) | |
| description | text | |
| logo_url | text | Storage `media/` |
| created_at | timestamptz default now() | |

Модераторская служба — **не** организация; модераторы имеют `organization_id = null`.

### profiles (1:1 с auth.users)
| Колонка | Тип | Примечание |
|---|---|---|
| id | uuid pk references auth.users(id) on delete cascade | |
| role | user_role (`super_admin` \| `main_moderator` \| `assistant_moderator` \| `org_admin` \| `org_member`) not null default `org_member` | |
| organization_id | uuid references organizations(id) on delete set null | null у супер-админа и модераторов |
| full_name | text not null | |
| created_at | timestamptz default now() | |

Создаётся триггером `on_auth_user_created` (role назначается отдельно супер-админом — анонимный sign-up отключён).

### posts
| Колонка | Тип | Примечание |
|---|---|---|
| id | uuid pk | |
| organization_id | uuid references organizations on delete cascade not null | |
| author_id | uuid references profiles on delete set null | |
| title | text not null | |
| description | text not null | Markdown |
| type | post_type (`event` \| `vacancy` \| `internship` \| `scholarship` \| `project`) not null | |
| format | text (`online` \| `offline` \| `hybrid`) default `offline` | |
| campuses | text[] default '{}' | целевые кампусы, пусто = все |
| institutes | text[] default '{}' | целевые институты, пусто = все |
| directions | text[] default '{}' | пусто = все |
| tags | text[] default '{}' | ключевые слова |
| external_link | text | регистрация/заявка |
| image_url | text | обложка |
| event_date | date | дата события/дедлайна |
| is_featured | boolean default false | hero-карусель, ставит главный модератор |
| priority_weight | int default 0 | ручное поднятие в ленте |
| status | post_status (`draft` \| `pending_review` \| `reviewed_ready` \| `published` \| `rejected`) default `draft` | |
| views_count | bigint default 0 | только через RPC |
| favorites_count | bigint default 0 | только через RPC |
| created_at / updated_at | timestamptz | |
| published_at | timestamptz | ставится при публикации |

Организация-владелец поста неизменна после создания (автор привязан к своей org — RLS это гарантирует).

### rejection_notes
| Колонка | Тип |
|---|---|
| id | uuid pk |
| post_id | uuid references posts on delete cascade |
| author_id | uuid references profiles |
| note | text not null |
| created_at | timestamptz default now() |

Внутренние заметки ассистентов при отклонении — видны модераторам и авторам поста, не анонимам. `ponytail:` история всех переходов статуса (audit log) не ведётся — добавить `status_history`, когда появится требование расследований.

## 3. Матрица прав (кто какой переход статуса может)

**Публикует автор (компания), а не модерация.** Модерация только штампует одобрение,
автор публикует сам. Глава организации действует за всю организацию, сотрудник — за свои
посты и только в пределах выданных разрешений.

Роли (миграции 0012–0013): `super_admin` · `administrator` (бывший `main_moderator`) ·
`moderator` (бывший `assistant_moderator`) · `org_admin` · `org_member`.
Модераторская служба — сотрудники системной организации **«Администрация»**
(`org_type = 'administration'`, id `0000…0001`); над ней по правам только супер-админ.

| Переход | org_member | org_admin | moderator | administrator | super_admin |
|---|---|---|---|---|---|
| create draft | ✅ свои | ✅ за org | — | — | ✅ |
| draft → pending_review | ✅ | ✅ | — | — | ✅ |
| pending_review → draft (отозвать) | ✅ | ✅ | — | — | ✅ |
| rejected → draft / pending_review | ✅ | ✅ | — | — | ✅ |
| withdrawn → draft / pending_review | ✅ | ✅ | — | — | ✅ |
| pending_review → reviewed_ready | — | — | ✅ | ✅ | ✅ |
| pending_review → rejected (+пояснение) | — | — | ✅ | ✅ | ✅ |
| reviewed_ready → published | ✅ по `can_publish` | ✅ | — | **—** | ✅ |
| published → draft (скрыть) | ✅ по `can_withdraw` | ✅ | — | — | ✅ |
| published → withdrawn (снять) | — | — | — | ✅ (+пояснение) | ✅ |
| is_featured / priority_weight / аудитории | — | — | — | ✅ | ✅ |
| роль и организация профиля | — | — | — | ✅ ответственный | ✅ |
| разрешения/активность сотрудника | — | ✅ свои | — | ✅ | ✅ |
| CRUD организаций | — | ✅ своя | — | ✅ кроме «Администрации» | ✅ |
| удаление поста | ✅ по `can_delete_posts` | ✅ своя org | — | ✅ | ✅ |

Права сотрудника (`profiles`): `can_publish`, `can_withdraw`, `can_delete_posts` —
три независимых флага, выдаёт глава организации. Деактивация — `is_active` (вход закрыт),
сброс пароля — `must_change_password` (только ответственный).

Реализация: RLS-политики + триггеры `guard_post_update` / `guard_moderation_note` /
`guard_profile_update` (см. п.4) — не клиентская логика. **Отклонение и снятие требуют
пояснения**: пустая заметка не даст сменить статус (проверяется в БД).

## 4. RLS — политики (суть, исполняемый SQL в миграции 0002)

Включён на всех таблицах. Хелперы:

```sql
create function user_role() returns user_role …      -- роль текущего auth.uid()
create function is_moderator() returns boolean …     -- role in (main, assistant, super)
create function owns_post(p posts) returns boolean … -- profiles.organization_id = p.organization_id
```

**posts SELECT:**
```
USING (
  status = 'published' AND published_at <= now()          -- анонимы
  OR is_moderator()                                        -- модераторы видят всё
  OR (owns_post(posts) AND status <> 'published')          -- авторы — своё неопубликованное
)
```
Аноним видит опубликованное + свои метрики; черновики партнёра видны только его организации и модераторам.

**posts INSERT:** `WITH CHECK (owns_profile(author_id) AND organization_id = своя org AND is_moderator() OR …)` — упрощённо: автор может вставить пост только в свою организацию (супер-админ/модератор — в любую).

**posts UPDATE:**
- авторы: только свои строки своей org, и только переходы из своей колонки матрицы (`status` меняется лишь draft↔pending_review, rejected→draft; `published_at`, `is_featured`, `priority_weight`, `views/favorites_count` — **недоступны**);
- ассистенты: любая строка, переходы `pending_review → reviewed_ready|rejected`;
- главный/супер: любая строка, любые переходы + featured/weight/аудитории;
- счётчики: UPDATE запрещён всем напрямую (только RPC `security definer`).

**rejection_notes:** SELECT — модераторы + авторы отмеченного поста; INSERT — модераторы.
**organizations / profiles:** SELECT — всем аутентифицированным (админке нужны списки) + organizations доступны анонимам (логотипы в ленте — через join в SELECT posts, поэтому отдельная анонимная политика на organizations: `type is not null` — чтение разрешено). UPDATE organizations — её org_admin и супер-админ. profiles UPDATE — только своя строка (кроме супер-админа: role/organization_id).

## 5. RPC (security definer, миграция 0003)

```sql
increment_post_views(target uuid)        -- +1 views_count, только если status='published'
modify_post_favorites(target uuid, delta int)  -- favorites_count = greatest(0, count+delta)
```

Обе — `grant execute to anon, authenticated`; `security definer` обходит RLS, но сама проверяет `status='published'`, чтобы нельзя было накручивать черновики. Дедупликация просмотров — на клиенте (viewed_ids в SP).

## 6. Realtime

`alter publication supabase_realtime add table posts;` — INSERT/UPDATE публикуются; клиент фильтрует `status='published'` на приёме (payload для анонима и так пройдёт только через RLS SELECT-политику публикации realtime).

## 7. Seed демо-данных (миграция 0004) — применён
- Пользователи (пароль `Demo1234!`, созданы `supabase/scripts/seed-users.js` через GoTrue Admin API): `superadmin@demo.mirea` (super_admin), `chiefmod@demo.mirea` (main_moderator), `assist@demo.mirea` (assistant_moderator), `career@demo.mirea` (org_admin «Карьерный центр»), `partner@demo.mirea` (org_admin «Яндекс»), `partner_emp@demo.mirea` (org_member «Яндекс»).
- Организации: Карьерный центр, Кафедра ИТ, Студенческий клуб (university_dept); Яндекс, Сбер, VK (partner). UUID `1111…01`–`1111…06`.
- 11 постов (UUID `2222…01`–`2222…0b`): 8 published (2 featured), 1 pending_review, 1 reviewed_ready, 1 draft — демо модерации есть на чём показать.
- Smoke-тест всей модели прав: `node supabase/scripts/smoke-test.js` → 29 проверок, идемпотентен.

Роли назначаются SQL-ом (psql через SSH-туннель — прямой Postgres:5432 из рабочей среды недостижим, см. ROADMAP.md).

## 8. Индексы

`posts(status, published_at desc)`, `posts(organization_id)`, GIN на `posts(tags)`, `posts(campuses)`, `posts(institutes)` — на вырост; для MVP хватит и seq scan, но индексы дешевле, чем их отсутствие на демо.
