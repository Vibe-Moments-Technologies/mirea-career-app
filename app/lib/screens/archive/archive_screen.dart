import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_back_button.dart';
import '../../core/widgets/list_tail.dart';
import '../../core/widgets/pinned_header_screen.dart';
import '../../core/widgets/post_card.dart';
import '../../core/widgets/reveal_on_mount.dart';
import '../../core/widgets/search_overlay.dart';
import '../../data/models.dart';
import '../../state/feed_filters.dart';
import '../../state/feed_query.dart';
import '../../state/providers.dart';
import '../post/post_detail_screen.dart';

/// Архив: лента протухших постов (end_date < now).
///
/// Подстраница «Ещё» (как «Настройки»): AppBar со стеклянной кнопкой
/// «назад» — закрыть можно и жестом, и кнопкой.
///
/// ВАЖНО: архив держит СВОЁ локальное состояние (не общий feedNotifier):
/// раньше он перезаписывал общий запрос ленты архивным фильтром, и при
/// возврате на главную она показывала пустоту — архивные посты мгновенно
/// отсеивались фильтром актуальности. Локальный state не трогает главную.
class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key});

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  bool _searchOpen = false;
  String _query = '';
  final _search = TextEditingController();

  String _tab = 'all';
  Set<String> _types = const {};

  List<Post> _posts = const [];
  bool _loading = false;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    // Архивный запрос: то же «Все», но end_date < @now.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _offline = false;
    });
    try {
      final posts = await ref.read(postsRepoProvider).fetchFeed(
            tab: _tab == 'all' ? 'all' : _tab,
            query: _query,
            types: _types,
            showArchived: true,
          );
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _offline = true;
      });
    }
  }

  void _closeSearch() {
    closeSearch();
    setState(() {
      _searchOpen = false;
      _query = '';
      _search.clear();
    });
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    final posts = _posts;

    static const _tabs = <(String, String)>[
      ('foryou', 'Для вас'),
      ('all', 'Все'),
      ('university', 'От вуза'),
      ('partner', 'Партнёры'),
      ('current', 'Текущие'),
      ('future', 'Будущие'),
    ];

    return Scaffold(
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _load,
            child: PinnedHeaderScreen(
              title: 'Архив',
              leading: const GlassBackButton(),
              actions: [
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
                  _load();
                },
              ),
              onRefresh: _load,
              slivers: [
                if (_offline)
                  const SliverToBoxAdapter(child: _ArchiveOfflineBanner()),
                if (_loading)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
                    sliver: SliverList.separated(
                      itemCount: 3,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, _) => const PostCardSkeleton(),
                    ),
                  )
                else if (posts.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(pad, 16, pad, 0),
                      child: ListTail(
                        isEmpty: true,
                        emptyTitle: 'Архив пуст',
                        emptyBody: 'В архив попадают события, завершившиеся '
                            'ранее текущего момента',
                      ),
                    ),
                  )
                else ...[
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
                    sliver: SliverList.separated(
                      itemCount: posts.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => RevealOnMount(
                        child: PostCard(
                          post: posts[i],
                          onTap: () => _open(posts[i]),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(pad, 16, pad, AppInsets.scrollBottom(context)),
                      child: ListTail(
                        isEmpty: false,
                        loaded: posts.length,
                        total: posts.length,
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
            onChanged: (v) => setState(() => _query = v),
            onClose: _closeSearch,
            onSubmitted: (v) {
              setState(() => _query = v);
              _load();
            },
          ),
        ],
      ),
    );
  }

  void _open(Post post) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).push(
      appRoute(context, PostDetailScreen(post: post)),
    );
  }
}

class _ArchiveOfflineBanner extends StatelessWidget {
  const _ArchiveOfflineBanner();

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
