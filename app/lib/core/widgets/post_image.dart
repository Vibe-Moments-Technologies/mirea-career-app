import 'package:flutter/material.dart';

import '../../data/app_http_client.dart';
import '../../data/crash_reporting.dart';
import '../../data/models.dart';
import '../theme/app_theme.dart';

/// Единая обложка поста: картинка, буквенная заглушка или нейтральная
/// поверхность — и больше ничего.
///
/// Использует [DohNetworkImage] вместо Image.network, потому что последний
/// игнорирует HttpOverrides.global и не работает с DoH.
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
  final double? size;
  final double? radius;
  final BorderRadius? borderRadius;
  final bool letter;

  @override
  Widget build(BuildContext context) {
    final br = borderRadius ?? BorderRadius.circular(radius ?? AppRadius.thumb);
    final url = post.imageUrl;
    final placeholder = _Placeholder(post: post, letter: letter);

    return ClipRRect(
      borderRadius: br,
      child: SizedBox(
        width: size,
        height: size,
        child: url == null || url.isEmpty
            ? placeholder
            : DohNetworkImage(
                url: url,
                fit: BoxFit.cover,
                width: size,
                height: size,
                placeholder: placeholder,
                errorWidget: Builder(builder: (_) {
                  // Ошибка загрузки — отправляем в Sentry.
                  CrashReporting.report(
                    Exception('PostCover: failed to load $url'),
                    StackTrace.current,
                    context: 'post_cover_load:$url',
                  );
                  return placeholder;
                }),
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
                  fontSize:
                      post.organizationName != null && initial.length > 1
                          ? 18
                          : 26,
                ),
              )
            : Icon(_iconForType(post.type),
                color: AppColors.secondaryLight, size: 30),
      ),
    );
  }
}

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
