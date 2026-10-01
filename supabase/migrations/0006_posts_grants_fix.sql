-- 0006_posts_grants_fix.sql — добивка колоночных грантов 0002. Идемпотентно.
--
-- Контекст: грант INSERT на posts не включал author_id, а UPDATE — published_at,
-- клиенты получали `permission denied for table posts`, хотя RLS-политики разрешали.
-- author_id ставит триггер guard_post_insert (= auth.uid() для не-модераторов),
-- published_at — guard_post_update при публикации; триггеры остаются источником правды.
-- Прямая запись published_at автором без смены статуса инертна: аноним читает
-- только status='published', а переходы статуса сторожит guard_post_update.
grant insert (author_id) on public.posts to authenticated;
grant update (published_at) on public.posts to authenticated;
