import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'collapsible_section.dart';

/// Фильтр-панель как bottom sheet поверх контента.
///
/// По умолчанию — полэкрана, тянется до полного. Закрывается свайпом вниз
/// или по «Показать». Содержимое — список секций [sections], а кнопки
/// «Сбросить»/«Показать N» прижаты к низу и видны в любом размере.
///
/// Настраивается под страницу: главная не показывает «Архивное» (там свой
/// переключатель), архив не показывает его вовсе — передаются только нужные
/// секции.
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
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.34),
    builder: (sheetContext) => DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        final scheme = Theme.of(sheetContext).colorScheme;
        return Material(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Ручка + заголовок: всегда видны, не скроллятся.
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
                        onPressed: onReset,
                        child: const Text('Сбросить'),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.separator(sheetContext)),
              // Секции фильтров скроллятся внутри шторки.
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  children: [
                    builder(sheetContext),
                  ],
                ),
              ),
              // Кнопка «Показать» прижата к низу — доступна в любом размере.
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
                          borderRadius: BorderRadius.circular(AppRadius.pill),
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
    ),
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
