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

  /// Показано карточек в ленте: грузим по 5, дальше — по мере прокрутки.
  ///
  /// «Бесконечная» лента на самом деле пагинируется на клиенте: сервер
  /// отдаёт всё (perPage=200), но показываем порциями — список длинный,
  /// и разом отрисовывать 50+ карточек бессмысленно. Сбрасывается при
  /// смене вкладки/фильтров/поиска.
  int _visibleCount = 10;

  static const _tabs = <(String, String)>[
    ('foryou', 'Для вас'),
    ('all', 'Все'),
    ('survey', 'Опросы'),
  ];

  /// Запрос по действию: параметры изменились — идём на сервер.
  ///
  /// Типы/поиск/архив фильтрует PocketBase; теги, институт, кампус и
  /// формат применяются поверх ответа на клиенте (applyFilters).
  void _reload() {
    // Новая выборка — показ карточек с начала.
    _visibleCount = 10;
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
    final banners = ref.watch(spotlightProvider);
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    // Посты ленты с клиентскими фильтрами поверх серверного ответа,
    // показанные порционно (догрузка по 5 при прокрутке).
    final posts = _clientFiltered(feed.posts).take(_visibleCount).toList();
    final totalPosts = _clientFiltered(feed.posts).length;

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
                if (banners.isNotEmpty && _tab == 'foryou')
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
                      child: SpotlightGallery(
                        banners: banners,
                        onOpenPost: _openByPublicId,
                      ),
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
                          // Приглашение настроить профиль — первой карточкой
                          // ЛЕНТЫ (не баннером над ней): на уровне постов.
                          itemCount: posts.length +
                              (!profile.hasAnswers && _tab == 'foryou' ? 1 : 0),
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            if (!profile.hasAnswers &&
                                _tab == 'foryou' &&
                                i == 0) {
                              return const _PromptProfile(profile: null);
                            }
                            final postIndex =
                                i - (!profile.hasAnswers && _tab == 'foryou' ? 1 : 0);
                            return RevealOnMount(
                              child: PostCard(
                                post: posts[postIndex],
                                onTap: () => _open(posts[postIndex]),
                                filledForm: ref.watch(
                                    hasSubmittedProvider(posts[postIndex].id)),
                              ),
                            );
                          },
                        ),
                ),
                // Догрузка по 5: когда лента дошла до конца показанного,
                // под скроллом лежит индикатор «ещё» — подъезд к нему
                // открывает следующую пятёрку.
                if (!feed.loading && posts.length < totalPosts)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(pad, 10, pad, 0),
                    sliver: SliverToBoxAdapter(
                      child: _LoadMoreCard(
                        onLoad: () =>
                            setState(() => _visibleCount = totalPosts.clamp(
                              _visibleCount,
                              _visibleCount + 5,
                            )),
                      ),
                    ),
                  ),
                // Хвост ленты: в «Для вас»/«Опросы» — карточка-CTA
                // «Это всё» размером с обычную карточку; во «Все» — только
                // строка-подпись о конце списка.
                if (!feed.loading && posts.length == totalPosts &&
                    posts.isNotEmpty) ...[
                  if (_tab != 'all')
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(pad, 10, pad, 0),
                      sliver: SliverToBoxAdapter(
                        child: _AllPostsCta(
                          onTap: () {
                            setState(() => _tab = 'all');
                            _reload();
                          },
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(pad, 16, pad, 0),
                      sliver: SliverToBoxAdapter(
                        child: const ListTail(
                          isEmpty: false,
                          footer: 'Это всё — новых записей больше нет',
                        ),
                      ),
                    ),
                ],
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
                        : (posts.isEmpty
                            ? const ListTail(isEmpty: true)
                            : const SizedBox.shrink()),
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
            onSubmitted: (v) {
              setState(() => _query = v);
              _reload();
            },
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

  /// Баннер с пост-ссылкой (post:XXXXXX): пост ищется по публичному
  /// номеру и открывается стандартным экраном деталей.
  Future<void> _openByPublicId(String publicId) async {
    FocusManager.instance.primaryFocus?.unfocus();

    final post = await ref.read(postsRepoProvider).fetchPostByPublicId(publicId);
    if (!mounted) return;
    if (post == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пост недоступен')),
      );
      return;
    }
    Navigator.of(context).push(
      appRoute(context, PostDetailScreen(post: post)),
    );
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

/// CTA в конце ленты: «Для вас»/«От вуза»/«Партнёры» → открыть «Все».
///
/// Размер — как у обычной карточки поста (та же сетка: превью-заглушка,
/// заголовок, метка), чтобы не выглядела чужеродной узкой полоской.
class _AllPostsCta extends StatelessWidget {
  const _AllPostsCta({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Превью того же размера, что у карточек поста (72×72).
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.thumb),
                ),
                child: Icon(
                  Icons.grid_view_rounded,
                  size: 30,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Это всё, что подходит вам',
                      style: AppText.cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Откройте полный каталог — там есть и другое',
                      style: AppText.footnote.copyWith(
                        color: AppColors.secondaryLight,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 7),
                    // Кнопка-чип: текст сжимается, а не выталкивает строку.
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(
                          maxWidth: double.infinity,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          'Все предложения →',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
  const _PromptProfile({this.profile});

  /// Профиль нужен только для предзаполнения при повторном открытии —
  /// карточка может жить и без него (всегда берётся из watch).
  final StudentProfile? profile;

  /// Карточка-приглашение уровня ленты (не баннер): стоит ПЕРВОЙ среди
  /// постов, размером и скруглением совпадает с PostCard — не «вываливается»
  /// из списка. Вместо превью — крупная иконка на подложке.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final current = profile ?? ref.watch(profileProvider);
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(
          color: scheme.primary.withValues(alpha: 0.45),
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          appRoute(
            context,
            OnboardingScreen(
              initial: current ?? StudentProfile.empty,
              onDone: (p) {
                ref.read(profileProvider.notifier).save(p);
                Navigator.of(context).pop();
              },
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Превью-заглушка в геометрии карточки ленты.
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.thumb),
                ),
                child: Icon(Icons.auto_awesome_rounded,
                    size: 30, color: scheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Настройте ленту под себя',
                        style: AppText.headline),
                    const SizedBox(height: 3),
                    Text(
                      'Короткий опрос — институт, курс, интересы — '
                      'и «Для вас» станет вашим',
                      style: AppText.footnote
                          .copyWith(color: AppColors.secondaryLight),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Индикатор-кнопка «показать ещё»: догрузка пятёрки карточек.
///
/// Не автозагрузка по ScrollController: ручная кнопка предсказуема,
/// не грузит список сама при случайном подъезде и не спорит со свайп-
/// обновлением на резком скролле вверх.
class _LoadMoreCard extends StatelessWidget {
  const _LoadMoreCard({required this.onLoad});
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: onLoad,
        icon: const Icon(Icons.expand_more_rounded),
        label: const Text('Показать ещё 5'),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {  const _OfflineBanner();

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
