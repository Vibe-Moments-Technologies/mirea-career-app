import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scroll.dart';
import '../../core/widgets/list_tail.dart';
import '../../core/widgets/post_card.dart';
import '../../core/widgets/reveal_on_mount.dart';
import '../../core/widgets/screen_header.dart';
import '../../data/models.dart';
import '../../state/feed_filters.dart';
import '../../state/providers.dart';
import '../post/post_detail_screen.dart';

/// Архив: записи, чьё событие уже прошло (по часам телефона).
///
/// Дубликат ленты по времени, а не «второй каталог»: главная и каталог
/// показывают только актуальное, сюда уходит всё, чьё событие уже прошло.
/// Записи без даты события остаются в ленте — истёкшими они не считаются.
///
/// Сам раздел приглушён по насыщенности: истёкшее не должно спорить с
/// актуальным за цветом.
class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key});

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  /// Блочная подгрузка, как в каталоге: архив за сезон бывает длинным.
  static const _pageSize = 20;
  int _visible = _pageSize;

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider);
    final favorites = ref.watch(favoritesProvider);
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    final posts = archiveOnly(feed.posts);
    final shown = posts.take(_visible).toList();
    final loading = feed.loading && feed.posts.isEmpty;

    return Scaffold(
      body: RefreshIndicator(
        // Свайп сверху вниз: архив отстаёт от ленты, когда модерация
        // публикует новые записи с прошедшей датой.
        onRefresh: () => ref.read(feedProvider.notifier).refresh(),
        child: ColorFiltered(
          // Истёкшее — серое: гасим насыщенность всего архива, чтобы он не
          // читался как вторая лента. Яркость матрица сохраняет, поэтому
          // текст остаётся контрастным, а краски и фото уходят в серый.
          colorFilter: const ColorFilter.matrix(expiredMatrix),
          child: CustomScrollView(
            physics: AppScroll.refreshable,
            slivers: [
              const SliverToBoxAdapter(
                child: ScreenHeader(title: 'Архив', bottom: 10),
              ),
              // Первая загрузка: скелетоны, а не «ничего не нашлось».
              if (loading)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
                  sliver: SliverList.separated(
                    itemCount: 4,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, _) => const PostCardSkeleton(),
                  ),
                )
              else if (posts.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyArchive(),
                )
              else ...[
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
                  sliver: SliverList.separated(
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    // Появление карточек внахлёст — как на главной.
                    itemBuilder: (_, i) => RevealOnMount(
                      child: _card(shown[i], favorites),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      pad,
                      16,
                      pad,
                      AppInsets.scrollBottom(context),
                    ),
                    child: ListTail(
                      hasMore: posts.length > shown.length,
                      loaded: shown.length,
                      total: posts.length,
                      footer: 'Это всё — прошедшие записи закончились',
                      onMore: () => setState(() => _visible += _pageSize),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(Post post, List<String> favorites) => PostCard(
        post: post,
        isFavorite: favorites.contains(post.id),
        onTap: () {
          // Запрос остаётся: возврат показывает ту же ленту.
          FocusManager.instance.primaryFocus?.unfocus();
          Navigator.of(context).push(
            appRoute(context, PostDetailScreen(post: post)),
          );
        },
        onToggleFavorite: () async {
          final added = await ref.read(favoritesProvider.notifier).toggle(post.id);
          await ref.read(metricsProvider).registerFavorite(post.id, added ? 1 : -1);
        },
      );
}

class _EmptyArchive extends StatelessWidget {
  const _EmptyArchive();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 56,
                color: AppColors.secondaryLight.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 12),
              Text('Архив пока пуст', style: AppText.headline),
              const SizedBox(height: 4),
              Text(
                'Сюда попадут записи, когда их события пройдут',
                textAlign: TextAlign.center,
                style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
              ),
            ],
          ),
        ),
      );
}
