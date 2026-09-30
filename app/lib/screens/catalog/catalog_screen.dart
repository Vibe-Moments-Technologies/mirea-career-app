import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/post_card.dart';
import '../../data/catalogs.dart';
import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../state/feed_filters.dart';
import '../../state/providers.dart';
import '../onboarding/onboarding_screen.dart';
import '../post/post_detail_screen.dart';

/// Каталог: переключатель «Вуз / Партнёры» + панель фильтров (docs/UI.md §5).
class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  /// 'for_you' | 'university_dept' | 'partner'.
  /// По умолчанию — «Для вас»: это персональный вход, ради которого
  /// студент и открывает каталог.
  String _source = 'for_you';
  FeedFilters _filters = const FeedFilters();
  bool _sortPopular = false;

  /// Блочная подгрузка: не вываливаем весь каталог сразу.
  static const _pageSize = 10;
  int _visible = _pageSize;

  /// Поиск. Поле `query` в фильтрах существовало, но ввода не было —
  /// это была самая заметная дырка в каталоге.
  final _search = TextEditingController();

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
        onApply: (f) => setState(() {
          _filters = f;
          // «Сбросить» в панели фильтров должен очищать и строку поиска,
          // иначе поле осталось бы с текстом, которого уже нет в фильтре.
          if (_search.text != f.query) _search.text = f.query;
          _visible = _pageSize;
          _persist();
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider);
    final profile = ref.watch(profileProvider);
    final favorites = ref.watch(favoritesProvider);
    final width = MediaQuery.sizeOf(context).width;
    final pad = AppInsets.horizontal(width);
    final twoColumns = width >= 600;

    final forYouMode = _source == 'for_you';

    final List<Post> posts;
    if (forYouMode) {
      // Персональный подбор переехал сюда с главной: здесь его можно
      // осмысленно отфильтровать, а не просто пролистать.
      // priorityFirst обязателен и здесь: applyFilters сортирует по дате и
      // возвращал приоритетные в середину, хотя в остальных разделах они
      // всегда первые.
      posts = priorityFirst(
        applyFilters(forYou(feed.posts, profile, limit: 200), _filters),
      );
    } else {
      final effective =
          _filters.copyWith(source: _source, sortByPopularity: _sortPopular);
      posts = priorityFirst(applyFilters(feed.posts, effective));
    }

    final shown = posts.take(_visible).toList();
    final hasMore = posts.length > shown.length;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Заголовка страницы нет (по правкам): экран начинается сразу
          // с переключателя разделов. Отступ — только safe area.
          SliverToBoxAdapter(
            child: SizedBox(height: AppInsets.top(context)),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, 4, pad, 10),
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
          // Поиск по заголовку, тегам и организатору. Фильтрация локальная и
          // мгновенная: список уже в памяти, поэтому debounce не нужен.
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, 10),
              child: _SearchField(
                controller: _search,
                onChanged: (v) => setState(() {
                  _filters = _filters.copyWith(query: v);
                  _visible = _pageSize;
                  _persist();
                }),
              ),
            ),
          ),
          // В режиме «Для вас» строка с фильтрами не нужна: фильтры скрыты,
          // а одинокая цифра справа выглядит странно.
          if (!forYouMode)
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
                      onPressed: () => setState(() {
                        _sortPopular = !_sortPopular;
                        _visible = _pageSize;
                      }),
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
          if (forYouMode && !profile.completed)
            SliverToBoxAdapter(
              child: _PromptFillProfile(
                onTap: () => _openProfile(profile),
              ),
            ),
          if (feed.loading && feed.posts.isEmpty)
            // Первая загрузка: скелетоны, а не «ничего не нашлось».
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
              sliver: SliverList.separated(
                itemCount: 4,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => PostCardSkeleton(),
              ),
            )
          else if (posts.isEmpty && !feed.loading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyCatalog(
                forYouMode: forYouMode,
                onReset: () => setState(() {
                  _filters = const FeedFilters();
                  _search.clear();
                  _visible = _pageSize;
                  _persist();
                }),
                onFillProfile: () => _openProfile(profile),
              ),
            )
          else ...[
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
              sliver: twoColumns
                  ? SliverGrid.builder(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 380,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        // Карточка выросла: блок контента + кнопка «Регистрация»
                        // внутри. 148 pt обрезали её на планшетах.
                        mainAxisExtent: 210,
                      ),
                      itemCount: shown.length,
                      itemBuilder: (_, i) => _card(shown[i], favorites),
                    )
                  : SliverList.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _card(shown[i], favorites),
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
                child: hasMore
                    ? OutlinedButton(
                        onPressed: () => setState(() => _visible += _pageSize),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                        ),
                        child: Text('Показать ещё (${shown.length} из ${posts.length})'),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline_rounded,
                              size: 16, color: AppColors.secondaryLight),
                          const SizedBox(width: 6),
                          Text(
                            'Это всё — новых записей больше нет',
                            style: AppText.footnote
                                .copyWith(color: AppColors.secondaryLight),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openProfile(StudentProfile profile) {
    Navigator.of(context).push(
      CupertinoPageRoute(
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

  Widget _card(Post post, List<String> favorites) => PostCard(
        post: post,
        isFavorite: favorites.contains(post.id),
        onTap: () => Navigator.of(context).push(
          CupertinoPageRoute(builder: (_) => PostDetailScreen(post: post)),
        ),
        onToggleFavorite: () async {
          final added = await ref.read(favoritesProvider.notifier).toggle(post.id);
          await ref.read(metricsProvider).registerFavorite(post.id, added ? 1 : -1);
        },
      );
}

/// Поле поиска: по одному запуску на ввод, без задержки.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: AppText.body,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Поиск по вакансиям и событиям',
        hintStyle: AppText.body.copyWith(color: AppColors.secondaryLight),
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'Очистить',
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide(color: AppColors.separator(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide(color: AppColors.separator(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
    );
  }
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
          // «Для вас» первым: это персональный вход по цели студента,
          // а не ещё одна рубрика каталога.
          _segment('for_you', 'Для вас', scheme),
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
  const _EmptyCatalog({
    required this.onReset,
    this.forYouMode = false,
    this.onFillProfile,
  });

  final VoidCallback onReset;
  final bool forYouMode;
  final VoidCallback? onFillProfile;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              forYouMode ? Icons.auto_awesome_rounded : Icons.filter_alt_off_rounded,
              size: 48,
              color: AppColors.secondaryLight.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              forYouMode ? 'Подбор пока пуст' : 'Ничего не нашлось',
              style: AppText.headline,
            ),
            const SizedBox(height: 4),
            Text(
              forYouMode
                  ? 'Заполните профиль — подберём подходящее'
                  : 'Попробуйте изменить фильтры',
              textAlign: TextAlign.center,
              style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
            ),
            const SizedBox(height: 16),
            if (forYouMode && onFillProfile != null)
              FilledButton(onPressed: onFillProfile, child: const Text('Заполнить профиль'))
            else
              OutlinedButton(onPressed: onReset, child: const Text('Сбросить фильтры')),
          ],
        ),
      ),
    );
  }
}

/// Приглашение заполнить профиль — то, ради чего существует «Для вас».
class _PromptFillProfile extends StatelessWidget {
  const _PromptFillProfile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 16, pad, 0),
      child: Material(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Padding(
            padding: const EdgeInsets.all(16),
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