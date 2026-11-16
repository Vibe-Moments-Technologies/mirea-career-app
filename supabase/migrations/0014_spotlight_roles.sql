-- 0014_spotlight_roles.sql — чиним права витрины после ренейма ролей (0012/0013).
--
-- Проблема: spotlight_write проверял несуществующую роль main_moderator —
-- писать в spotlight_banners не мог никто, включая супера. В posts_insert
-- осталась мёртвая ветка main_moderator — возвращаем исходный смысл
-- (администратор может вставить пост в любую организацию, как мог главный).
drop policy if exists spotlight_write on public.spotlight_banners;
create policy spotlight_write on public.spotlight_banners
  for all to authenticated
  using (public.current_role() in ('administrator', 'super_admin'))
  with check (public.current_role() in ('administrator', 'super_admin'));

drop policy if exists posts_insert on public.posts;
create policy posts_insert on public.posts
  for insert to authenticated
  with check (
    public.current_role() in ('super_admin', 'administrator')
    or (organization_id = public.current_org_id())
  );
