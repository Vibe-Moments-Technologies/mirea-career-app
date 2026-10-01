import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Один пункт дока.
class DockItem {
  const DockItem(this.icon, this.label);
  final IconData icon;
  final String label;
}

/// Плавающий стеклянный док фиксированного размера (docs/UI.md §2).
///
/// Ширина фиксированная, а не «по содержимому» и не «на весь экран»:
/// `ConstrainedBox(maxWidth:)` внутри `Positioned(left:0,right:0:)` даёт ЖЁСТКУЮ
/// ширину (min = max родителя минус отступ), и док растягивался на весь экран.
/// Здесь размер задан явно: `width` у контейнера.
///
/// Пункты делят ширину поровну (`Expanded`) и показывают только иконку:
/// подпись у выбранного пункта расширяла его и сдвигала соседей — док
/// «дышал» при переключении. Название остаётся в `Semantics` для а11ы.
///
/// ВАЖНО: виджет нельзя ставить в `Scaffold.bottomNavigationBar` — тот слот
/// даёт свободные ограничения по высоте, и док раздувается. Живёт в Stack.
class GlassDock extends StatelessWidget {
  const GlassDock({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<DockItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Высота капсулы.
  static const height = 58.0;

  /// Сторона кнопки. Док по ширине = кнопки + внутренние отступы, то есть
  /// жмётся под фактическое число значков, а не растягивается.
  static const button = 46.0;

  /// Отступ от нижнего края ЭКРАНА до низа капсулы.
  ///
  /// Разный по платформам не по вкусу, а по устройству:
  ///  * iOS — home-indicator это тонкая полоска ПОВЕРХ контента, а не панель.
  ///    Резервируем только её видимую зону: нижний край остаётся на 22 pt,
  ///    то есть чуть выше полоски, но не виснет в воздухе.
  ///  * Android — панель навигации настоящая: жестовая ~24 pt, кнопочная
  ///    ~48 pt. Её надо перекрыть целиком, поэтому берём системный inset.
  ///
  /// `viewPadding`, а не `padding`: клавиатура не должна поднимать док.
  static double bottomInset(BuildContext context) {
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    return switch (Theme.of(context).platform) {
      TargetPlatform.iOS => inset > 0 ? 22 : 8,
      _ => inset + 8,
    };
  }

  /// Полная высота дока вместе с отступом — отсюда экраны берут нижний
  /// отступ скролла, чтобы последняя карточка не пряталась под доком.
  static double totalHeight(BuildContext context) => height + bottomInset(context);

  static double scrollBottom(BuildContext context) => totalHeight(context) + 16;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final inactive = isDark ? AppColors.secondaryDark : AppColors.secondaryLight;
    final radius = BorderRadius.circular(AppRadius.dock);

    return Center(
      child: Container(
        // ширины нет: капсула жмётся под содержимое (кнопки + отступы)
        height: height,
        // Тень на внешнем контейнере, размытие — строго по капсуле.
        // Раньше BackdropFilter лежал ВНУТРИ отступов: размытая область была
        // меньше капсулы и со своими скруглениями — на экране читалось как
        // «док поверх дока».
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: AppShadows.dock(isDark ? Brightness.dark : Brightness.light),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1C1C1E).withValues(alpha: 0.86)
                    : Colors.white.withValues(alpha: 0.9),
                borderRadius: radius,
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.07),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < items.length; i++)
                    _DockButton(
                      item: items[i],
                      selected: selectedIndex == i,
                      color: scheme.primary,
                      inactive: inactive,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        onSelected(i);
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.item,
    required this.selected,
    required this.color,
    required this.inactive,
    required this.onTap,
  });

  final DockItem item;
  final bool selected;
  final Color color;
  final Color inactive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: GlassDock.button,
            height: GlassDock.button,
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.14) : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Icon(item.icon, size: 23, color: selected ? color : inactive),
          ),
        ),
      ),
    );
  }
}
