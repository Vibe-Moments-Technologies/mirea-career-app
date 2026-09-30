import 'package:flutter/material.dart';

import '../../data/catalogs.dart';
import '../../data/models.dart';
import '../theme/app_theme.dart';
import 'post_image.dart';

/// Карточка поста в ленте (docs/UI.md §6).
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
    final brightness = Theme.of(context).brightness;

    return Material(
      color: scheme.surface,
      // Тонкая граница вместо одной только тени: на светлом фоне карточки
      // без границы «плывут», а тень выглядит грязным пятном.
      // (borderRadius и shape вместе Material не принимает — только shape.)
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: AppColors.separator(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        // Подложка нажатия мягче splash-цветов Material: короткое
        // затемнение поверхности, а не серая волна.
        highlightColor: scheme.primary.withValues(alpha: 0.06),
        splashColor: scheme.primary.withValues(alpha: 0.08),
        child: Padding(
          // Вертикальные отступы больше горизонтальных: карточка дышит
          // и не выглядит сжатой по высоте относительно превью.
          padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Thumb(post: post),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TypeBadge(type: post.type, brightness: brightness),
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
                      const SizedBox(height: 6),
                      Text(
                        // Теги одной строкой текста, а не набором цветных
                        // плашек: те же данные, но без визуального шума.
                        post.tags.take(3).map((t) => '#$t').join('  '),
                        style: AppText.caption.copyWith(color: AppColors.secondaryLight),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) =>
      PostCover(post: post, size: 84, radius: AppRadius.thumb, letter: true);
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type, required this.brightness});
  final String type;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    // Бейдж нейтральный, а не цветной по типу: пять разных цветов на карточках
    // превращали ленту в пёстрое поле. Цвет оставлен только там, где несёт
    // смысл — в заглушке картинки его тоже нет.
    return Text(
      (Catalogs.postTypes[type] ?? type).toUpperCase(),
      style: AppText.caption.copyWith(
        color: AppColors.secondaryLight,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _OrgLine extends StatelessWidget {
  const _OrgLine({required this.post});
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