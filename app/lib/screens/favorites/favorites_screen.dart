import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/pinned_header_screen.dart';
import '../../core/widgets/post_card.dart';
import '../../data/form_history.dart';
import '../../state/providers.dart';
import '../post/post_detail_screen.dart';

/// «Сохранённое» — вкладка дока со свитчером: Избранное / Анкеты.
///
/// Прежде «Избранное» было отдельной вкладкой, а «Мои анкеты» — подстраницей
/// «Ещё». Обе сущности про «моё, сохранённое на устройстве» — они живут
/// в одной вкладке с переключателем наверху, как вкладки главной.
class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  String _tab = 'favorites';

  static const _tabs = <(String, String)>[
    ('favorites', 'Избранное'),
    ('forms', 'Анкеты'),
  ];

  @override
  Widget build(BuildContext context) {
    return PinnedHeaderScreen(
      title: 'Сохранённое',
      tabs: PinnedTabStrip(
        segments: _tabs,
        selected: _tab,
        onSelected: (id) => setState(() => _tab = id),
      ),
      slivers: [
        if (_tab == 'favorites')
          const _FavoritesList()
        else
          const _FormsList(),
      ],
    );
  }
}

/// Вкладка «Избранное»: локальный список, работает офлайн.
class _FavoritesList extends ConsumerStatefulWidget {
  const _FavoritesList();

  @override
  ConsumerState<_FavoritesList> createState() => _FavoritesListState();
}

class _FavoritesListState extends ConsumerState<_FavoritesList> {
  @override
  void initState() {
    super.initState();
    // Данные для карточек подтягиваются при открытии экрана, а не на старте.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(feedProvider.notifier).ensureLoaded(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ids = ref.watch(favoritesProvider);
    final feed = ref.watch(feedProvider);
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    // Порядок «сначала недавно добавленные» и без выделения приоритетных:
    // список и так собран студентом, а модераторская метка в нём — шум.
    final byId = {for (final p in feed.posts) p.id: p};
    final posts = [for (final id in ids) if (byId[id] != null) byId[id]!];

    if (posts.isEmpty) {
      return const _EmptyTab(
        icon: Icons.star_border_rounded,
        title: 'Здесь пока пусто',
        text: 'Сохраняйте интересное — оно останется на устройстве',
      );
    }

    return SliverPadding(
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
              onTap: () => Navigator.of(context).push(
                appRoute(context, PostDetailScreen(post: post)),
              ),
              filledForm: ref.watch(hasSubmittedProvider(post.id)),
            ),
          );
        },
      ),
    );
  }
}

/// Вкладка «Анкеты»: история отправленных опросников (файл на устройстве).
class _FormsList extends ConsumerWidget {
  const _FormsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final submissions = ref.watch(formSubmissionsProvider);
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    if (submissions.isEmpty) {
      return const _EmptyTab(
        icon: Icons.assignment_outlined,
        title: 'Пока пусто',
        text: 'Здесь появятся анкеты мероприятий,\nкоторые вы заполнили',
      );
    }

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(pad, 8, pad, AppInsets.scrollBottom(context)),
      sliver: SliverList.separated(
        itemCount: submissions.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _SubmissionCard(
          submission: submissions[i],
          onTap: () => _showAnswers(context, submissions[i]),
        ),
      ),
    );
  }

  /// Снимок отправленных ответов: вопрос → ответ.
  ///
  /// Подписи вопросов — из снимка на момент отправки (questions),
  /// ответы — в человекочитаемом виде (bool → «Да»). Голые id и
  /// «true» показываться не должны.
  static void _showAnswers(BuildContext context, FormSubmission s) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          children: [
            Text(s.formTitle, style: AppText.title),
            const SizedBox(height: 4),
            Text(
              _formDate(s.submittedAt),
              style: AppText.caption.copyWith(color: AppColors.secondaryLight),
            ),
            const SizedBox(height: 16),
            for (final e in s.answers.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.questionLabel(e.key),
                      style: AppText.caption
                          .copyWith(color: AppColors.secondaryLight),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      FormSubmission.answerText(e.value),
                      style: AppText.body,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Дата+время для карточек и снимка: 03.11.2026 · 14:05.
String _formDate(DateTime dt) =>
    '${dt.day.toString().padLeft(2, '0')}.'
    '${dt.month.toString().padLeft(2, '0')}.'
    '${dt.year} · '
    '${dt.hour.toString().padLeft(2, '0')}:'
    '${dt.minute.toString().padLeft(2, '0')}';

/// Пустая вкладка: иконка + две строки.
class _EmptyTab extends StatelessWidget {
  const _EmptyTab({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: AppColors.secondaryLight.withValues(alpha: 0.6)),
              const SizedBox(height: 12),
              Text(title, style: AppText.headline),
              const SizedBox(height: 4),
              Text(
                text,
                textAlign: TextAlign.center,
                style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Карточка отправленной анкеты: пост, анкета, дата, число ответов.
class _SubmissionCard extends StatelessWidget {
  const _SubmissionCard({required this.submission, required this.onTap});
  final FormSubmission submission;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: AppColors.separator(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.task_alt_rounded,
                size: 28,
                color: scheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      submission.postTitle.isEmpty
                          ? submission.formTitle
                          : submission.postTitle,
                      style: AppText.headline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${submission.formTitle} · ${_formDate(submission.submittedAt)}',
                      style: AppText.caption
                          .copyWith(color: AppColors.secondaryLight),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
