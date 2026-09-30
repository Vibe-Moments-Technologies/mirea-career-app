import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/post_card.dart';
import '../../data/models.dart';
import '../../state/feed_filters.dart';
import '../../state/providers.dart';
import '../post/post_detail_screen.dart';

/// Главная: карусель приоритетного → чипсы → единая лента (docs/UI.md §4).
///
/// Лента одна и сортируется сразу по трём критериям (homeFeed):
/// приоритетное (метка главного модератора) → релевантность профилю →
/// свежесть. Отдельной секции «Новое» больше нет: заголовок «Новое» после
/// фильтров выглядел странно, потому что содержимое было не только новым.
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
    final profile = ref.watch(profileProvider);
    final favorites = ref.watch(favoritesProvider);
    final width = MediaQuery.sizeOf(context).width;
    final pad = AppInsets.horizontal(width);

    final filtered = applyFilters(feed.posts, _applyQuick(const FeedFilters()));
    final featured = filtered.where((p) => p.isFeatured).take(5).toList();
    // Единая лента: приоритетное остаётся и в карусели, и в списке —
    // карусель это витрина, а пролистнувший её пользователь не должен
    // терять пост из общего потока.
    final all = homeFeed(filtered, profile);

    final shown = all.take(_visible).toList();
    final hasMore = all.length > shown.length;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.read(feedProvider.notifier).refresh(),
        child: CustomScrollView(
          slivers: [
            // Названия страницы нет (по правкам): экран начинается сразу
            // с контента — карусели или чипсов. Отступ — только safe area.
            if (feed.offline)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: AppInsets.top(context)),
                  child: const _OfflineBanner(),
                ),
              )
            else
              SliverToBoxAdapter(
                child: SizedBox(height: AppInsets.top(context)),
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
            // Плавный переход карусель → чипсы: воздух сверху и снизу,
            // чипсы не прилипают к краям карточек.
            SliverToBoxAdapter(
              child: SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.fromLTRB(pad, featured.isNotEmpty ? 14 : 8, pad, 0),
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
              padding: EdgeInsets.fromLTRB(pad, 10, pad, 0),
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
            // Хвост ленты: кнопка «показать ещё» или явный конец списка.
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

/// Чип быстрого фильтра: капсула с мягкой анимацией выбора.
class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.selected, required this.onTap});

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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
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
    if (isEmpty) {
      return const _EmptyState();
    }
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
  late final PageController _pc = PageController(viewportFraction: 0.9);
  int _page = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final pad = AppInsets.horizontal(width);
    // Высота соразмерна ширине экрана: на узких телефонах карточка иначе
    // выглядит приплюснутой, на широких — вытянутой.
    final height = (width * 0.5).clamp(170.0, 240.0);

    return Column(
      children: [
        SizedBox(
          height: height,
          child: PageView.builder(
            controller: _pc,
            itemCount: widget.posts.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) {
              final post = widget.posts[i];
              return Padding(
                padding: EdgeInsets.only(
                  left: i == 0 ? pad : 5,
                  right: i == widget.posts.length - 1 ? pad : 5,
                  top: 4,
                  bottom: 4,
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
        ),
        // Точки-индикаторы: видно, сколько карточек в витрине и где ты сейчас.
        // Раньше их не было, и переход от карусели к чипсам читался
        // как обрыв контента.
        if (widget.posts.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.posts.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? Theme.of(context).colorScheme.primary
                          : AppColors.separator(context),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
      ],
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
              // а не цветной градиент: он давал «цветные кусочки».
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
              // Метка «Приоритет»: её ставит главный модератор, и она
              // должна быть видна на витрине.
              Positioned(
                left: 14,
                top: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded, size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        'Приоритет',
                        style: AppText.caption.copyWith(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 52,
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
                    const SizedBox(height: 5),
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
                right: 10,
                bottom: 10,
                child: _RoundIconButton(
                  icon: isFavorite
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  onTap: onFav,
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
  const _RoundIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

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