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
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Thumb(post: post),
              const SizedBox(width: 12),
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
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _OrgLine(post: post),
                      ],
                    ),
                    if (post.eventDate != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _formatDate(post.eventDate!),
                        style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
                      ),
                    ],
                    if (post.tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in post.tags.take(2))
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(AppRadius.pill),
                              ),
                              child: Text(
                                '#$t',
                                style: AppText.caption.copyWith(color: scheme.primary),
                              ),
                            ),
                        ],
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
    final color = AppColors.forPostType(post.type, Theme.of(context).brightness);
    final hasImage = post.imageUrl != null && post.imageUrl!.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.thumb),
      child: SizedBox(
        width: 96,
        height: 96,
        child: hasImage
            ? Image.network(
                post.imageUrl!,
                fit: BoxFit.cover,
                // офлайн/битая ссылка — тип-заглушка вместо пустоты
                errorBuilder: (_, __, ___) => _fallback(color),
              )
            : _fallback(color),
      ),
    );
  }

  Widget _fallback(Color color) => Container(
        color: color.withValues(alpha: 0.18),
        alignment: Alignment.center,
        child: Icon(_iconForType(post.type), color: color, size: 32),
      );
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type, required this.brightness});
  final String type;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forPostType(type, brightness);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        Catalogs.postTypes[type] ?? type,
        style: AppText.caption.copyWith(color: color, fontWeight: FontWeight.w600),
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
    return Expanded(
      child: Row(
        children: [
          if (hasLogo)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                post.organizationLogoUrl!,
                width: 18,
                height: 18,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(width: 18, height: 18),
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
      ),
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