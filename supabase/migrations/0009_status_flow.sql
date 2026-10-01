-- 0009_status_flow.sql — поток статусов и охранники. Заменяет guard_post_update из 0007.
-- Идемпотентно.
--
-- Поток (DATABASE.md §3):
--   draft ──отправить──► pending_review ──одобрить──► reviewed_ready ──публикует автор──► published
--     ▲                      │                              ▲                                 │
--     │                      ├──отклонить (я≥1)──► rejected │                                 │
--     └──править/вернуть─────┘                              └──отзыв компанией (я≥1)─────────┤
--   published ──отзыв/снятие модерацией (я≥1)──► withdrawn ──править──► pending_review
--
-- Публикует АВТОР (компания), а не главный модератор: право — can_author_publish().
-- Модераторы только проверяют и снимают; редактировать чужой контент не могут.
-- Любое отклонение и снятие требует пояснения — проверяется здесь, в БД.

-- Право автора править содержимое поста
create or replace function public.can_author_edit(p public.posts) returns boolean
language sql stable security definer set search_path = public as $$
  select case public.current_role()
    when 'super_admin' then true
    when 'org_admin'   then p.organization_id = public.current_org_id()
    when 'org_member'  then p.organization_id = public.current_org_id()
                            -- черновик и отклонённое правит и без разрешений
                            and p.status in ('draft','rejected','withdrawn','pending_review')
    else false
  end
$$;

-- ---------- Охранник UPDATE: матрица переходов ----------
create or replace function public.guard_post_update() returns trigger
language plpgsql security definer set search_path = public as $$
declare r public.user_role := public.current_role();
begin
  -- RPC-инкремент счётчиков: статус и приоритет не меняются — пропускаем
  if new.status = old.status
     and new.is_featured = old.is_featured
     and new.priority_weight = old.priority_weight then
    return new;
  end if;

  -- приоритет и целевая аудитория — только ответственный (главный/супер)
  if (new.is_featured <> old.is_featured
        or new.priority_weight <> old.priority_weight
        or new.campuses <> old.campuses
        or new.institutes <> old.institutes
        or new.directions <> old.directions)
     and not public.is_chief() then
    raise exception 'менять приоритет/аудиторию может только главный модератор';
  end if;

  if new.status <> old.status then
    if r = 'assistant_moderator' then
      -- ассистент: только проверка очереди
      if not (old.status = 'pending_review'
              and new.status in ('reviewed_ready','rejected')) then
        raise exception 'ассистент проверяет только посты на модерации';
      end if;

    elsif r = 'main_moderator' then
      -- главный модератор: проверяет и снимает, но НЕ публикует и НЕ правит
      if new.status = 'published' then
        raise exception 'публикует автор поста, а не модератор';
      end if;
      if not ((old.status = 'pending_review' and new.status in ('reviewed_ready','rejected'))
           or (old.status = 'published'      and new.status = 'withdrawn')) then
        raise exception 'главный модератор проверяет и снимает с публикации';
      end if;

    elsif r in ('org_admin','org_member') then
      if old.organization_id <> public.current_org_id() then
        raise exception 'нет доступа к чужой организации';
      end if;
      -- начальник действует за всю организацию, сотрудник — только за себя
      if r = 'org_member' and old.author_id is distinct from auth.uid() then
        raise exception 'сотрудник может менять только свои посты';
      end if;
      if not (
           (old.status = 'draft'           and new.status = 'pending_review')
        or (old.status = 'rejected'        and new.status in ('draft','pending_review'))
        or (old.status = 'withdrawn'       and new.status in ('draft','pending_review'))
        or (old.status = 'pending_review'  and new.status = 'draft')
        or (old.status = 'reviewed_ready'  and new.status in ('published','draft'))
        or (old.status = 'published'       and new.status = 'draft')
      ) then
        raise exception 'недопустимый переход статуса';
      end if;
      -- публикация: начальник всегда, сотрудник — по разрешению
      if new.status = 'published' and not public.can_author_publish(old) then
        raise exception 'публиковать может начальник или сотрудник с разрешением';
      end if;
      -- отзыв опубликованного: разрешение индивидуально
      if old.status = 'published' and new.status = 'draft' and not public.can_author_withdraw(old) then
        raise exception 'отзывать публикацию может начальник или сотрудник с разрешением';
      end if;

    elsif r = 'super_admin' then
      null; -- любое
    else
      raise exception 'недостаточно прав для смены статуса';
    end if;
  end if;

  -- ушло из публикации — из hero-карусели тоже
  if old.status = 'published' and new.status <> 'published' then
    new.is_featured := false;
  end if;

  -- публикация автором: ставим дату сами (триггер — источник правды)
  if new.status = 'published' and old.status <> 'published' then
    new.published_at := now();
  end if;

  return new;
end $$;

drop trigger if exists posts_guard_update on public.posts;
create trigger posts_guard_update before update on public.posts
  for each row execute function public.guard_post_update();

-- ---------- Охранник INSERT: автор — в свою org, author_id = текущий ----------
create or replace function public.guard_post_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_moderator() then
    if new.organization_id <> public.current_org_id() then
      raise exception 'пост можно создавать только в своей организации';
    end if;
    -- сотрудник — только от своего имени; начальник может создать за сотрудника
    if public.current_role() = 'org_member' or new.author_id is null then
      new.author_id := auth.uid();
    end if;
  elsif new.author_id is null then
    new.author_id := auth.uid();
  end if;
  return new;
end $$;

drop trigger if exists posts_guard_insert on public.posts;
create trigger posts_guard_insert before insert on public.posts
  for each row execute function public.guard_post_insert();

-- ---------- Пояснения обязательны при отклонении и снятии ----------
-- Проверяем в том же BEFORE-триггере: к моменту проверки строка пояснения уже
-- вставлена (клиент пишет её первым), иначе откатываем смену статуса.
create or replace function public.guard_moderation_note() returns trigger
language plpgsql security definer set search_path = public as $$
declare has_note boolean;
begin
  if new.status in ('rejected','withdrawn') and old.status <> new.status then
    select exists (
      select 1 from public.rejection_notes n
       where n.post_id = new.id and btrim(n.note) <> ''
    ) into has_note;
    if not has_note then
      raise exception 'отклонение и снятие требуют пояснения';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists posts_guard_note on public.posts;
create trigger posts_guard_note before update on public.posts
  for each row execute function public.guard_moderation_note();
