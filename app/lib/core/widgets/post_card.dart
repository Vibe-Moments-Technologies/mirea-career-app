import 'package:flutter/material.dart';

import '../../data/catalogs.dart';
import '../../data/models.dart';
import '../theme/app_theme.dart';

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
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          // Вертикальные отступы больше горизонтальных: карточка дышит
          // и не выглядит сжатой по высоте относительно превью.
          padding: const EdgeInsets.fromLTRB(12, 14, 4, 14),
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
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final hasImage = post.imageUrl != null && post.imageUrl!.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.thumb),
      child: SizedBox(
        width: 84,
        height: 84,
        child: hasImage
            ? Image.network(
                post.imageUrl!,
                fit: BoxFit.cover,
                // офлайн/битая ссылка — нейтральная заглушка вместо пустоты
                errorBuilder: (_, _, _) => _fallback(brightness),
              )
            : _fallback(brightness),
      ),
    );
  }

  /// Нейтральная подложка с иконкой типа.
  ///
  /// Раньше каждая карточка несла цветной блок по типу поста — в ленте это
  /// выглядело как набор разноцветных заплаток. Тип уже подписан бейджем,
  /// так что цвет здесь ничего не добавлял.
  Widget _fallback(Brightness brightness) => Container(
        color: AppColors.placeholder(brightness),
        alignment: Alignment.center,
        child: Icon(
          _iconForType(post.type),
          color: AppColors.secondaryLight,
          size: 30,
        ),
      );
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
    final hasLogo = post.organizationLogoUrl != null && post.organizationLogoUrl!.isNotEmpty;
    return Row(
      children: [
        if (hasLogo)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.network(
              post.organizationLogoUrl!,
              width: 16,
              height: 16,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(width: 16, height: 16),
            ),
          ),
        if (hasLogo) const SizedBox(width: 6),
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

IconData _iconForType(String type) => switch (type) {
      'vacancy' => Icons.work_rounded,
      'internship' => Icons.school_rounded,
      'event' => Icons.event_rounded,
      'scholarship' => Icons.card_giftcard_rounded,
      'project' => Icons.rocket_launch_rounded,
      _ => Icons.article_rounded,
    };

String _formatDate(DateTime d) {
  const months = [
    'янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];
  return '${d.day} ${months[d.month - 1]}';
}