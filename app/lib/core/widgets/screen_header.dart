import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Шапка экрана: название слева, действия справа.
///
/// Заголовок вернулся после замечания «название страницы убрано намеренно»:
/// без него не видно, где находишься, а над лентой вместо него — пустое
/// место. Действия (поиск, фильтры, обновление) открывают то, что раньше
/// пряталось в шторке и в шапке Material.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.actions = const [],
    this.bottom = 4,
  });

  final String title;

  /// Иконки справа от названия.
  final List<Widget> actions;

  /// Отступ под шапкой.
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppInsets.horizontal(MediaQuery.sizeOf(context).width),
        AppInsets.top(context),
        AppInsets.horizontal(MediaQuery.sizeOf(context).width),
        bottom,
      ),
      child: Row(
        children: [
          Expanded(child: ScreenTitle(title)),
          for (final a in actions) a,
        ],
      ),
    );
  }
}

/// Круглая иконка-действие в шапке.
///
/// Одинаковая для поиска, фильтров и обновления, чтобы взгляд не цеплялся
/// за разные формы кнопок.
class HeaderAction extends StatelessWidget {
  const HeaderAction({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  /// Подсветка активного состояния (например, открытые фильтры).
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Material(
        color: active
            ? scheme.primary.withValues(alpha: 0.14)
            : AppColors.placeholder(Theme.of(context).brightness),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          onPressed: onTap,
          icon: Icon(icon, size: 20, color: active ? scheme.primary : null),
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}
