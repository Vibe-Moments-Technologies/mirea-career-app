import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/post_card.dart';
import '../../data/models.dart';
import '../../state/feed_filters.dart';
import '../../state/providers.dart';
import '../post/post_detail_screen.dart';

/// Главная: приоритетная карусель → чипсы → лента «Новое» (docs/UI.md §4).
///
/// Секции «Для вас» здесь намеренно нет: главная — это хронологическая лента
/// всего нового, а персональный подбор живёт в каталоге, где его можно
/// осмысленно отфильтровать. Дублировать одно и то же на двух экранах
/// смысла не было.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _quick = 'all';

  /// Сколько карточек показываем изначально и сколько докладываем.
  ///
  /// Раньше лента отдавалась целиком (`latest(..., limit: 50)`), и страница
  /// бесконечно листалась в пустоту: высота списка не соответствовала
  /// реальному числу карточек, а конца у него не было видно.
  static const _pageSize = 10;
  int _visible = _pageSize;

  static const _quickChips = <({String id, String label})>[
    (id: 'all', label: 'Все'),
    (id: 'upcoming', label: 'Ближайшие'),
    (id: 'internship', label: 'Стажировки'),
    (id: 'event', label: 'События'),
  ];

  FeedFilters _applyQuick(FeedFilters f) {
    switch (_quick) {
      case 'upcoming':
        return f.copyWith(onlyUpcoming: true);
      case 'internship':
        return f.copyWith(types: {'internship'});
      case 'event':
        return f.copyWith(types: {'event'});
      default:
        return f;
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider);
    final favorites = ref.watch(favoritesProvider);
    final width = MediaQuery.sizeOf(context).width;
    final pad = AppInsets.horizontal(width);

    final filtered = applyFilters(feed.posts, _applyQuick(const FeedFilters()));
    final featured = filtered.where((p) => p.isFeatured).take(5).toList();
    // приоритетные уже показаны в карусели — в списке не дублируем
    final featuredIds = featured.map((p) => p.id).toSet();
    final all = latest(filtered, exclude: featuredIds);

    // Блочная подгрузка: отдаём не больше _visible карточек за раз.
    final shown = all.take(_visible).toList();
    final hasMore = all.length > shown.length;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.read(feedProvider.notifier).refresh(),
        child: CustomScrollView(
          slivers: [
            // Крупный заголовок с учётом верхнего safe area. SliverAppBar
            // прижимал текст к кромке экрана (вырез, статус-бар).
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, AppInsets.top(context), pad, 10),
              sliver: SliverToBoxAdapter(
                child: ScreenTitle('Карьера РТУ МИРЭА'),
              ),
            ),
            if (feed.offline)
              const SliverToBoxAdapter(child: _OfflineBanner()),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                child: const _SearchHint(),
              ),
            ),
            if (featured.isNotEmpty)
              SliverToBoxAdapter(
                child: _HeroCarousel(
                  posts: featured,
                  favorites: favorites,
                  onOpen: _open,
                  onFav: _toggleFavorite,
                ),
              ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 46,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: pad),
                  children: [
                    for (final c in _quickChips)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(c.label),
                          selected: _quick == c.id,
                          onSelected: (_) => setState(() {
                            _quick = c.id;
                            _visible = _pageSize; // смена фильтра — с начала
                          }),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _SectionTitle(title: 'Новое', padding: pad),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, 0),
              sliver: SliverList.separated(
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
            // Конец списка: либо кнопка «показать ещё», либо подпись о том,
            // что лента закончилась. Без этого страница уходила в пустоту.
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  pad,
                  16,
                  pad,
                  AppInsets.scrollBottom(context),
                ),
                child: _ListTail(
                  hasMore: hasMore,
                  isEmpty: all.isEmpty && !feed.loading,
                  loaded: shown.length,
                  total: all.length,
                  onMore: () => setState(() => _visible += _pageSize),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _open(Post post) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
    );
  }

  Future<void> _toggleFavorite(String id) async {
    // delta считаем ПО РЕЗУЛЬТАТУ переключения: +1 добавлено, -1 убрано
    final added = await ref.read(favoritesProvider.notifier).toggle(id);
    await ref.read(metricsProvider).registerFavorite(id, added ? 1 : -1);
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
    if (isEmpty) {
      return const _EmptyState();
    }
    if (hasMore) {
      return Column(
        children: [
          OutlinedButton(
            onPressed: onMore,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            child: Text('Показать ещё ($loaded из $total)'),
          ),
          const SizedBox(height: 8),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.check_circle_outline_rounded,
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

class _HeroCarousel extends StatefulWidget {
  const _HeroCarousel({
    required this.posts,
    required this.favorites,
    required this.onOpen,
    required this.onFav,
  });

  final List<Post> posts;
  final List<String> favorites;
  final ValueChanged<Post> onOpen;
  final ValueChanged<String> onFav;

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  late final PageController _pc = PageController(viewportFraction: 0.88);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final pad = AppInsets.horizontal(width);
    // Высота карусели соразмерна ширине экрана: на узких телефонах карточка
    // иначе выглядела приплюснутой, а на широких — вытянутой.
    final height = (width * 0.52).clamp(180.0, 260.0);

    return SizedBox(
      height: height,
      child: PageView.builder(
        controller: _pc,
        itemCount: widget.posts.length,
        itemBuilder: (_, i) {
          final post = widget.posts[i];
          return Padding(
            padding: EdgeInsets.only(
              left: i == 0 ? pad : 6,
              right: i == widget.posts.length - 1 ? pad : 6,
              top: 8,
            ),
            child: _HeroCard(
              post: post,
              isFavorite: widget.favorites.contains(post.id),
              onTap: () => widget.onOpen(post),
              onFav: () => widget.onFav(post.id),
            ),
          );
        },
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.post,
    required this.isFavorite,
    required this.onTap,
    required this.onFav,
  });

  final Post post;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFav;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final hasImage = post.imageUrl != null && post.imageUrl!.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: AppShadows.card(brightness),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Без картинки — нейтральная поверхность с иконкой типа,
              // а не цветной градиент: он давал те самые «цветные кусочки».
              if (hasImage)
                Image.network(
                  post.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _HeroFallback(post: post),
                )
              else
                _HeroFallback(post: post),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xCC000000)],
                    stops: [0.35, 1],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.organizationName ?? '',
                      style: AppText.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      post.title,
                      style: AppText.title.copyWith(color: Colors.white),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: _RoundIconButton(
                  icon: isFavorite
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  onTap: onFav,
                  tooltip: isFavorite ? 'Убрать из избранного' : 'В избранное',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroFallback extends StatelessWidget {
  const _HeroFallback({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color = AppColors.forPostType(post.type, brightness);
    return Container(
      color: AppColors.placeholder(brightness),
      alignment: Alignment.center,
      child: Icon(_iconForType(post.type), size: 44, color: color.withValues(alpha: 0.6)),
    );
  }
}

/// Круглая кнопка поверх картинки — единый вид для «в избранное».
class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.3),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}

IconData _iconForType(String type) => switch (type) {
      'vacancy' => Icons.work_rounded,
      'internship' => Icons.school_rounded,
      'event' => Icons.event_rounded,
      'scholarship' => Icons.card_giftcard_rounded,
      'project' => Icons.rocket_launch_rounded,
      _ => Icons.article_rounded,
    };

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.padding});
  final String title;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padding, 18, padding, 6),
      child: Text(title, style: AppText.title),
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 42,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 20, color: AppColors.secondaryLight),
          const SizedBox(width: 8),
          // Expanded обязателен: без него длинная подсказка не сжимается
          // и вылезает за границы на узких экранах (RenderFlex overflow).
          Expanded(
            child: Text(
              'Поиск по событиям и вакансиям',
              style: AppText.body.copyWith(color: AppColors.secondaryLight),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.warning.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          Icon(Icons.inbox_rounded, size: 44, color: AppColors.secondaryLight.withValues(alpha: 0.6)),
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