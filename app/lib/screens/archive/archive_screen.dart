import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_back_button.dart';
import '../../core/widgets/list_tail.dart';
import '../../core/widgets/post_card.dart';
import '../../core/widgets/reveal_on_mount.dart';
import '../../core/widgets/search_overlay.dart';
import '../../data/models.dart';
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
            tab: 'all',
            query: _query,
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
    final favorites = ref.watch(favoritesProvider);
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    final posts = _posts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Архив'),
        titleTextStyle: AppText.headline,
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Поиск',
            onPressed: () => setState(() => _searchOpen = true),
          ),
          const SizedBox(width: 4),
        ],
        leading: const GlassBackButton(),
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding:
                  EdgeInsets.fromLTRB(pad, 8, pad, AppInsets.screenBottom(context)),
              children: [
                if (_offline)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ArchiveOfflineBanner(),
                  ),
                if (_loading)
                  const Column(
                    children: [
                      PostCardSkeleton(),
                      SizedBox(height: 10),
                      PostCardSkeleton(),
                      SizedBox(height: 10),
                      PostCardSkeleton(),
                    ],
                  )
                else if (posts.isEmpty)
                  ListTail(
                    isEmpty: true,
                    emptyTitle: 'Архив пуст',
                    emptyBody: 'Завершённые записи появятся здесь '
                        'после окончания их срока',
                  )
                else ...[
                  for (var i = 0; i < posts.length; i++) ...[
                    RevealOnMount(
                      child: PostCard(
                        post: posts[i],
                        isFavorite: favorites.contains(posts[i].id),
                        onTap: () => _open(posts[i]),
                        onToggleFavorite: () => _toggleFavorite(posts[i].id),
                      ),
                    ),
                    if (i < posts.length - 1) const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 16),
                  ListTail(
                    isEmpty: false,
                    loaded: posts.length,
                    total: posts.length,
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

  Future<void> _toggleFavorite(String id) async {
    final added = await ref.read(favoritesProvider.notifier).toggle(id);
    await ref.read(metricsProvider).registerFavorite(id, added ? 1 : -1);
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
