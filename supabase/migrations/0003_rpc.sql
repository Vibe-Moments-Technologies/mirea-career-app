-- 0003_rpc.sql — счётчики интереса (анонимная запись без UPDATE-прав на posts)

create or replace function public.increment_post_views(target_post_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  update public.posts
     set views_count = views_count + 1
   where id = target_post_id
     and status = 'published'
     and published_at <= now();
end $$;

create or replace function public.modify_post_favorites(target_post_id uuid, delta int)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if delta not in (-1, 1) then
    raise exception 'delta must be -1 or 1';
  end if;
  update public.posts
     set favorites_count = greatest(0, favorites_count + delta)
   where id = target_post_id
     and status = 'published';
end $$;

revoke all on function public.increment_post_views(uuid) from public;
revoke all on function public.modify_post_favorites(uuid, int) from public;
grant execute on function public.increment_post_views(uuid) to anon, authenticated;
grant execute on function public.modify_post_favorites(uuid, int) to anon, authenticated;
