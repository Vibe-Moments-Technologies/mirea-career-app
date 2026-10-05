import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Закрыть поиск: снять фокус, иначе клавиатура остаётся висеть поверх
/// уже невидимого поля.
void closeSearch() {
  FocusManager.instance.primaryFocus?.unfocus();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    FocusManager.instance.primaryFocus?.unfocus();
  });
}

/// Поиск поверх экрана: поле «выплывает» сверху из значка.
///
/// Механика (все состояния продуманы):
///  * открытие — поле получает фокус, поднимается клавиатура, включается
///    затемнение: контент под ним «заморожен» (тап гасит клавиатуру,
///    но не открывает карточки);
///  * сабмит (кнопка «Поиск»), тап по затемнению или тап мимо поля —
///    клавиатура уходит, затемнение тает, а поле ОСТАЁТСЯ плавать поверх
///    ленты с введённым запросом. Из этого режима два выхода:
///    крестик (закрыть) или тап по полю (вернуться к вводу);
///  * в «плавающем» режиме карточки под полем открыты: запрос не мешает.
///
/// Затемнение — НЕУДАЛЯЕМЫЙ ребёнок Stack (управляется только opacity):
/// если прятать его через `if`, индексы детей сдвигаются, поле
/// пересоздаётся и `autofocus` мгновенно поднимает клавиатуру обратно —
/// «клавиатура мигает и не выключается».
class SearchOverlay extends StatefulWidget {
  const SearchOverlay({
    super.key,
    required this.open,
    required this.controller,
    required this.onChanged,
    required this.onClose,
    this.onSubmitted,
  });

  final bool open;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  /// Сабмит (кнопка «Поиск» на клавиатуре): клавиатура гаснет,
  /// запрос уходит наверх.
  final ValueChanged<String>? onSubmitted;

  @override
  State<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<SearchOverlay> {
  FocusNode? _focusNode;
  bool _focused = false;

  FocusNode get _node => _focusNode ??= FocusNode();

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() => _focused = _node.hasFocus);
  }

  @override
  void dispose() {
    _focusNode?.dispose();
    super.dispose();
  }

  /// Выход из режима ввода: клавиатура уходит, затемнение тает,
  /// поле остаётся с текстом.
  void _unfocus() => _node.unfocus();

  @override
  Widget build(BuildContext context) {
    // Закрытый поиск ничего не строит: поле не держит фокус и не может
    // поднять клавиатуру на старте приложения.
    if (!widget.open) return const SizedBox.shrink();

    return Positioned.fill(
      child: Stack(
        children: [
          // Затемнение — ПОСТОЯННЫЙ ребёнок Stack (см. класс-комментарий).
          Positioned.fill(
            child: IgnorePointer(
              // Невидимо — пропускает тапы к контенту под ним.
              ignoring: !_focused,
              child: GestureDetector(
                // Тап по затемнению только гасит клавиатуру.
                onTap: _unfocus,
                behavior: HitTestBehavior.opaque,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: _focused ? 1 : 0,
                  child: Container(
                    constraints: const BoxConstraints.expand(),
                    color: Colors.black.withValues(alpha: 0.34),
                  ),
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
                offset: Offset.zero,
                child: _Field(
                  node: _node,
                  controller: widget.controller,
                  onChanged: widget.onChanged,
                  onClose: widget.onClose,
                  onSubmitted: widget.onSubmitted,
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
    required this.node,
    required this.controller,
    required this.onChanged,
    required this.onClose,
    this.onSubmitted,
  });

  final FocusNode node;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;
  final ValueChanged<String>? onSubmitted;

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
                focusNode: node,
                // Поле монтируется только открытым, поэтому фокус безопасен.
                autofocus: true,
                onChanged: onChanged,
                // Тап мимо поля — тот же выход из ввода: клавиатура уходит,
                // поле остаётся плавать. Повторного фокуса не будет:
                // дерево поля стабильно, ничего не пересоздаётся.
                onTapOutside: (_) => node.unfocus(),
                textInputAction: TextInputAction.search,
                onSubmitted: (v) {
                  node.unfocus();
                  onSubmitted?.call(v);
                },
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
