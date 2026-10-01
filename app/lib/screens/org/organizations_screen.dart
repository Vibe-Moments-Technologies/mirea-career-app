import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/screen_header.dart';
import '../../core/widgets/search_overlay.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import 'org_screen.dart';

/// Организации: список тех, кто публикует карточки.
///
/// Список собирается из уже загруженной ленты — отдельного запроса к БД не
/// нужно: каждая карточка несёт вложенную организацию. Таблицы
/// organizations в фиде нет отдельным списком, поэтому показываем тех, у кого
/// есть хотя бы одна опубликованная карточка.
class OrganizationsScreen extends ConsumerStatefulWidget {
  const OrganizationsScreen({super.key});

  @override
  ConsumerState<OrganizationsScreen> createState() => _OrganizationsScreenState();
}

class _OrganizationsScreenState extends ConsumerState<OrganizationsScreen> {
  /// null = все, иначе 'university_dept' | 'partner'.
  String? _source;
  bool _searchOpen = false;
  String _query = '';
  final _search = TextEditingController();

  void _closeSearch() {
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
    final orgs = _organizationsOf(feed.posts, _source, _query);
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);
    final loading = feed.loading && feed.posts.isEmpty;

    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: ScreenHeader(
                  title: 'Организации',
                  actions: [
                    HeaderAction(
                      icon: Icons.search_rounded,
                      tooltip: 'Поиск',
                      onTap: () => setState(() => _searchOpen = true),
                    ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(pad, 0, pad, 12),
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
                      child: Text(
                        _query.isEmpty
                            ? 'Организаций пока нет'
                            : 'Никого не нашлось по запросу «$_query»',
                        textAlign: TextAlign.center,
                        style: AppText.body
                            .copyWith(color: AppColors.secondaryLight),
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
                    itemBuilder: (_, i) => _OrgCard(org: orgs[i]),
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
                  child: const SizedBox.shrink(),
                ),
              ),
            ],
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

/// Список организаций, собранный из ленты, с фильтром по типу и поиском.
List<Organization> _organizationsOf(
  List<Post> posts,
  String? source,
  String query,
) {
  final byId = <String, Organization>{};
  final postCount = <String, int>{};
  for (final p in posts) {
    final org = p.organization;
    if (org == null) continue;
    postCount[p.organizationId] = (postCount[p.organizationId] ?? 0) + 1;
    byId.putIfAbsent(p.organizationId, () => org);
  }
  final q = query.trim().toLowerCase();
  final out = byId.values
      .where((o) => source == null || o.type == source)
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
    final count = id == null
        ? counts.values.fold(0, (a, b) => a + b)
        : (counts[id] ?? 0);
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

/// Карточка организации: кто это, сколько у него предложений.
class _OrgCard extends StatelessWidget {
  const _OrgCard({required this.org});

  final Organization org;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial =
        org.name.trim().isEmpty ? '—' : org.name.trim().substring(0, 1).toUpperCase();

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
                      style: AppText.headline,
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