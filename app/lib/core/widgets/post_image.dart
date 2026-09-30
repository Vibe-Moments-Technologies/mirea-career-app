import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../theme/app_theme.dart';

/// Единая обложка поста: картинка, буквенная заглушка или нейтральная
/// поверхность — и больше ничего.
///
/// Живёт отдельным файлом, потому что раньше каждая карточка рисовала
/// свою версию (`_Thumb`, `_Cover`, `_HeroFallback`) с разной логикой
/// отказа — отсюда «то значок, то пустота» при мерцающих загрузках.
///
/// Правило отображения (по правкам):
///  1. `image_url` есть и загрузилась → фото;
///  2. `image_url` есть, но не загрузилась (офлайн, 404, ещё грузится) →
///     НЕ иконка, а ровная заглушка цвета поверхности: иконка поверх
///     недогруженного фото выглядела как случайный глюк;
///  3. `image_url` пуст → заглушка с буквой названия организации.
///
/// Логотип (`logo_url`) больше не рисуется иконкой-подменой: у организаций
/// в демо-данных это placehold.co, который в приложении отдаёт 403 и вместо
/// логотипа показывал серый квадрат. Нет логотипа — нет и квадрата.
class PostCover extends StatelessWidget {
  const PostCover({
    super.key,
    required this.post,
    required this.size,
    this.radius,
    this.borderRadius,
    this.letter = false,
  });

  final Post post;

  /// Сторона квадрата (для карточки ленты).
  final double? size;

  /// Радиус и способ отрисовки: квадрат или прямоугольник на всю ширину.
  final double? radius;
  final BorderRadius? borderRadius;

  /// Показывать букву организации вместо иконки типа.
  final bool letter;

  @override
  Widget build(BuildContext context) {
    final br = borderRadius ?? BorderRadius.circular(radius ?? AppRadius.thumb);
    final url = post.imageUrl;

    return ClipRRect(
      borderRadius: br,
      child: SizedBox(
        width: size,
        height: size,
        child: url == null || url.isEmpty
            ? _Placeholder(post: post, letter: letter)
            : Image.network(
                url,
                fit: BoxFit.cover,
                // Пока грузится и при ошибке — та же ровная заглушка,
                // без иконки: она «мигала» поверх недогруженного фото.
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : _Placeholder(post: post, letter: letter),
                errorBuilder: (_, _, _) => _Placeholder(post: post, letter: letter),
              ),
      ),
    );
  }
}

/// Заглушка: буква организации или иконка типа на нейтральной поверхности.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.post, required this.letter});
  final Post post;
  final bool letter;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final initial = _initialOf(post.organizationName);

    return ColoredBox(
      color: AppColors.placeholder(brightness),
      child: Center(
        child: letter && initial != null
            ? Text(
                initial,
                style: AppText.title.copyWith(
                  color: AppColors.secondaryLight,
                  fontSize: post.organizationName != null && initial.length > 1 ? 18 : 26,
                ),
              )
            : Icon(_iconForType(post.type), color: AppColors.secondaryLight, size: 30),
      ),
    );
  }
}

/// Первая буква организации — «Я» для Яндекса, «С» для Сбера.
/// null, если имени нет: пустая буква выглядела бы как артефакт.
String? _initialOf(String? name) {
  final trimmed = name?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed.substring(0, 1).toUpperCase();
}

IconData _iconForType(String type) => switch (type) {
      'vacancy' => Icons.work_rounded,
      'internship' => Icons.school_rounded,
      'event' => Icons.event_rounded,
      'scholarship' => Icons.card_giftcard_rounded,
      'project' => Icons.rocket_launch_rounded,
      _ => Icons.article_rounded,
    };