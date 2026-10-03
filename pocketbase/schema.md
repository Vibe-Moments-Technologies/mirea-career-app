# PocketBase Schema for MIREA Career App

## Создание коллекций

Открой Admin UI: `https://vmt-mireacareer.l1ratch.ru/_/`
Создай admin-аккаунт, затем создай коллекции ниже.

---

### 1. organizations

| Поле | Тип | Обязательное | Описание |
|------|-----|-------------|----------|
| name | text | ✅ | Название организации |
| type | select | ✅ | `university_dept` / `partner` |
| description | editor | ❌ | Описание (rich text) |
| logo_url | url | ❌ | URL логотипа |
| website | url | ❌ | Сайт организации |
| contact_email | email | ❌ | Email для связи |
| contact_phone | text | ❌ | Телефон |
| contact_name | text | ❌ | Контактное лицо |

**API Rules:**
- List/View: `""` (публичный доступ)
- Create/Update/Delete: `@request.auth.role = "main_moderator" || @request.auth.role = "super_admin"`

---

### 2. posts

| Поле | Тип | Обязательное | Описание |
|------|-----|-------------|----------|
| title | text | ✅ | Заголовок поста |
| description | editor | ❌ | Описание (markdown/rich text) |
| type | select | ✅ | `vacancy`/`internship`/`event`/`scholarship`/`project` |
| format | select | ❌ | `online`/`offline`/`hybrid` |
| external_link | url | ❌ | Ссылка на регистрацию |
| image | file | ❌ | Обложка (max 5MB, images only) |
| event_date | date | ❌ | Дата события |
| campuses | json | ❌ | Массив кампусов |
| institutes | json | ❌ | Массив институтов |
| directions | json | ❌ | Массив направлений |
| tags | json | ❌ | Массив тегов |
| is_featured | bool | ❌ | Приоритетный пост |
| priority_weight | number | ❌ | Вес приоритета |
| status | select | ✅ | `draft`/`pending_review`/`published`/`rejected`/`withdrawn` |
| views_count | number | ❌ | Счётчик просмотров (default: 0) |
| favorites_count | number | ❌ | Счётчик избранного (default: 0) |
| published_at | date | ❌ | Дата публикации |
| organization | relation | ❌ | → organizations (1:1) |
| author | relation | ❌ | → users (автор поста) |

**API Rules:**
- List/View: `status = "published" && published_at <= @now`
- Create: `@request.auth.id != ""`
- Update: `@request.auth.id != ""`
- Delete: `@request.auth.role = "main_moderator" || @request.auth.role = "super_admin"`

---

### 3. spotlight_banners

| Поле | Тип | Обязательное | Описание |
|------|-----|-------------|----------|
| title | text | ✅ | Заголовок баннера |
| subtitle | text | ❌ | Подзаголовок |
| image | file | ❌ | Обложка баннера |
| link_url | url | ❌ | Куда ведёт тап |
| sort_order | number | ✅ | Порядок сортировки (default: 0) |
| is_active | bool | ✅ | Активен ли баннер (default: true) |
| starts_at | date | ❌ | Начало показа |
| ends_at | date | ❌ | Конец показа |

**API Rules:**
- List/View: `is_active = true && (starts_at = null || starts_at <= @now) && (ends_at = null || ends_at >= @now)`
- Create/Update/Delete: `@request.auth.role = "main_moderator" || @request.auth.role = "super_admin"`

---

### 4. profiles (расширение стандартной коллекции users)

PocketBase имеет встроенную коллекцию `users`. Добавь поля:

| Поле | Тип | Обязательное | Описание |
|------|-----|-------------|----------|
| role | select | ❌ | `org_member`/`org_admin`/`assistant_moderator`/`main_moderator`/`super_admin` |
| institute | text | ❌ | Институт студента |
| level | text | ❌ | Уровень обучения |
| interests | json | ❌ | Массив интересов |
| organization | relation | ❌ | → organizations |
| profile_completed | bool | ❌ | Профиль заполнен |
| must_change_password | bool | ❌ | Требует смены пароля |

---

## Миграция данных из Supabase

После создания коллекций, данные можно мигрировать через:
1. Admin UI — вручную (21 пост, 3 баннера)
2. API скрипт — автоматическая миграция (см. migrate.js)
