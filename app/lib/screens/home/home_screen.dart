import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/post_card.dart';
import '../../core/widgets/screen_header.dart';
import '../../core/widgets/search_overlay.dart';
import '../../data/models.dart';
import '../../state/feed_filters.dart';
import '../../state/providers.dart';
import '../post/post_detail_screen.dart';

/// Главная: шапка → быстрые фильтры → лента, подсобранная под профиль.
///
/// Приоритетные карточки (is_featured) всегда вверху, с акцентной обводкой.
/// Отдельной витрины-карусели нет: она дублировала эти же посты.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _quick = 'all';

  /// Блочная подгрузка: сколько карточек показываем и докладываем за раз.
  static const _pageSize = 10;
  int _visible = _pageSize;

  bool _searchOpen = false;
  String _query = '';
  final _search = TextEditingController();

  static const _quickChips = <({String id, String label})>[
    (id: 'all', label: 'Все'),
    (id: 'upcoming', label: 'Ближайшие'),
    (id: 'internship', label: 'Стажировки'),
    (id: 'event', label: 'События'),
  ];

  FeedFilters _applyQuick(FeedFilters f) {
    final withQuery = f.copyWith(query: _query);
    return switch (_quick) {
      'upcoming' => withQuery.copyWith(onlyUpcoming: true),
      'internship' => withQuery.copyWith(types: {'internship'}),
      'event' => withQuery.copyWith(types: {'event'}),
      _ => withQuery,
    };
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider);
    final profile = ref.watch(profileProvider);
    final favorites = ref.watch(favoritesProvider);
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    final filtered = applyFilters(feed.posts, _applyQuick(const FeedFilters()));
    // homeFeed уже ставит приоритетные выше остальных (docs/ARCHITECTURE.md §3)
    final all = homeFeed(filtered, profile);
    final shown = all.take(_visible).toList();
    final loading = feed.loading && feed.posts.isEmpty;

    return Scaffold(
      // Поиск лежит поверх ленты, поэтому экран — Stack: поле затемняет
      // контент целиком, а не торчит из-под дока.
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              if (feed.offline)
                const SliverToBoxAdapter(child: _OfflineBanner())
              else
                SliverToBoxAdapter(
                  child: SizedBox(height: AppInsets.top(context)),
                ),
              SliverToBoxAdapter(
                child: ScreenHeader(
                  title: 'Карьера МИРЭА',
                  actions: [
                    HeaderAction(
                      icon: Icons.refresh_rounded,
                      tooltip: 'Обновить',
                      onTap: () => ref.read(feedProvider.notifier).refresh(),
                    ),
                    HeaderAction(
                      icon: Icons.search_rounded,
                      tooltip: 'Поиск',
                      onTap: () => setState(() => _searchOpen = true),
                    ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.fromLTRB(pad, 4, pad, 0),
                    children: [
                      for (final c in _quickChips)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _QuickChip(
                            label: c.label,
                            selected: _quick == c.id,
                            onTap: () => setState(() {
                              _quick = c.id;
                              _visible = _pageSize; // смена фильтра — с начала
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
                // Первая загрузка: показываем форму карточек, а не
                // «Пока ничего нет» — контент уже едет, просто не дошёл.
                sliver: loading
                    ? SliverList.separated(
                        itemCount: 4,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, _) => const PostCardSkeleton(),
                      )
                    : SliverList.separated(
                        itemCount: shown.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => PostCard(
                          post: shown[i],
                          isFavorite: favorites.contains(shown[i].id),
                          onTap: () => _open(shown[i]),
                          onToggleFavorite: () => _toggleFavorite(shown[i].id),
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
                  // Пока грузится, хвост скрыт: он мигал поверх скелетонов.
                  child: loading
                      ? const SizedBox.shrink()
                      : _ListTail(
                          hasMore: all.length > shown.length,
                          isEmpty: all.isEmpty && !feed.loading,
                          loaded: shown.length,
                          total: all.length,
                          onMore: () => setState(() => _visible += _pageSize),
                        ),
                ),
              ),
            ],
          ),
          SearchOverlay(
            open: _searchOpen,
            controller: _search,
            onChanged: (v) => setState(() {
              _query = v;
              _visible = _pageSize;
            }),
            onClose: () => setState(() {
              _searchOpen = false;
              _query = '';
              _search.clear();
            }),
          ),
        ],
      ),
    );
  }

  void _open(Post post) {
    Navigator.of(context).push(
      appRoute(context, PostDetailScreen(post: post)),
    );
  }

  Future<void> _toggleFavorite(String id) async {
    // delta считаем ПО РЕЗУЛЬТАТУ переключения: +1 добавлено, -1 убрано
    final added = await ref.read(favoritesProvider.notifier).toggle(id);
    await ref.read(metricsProvider).registerFavorite(id, added ? 1 : -1);
  }
}

/// Чип быстрого фильтра: капсула с мягкой анимацией выбора.
class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : scheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? scheme.primary : AppColors.separator(context),
          ),
        ),
        child: Text(
          label,
          style: AppText.footnote.copyWith(
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : null,
          ),
        ),
      ),
    );
  }
}

/// Хвост ленты: «показать ещё» или «лента закончилась».
class _ListTail extends StatelessWidget {
  const _ListTail({
    required this.hasMore,
    required this.isEmpty,
    required this.loaded,
    required this.total,
    required this.onMore,
  });

  final bool hasMore;
  final bool isEmpty;
  final int loaded;
  final int total;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    if (isEmpty) return const _EmptyState();
    if (hasMore) {
      return OutlinedButton(
        onPressed: onMore,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        ),
        child: Text('Показать ещё ($loaded из $total)'),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle_outline_rounded,
            size: 16, color: AppColors.secondaryLight),
        const SizedBox(width: 6),
        // Flexible: длинная подпись на узком экране должна сжиматься,
        // иначе строка вылезает за границы (RenderFlex overflow).
        Flexible(
          child: Text(
            'Это всё — новых записей больше нет',
            style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

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
              'Нет сети — показаны сохранённые данные',
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.inbox_rounded,
              size: 44, color: AppColors.secondaryLight.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text(
            'Пока ничего нет',
            style: AppText.headline.copyWith(color: AppColors.secondaryLight),
          ),
          const SizedBox(height: 4),
          Text(
            'Новые записи появятся здесь сразу после публикации',
            textAlign: TextAlign.center,
            style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
          ),
        ],
      ),
    );
  }
}
