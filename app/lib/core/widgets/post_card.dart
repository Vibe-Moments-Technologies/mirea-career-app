import 'package:flutter/material.dart';

import '../../data/catalogs.dart';
import '../../data/models.dart';
import '../format.dart';
import '../theme/app_theme.dart';
import 'post_image.dart';

/// Размер превью в карточке ленты.
///
/// Карточка намеренно крупная (превью 104, воздух 14): лента — главный экран
/// приложения, и событие должно читаться с одного взгляда, а не выцарапываться
/// из плотного списка. При превью 72 правая колонка получалась выше картинки
/// и карточка выглядела «прижатой».
const double _kThumb = 104;

/// Карточка поста в ленте.
///
/// Структура: превью слева, справа — тип, заголовок, организатор и короткая
/// строка фактов (дата · формат · кампус). Если дедлайн близко, добавляется
/// плашка срочности: это единственное, что в ленте окрашено предупреждающим.
///
/// Кнопки избранного здесь нет. Карточка ведёт на детали, а там избранное
/// живёт в закреплённой шапке — сохранить можно не листая обратно. Дубль
/// в ленте забирал место у заголовка и ловил случайные нажатия при прокрутке;
/// из самого списка избранного пост убирается свайпом.
///
/// Приоритет (is_featured) на карточке никак не рисуется: он влияет только
/// на порядок в списке (`priorityFirst`). Метка и обводка делали из карточки
/// «особый тип», которого на самом деле нет.
class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.onTap,
  });

  final Post post;
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
        highlightColor: scheme.primary.withValues(alpha: 0.06),
        splashColor: scheme.primary.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PostCover(
                post: post,
                size: _kThumb,
                radius: AppRadius.thumb,
                letter: true,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TypeLabel(type: post.type),
                    const SizedBox(height: 7),
                    Text(
                      post.title,
                      style: AppText.headline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if ((post.organizationName ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        post.organizationName!.trim(),
                        style: AppText.footnote
                            .copyWith(color: AppColors.secondaryLight),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    _Facts(post: post),
                    _Urgency(end: post.endDate),
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

/// Заглушка на время первой загрузки.
///
/// Без неё экран показывал «Пока ничего нет», пока посты ещё ехали из сети —
/// выглядело как пустой каталог, а потом контент появлялся скачком.
/// Повторяет геометрию настоящей карточки, чтобы список не «прыгал».
class PostCardSkeleton extends StatelessWidget {
  const PostCardSkeleton({super.key});

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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _block(color, _kThumb, _kThumb, AppRadius.thumb),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _block(color, 70, 10, AppRadius.pill),
                const SizedBox(height: 12),
                _block(color, double.infinity, 15, 6),
                const SizedBox(height: 8),
                _block(color, 180, 15, 6),
                const SizedBox(height: 10),
                _block(color, 120, 11, 6),
                const SizedBox(height: 12),
                _block(color, 150, 11, 6),
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

/// Тип поста: цветная точка + нейтральная подпись.
///
/// Точка, а не цветной бейдж: пять ярких подложек на каждой карточке
/// превращали ленту в пёстрое поле. Разницу между «вакансией» и «стажировкой»
/// несёт подпись, а точка лишь помогает быстрее сканировать список.
class _TypeLabel extends StatelessWidget {
  const _TypeLabel({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: AppColors.forPostType(type, brightness),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            (Catalogs.postTypes[type] ?? type).toUpperCase(),
            style: AppText.caption.copyWith(
              color: AppColors.secondaryLight,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Короткие факты: дата, формат, кампус.
///
/// [Wrap], а не [Row]: на узком экране пара «дата + кампус» не влезает
/// в одну строку и обрезалась бы — здесь второй факт просто переносится.
class _Facts extends StatelessWidget {
  const _Facts({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    final p = post;

    final facts = <Widget>[
      if (p.startDate != null)
        _fact(context, Icons.schedule_rounded, dateShort(p.startDate!)),
      if (Catalogs.formats[p.format] != null)
        _fact(context, _formatIcon(p.format), Catalogs.formats[p.format]!),
      if (p.campuses.isNotEmpty)
        _fact(
          context,
          Icons.place_rounded,
          Catalogs.campusTitle(p.campuses.first),
        ),
    ];
    if (facts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(spacing: 12, runSpacing: 5, children: facts),
    );
  }

  IconData _formatIcon(String format) => switch (format) {
        'online' => Icons.videocam_rounded,
        'hybrid' => Icons.sync_alt_rounded,
        _ => Icons.location_city_rounded,
      };

  Widget _fact(BuildContext context, IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.secondaryLight),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style:
                  AppText.caption.copyWith(color: AppColors.secondaryLight),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
}

/// Плашка срочности: видна только когда дедлайн близко.
class _Urgency extends StatelessWidget {
  const _Urgency({required this.end});
  final DateTime? end;

  @override
  Widget build(BuildContext context) {
    final label = urgencyLabel(end);
    if (label == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt_rounded, size: 13, color: AppColors.warning),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: AppText.caption.copyWith(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


