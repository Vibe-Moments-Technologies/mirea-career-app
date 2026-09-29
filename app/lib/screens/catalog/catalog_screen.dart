import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/post_card.dart';
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
  String _source = 'university_dept'; // 'university_dept' | 'partner'
  FeedFilters _filters = const FeedFilters();
  bool _sortPopular = false;

  void _openSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FilterSheet(
        initial: _filters,
        source: _source,
        // список организаций собираем из уже загруженной ленты
        organizations: _organizationsOf(ref.read(feedProvider).posts, _source),
        onApply: (f) => setState(() => _filters = f),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider);
    final favorites = ref.watch(favoritesProvider);
    final width = MediaQuery.sizeOf(context).width;
    final pad = AppInsets.horizontal(width);
    final twoColumns = width >= 600;

    final effective = _filters.copyWith(source: _source, sortByPopularity: _sortPopular);
    final posts = applyFilters(feed.posts, effective);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            titleSpacing: pad,
            title: Text('Каталог', style: AppText.title),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: _SourceSwitcher(
                value: _source,
                onChanged: (v) => setState(() => _source = v),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, 12, pad, 4),
              child: Row(
                children: [
                  _FilterButton(
                    activeCount: _filters.activeCount,
                    onTap: _openSheet,
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    onPressed: () => setState(() => _sortPopular = !_sortPopular),
                    avatar: Icon(
                      _sortPopular ? Icons.trending_up_rounded : Icons.schedule_rounded,
                      size: 18,
                    ),
                    label: Text(_sortPopular ? 'По популярности' : 'По дате'),
                  ),
                  const Spacer(),
                  Text(
                    '${posts.length}',
                    style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
                  ),
                ],
              ),
            ),
          ),
          if (posts.isEmpty && !feed.loading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyCatalog(onReset: () => setState(() => _filters = const FeedFilters())),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                pad,
                8,
                pad,
                AppInsets.scrollBottom(context),
              ),
              sliver: twoColumns
                  ? SliverGrid.builder(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 380,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        mainAxisExtent: 132,
                      ),
                      itemCount: posts.length,
                      itemBuilder: (_, i) => _card(posts[i], favorites),
                    )
                  : SliverList.separated(
                      itemCount: posts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _card(posts[i], favorites),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _card(Post post, List<String> favorites) => PostCard(
        post: post,
        isFavorite: favorites.contains(post.id),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
        ),
        onToggleFavorite: () async {
          final added = await ref.read(favoritesProvider.notifier).toggle(post.id);
          await ref.read(metricsProvider).registerFavorite(post.id, added ? 1 : -1);
        },
      );
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? scheme.primary.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppText.headline.copyWith(
              fontSize: 15,
              color: selected ? scheme.primary : AppColors.secondaryLight,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.activeCount, required this.onTap});
  final int activeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ActionChip(
      onPressed: onTap,
      avatar: Icon(
        Icons.tune_rounded,
        size: 18,
        color: activeCount > 0 ? scheme.primary : null,
      ),
      label: Text(activeCount > 0 ? 'Фильтры · $activeCount' : 'Фильтры'),
      backgroundColor: activeCount > 0 ? scheme.primary.withValues(alpha: 0.12) : null,
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
              'Попробуйте изменить фильтры',
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

/// Панель фильтров (docs/UI.md §5).
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.initial,
    required this.source,
    required this.organizations,
    required this.onApply,
  });

  final FeedFilters initial;
  final String source;

  /// Организации выбранного источника — берутся из уже загруженной ленты,
  /// отдельного запроса к БД не нужно.
  final List<Organization> organizations;
  final ValueChanged<FeedFilters> onApply;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late FeedFilters _f = widget.initial.copyWith(source: widget.source);

  @override
  Widget build(BuildContext context) {
    final organizations = widget.organizations;
    final scheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      builder: (_, controller) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              children: [
                Text('Фильтры', style: AppText.title),
                const SizedBox(height: 16),
                const _Label('Тип'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in Catalogs.postTypes.entries)
                      FilterChip(
                        label: Text(e.value),
                        selected: _f.types.contains(e.key),
                        onSelected: (_) => setState(() {
                          final t = {..._f.types};
                          t.contains(e.key) ? t.remove(e.key) : t.add(e.key);
                          _f = _f.copyWith(types: t);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                const _Label('Формат'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final e in Catalogs.formats.entries)
                      ChoiceChip(
                        label: Text(e.value),
                        selected: _f.format == e.key,
                        onSelected: (sel) => setState(
                          () => _f = _f.copyWith(format: sel ? e.key : null),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                const _Label('Кампус'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final c in Catalogs.campuses)
                      ChoiceChip(
                        label: Text(c.title),
                        selected: _f.campus == c.id,
                        onSelected: (sel) => setState(
                          () => _f = _f.copyWith(campus: sel ? c.id : null),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                const _Label('Институт'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final i in Catalogs.institutes)
                      ChoiceChip(
                        label: Text(i.short),
                        selected: _f.institute == i.id,
                        onSelected: (sel) => setState(
                          () => _f = _f.copyWith(institute: sel ? i.id : null),
                        ),
                      ),
                  ],
                ),
                if (organizations.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _Label(widget.source == 'partner' ? 'Компания' : 'Подразделение'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final o in organizations)
                        ChoiceChip(
                          label: Text(o.name),
                          selected: _f.organizationId == o.id,
                          onSelected: (sel) => setState(
                            () => _f = _f.copyWith(organizationId: sel ? o.id : null),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                const _Label('Теги'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in Catalogs.interests)
                      FilterChip(
                        label: Text(t.title),
                        selected: _f.tags.contains(t.id),
                        onSelected: (_) => setState(() {
                          final s = {..._f.tags};
                          s.contains(t.id) ? s.remove(t.id) : s.add(t.id);
                          _f = _f.copyWith(tags: s);
                        }),
                      ),
                  ],
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() => _f = FeedFilters(source: widget.source)),
                    child: const Text('Сбросить'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        widget.onApply(_f);
                        Navigator.of(context).pop();
                      },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        backgroundColor: scheme.primary,
                      ),
                      child: const Text('Показать'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: AppText.headline.copyWith(color: AppColors.secondaryLight, fontSize: 14),
        ),
      );
}

/// Организации выбранного источника, собранные из загруженной ленты.
List<Organization> _organizationsOf(List<Post> posts, String source) {
  final map = <String, Organization>{};
  for (final p in posts) {
    if (p.organizationType != source) continue;
    map.putIfAbsent(
      p.organizationId,
      () => Organization(
        id: p.organizationId,
        name: p.organizationName ?? '',
        type: p.organizationType ?? '',
        logoUrl: p.organizationLogoUrl,
      ),
    );
  }
  return map.values.toList()..sort((a, b) => a.name.compareTo(b.name));
}