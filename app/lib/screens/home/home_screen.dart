import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scroll.dart';
import '../../core/widgets/list_tail.dart';
import '../../core/widgets/post_card.dart';
import '../../core/widgets/reveal_on_mount.dart';
import '../../core/widgets/screen_header.dart';
import '../../core/widgets/search_overlay.dart';
import '../../core/widgets/spotlight_gallery.dart';
import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../state/feed_filters.dart';
import '../../state/providers.dart';
import '../catalog/catalog_screen.dart';
import '../onboarding/onboarding_screen.dart';
import '../post/post_detail_screen.dart';

/// Главная: шапка → витрина важного → персональная лента.
///
/// Ленту подбирает система под профиль (институт, уровень, интересы). Если
/// профиль не заполнен, показываем всё: пустой главный экран хуже, чем
/// общий список.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _quick = 'all';

  /// Сколько карточек показываем на главной.
  ///
  /// Остальное — по кнопке внизу, которая открывает каталог. Догружать
  /// прямо в ленту смысла нет: подборка «для вас» и так урезана, а полный
  /// список со всеми фильтрами всё равно показывает каталог.
  static const _pageSize = 10;

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

  void _closeSearch() {
    // снять фокус: иначе клавиатура остаётся висеть поверх закрытого поля
    closeSearch();
    setState(() {
      _searchOpen = false;
      _query = '';
      _search.clear();
    });
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

    // Прошедшие записи живут в архиве: в ленте им не место, но и выбрасывать
    // их из выборки раньше времени нельзя — фильтр по актуальности общий с
    // каталогом, иначе главная и каталог показывали бы разное.
    final current = relevantOnly(feed.posts);
    final filtered = applyFilters(current, _applyQuick(const FeedFilters()));
    final picked = forYou(filtered, profile, limit: 60);
    final all = homeFeed(picked.isNotEmpty ? picked : filtered, profile);
    final shown = all.take(_pageSize).toList();
    final loading = feed.loading && feed.posts.isEmpty;
    // Витрина — самостоятельные баннеры из консоли, к постам отношения не
    // имеют: в ленту не попадают, приоритет не трогают.
    final banners = ref.watch(spotlightProvider);

    return Scaffold(
      // Поиск лежит поверх ленты, поэтому экран — Stack: поле затемняет
      // контент целиком, а не торчит из-под дока.
      body: Stack(
        children: [
          RefreshIndicator(
            // свайп сверху вниз: срабатывает только у самого верха ленты,
            // ниже тянет уже сам скролл
            onRefresh: () async {
              // витрина — отдельная сущность, обновляем вместе с лентой
              await Future.wait([
                ref.read(feedProvider.notifier).refresh(),
                ref.read(spotlightProvider.notifier).refresh(),
              ]);
            },
            child: CustomScrollView(
              physics: AppScroll.refreshable,
              slivers: [
                if (feed.offline)
                  const SliverToBoxAdapter(child: _OfflineBanner()),
                // Верхний отступ берёт сама шапка: отдельный отступ давал
                // пустое поле над названием страницы.
                SliverToBoxAdapter(
                  child: ScreenHeader(
                    title: 'Карьера МИРЭА',
                    actions: [
                      HeaderAction(
                        icon: Icons.search_rounded,
                        tooltip: 'Поиск',
                        onTap: () => setState(() => _searchOpen = true),
                      ),
                    ],
                  ),
                ),
                if (!profile.hasAnswers)
                  SliverToBoxAdapter(
                    child: _PromptProfile(profile: profile),
                  ),
                if (banners.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SpotlightGallery(banners: banners),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.fromLTRB(pad, 10, pad, 0),
                      children: [
                        for (final c in _quickChips)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _QuickChip(
                              label: c.label,
                              selected: _quick == c.id,
                              onTap: () => setState(() => _quick = c.id),
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
                          // Появление карточек внахлёст: список проявляется,
                          // а не «выпрыгивает» целиком после скелетонов.
                          itemBuilder: (_, i) => RevealOnMount(
                            child: PostCard(
                              post: shown[i],
                              isFavorite: favorites.contains(shown[i].id),
                              onTap: () => _open(shown[i]),
                              onToggleFavorite: () =>
                                  _toggleFavorite(shown[i].id),
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
                      AppInsets.scrollBottom(context),
                    ),
                    // Пока грузится, хвост скрыт: он мигал поверх скелетонов.
                    child: loading
                        ? const SizedBox.shrink()
                        : ListTail(
                            hasMore: all.length > shown.length,
                            isEmpty: all.isEmpty && !feed.loading,
                            loaded: shown.length,
                            total: all.length,
                            // Кнопка не догружает, а уводит в каталог: там
                            // полный список и фильтры, здесь — только витрина.
                            onMore: _openCatalog,
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

  void _openCatalog() {
    // Каталог убран из дока, поэтому вход в него только отсюда.
    Navigator.of(context).push(
      appRoute(context, const CatalogScreen()),
    );
  }

  void _open(Post post) {
    // Поиск остаётся открытым за деталями, но клавиатура обязана уйти.
    FocusManager.instance.primaryFocus?.unfocus();
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

/// Приглашение заполнить профиль: без него подбор не работает.
class _PromptProfile extends ConsumerWidget {
  const _PromptProfile({required this.profile});

  final StudentProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 0, pad, 12),
      child: Material(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            appRoute(
              context,
              OnboardingScreen(
                initial: profile,
                onDone: (p) {
                  ref.read(profileProvider.notifier).save(p);
                  Navigator.of(context).pop();
                },
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                Icon(Icons.chevron_right_rounded, color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
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

