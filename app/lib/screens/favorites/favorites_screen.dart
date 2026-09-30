import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/post_card.dart';
import '../../state/providers.dart';
import '../post/post_detail_screen.dart';

/// Избранное: локальный список, работает офлайн.
/// Приоритетные (isFeatured) — сверху.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(favoritesProvider);
    final feed = ref.watch(feedProvider);
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    // Порядок «сначала недавно добавленные» и без выделения приоритетных:
    // список и так собран студентом, а модераторская метка в нём — шум.
    final byId = {for (final p in feed.posts) p.id: p};
    final posts = [for (final id in ids) if (byId[id] != null) byId[id]!];

    return Scaffold(
      body: CustomScrollView(
        // Отступ учитывает верхний safe area — заголовок больше не упирается
        // в вырез экрана.
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, AppInsets.top(context), pad, 8),
            sliver: SliverToBoxAdapter(
              child: ScreenTitle('Избранное'),
            ),
          ),
          if (posts.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bookmark_border_rounded,
                        size: 56,
                        color: AppColors.secondaryLight.withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 12),
                      Text('Здесь пока пусто', style: AppText.headline),
                      const SizedBox(height: 4),
                      Text(
                        'Сохраняйте интересное — оно останется на устройстве',
                        textAlign: TextAlign.center,
                        style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 8, pad, AppInsets.scrollBottom(context)),
              sliver: SliverList.separated(
                itemCount: posts.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final post = posts[i];
                  return Dismissible(
                    key: ValueKey(post.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppRadius.card),
                      ),
                      child: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                    ),
                    onDismissed: (_) {
                      ref.read(favoritesProvider.notifier).toggle(post.id);
                      ref.read(metricsProvider).registerFavorite(post.id, -1);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Убрано из избранного')),
                      );
                    },
                    child: PostCard(
                      post: post,
                      isFavorite: true,
                      showPriority: false,
                      onTap: () => Navigator.of(context).push(
                        appRoute(context, PostDetailScreen(post: post))
                      ),
                      onToggleFavorite: () {
                        ref.read(favoritesProvider.notifier).toggle(post.id);
                        ref.read(metricsProvider).registerFavorite(post.id, -1);
                      },
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
