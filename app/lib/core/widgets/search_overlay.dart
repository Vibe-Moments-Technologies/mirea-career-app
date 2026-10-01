import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Закрыть поиск: снять фокус, иначе клавиатура остаётся висеть поверх
/// уже невидимого поля.
///
/// Снимаем дважды — сразу и после кадра. Поле остаётся в дереве (оно нужно
/// для анимации ухода), и если снять фокус только до перестроения, текстовое
/// поле успевает его вернуть: на телефоне клавиатура так и остаётся.
void closeSearch() {
  FocusManager.instance.primaryFocus?.unfocus();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    FocusManager.instance.primaryFocus?.unfocus();
  });
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
    // Закрытый оверлей ничего не строит, поэтому скрытое поле не может
    // держать фокус и подтягивать клавиатуру.
    if (!open) return const SizedBox.shrink();

    // Фон — только визуальный слой: он не перехватывает касания, и карточки
    // под ним остаются живыми. Касание фона лишь прячет клавиатуру через
    // TextField.onTapOutside; очищает запрос только закрытие.
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: 1,
                child: Container(
                  constraints: const BoxConstraints.expand(),
                  color: Colors.black.withValues(alpha: 0.34),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: EdgeInsets.only(
                left: AppInsets.horizontal(MediaQuery.sizeOf(context).width),
                right: AppInsets.horizontal(MediaQuery.sizeOf(context).width),
                top: AppInsets.top(context),
              ),
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                offset: open ? Offset.zero : const Offset(0, -1),
                child: _Field(
                  controller: controller,
                  onChanged: onChanged,
                  onClose: onClose,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.onChanged,
    required this.onClose,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                // Поле монтируется только открытым, поэтому фокус безопасен.
                autofocus: true,
                onChanged: onChanged,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
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
