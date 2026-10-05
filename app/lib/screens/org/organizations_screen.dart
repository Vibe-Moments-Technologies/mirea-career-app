import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/collapsible_section.dart';
import '../../core/widgets/filter_sheet.dart';
import '../../core/widgets/list_tail.dart';
import '../../core/widgets/pinned_header_screen.dart';
import '../../core/widgets/reveal_on_mount.dart';
import '../../core/widgets/screen_header.dart';
import '../../core/widgets/search_overlay.dart';
import '../../data/app_http_client.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import 'org_screen.dart';

/// Организации: список тех, кто публикует карточки.
///
/// Данные — прямой запрос к коллекции организаций (лёгкий, без expand
/// постов): страница открывается быстро. Шаблон страницы — как на главной:
/// закреплённая шапка, фильтры в bottom sheet, поиск поверх.
class OrganizationsScreen extends ConsumerStatefulWidget {
  const OrganizationsScreen({super.key});

  @override
  ConsumerState<OrganizationsScreen> createState() =>
      _OrganizationsScreenState();
}

class _OrganizationsScreenState extends ConsumerState<OrganizationsScreen> {
  /// null = все, иначе 'university_dept' | 'partner'.
  String? _source;
  bool _searchOpen = false;
  String _query = '';

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

  @override
  void initState() {
    super.initState();
    // Организации запрашиваются при открытии экрана, а не на старте.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(organizationsProvider.notifier).ensureLoaded(),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orgsState = ref.watch(organizationsProvider);
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);
    final loading = orgsState.loading && orgsState.orgs.isEmpty;

    final orgs = _filtered(
      orgsState.orgs,
      source: _source,
      query: _query,
      withContacts: _withContacts,
    );

    return Scaffold(
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () =>
                ref.read(organizationsProvider.notifier).refresh(),
            child: PinnedHeaderScreen(
              title: 'Организации',
              actions: [
                HeaderAction(
                  icon: Icons.tune_rounded,
                  tooltip: 'Фильтры',
                  active: _withContacts || _source != null,
                  onTap: _openFilters,
                ),
                HeaderAction(
                  icon: Icons.search_rounded,
                  tooltip: 'Поиск',
                  onTap: () => setState(() => _searchOpen = true),
                ),
              ],
              onRefresh: () =>
                  ref.read(organizationsProvider.notifier).refresh(),
              slivers: [
                if (orgsState.offline)
                  SliverToBoxAdapter(
                    child: _OfflineBanner(onRefresh: () =>
                        ref.read(organizationsProvider.notifier).refresh()),
                  ),
                if (loading)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
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
                            if (_withContacts || _source != null) ...[
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
                    padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
                    sliver: SliverList.separated(
                      itemCount: orgs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) =>
                          RevealOnMount(child: _OrgCard(org: orgs[i])),
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

  void _resetFilters() => setState(() {
        _source = null;
        _withContacts = false;
      });

  /// Фильтр-шторка: источник (вуз/партнёры) и контакты.
  Future<void> _openFilters() async {
    var source = _source;
    var withContacts = _withContacts;
    await showFilterSheet(
      context: context,
      title: 'Фильтры',
      onReset: () {
        source = null;
        withContacts = false;
      },
      applyLabel: 'Показать',
      onApply: () => setState(() {
        _source = source;
        _withContacts = withContacts;
      }),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => _OrgFilters(
          source: source,
          withContacts: withContacts,
          onSource: (v) => setSheet(() => source = v),
          onContacts: (v) => setSheet(() => withContacts = v),
        ),
      ),
    );
  }
}

/// Фильтры страницы организаций.
class _OrgFilters extends StatelessWidget {
  const _OrgFilters({
    required this.source,
    required this.withContacts,
    required this.onSource,
    required this.onContacts,
  });

  final String? source;
  final bool withContacts;
  final ValueChanged<String?> onSource;
  final ValueChanged<bool> onContacts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CollapsibleSection(
          title: 'Источник',
          initiallyOpen: true,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              children: [
                _seg(context, null, 'Все', scheme),
                _seg(context, 'university_dept', 'От вуза', scheme),
                _seg(context, 'partner', 'Партнёры', scheme),
              ],
            ),
          ),
        ),
        CollapsibleSection(
          title: 'Контакты',
          initiallyOpen: true,
          child: SwitchListTile(
            value: withContacts,
            onChanged: onContacts,
            title: const Text('Только с контактами'),
            subtitle: const Text('Есть почта, телефон или сайт'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Widget _seg(
    BuildContext context,
    String? id,
    String label,
    ColorScheme scheme,
  ) {
    final selected = source == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSource(id),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            label,
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

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.warning.withValues(alpha: 0.12),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: 16, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Нет сети — показан последний список',
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

/// Отфильтрованный список организаций.
List<Organization> _filtered(
  List<Organization> orgs, {
  String? source,
  String query = '',
  bool withContacts = false,
}) {
  final q = query.trim().toLowerCase();
  return orgs
      .where((o) => source == null || o.type == source)
      .where((o) => !withContacts ||
          (o.contactEmail ?? '').isNotEmpty ||
          (o.contactPhone ?? '').isNotEmpty ||
          (o.website ?? '').isNotEmpty)
      .where((o) => q.isEmpty || o.name.toLowerCase().contains(q))
      .toList();
}

class _OrgSkeleton extends StatelessWidget {
  const _OrgSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
    );
  }
}

class _OrgCard extends StatelessWidget {
  const _OrgCard({required this.org});

  final Organization org;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          appRoute(context, OrgScreen(organization: org)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _logo(context),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      org.name,
                      style: AppText.cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      org.isPartner ? 'Партнёр' : 'Подразделение вуза',
                      style: AppText.footnote
                          .copyWith(color: AppColors.secondaryLight),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: AppColors.secondaryLight),
            ],
          ),
        ),
      ),
    );
  }

  Widget _logo(BuildContext context) {
    if (org.logoUrl == null || org.logoUrl!.isEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundColor:
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
        child: Text(
          org.name.isNotEmpty ? org.name[0] : '?',
          style: AppText.headline,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: AppNetworkImage(
        url: org.logoUrl!,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
      ),
    );
  }
}
