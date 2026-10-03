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
    this.leading,
    this.actions = const [],
    this.bottom = 4,
  });

  final String title;

  /// Слева от названия: обычно кнопка «назад» — на выталкиваемых экранах
  /// своего AppBar у них нет, а вернуться нужно не только жестом.
  final Widget? leading;

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
          ?leading,
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
      child: IconButton(
        onPressed: onTap,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          backgroundColor: active
              ? scheme.primary.withValues(alpha: 0.14)
              : scheme.surface,
          foregroundColor: active ? scheme.primary : null,
          side: BorderSide(
            color: active ? scheme.primary : AppColors.separator(context),
          ),
          shape: const CircleBorder(),
        ),
        icon: Icon(icon, size: 20),
      ),
    );
  }
}
