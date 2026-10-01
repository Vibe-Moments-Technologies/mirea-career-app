-- 0007_author_withdraw.sql — отзыв с модерации и скрытие публикации автором. Идемпотентно.
--
-- Что меняется в матрице (DATABASE.md §3):
--   pending_review → draft  — org_admin/org_member своей org (отозвать с проверки);
--   published → draft       — только org_admin своей org (скрыть публикацию);
--   при уходе из published флаг is_featured сбрасывается триггером (не возвращается
--     в hero-карусель сам по себе при повторной публикации).
-- RLS-политики не трогаем: update своей строки автором уже разрешён, решает охранник.
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

  -- приоритет и целевая аудитория — только главный/супер
  if (new.is_featured <> old.is_featured
        or new.priority_weight <> old.priority_weight
        or new.campuses <> old.campuses
        or new.institutes <> old.institutes
        or new.directions <> old.directions)
     and not public.is_chief() then
    raise exception 'менять приоритет/аудиторию может только главный модератор';
  end if;

  if new.status <> old.status then
    if public.is_chief() then
      -- главный/супер: любой переход; при публикации ставим published_at
      if new.status = 'published' and old.status <> 'published' then
        new.published_at := now();
      end if;
    elsif r = 'assistant_moderator' then
      if not (old.status = 'pending_review'
              and new.status in ('reviewed_ready','rejected')) then
        raise exception 'ассистент проверяет только pending_review';
      end if;
    elsif r in ('org_admin','org_member') then
      if old.organization_id <> public.current_org_id() then
        raise exception 'нет доступа к чужой организации';
      end if;
      if not ((old.status = 'draft'    and new.status = 'pending_review')
           or (old.status = 'rejected' and new.status = 'draft')
           or (old.status = 'pending_review' and new.status = 'draft')
           or (r = 'org_admin' and old.status = 'published' and new.status = 'draft')) then
        raise exception 'автор может отправить на модерацию, отозвать или скрыть публикацию';
      end if;
    else
      raise exception 'недостаточно прав для смены статуса';
    end if;
  end if;

  -- ушло из публикации — из hero-карусели тоже (кто бы ни снимал)
  if old.status = 'published' and new.status <> 'published' then
    new.is_featured := false;
  end if;

  return new;
end $$;
