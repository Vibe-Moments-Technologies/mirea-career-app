import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/catalogs.dart';
import '../../data/models.dart';
import '../theme/app_theme.dart';
import 'post_image.dart';

/// Карточка поста в ленте.
///
/// Приоритетная (isFeatured) — с акцентной обводкой и кнопкой регистрации внутри.
class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.isFavorite,
    required this.onTap,
    required this.onToggleFavorite,
  });

  final Post post;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPriority = post.isFeatured;
    final hasLink = post.externalLink != null && post.externalLink!.isNotEmpty;

    final borderColor = isPriority
        ? scheme.primary
        : AppColors.separator(context);
    final borderWidth = isPriority ? 2.0 : 1.0;

    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: borderColor, width: borderWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        highlightColor: scheme.primary.withValues(alpha: 0.06),
        splashColor: scheme.primary.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Thumb(post: post),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TypeBadge(type: post.type, isPriority: isPriority),
                        const SizedBox(height: 6),
                        Text(
                          post.title,
                          style: AppText.headline,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        _OrgLine(post: post),
                        if (post.eventDate != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            _formatDate(post.eventDate!),
                            style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
                          ),
                        ],
                        if (post.tags.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _TagsRow(tags: post.tags),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onToggleFavorite,
                    icon: Icon(
                      isFavorite ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                      color: isFavorite ? scheme.primary : AppColors.secondaryLight,
                    ),
                    tooltip: isFavorite ? 'Убрать из избранного' : 'В избранное',
                  ),
                ],
              ),
              if (hasLink) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _launchLink(post.externalLink!),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Регистрация'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _launchLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Заглушка на время первой загрузки.
///
/// Без неё экран показывал «Пока ничего нет», пока посты ещё ехали из сети —
/// выглядело как пустой каталог, а потом контент появлялся скачком.
class PostCardSkeleton extends StatelessWidget {
  const PostCardSkeleton({super.key, this.withAction = false});

  /// Место под кнопку «Регистрация» — у карточек со ссылкой.
  final bool withAction;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.placeholder(Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.separator(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _block(color, 84, 84, AppRadius.thumb),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _block(color, 70, 10, AppRadius.pill),
                    const SizedBox(height: 10),
                    _block(color, double.infinity, 16, 6),
                    const SizedBox(height: 8),
                    _block(color, 140, 12, 6),
                  ],
                ),
              ),
            ],
          ),
          if (withAction) ...[
            const SizedBox(height: 12),
            _block(color, double.infinity, 40, AppRadius.pill),
          ],
        ],
      ),
    );
  }

  Widget _block(Color color, double width, double height, double radius) =>
      Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) =>
      PostCover(post: post, size: 84, radius: AppRadius.thumb, letter: true);
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type, required this.isPriority});
  final String type;
  final bool isPriority;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Метка «Приоритет» ставит главный модератор: она и есть опознавательный
    // знак карточки, поэтому идёт перед типом, а не заменяет его.
    return Row(
      children: [
        if (isPriority) ...[
          Icon(Icons.star_rounded, size: 13, color: scheme.primary),
          const SizedBox(width: 3),
          Text(
            'Приоритет',
            style: AppText.caption.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          Text(
            '  ·  ',
            style: AppText.caption.copyWith(color: AppColors.secondaryLight),
          ),
        ],
        Text(
          (Catalogs.postTypes[type] ?? type).toUpperCase(),
          style: AppText.caption.copyWith(
            color: isPriority ? scheme.primary : AppColors.secondaryLight,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}

/// Теги: один чип и счётчик остальных.
///
/// Раньше это была строка текста `#карьера  #it  #дизайн` — при длинных
/// тегах она занимала две строки и выглядела шумом. Один чип читается
/// быстрее, а «+N» сразу показывает, что список не закончился.
class _TagsRow extends StatelessWidget {
  const _TagsRow({required this.tags});
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extra = tags.length - 1;
    return Row(
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              '#${tags.first}',
              style: AppText.caption.copyWith(color: scheme.primary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (extra > 0) ...[
          const SizedBox(width: 6),
          Text(
            '+$extra',
            style: AppText.caption.copyWith(color: AppColors.secondaryLight),
          ),
        ],
      ],
    );
  }
}

class _OrgLine extends StatelessWidget {  const _OrgLine({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    // Логотип-картинка убран: в демо у организаций placehold.co, который
    // отдаёт 403, и на его месте мигал серый квадрат. Имя организации
    // и так рядом — квадрат не добавлял ничего, кроме мерцания.
    return Row(
      children: [
        Expanded(
          child: Text(
            post.organizationName ?? '',
            style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

String _formatDate(DateTime d) {
  const months = [
    'янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];
  return '${d.day} ${months[d.month - 1]}';
}