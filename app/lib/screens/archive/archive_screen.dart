import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/screen_header.dart';
import '../../core/widgets/list_tail.dart';
import '../../core/widgets/pinned_header_screen.dart';
import '../../core/widgets/post_card.dart';
import '../../core/widgets/reveal_on_mount.dart';
import '../../core/widgets/search_overlay.dart';
import '../../data/models.dart';
import '../../state/feed_query.dart';
import '../../state/providers.dart';
import '../post/post_detail_screen.dart';

/// Архив: лента протухших постов (end_date < now).
///
/// Это «Все» с принудительно применённым фильтром «Архивные»: переключатель
/// актуальности здесь отсутствует. Поиск и типы работают как на главной.
/// Открывается из раздела «Ещё».
class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key});

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  bool _searchOpen = false;
  String _query = '';
  final _search = TextEditingController();

  static const _pageSize = 10;
  int _visible = _pageSize;

  @override
  void initState() {
    super.initState();
    // Принудительный архивный запрос: то же «Все», но end_date < @now.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  void _reload() {
    ref.read(feedQueryProvider.notifier).set(
          FeedQuery(
            tab: 'all',
            filters: FeedFiltersLite(
              query: _query,
              showArchived: true,
            ),
          ),
        );
    setState(() => _visible = _pageSize);
  }

  void _closeSearch() {
    closeSearch();
    setState(() {
      _searchOpen = false;
      _query = '';
      _search.clear();
    });
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedNotifierProvider);
    final favorites = ref.watch(favoritesProvider);
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    final posts = feed.posts.take(_visible).toList();
    final hasMore = feed.posts.length > _visible;

    return Scaffold(
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () => ref.read(feedNotifierProvider.notifier).refresh(),
            child: PinnedHeaderScreen(
              title: 'Архив',
              actions: [
                HeaderAction(
                  icon: Icons.search_rounded,
                  tooltip: 'Поиск',
                  onTap: () => setState(() => _searchOpen = true),
                ),
              ],
              onRefresh: () =>
                  ref.read(feedNotifierProvider.notifier).refresh(),
              slivers: [
                if (feed.offline)
                  const SliverToBoxAdapter(
                    child: _ArchiveOfflineBanner(),
                  ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
                  sliver: feed.loading
                      ? SliverList.separated(
                          itemCount: 4,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (_, _) => const PostCardSkeleton(),
                        )
                      : SliverList.separated(
                          itemCount: posts.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => RevealOnMount(
                            child: PostCard(
                              post: posts[i],
                              isFavorite: favorites.contains(posts[i].id),
                              onTap: () => _open(posts[i]),
                              onToggleFavorite: () =>
                                  _toggleFavorite(posts[i].id),
                            ),
                          ),
                        ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      pad,
                      16,
                      pad,
                      AppInsets.screenBottom(context),
                    ),
                    child: feed.loading
                        ? const SizedBox.shrink()
                        : ListTail(
                            hasMore: hasMore,
                            isEmpty: posts.isEmpty && !feed.loading,
                            loaded: posts.length,
                            total: feed.posts.length,
                            onMore: () =>
                                setState(() => _visible += _pageSize),
                          ),
                  ),
                ),
              ],
            ),
          ),
          SearchOverlay(
            open: _searchOpen,
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            onClose: _closeSearch,
          ),
        ],
      ),
    );
  }

  void _open(Post post) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).push(
      appRoute(context, PostDetailScreen(post: post)),
    );
  }

  Future<void> _toggleFavorite(String id) async {
    final added = await ref.read(favoritesProvider.notifier).toggle(id);
    await ref.read(metricsProvider).registerFavorite(id, added ? 1 : -1);
  }
}

class _ArchiveOfflineBanner extends StatelessWidget {
  const _ArchiveOfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.warning.withValues(alpha: 0.12),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 16, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Нет сети — попробуйте обновить',
              style: AppText.footnote,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
