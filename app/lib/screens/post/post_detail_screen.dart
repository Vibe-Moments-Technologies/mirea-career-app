import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../data/catalogs.dart';
import '../../data/models.dart';
import '../../state/providers.dart';

/// Экран деталей поста (docs/UI.md §7).
/// Открытие = один просмотр (дедупликация на устройстве), кнопка заявки —
/// всегда на виду внизу.
class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.post});

  final Post post;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  @override
  void initState() {
    super.initState();
    // просмотр засчитываем после первого кадра, чтобы не тормозить переход
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(metricsProvider).registerView(widget.post.id).then((counted) {
        if (counted && mounted) ref.read(feedProvider.notifier).bumpViews(widget.post.id);
      });
    });
  }

  Future<void> _openLink() async {
    final link = widget.post.externalLink;
    if (link == null || link.isEmpty) return;
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    // внешний браузер, не WebView (docs/UI.md §7)
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final scheme = Theme.of(context).colorScheme;
    final favorites = ref.watch(favoritesProvider);
    final isFav = favorites.contains(post.id);
    final hasLink = post.externalLink != null && post.externalLink!.isNotEmpty;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 220,
            backgroundColor: scheme.surface.withValues(alpha: 0.9),
            leading: const _GlassBackButton(),
            flexibleSpace: FlexibleSpaceBar(
              background: _Cover(post: post),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppInsets.horizontal(MediaQuery.sizeOf(context).width),
                20,
                AppInsets.horizontal(MediaQuery.sizeOf(context).width),
                // запас под закреплённую кнопку и док
                AppInsets.scrollBottom(context) + (hasLink ? 64 : 0),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MetaChips(post: post),
                  const SizedBox(height: 12),
                  Text(post.title, style: AppText.largeTitle.copyWith(fontSize: 28)),
                  const SizedBox(height: 16),
                  _Organizer(post: post),
                  const SizedBox(height: 20),
                  if (post.description.isNotEmpty)
                    _Markdownish(text: post.description),
                  if (post.tags.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in post.tags)
                          Chip(
                            label: Text('#$t'),
                            visualDensity: VisualDensity.compact,
                            side: BorderSide.none,
                            backgroundColor: scheme.primary.withValues(alpha: 0.1),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  _Stats(post: post, isFavorite: isFav),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: hasLink
          ? Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                AppInsets.scrollBottom(context) + 4,
              ),
              child: FilledButton.icon(
                onPressed: _openLink,
                icon: const Icon(Icons.open_in_new_rounded, size: 20),
                label: const Text('Перейти к регистрации'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class _GlassBackButton extends StatelessWidget {
  const _GlassBackButton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        color: Colors.black.withValues(alpha: 0.28),
        shape: const CircleBorder(),
        child: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Назад',
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forPostType(post.type, Theme.of(context).brightness);
    final hasImage = post.imageUrl != null && post.imageUrl!.isNotEmpty;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasImage)
          Image.network(
            post.imageUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: color.withValues(alpha: 0.25)),
          )
        else
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.12)],
              ),
            ),
          ),
        // затемнение под заголовок/кнопку «назад»
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x55000000), Colors.transparent],
            ),
          ),
        ),
      ],
    );
  }
}

class _MetaChips extends StatelessWidget {
  const _MetaChips({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = AppColors.forPostType(post.type, Theme.of(context).brightness);
    final items = <String>[
      Catalogs.postTypes[post.type] ?? post.type,
      Catalogs.formats[post.format] ?? post.format,
      if (post.eventDate != null) _fullDate(post.eventDate!),
      if (post.campuses.isNotEmpty) Catalogs.campusTitle(post.campuses.first),
      if (post.institutes.isNotEmpty) Catalogs.instituteTitle(post.institutes.first),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < items.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: i == 0
                  ? color.withValues(alpha: 0.15)
                  : scheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              items[i],
              style: AppText.caption.copyWith(
                color: i == 0 ? color : AppColors.secondaryLight,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

class _Organizer extends StatelessWidget {
  const _Organizer({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasLogo = post.organizationLogoUrl != null && post.organizationLogoUrl!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          if (hasLogo)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                post.organizationLogoUrl!,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _orgFallback(scheme),
              ),
            )
          else
            _orgFallback(scheme),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(post.organizationName ?? 'Организатор', style: AppText.headline),
                Text(
                  post.isPartner ? 'Компания-партнёр' : 'Подразделение вуза',
                  style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _orgFallback(ColorScheme scheme) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.apartment_rounded, color: scheme.primary, size: 22),
      );
}

class _Stats extends ConsumerWidget {
  const _Stats({required this.post, required this.isFavorite});
  final Post post;
  final bool isFavorite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // счётчики берём из ленты: там же мгновенно отражаются изменения
    final live = ref.watch(feedProvider).posts.firstWhere(
          (p) => p.id == post.id,
          orElse: () => post,
        );
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        _StatItem(icon: Icons.visibility_rounded, value: live.viewsCount, label: 'просмотров'),
        const SizedBox(width: 20),
        _StatItem(icon: Icons.bookmark_rounded, value: live.favoritesCount, label: 'в избранном'),
        const Spacer(),
        IconButton.filledTonal(
          onPressed: () async {
            HapticFeedback.mediumImpact();
            final added = await ref.read(favoritesProvider.notifier).toggle(post.id);
            ref.read(metricsProvider).registerFavorite(post.id, added ? 1 : -1);
          },
          icon: Icon(isFavorite ? Icons.bookmark_rounded : Icons.bookmark_border_rounded),
          tooltip: isFavorite ? 'Убрать из избранного' : 'В избранное',
          style: IconButton.styleFrom(
            backgroundColor: isFavorite ? scheme.primary.withValues(alpha: 0.18) : null,
          ),
        ),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.icon, required this.value, required this.label});
  final IconData icon;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.secondaryLight),
        const SizedBox(width: 6),
        Text(
          '$value',
          style: AppText.headline.copyWith(fontSize: 15),
        ),
        const SizedBox(width: 4),
        Text(label, style: AppText.footnote.copyWith(color: AppColors.secondaryLight)),
      ],
    );
  }
}

/// Минимальный рендер описания: абзацы и **жирный**.
/// ponytail: без flutter_markdown — тянем пакет ради трёх элементов разметки
/// не стоит; полноценный Markdown добавим, когда авторы начнут использовать
/// списки, ссылки и таблицы.
class _Markdownish extends StatelessWidget {
  const _Markdownish({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final paragraphs = text.split(RegExp(r'\n\s*\n'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _stripBold(p),
              style: AppText.body.copyWith(height: 1.45),
            ),
          ),
      ],
    );
  }

  static String _stripBold(String s) => s.replaceAll('**', '');
}

String _fullDate(DateTime d) {
  const months = [
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
  ];
  return '${d.day} ${months[d.month - 1]}';
}