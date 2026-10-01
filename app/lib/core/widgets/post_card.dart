import 'package:flutter/material.dart';

import '../../data/catalogs.dart';
import '../../data/models.dart';
import '../theme/app_theme.dart';
import 'post_image.dart';

/// Карточка поста в ленте.
///
/// Приоритет (is_featured) на карточке никак не рисуется: он влияет только
/// на порядок в списке (`priorityFirst`). Метка, обводка и подпись делали из
/// карточки «особый тип», которого на самом деле нет.
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

    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: AppColors.separator(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        highlightColor: scheme.primary.withValues(alpha: 0.06),
        splashColor: scheme.primary.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Thumb(post: post),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TypeBadge(type: post.type),
                    const SizedBox(height: 5),
                    Text(
                      post.title,
                      style: AppText.cardTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    _MetaLine(post: post),
                    if (post.tags.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      _TagsRow(tags: post.tags),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: onToggleFavorite,
                icon: Icon(
                  isFavorite
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  color:
                      isFavorite ? scheme.primary : AppColors.secondaryLight,
                ),
                tooltip:
                    isFavorite ? 'Убрать из избранного' : 'В избранное',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Заглушка на время первой загрузки.
///
/// Без неё экран показывал «Пока ничего нет», пока посты ещё ехали из сети —
/// выглядело как пустой каталог, а потом контент появлялся скачком.
class PostCardSkeleton extends StatelessWidget {
  const PostCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.placeholder(Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.separator(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _block(color, 72, 72, AppRadius.thumb),
          const SizedBox(width: 12),
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
      PostCover(post: post, size: 72, radius: AppRadius.thumb, letter: true);
}

/// Тип поста нейтральным текстом.
///
/// Бейдж не цветной по типу: пять разных цветов на карточках превращали ленту
/// в пёстрое поле, а разницу между «вакансией» и «стажировкой» несёт подпись.
class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    return Text(
      (Catalogs.postTypes[type] ?? type).toUpperCase(),
      style: AppText.caption.copyWith(
        color: AppColors.secondaryLight,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
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
            style:
                AppText.caption.copyWith(color: AppColors.secondaryLight),
          ),
        ],
      ],
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    // Организация и дата в одну строку: две отдельные серые строки опускали
    // заголовок и выглядели как дублирование метаданных.
    final organization = post.organizationName?.trim();
    final details = [
      if (organization?.isNotEmpty ?? false) organization!,
      if (post.eventDate != null) _formatDate(post.eventDate!),
    ].join(' · ');
    if (details.isEmpty) return const SizedBox.shrink();

    return Text(
      details,
      style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

String _formatDate(DateTime d) {
  const months = [
    'янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];
  return '${d.day} ${months[d.month - 1]}';
}
