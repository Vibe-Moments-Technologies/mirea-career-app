import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/post_card.dart';
import '../../data/models.dart';
import '../../state/feed_filters.dart';
import '../../state/providers.dart';
import '../onboarding/onboarding_screen.dart';
import '../post/post_detail_screen.dart';

/// Главная: приоритетная карусель → чипсы → «Для вас» → «Новое» (docs/UI.md §4).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _quick = 'all';

  static const _quickChips = <({String id, String label})>[
    (id: 'all', label: 'Все'),
    (id: 'upcoming', label: 'Ближайшие'),
    (id: 'internship', label: 'Стажировки'),
    (id: 'event', label: 'События'),
    (id: 'mycampus', label: 'Мой кампус'),
  ];

  FeedFilters _applyQuick(FeedFilters f, String profileCampus) {
    switch (_quick) {
      case 'upcoming':
        return f.copyWith(onlyUpcoming: true);
      case 'internship':
        return f.copyWith(types: {'internship'});
      case 'event':
        return f.copyWith(types: {'event'});
      case 'mycampus':
        return f.copyWith(campus: profileCampus);
      default:
        return f;
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider);
    final profile = ref.watch(profileProvider);
    final favorites = ref.watch(favoritesProvider);
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    final base = const FeedFilters();
    final filtered = applyFilters(feed.posts, _applyQuick(base, profile.campus ?? ''));
    final featured = filtered.where((p) => p.isFeatured).take(5).toList();
    final personal = forYou(filtered, profile, limit: 10);
    final personalIds = personal.map((p) => p.id).toSet();
    final rest = latest(filtered, exclude: personalIds);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.read(feedProvider.notifier).refresh(),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              titleSpacing: pad,
              title: Text('Карьера МИРЭА', style: AppText.title),
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
                height: 44,
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
                          onSelected: (_) => setState(() => _quick = c.id),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (personal.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _SectionTitle(
                  title: 'Для вас',
                  action: profile.completed ? 'настроить' : null,
                  padding: pad,
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 210,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: pad),
                    itemCount: personal.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => SizedBox(
                      width: 280,
                      child: _CompactCard(
                        post: personal[i],
                        isFavorite: favorites.contains(personal[i].id),
                        onTap: () => _open(personal[i]),
                        onFav: () => _toggleFavorite(personal[i].id),
                      ),
                    ),
                  ),
                ),
              ),
            ] else if (!profile.completed)
              SliverToBoxAdapter(
                child: _PromptFillProfile(onTap: () => _openProfile()),
              ),
            SliverToBoxAdapter(
              child: _SectionTitle(title: 'Новое', padding: pad),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                pad,
                0,
                pad,
                AppInsets.scrollBottom(context),
              ),
              sliver: SliverList.separated(
                itemCount: rest.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => PostCard(
                  post: rest[i],
                  isFavorite: favorites.contains(rest[i].id),
                  onTap: () => _open(rest[i]),
                  onToggleFavorite: () => _toggleFavorite(rest[i].id),
                ),
              ),
            ),
            if (rest.isEmpty && !feed.loading)
              const SliverToBoxAdapter(child: _EmptyState()),
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

  void _openProfile() {
    final profile = ref.read(profileProvider);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnboardingScreen(
          initial: profile,
          onDone: (p) {
            ref.read(profileProvider.notifier).save(p);
            Navigator.of(context).pop();
          },
        ),
      ),
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
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);
    return SizedBox(
      height: 216,
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
    final color = AppColors.forPostType(post.type, Theme.of(context).brightness);
    final hasImage = post.imageUrl != null && post.imageUrl!.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: AppShadows.card(Theme.of(context).brightness),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasImage)
                Image.network(
                  post.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: color.withValues(alpha: 0.3)),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [color.withValues(alpha: 0.5), color.withValues(alpha: 0.2)],
                    ),
                  ),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xCC000000)],
                    stops: [0.4, 1],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        post.organizationName ?? '',
                        style: AppText.caption.copyWith(color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 8),
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
                top: 8,
                right: 8,
                child: IconButton(
                  onPressed: onFav,
                  icon: Icon(
                    isFavorite ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                    color: Colors.white,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.25),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactCard extends StatelessWidget {
  const _CompactCard({
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
    final scheme = Theme.of(context).colorScheme;
    final color = AppColors.forPostType(post.type, Theme.of(context).brightness);

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      post.organizationName ?? '',
                      style: AppText.caption.copyWith(color: color),
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: onFav,
                    child: Icon(
                      isFavorite ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                      size: 20,
                      color: isFavorite ? scheme.primary : AppColors.secondaryLight,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Text(
                  post.title,
                  style: AppText.headline,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _subtitle(post),
                style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _subtitle(Post p) {
    final parts = <String>[
      if (p.eventDate != null) 'до ${p.eventDate!.day}.${p.eventDate!.month.toString().padLeft(2, '0')}',
      if (p.campuses.isNotEmpty) 'кампус',
    ];
    return parts.isEmpty ? (p.organizationName ?? '') : parts.join(' · ');
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.action, required this.padding});
  final String title;
  final String? action;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padding, 20, padding, 4),
      child: Row(
        children: [
          Text(title, style: AppText.title),
          const Spacer(),
          if (action != null)
            Text(action!, style: AppText.footnote.copyWith(color: Theme.of(context).colorScheme.primary)),
        ],
      ),
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 40,
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
          Text(
            'Поиск по событиям и вакансиям',
            style: AppText.body.copyWith(color: AppColors.secondaryLight),
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
      color: AppColors.warning.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 16, color: AppColors.warning),
          const SizedBox(width: 8),
          Text('Нет сети — показаны сохранённые данные', style: AppText.footnote),
        ],
      ),
    );
  }
}

class _PromptFillProfile extends StatelessWidget {
  const _PromptFillProfile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 16, pad, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Расскажите о себе — подберём подходящее',
                style: AppText.body,
              ),
            ),
            TextButton(onPressed: onTap, child: const Text('Заполнить')),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: AppColors.secondaryLight.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text(
            'Пока ничего нет',
            style: AppText.headline.copyWith(color: AppColors.secondaryLight),
          ),
        ],
      ),
    );
  }
}