import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'collapsible_section.dart';

/// Фильтр-панель как bottom sheet поверх контента.
///
/// Шторка из DraggableScrollableSheet: тянется ВНИЗ за любую область
/// (enableDrag шторки + ручка), а ВВЕРХ раскрывается до 95% за
/// заголовок и список (scrollController листа). Крестика нет:
/// закрытие — свайп вниз, тап по фону, «Сбросить» или «Показать».
///
/// «Сбросить» — автоприменение (запрос): сбрасывает фильтры, ЗАКРЫВАЕТ
/// шторку и применяет пустой черновик — как «Показать», но без
/// промежуточного шага.
Future<void> showFilterSheet({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  VoidCallback? onReset,
  required String applyLabel,
  required VoidCallback onApply,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.34),
    builder: (sheetContext) {
      final scheme = Theme.of(sheetContext).colorScheme;
      return DraggableScrollableSheet(
        initialChildSize: 0.62,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        snap: true,
        snapSizes: const [0.62],
        builder: (context, scrollController) {
          return Material(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // Ручка + заголовок: всегда видны, не скроллятся.
                // Тянуть можно и их: enableDrag шторки закрывает при
                // свайпе вниз, а вверх растягивает сам лист.
                _GrabHandle(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(title, style: AppText.headline),
                      ),
                      if (onReset != null)
                        TextButton(
                          // Автоприменение сброса: сброс → закрыть →
                          // применить. Одна кнопка = один результат.
                          onPressed: () {
                            onReset();
                            Navigator.of(sheetContext).pop();
                            onApply();
                          },
                          child: const Text('Сбросить'),
                        ),
                    ],
                  ),
                ),
                Divider(height: 1, color: AppColors.separator(sheetContext)),
                // Секции фильтров скроллятся и ТЯНУТ шторку: контроллер
                // DraggableScrollableSheet — тянуть вверх = раскрыть.
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    children: [
                      builder(sheetContext),
                    ],
                  ),
                ),
                // Кнопка «Показать» прижата к низу — доступна всегда.
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          onApply();
                        },
                        child: Text(applyLabel),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class _GrabHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.secondaryLight.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

/// Секция «Актуальное / Архивное»: два сегмента, как вкладки.
///
/// На главной и в каталоге — да, на странице архива её нет вовсе:
/// там архив принудительно применён.
class ActualitySegment extends StatelessWidget {
  const ActualitySegment({
    super.key,
    required this.showArchived,
    required this.onChanged,
  });

  final bool showArchived;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CollapsibleSection(
      title: 'Актуальность',
      initiallyOpen: true,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          children: [
            _seg('Актуальное', false, scheme),
            _seg('Архивное', true, scheme),
          ],
        ),
      ),
    );
  }

  Widget _seg(String label, bool value, ColorScheme scheme) {
    final selected = showArchived == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            label,
            style: AppText.headline.copyWith(
              fontSize: 14,
              color: selected ? scheme.primary : AppColors.secondaryLight,
            ),
          ),
        ),
      ),
    );
  }
}
