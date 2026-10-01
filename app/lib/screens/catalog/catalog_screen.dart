import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/collapsible_section.dart';
import '../../core/widgets/list_tail.dart';
import '../../core/widgets/post_card.dart';
import '../../core/widgets/reveal_on_mount.dart';
import '../../core/widgets/screen_header.dart';
import '../../core/widgets/search_overlay.dart';
import '../../data/catalogs.dart';
import '../../data/models.dart';
import '../../state/feed_filters.dart';
import '../../state/providers.dart';
import '../post/post_detail_screen.dart';

/// Каталог: переключатель «Вуз / Партнёры» + панель фильтров (docs/UI.md §5).
class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  /// 'university_dept' | 'partner'. Вкладки «Для вас» больше нет: персональная
  /// подборка переехала на главную, а каталог — это поиск по всей базе.
  String _source = 'university_dept';
  FeedFilters _filters = const FeedFilters();
  bool _sortPopular = false;

  /// Блочная подгрузка: не вываливаем весь каталог сразу.
  static const _pageSize = 10;
  int _visible = _pageSize;

  /// Поиск. Поле `query` в фильтрах существовало, но ввода не было —
  /// это была самая заметная дырка в каталоге.
  final _search = TextEditingController();
  bool _searchOpen = false;
  bool _filtersOpen = false;

  @override
  void initState() {
    super.initState();
    // Фильтры — настройка интерфейса; сбрасывать их при каждом старте
    // раздражает. Читаем синхронно из LocalStore, до первого кадра.
    final saved = ref.read(localStoreProvider).catalogState;
    if (saved != null) {
      _source = saved['source'] as String? ?? _source;
      _sortPopular = saved['sortByPopularity'] as bool? ?? _sortPopular;
      final raw = saved['filters'];
      if (raw is Map) {
        _filters = FeedFilters.fromJson(raw.cast<String, dynamic>());
      }
      _search.text = _filters.query;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _persist() => ref.read(localStoreProvider).saveCatalogState({
        'source': _source,
        'sortByPopularity': _sortPopular,
        'filters': _filters.toJson(),
      });

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider);
    final favorites = ref.watch(favoritesProvider);
    final width = MediaQuery.sizeOf(context).width;
    final pad = AppInsets.horizontal(width);
    final twoColumns = width >= 600;

    final current = relevantOnly(feed.posts);

    // priorityFirst обязателен: applyFilters сортирует по дате и возвращал
    // приоритетные в середину, хотя в остальных разделах они всегда первые.
    // Прошедшие записи уходят в архив — здесь только то, что ещё актуально.
    final effective =
        _filters.copyWith(source: _source, sortByPopularity: _sortPopular);
    final posts = priorityFirst(applyFilters(current, effective));

    final shown = posts.take(_visible).toList();
    final hasMore = posts.length > shown.length;

    return Scaffold(
      // Поиск — поверх ленты (Stack), иначе поле не затемняет каталог.
      body: Stack(
        children: [
          RefreshIndicator(
            // свайп сверху вниз у самого верха списка; ниже тянет скролл
            onRefresh: () => ref.read(feedProvider.notifier).refresh(),
            child: CustomScrollView(
              slivers: [
                // Верхний отступ берёт сама шапка: отдельный давал пустое
                // поле над названием страницы.
                SliverToBoxAdapter(
                  child: ScreenHeader(
                    title: 'Каталог',
                    actions: [
                      HeaderAction(
                        icon: Icons.tune_rounded,
                        tooltip: 'Фильтры',
                        active: _filtersOpen && _filters.activeCount > 0,
                        onTap: () =>
                            setState(() => _filtersOpen = !_filtersOpen),
                      ),
                      HeaderAction(
                        icon: Icons.search_rounded,
                        tooltip: 'Поиск',
                        onTap: () => setState(() => _searchOpen = true),
                      ),
                    ],
                  ),
                ),
                // Фильтры раскрываются прямо на странице: шторка снизу
                // прятала выборку и требовала ещё одного тапа «Показать».
                SliverToBoxAdapter(
                  child: AnimatedCrossFade(
                    duration: const Duration(milliseconds: 220),
                    crossFadeState: _filtersOpen
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: const SizedBox(width: double.infinity),
                    secondChild: Padding(
                      padding: EdgeInsets.fromLTRB(pad, 0, pad, 12),
                      child: _FiltersPanel(
                        filters: _filters,
                        source: _source,
                        organizations: _organizationsOf(current, _source),
                        sortPopular: _sortPopular,
                        onChanged: (f, sort) => setState(() {
                          _filters = f;
                          _sortPopular = sort;
                          _visible = _pageSize;
                          _persist();
                        }),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(pad, 0, pad, 10),
                    child: _SourceSwitcher(
                      value: _source,
                      onChanged: (v) => setState(() {
                        _source = v;
                        _visible = _pageSize;
                        _persist();
                      }),
                    ),
                  ),
                ),
                if (feed.loading && feed.posts.isEmpty)
                  // Первая загрузка: скелетоны, а не «ничего не нашлось».
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
                    sliver: SliverList.separated(
                      itemCount: 4,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, _) => const PostCardSkeleton(),
                    ),
                  )
                else if (posts.isEmpty && !feed.loading)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyCatalog(
                      onReset: () => setState(() {
                        _filters = const FeedFilters();
                        _search.clear();
                        _visible = _pageSize;
                        _persist();
                      }),
                    ),
                  )
                else ...[
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
                    sliver: twoColumns
                        ? SliverGrid.builder(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 380,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              mainAxisExtent: 190,
                            ),
                            itemCount: shown.length,
                            itemBuilder: (_, i) => RevealOnMount(child: _card(shown[i], favorites)),
                          )
                        : SliverList.separated(
                            itemCount: shown.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) => RevealOnMount(child: _card(shown[i], favorites)),
                          ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        pad,
                        16,
                        pad,
                        // Каталог больше не в доке, а выталкивается с главной: резервировать
                        // под ним высоту дока нельзя, внизу осталась бы пустота.
                        AppInsets.screenBottom(context),
                      ),
                      child: ListTail(
                        hasMore: hasMore,
                        loaded: shown.length,
                        total: posts.length,
                        onMore: () => setState(() => _visible += _pageSize),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SearchOverlay(
            open: _searchOpen,
            controller: _search,
            onChanged: (v) => setState(() {
              _filters = _filters.copyWith(query: v);
              _visible = _pageSize;
              _persist();
            }),
            onClose: () {
              closeSearch();
              setState(() {
                _searchOpen = false;
                _search.clear();
                _filters = _filters.copyWith(query: '');
                _persist();
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _card(Post post, List<String> favorites) => PostCard(
        post: post,
        isFavorite: favorites.contains(post.id),
        onTap: () {
          // Запрос остаётся: возврат показывает ту же найденную ленту.
          FocusManager.instance.primaryFocus?.unfocus();
          Navigator.of(context).push(
            appRoute(context, PostDetailScreen(post: post))
          );
        },
        onToggleFavorite: () async {
          final added = await ref.read(favoritesProvider.notifier).toggle(post.id);
          await ref.read(metricsProvider).registerFavorite(post.id, added ? 1 : -1);
        },
      );
}

/// Раскрывающаяся панель фильтров прямо на странице каталога.
///
/// Каждая группа — своя раскрывающаяся секция: на телефоне шесть групп
/// чипов в один экран не влезали, а постоянно открытые — наоборот занимали
/// весь первый экран. Секции с выбранными значениями открыты по умолчанию.
class _FiltersPanel extends StatelessWidget {
  const _FiltersPanel({
    required this.filters,
    required this.source,
    required this.organizations,
    required this.sortPopular,
    required this.onChanged,
  });

  final FeedFilters filters;
  final String source;
  final List<Organization> organizations;
  final bool sortPopular;
  final void Function(FeedFilters filters, bool sortPopular) onChanged;

  void _apply(FeedFilters f) => onChanged(f, sortPopular);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.separator(context)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        children: [
          CollapsibleSection(
            title: 'Сортировка',
            initiallyOpen: true,
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('По дате'),
                  selected: !sortPopular,
                  onSelected: (_) => onChanged(filters, false),
                ),
                ChoiceChip(
                  label: const Text('По популярности'),
                  selected: sortPopular,
                  onSelected: (_) => onChanged(filters, true),
                ),
              ],
            ),
          ),
          CollapsibleSection(
            title: 'Тип',
            open: filters.types.isNotEmpty,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in Catalogs.postTypes.entries)
                  FilterChip(
                    label: Text(e.value),
                    selected: filters.types.contains(e.key),
                    onSelected: (on) => setStateChip(filters.copyWith(
                      types: _toggle(filters.types, e.key, on),
                    )),
                  ),
              ],
            ),
          ),
          CollapsibleSection(
            title: 'Формат',
            open: filters.format != null,
            child: Wrap(
              spacing: 8,
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
                    onSelected: (sel) =>
                        _apply(filters.copyWith(institute: sel ? i.id : null)),
                  ),
              ],
            ),
          ),
          if (organizations.isNotEmpty)
            CollapsibleSection(
              title: source == 'partner' ? 'Компания' : 'Подразделение',
              open: filters.organizationId != null,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in organizations)
                    ChoiceChip(
                      label: Text(o.name),
                      selected: filters.organizationId == o.id,
                      onSelected: (sel) => _apply(
                        filters.copyWith(organizationId: sel ? o.id : null),
                      ),
                    ),
                ],
              ),
            ),
          CollapsibleSection(
            title: 'Теги',
            open: filters.tags.isNotEmpty,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in Catalogs.interests)
                  FilterChip(
                    label: Text(t.title),
                    selected: filters.tags.contains(t.id),
                    onSelected: (on) =>
                        _apply(filters.copyWith(tags: _toggle(filters.tags, t.id, on))),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Мультивыбор: чипы сами меняют состояние фильтров — setState не нужен,
  /// перерисовку делает родитель через [onChanged].
  void setStateChip(FeedFilters f) => _apply(f);

  static Set<String> _toggle(Set<String> current, String id, bool on) =>
      on ? {...current, id} : ({...current}..remove(id));
}


class _SourceSwitcher extends StatelessWidget {
  const _SourceSwitcher({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        children: [
          _segment('university_dept', 'От вуза', scheme),
          _segment('partner', 'От партнёров', scheme),
        ],
      ),
    );
  }

  Widget _segment(String id, String label, ColorScheme scheme) {
    final selected = value == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(id),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? scheme.primary.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.headline.copyWith(
              fontSize: 14,
              color: selected ? scheme.primary : AppColors.secondaryLight,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog({required this.onReset});

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_alt_off_rounded,
              size: 48,
              color: AppColors.secondaryLight.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text('Ничего не нашлось', style: AppText.headline),
            const SizedBox(height: 4),
            Text(
              'Попробуйте изменить фильтры или поиск',
              textAlign: TextAlign.center,
              style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onReset, child: const Text('Сбросить фильтры')),
          ],
        ),
      ),
    );
  }
}


/// Организации выбранного источника, собранные из загруженной ленты.
List<Organization> _organizationsOf(List<Post> posts, String source) {
  final byId = <String, Organization>{};
  for (final p in posts) {
    if (p.organizationType != source) continue;
    byId.putIfAbsent(
      p.organizationId,
      () => Organization(
        id: p.organizationId,
        name: p.organizationName ?? '',
        type: p.organizationType ?? '',
        logoUrl: p.organizationLogoUrl,
      ),
    );
  }
  return byId.values.toList()..sort((a, b) => a.name.compareTo(b.name));
}