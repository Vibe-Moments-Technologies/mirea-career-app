import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/collapsible_section.dart';
import '../../core/widgets/filter_sheet.dart';
import '../../core/widgets/list_tail.dart';
import '../../core/widgets/pinned_header_screen.dart';
import '../../core/widgets/post_card.dart';
import '../../core/widgets/reveal_on_mount.dart';
import '../../core/widgets/screen_header.dart';
import '../../core/widgets/search_overlay.dart';
import '../../core/widgets/spotlight_gallery.dart';
import '../../data/catalogs.dart';
import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../state/feed_filters.dart';
import '../../state/feed_query.dart';
import '../../state/providers.dart';
import '../onboarding/onboarding_screen.dart';
import '../post/post_detail_screen.dart';

/// Главная — шаблон для остальных страниц:
/// закреплённая шапка + вкладки, контент прокручивается под ними.
///
/// Вкладки: «Для вас» (персональная подборка) / «Все» / «От вуза» /
/// «Партнёры». Лента запрашивается по действию: смена вкладки, поиск,
/// фильтры — а не выкачивается целиком на старте.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _tab = 'foryou';
  FeedFilters _filters = const FeedFilters();

  bool _searchOpen = false;
  String _query = '';
  final _search = TextEditingController();

  static const _tabs = <(String, String)>[
    ('foryou', 'Для вас'),
    ('all', 'Все'),
    ('university', 'От вуза'),
    ('partner', 'Партнёры'),
  ];

  /// Запрос по действию: параметры изменились — идём на сервер.
  ///
  /// Типы/поиск/архив фильтрует PocketBase; теги, институт, кампус и
  /// формат применяются поверх ответа на клиенте (applyFilters).
  void _reload() {
    ref.read(feedQueryProvider.notifier).set(
          FeedQuery(
            tab: _tab,
            filters: FeedFiltersLite(
              query: _query,
              types: _filters.types,
              showArchived: _filters.showArchived,
            ),
          ),
        );
  }

  /// Посты ленты с клиентскими фильтрами поверх серверного ответа.
  List<Post> _clientFiltered(List<Post> posts) =>
      applyFilters(posts, _filters);

  void _closeSearch() {
    // снять фокус: иначе клавиатура остаётся висеть поверх закрытого поля
    closeSearch();
    setState(() {
      _searchOpen = false;
      _query = '';
      _search.clear();
    });
    _reload();
  }

  @override
  void initState() {
    super.initState();
    // Первый запрос — открытие главной. Дальше только по действию.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedNotifierProvider);
    final profile = ref.watch(profileProvider);
    final favorites = ref.watch(favoritesProvider);
    final banners = ref.watch(spotlightProvider);
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    // «Для вас»: рекомендации закончились — CTA открывает «Все».
    final posts = _clientFiltered(feed.posts);
    final showCta = _tab == 'foryou' &&
        posts.isNotEmpty &&
        feed.exhausted &&
        forYou(posts, profile).length < posts.length;

    return Scaffold(
      // Поиск лежит поверх ленты, поэтому экран — Stack: поле затемняет
      // контент под собой, а не весь экран целиком.
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () => ref.read(feedNotifierProvider.notifier).refresh(),
            child: PinnedHeaderScreen(
              title: 'Карьера МИРЭА',
              actions: [
                HeaderAction(
                  icon: Icons.tune_rounded,
                  tooltip: 'Фильтры',
                  active: _filters.activeCount > 0,
                  onTap: _openFilters,
                ),
                HeaderAction(
                  icon: Icons.search_rounded,
                  tooltip: 'Поиск',
                  onTap: () => setState(() => _searchOpen = true),
                ),
              ],
              tabs: PinnedTabStrip(
                segments: _tabs,
                selected: _tab,
                onSelected: (id) {
                  setState(() => _tab = id);
                  _reload();
                },
              ),
              onRefresh: () =>
                  ref.read(feedNotifierProvider.notifier).refresh(),
              slivers: [
                if (feed.offline)
                  const SliverToBoxAdapter(child: _OfflineBanner()),
                if (!profile.hasAnswers)
                  SliverToBoxAdapter(
                    child: _PromptProfile(profile: profile),
                  ),
                if (banners.isNotEmpty && _tab == 'foryou')
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
                      child: SpotlightGallery(banners: banners),
                    ),
                  ),
                if (_filters.activeCount > 0)
                  SliverToBoxAdapter(
                    child: _ActiveFiltersBar(
                      filters: _filters,
                      onClear: () {
                        setState(() => _filters = const FeedFilters());
                        _reload();
                      },
                    ),
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
                if (showCta)
                  SliverToBoxAdapter(
                    child: _AllPostsCta(
                      onTap: () {
                        setState(() => _tab = 'all');
                        _reload();
                      },
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
                    child: feed.loading
                        ? const SizedBox.shrink()
                        : ListTail(
                            isEmpty: posts.isEmpty && !feed.loading,
                            loaded: posts.length,
                            total: posts.length,
                          ),
                  ),
                ),
              ],
            ),
          ),
          SearchOverlay(
            open: _searchOpen,
            controller: _search,
            onChanged: (v) {
              setState(() => _query = v);
            },
            onClose: _closeSearch,
          ),
        ],
      ),
    );
  }

  /// Смена фильтров открывает шторку; применяются по кнопке.
  ///
  /// Черновик фильтров живёт в StatefulBuilder шторки: каждый чип сразу
  /// перестраивает панель, а на сервер уходит только «Показать».
  Future<void> _openFilters() async {
    var draft = _filters;
    await showFilterSheet(
      context: context,
      title: 'Фильтры',
      onReset: () {
        draft = const FeedFilters();
      },
      applyLabel: 'Показать',
      onApply: () {
        setState(() => _filters = draft);
        _reload();
      },
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => _HomeFilters(
          filters: draft,
          onChanged: (f) => setSheet(() => draft = f),
        ),
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

/// Полоса активных фильтров под вкладками: показывает, что лента
/// отфильтрована, и даёт быстрый сброс.
class _ActiveFiltersBar extends StatelessWidget {
  const _ActiveFiltersBar({required this.filters, required this.onClear});

  final FeedFilters filters;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onClear,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.filter_alt_rounded, size: 16, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    filters.showArchived
                        ? 'Архивные записи · фильтр активен'
                        : 'Фильтры: ${filters.activeCount}',
                    style: AppText.footnote,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.close_rounded, size: 16, color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// CTA в конце рекомендаций «Для вас»: открывает вкладку «Все».
class _AllPostsCta extends StatelessWidget {
  const _AllPostsCta({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
      child: Material(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Icon(Icons.grid_view_rounded, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Это всё, что подходит вам.\nОткройте все предложения →',
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

/// Содержимое фильтр-панели главной: полный набор, как был в каталоге.
///
/// Типы и поиск уходят на сервер; теги/институт/кампус/формат
/// применяются поверх полученной страницы на клиенте.
class _HomeFilters extends StatelessWidget {
  const _HomeFilters({required this.filters, required this.onChanged});

  final FeedFilters filters;
  final ValueChanged<FeedFilters> onChanged;

  void _apply(FeedFilters f) => onChanged(f);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ActualitySegment(
          showArchived: filters.showArchived,
          onChanged: (v) => _apply(filters.copyWith(showArchived: v)),
        ),
        CollapsibleSection(
          title: 'Тип',
          open: filters.types.isNotEmpty,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in Catalogs.postTypes.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: filters.types.contains(e.key),
                  onSelected: (on) => _apply(filters.copyWith(
                    types: _toggle(filters.types, e.key, on),
                  )),
                ),
            ],
          ),
        ),
        CollapsibleSection(
          title: 'Интересы',
          open: filters.tags.isNotEmpty,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in Catalogs.interests)
                FilterChip(
                  label: Text(t.title),
                  selected: filters.tags.contains(t.id),
                  onSelected: (on) => _apply(filters.copyWith(
                    tags: _toggle(filters.tags, t.id, on),
                  )),
                ),
            ],
          ),
        ),
        CollapsibleSection(
          title: 'Институт',
          open: filters.institute != null,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final i in Catalogs.institutes)
                ChoiceChip(
                  label: Text(i.short),
                  selected: filters.institute == i.id,
                  onSelected: (sel) => _apply(
                    filters.copyWith(institute: sel ? i.id : null),
                  ),
                ),
            ],
          ),
        ),
        CollapsibleSection(
          title: 'Кампус',
          open: filters.campus != null,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in Catalogs.campuses)
                ChoiceChip(
                  label: Text(c.title),
                  selected: filters.campus == c.id,
                  onSelected: (sel) =>
                      _apply(filters.copyWith(campus: sel ? c.id : null)),
                ),
            ],
          ),
        ),
        CollapsibleSection(
          title: 'Формат',
          open: filters.format != null,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in Catalogs.formats.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: filters.format == e.key,
                  onSelected: (sel) =>
                      _apply(filters.copyWith(format: sel ? e.key : null)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static Set<String> _toggle(Set<String> current, String id, bool on) =>
      on ? {...current, id} : ({...current}..remove(id));
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
