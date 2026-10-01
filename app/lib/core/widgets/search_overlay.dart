import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Закрыть поиск: снять фокус, иначе клавиатура остаётся висеть поверх
/// уже невидимого поля.
void closeSearch() {
  FocusManager.instance.primaryFocus?.unfocus();
}

/// Поиск поверх экрана: затемняет фон и «выплывает» сверху из значка.
///
/// Живёт в дереве всегда и прячется через `IgnorePointer` + анимацию: так
/// поле уезжает и обратно, а не исчезает по щелчку.
class SearchOverlay extends StatelessWidget {
  const SearchOverlay({
    super.key,
    required this.open,
    required this.controller,
    required this.onChanged,
    required this.onClose,
  });

  final bool open;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !open,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: open ? 1 : 0,
          child: GestureDetector(
            // тап мимо поля — закрыть
            onTap: onClose,
            behavior: HitTestBehavior.opaque,
            child: Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppInsets.horizontal(MediaQuery.sizeOf(context).width),
                      AppInsets.top(context),
                      AppInsets.horizontal(MediaQuery.sizeOf(context).width),
                      0,
                    ),
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      offset: open ? Offset.zero : const Offset(0, -1),
                      child: _Field(
                        controller: controller,
                        autofocus: open,
                        onChanged: onChanged,
                        onClose: onClose,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.onChanged,
    required this.onClose,
    required this.autofocus,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  /// Фокус только в момент открытия. Постоянно живущий TextField с
  /// autofocus=true забирал фокус уже на старте приложения — клавиатура
  /// вылезала, хотя поиск не был активен.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Поле монтируется только когда оверлей открыт (ключ меняется вместе с
    // open), поэтому autofocus срабатывает ровно в момент открытия.
    // Постоянно живущий TextField иначе просил фокус при старте приложения,
    // и клавиатура вылезала сама, хотя поиск не был активен.
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.field),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.field),
          border: Border.all(color: AppColors.separator(context)),
          boxShadow: AppShadows.card(Theme.of(context).brightness),
        ),
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: autofocus,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                style: AppText.body,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Поиск по заголовку, тегам, организациям',
                  hintStyle:
                      AppText.body.copyWith(color: AppColors.secondaryLight),
                ),
              ),
            ),
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded, size: 20),
              tooltip: 'Закрыть поиск',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}
