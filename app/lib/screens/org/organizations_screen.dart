import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scroll.dart';
import '../../core/widgets/collapsible_section.dart';
import '../../core/widgets/list_tail.dart';
import '../../core/widgets/screen_header.dart';
import '../../core/widgets/reveal_on_mount.dart';
import '../../core/widgets/search_overlay.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import 'org_screen.dart';

/// Организации: список тех, кто публикует карточки.
///
/// Механика та же, что на главной: свайп-обновление и раскрывающаяся панель
/// фильтров. Список собирается из уже загруженной ленты — отдельного запроса
/// к БД не нужно: каждая карточка несёт вложенную организацию.
class OrganizationsScreen extends ConsumerStatefulWidget {
  const OrganizationsScreen({super.key});

  @override
  ConsumerState<OrganizationsScreen> createState() => _OrganizationsScreenState();
}

class _OrganizationsScreenState extends ConsumerState<OrganizationsScreen> {
  /// null = все, иначе 'university_dept' | 'partner'.
  String? _source;
  bool _searchOpen = false;
  bool _filtersOpen = false;
  String _query = '';

  /// Какие типы организаций показывать. Пусто = все.
  final Set<String> _kinds = {};

  /// Показывать только с заполненными контактами.
  bool _withContacts = false;

  final _search = TextEditingController();

  void _closeSearch() {
    closeSearch();
    setState(() {
      _searchOpen = false;
      _query = '';
      _search.clear();
    });
  }

  int get _activeFilters => _kinds.length + (_withContacts ? 1 : 0);

  void _resetFilters() => setState(() {
        _kinds.clear();
        _withContacts = false;
      });

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider);
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);
    final loading = feed.loading && feed.posts.isEmpty;

    final orgs = _organizationsOf(
      feed.posts,
      source: _source,
      query: _query,
      kinds: _kinds,
      withContacts: _withContacts,
    );

    return Scaffold(
      body: Stack(
        children: [
          RefreshIndicator(
            // свайп сверху вниз у самого верха списка; ниже тянет скролл
            onRefresh: () => ref.read(feedProvider.notifier).refresh(),
            child: CustomScrollView(
              physics: AppScroll.refreshable,
              slivers: [
                SliverToBoxAdapter(
                  child: ScreenHeader(
                    title: 'Организации',
                    actions: [
                      HeaderAction(
                        icon: Icons.tune_rounded,
                        tooltip: 'Фильтры',
                        active: _filtersOpen && _activeFilters > 0,
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
                // Фильтры раскрываются прямо на странице — как в каталоге.
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
                        active: _activeFilters,
                        kinds: _kinds,
                        withContacts: _withContacts,
                        onKind: (kind, on) => setState(() {
                          on ? _kinds.add(kind) : _kinds.remove(kind);
                        }),
                        onContacts: (on) =>
                            setState(() => _withContacts = on),
                        onReset: _resetFilters,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(pad, 0, pad, 10),
                    child: _SourceTabs(
                      value: _source,
                      counts: _counts(feed.posts),
                      onChanged: (v) => setState(() => _source = v),
                    ),
                  ),
                ),
                if (loading)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(pad, 0, pad, 0),
                    sliver: SliverList.separated(
                      itemCount: 4,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, _) => const _OrgSkeleton(),
                    ),
                  )
                else if (orgs.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.apartment_rounded,
                              size: 48,
                              color: AppColors.secondaryLight
                                  .withValues(alpha: 0.6),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _query.isEmpty
                                  ? 'Организаций пока нет'
                                  : 'Никого не нашлось',
                              style: AppText.headline,
                            ),
                            if (_activeFilters > 0) ...[
                              const SizedBox(height: 16),
                              OutlinedButton(
                                onPressed: _resetFilters,
                                child: const Text('Сбросить фильтры'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(pad, 0, pad, 0),
                    sliver: SliverList.separated(
                      itemCount: orgs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) =>
                          RevealOnMount(index: i, child: _OrgCard(org: orgs[i])),
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
                    child: ListTail(
                      isEmpty: false,
                      footer: 'Найдено организаций: ${orgs.length}',
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
}

/// Сколько организаций каждого типа — показано на переключателе.
Map<String, int> _counts(List<Post> posts) {
  final counts = <String, int>{};
  for (final p in posts) {
    final type = p.organizationType;
    if (type == null) continue;
    counts[type] = (counts[type] ?? 0) + 1;
  }
  return counts;
}

/// Список организаций, собранный из ленты, с фильтрами и поиском.
List<Organization> _organizationsOf(
  List<Post> posts, {
  String? source,
  String query = '',
  Set<String> kinds = const {},
  bool withContacts = false,
}) {
  final byId = <String, Organization>{};
  for (final p in posts) {
    final org = p.organization;
    if (org == null) continue;
    byId.putIfAbsent(p.organizationId, () => org);
  }

  final q = query.trim().toLowerCase();
  final out = byId.values
      .where((o) => source == null || o.type == source)
      .where((o) => kinds.isEmpty || kinds.contains(o.type))
      .where((o) => !withContacts ||
          (o.contactEmail ?? '').isNotEmpty ||
          (o.contactPhone ?? '').isNotEmpty ||
          (o.website ?? '').isNotEmpty)
      .where((o) => q.isEmpty || o.name.toLowerCase().contains(q))
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  return out;
}

class _SourceTabs extends StatelessWidget {
  const _SourceTabs({
    required this.value,
    required this.counts,
    required this.onChanged,
  });

  final String? value;
  final Map<String, int> counts;
  final ValueChanged<String?> onChanged;

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
          _tab(context, null, 'Все', scheme),
          _tab(context, 'university_dept', 'От вуза', scheme),
          _tab(context, 'partner', 'Партнёры', scheme),
        ],
      ),
    );
  }

  Widget _tab(
    BuildContext context,
    String? id,
    String label,
    ColorScheme scheme,
  ) {
    final selected = value == id;
    final count =
        id == null ? counts.values.fold(0, (a, b) => a + b) : (counts[id] ?? 0);
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(id),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            // число сразу в подписи: видно, что за вкладкой, без тычка
            '$label · $count',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.headline.copyWith(
              fontSize: 13,
              color: selected ? scheme.primary : AppColors.secondaryLight,
            ),
          ),
        ),
      ),
    );
  }
}

/// Фильтры организаций: тип и наличие контактов.
class _FiltersPanel extends StatelessWidget {
  const _FiltersPanel({
    required this.active,
    required this.kinds,
    required this.withContacts,
    required this.onKind,
    required this.onContacts,
    required this.onReset,
  });

  final int active;
  final Set<String> kinds;
  final bool withContacts;
  final void Function(String kind, bool on) onKind;
  final ValueChanged<bool> onContacts;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.separator(context)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CollapsibleSection(
            title: 'Тип организации',
            initiallyOpen: true,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('От вуза'),
                  selected: kinds.contains('university_dept'),
                  onSelected: (on) => onKind('university_dept', on),
                ),
                FilterChip(
                  label: const Text('Партнёры'),
                  selected: kinds.contains('partner'),
                  onSelected: (on) => onKind('partner', on),
                ),
              ],
            ),
          ),
          CollapsibleSection(
            title: 'Контакты',
            initiallyOpen: true,
            child: Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('Только с контактами'),
                  selected: withContacts,
                  onSelected: onContacts,
                ),
              ],
            ),
          ),
          if (active > 0)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onReset,
                child: const Text('Сбросить'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Карточка организации: кто это, сколько у него предложений.
class _OrgCard extends StatelessWidget {
  const _OrgCard({required this.org});

  final Organization org;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = org.name.trim().isEmpty
        ? '—'
        : org.name.trim().substring(0, 1).toUpperCase();
    final hasContacts = (org.contactEmail ?? '').isNotEmpty ||
        (org.contactPhone ?? '').isNotEmpty ||
        (org.website ?? '').isNotEmpty;

    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: AppColors.separator(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // Запрос остаётся: возврат показывает ту же найденную ленту.
          FocusManager.instance.primaryFocus?.unfocus();
          Navigator.of(context).push(
            appRoute(context, OrgScreen(organizationId: org.id)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.thumb),
                ),
                child: Text(
                  initial,
                  style: AppText.title.copyWith(color: scheme.primary),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      org.name,
                      style: AppText.cardTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      org.isPartner ? 'Компания-партнёр' : 'Подразделение вуза',
                      style: AppText.footnote
                          .copyWith(color: AppColors.secondaryLight),
                    ),
                    if ((org.description ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        org.description!,
                        style: AppText.caption
                            .copyWith(color: AppColors.secondaryLight),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (hasContacts)
                Icon(Icons.contacts_outlined,
                    size: 18, color: AppColors.secondaryLight),
              Icon(Icons.chevron_right_rounded, color: AppColors.secondaryLight),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrgSkeleton extends StatelessWidget {
  const _OrgSkeleton();

  @override
  Widget build(BuildContext context) {
    final color = AppColors.placeholder(Theme.of(context).brightness);
    return Container(
      height: 76,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.separator(context)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(AppRadius.thumb),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(height: 14, color: color),
                const SizedBox(height: 8),
                Container(height: 11, color: color),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
