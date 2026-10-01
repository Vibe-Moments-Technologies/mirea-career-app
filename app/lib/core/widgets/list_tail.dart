import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Хвост списка: «показать ещё», подпись о конце или итог.
///
/// Одинаков на главной, в каталоге и на странице организаций: раньше каждый
/// экран рисовал свой блок и они расходились по отступам и формулировкам.
class ListTail extends StatelessWidget {
  const ListTail({
    super.key,
    this.hasMore = false,
    this.isEmpty = false,
    this.loaded = 0,
    this.total = 0,
    this.footer,
    this.emptyTitle = 'Пока ничего нет',
    this.emptyBody = 'Новые записи появятся здесь сразу после публикации',
    this.onMore,
  });

  final bool hasMore;
  final bool isEmpty;
  final int loaded;
  final int total;

  /// Итоговая подпись вместо «конца ленты» (например, число организаций).
  final String? footer;

  final String emptyTitle;
  final String emptyBody;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    if (isEmpty) {
      return _Empty(title: emptyTitle, body: emptyBody);
    }
    if (hasMore && onMore != null) {
      return OutlinedButton(
        onPressed: onMore,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        ),
        child: Text('Показать ещё ($loaded из $total)'),
      );
    }
    return _Caption(text: footer ?? 'Это всё — новых записей больше нет');
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline_rounded,
              size: 16, color: AppColors.secondaryLight),
          const SizedBox(width: 6),
          // Flexible: длинная подпись на узком экране должна сжиматься,
          // иначе строка вылезает за границы (RenderFlex overflow).
          Flexible(
            child: Text(
              text,
              style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            Icon(Icons.inbox_rounded,
                size: 44,
                color: AppColors.secondaryLight.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            Text(
              title,
              style: AppText.headline.copyWith(color: AppColors.secondaryLight),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              textAlign: TextAlign.center,
              style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
            ),
          ],
        ),
      );
}
