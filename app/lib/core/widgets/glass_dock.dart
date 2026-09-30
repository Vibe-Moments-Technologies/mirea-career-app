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

/// Плавающий стеклянный док (docs/UI.md §2).
///
/// Парит над контентом у нижнего края: контент под ним размывается,
/// отступ снизу учитывает home-indicator.
///
/// Ширина — по содержимому, а не на весь экран: док выглядит как островок
/// по центру и не растягивается на планшетах.
///
/// ВАЖНО: этот виджет нельзя ставить в `Scaffold.bottomNavigationBar`.
/// Flutter даёт тому слоту свободные ограничения, а `Align` внутри
/// растягивается на всю доступную высоту — док раздувался и отъезжал
/// от нижнего края экрана. Поэтому он живёт в Stack поверх контента
/// (см. RootShell).
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

  /// Высота капсулы дока.
  static const height = 60.0;

  /// Отступ от нижнего края ЭКРАНА до низа капсулы.
  ///
  /// Платформенные различия здесь не вкусовщина:
  ///  * iOS — home-indicator ~34 pt. В прошлой сборке док уходил ЗА него,
  ///    и системная полоса ложилась поверх дока. Поэтому отступ считается
  ///    от низа экрана, а не от низа body.
  ///  * Android — жестовая навигация ~24 pt, кнопочная ~48 pt. Значение
  ///    берём из системного inset, а не хардкодим: у Android-устройств
  ///    высота панели разная, и фиксированные 34 pt на кнопочной навигации
  ///    оставляли бы док наполовину под кнопками.
  ///
  /// `viewPadding` (а не `padding`): клавиатура не должна поднимать док —
  /// на экранах с доком полей ввода нет, но если появятся, док останется
  /// на месте, а не запрыгнет над клавиатурой.
  ///
  /// Применять нужно в `Positioned(bottom: ...)` родителя (RootShell), а НЕ
  /// как Padding внутри дока: Positioned с left+right+bottom даёт жёсткие
  /// ограничения по высоте, и внутренний Padding растягивается, не оставляя
  /// отступа. Тесты это ловят — см. group('Док').
  static double bottomInset(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).bottom + 8;

  /// Полная высота, которую док занимает у нижнего края ЭКРАНА.
  ///
  /// Считается от низа экрана: `extendBody: true` отдаёт body во всю высоту,
  /// поэтому координаты Stack — экранные. Экраны берут отсюда нижний отступ
  /// скролла, чтобы последняя карточка не пряталась под доком.
  static double totalHeight(BuildContext context) =>
      height + bottomInset(context);

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // подписи скрываем только на очень узких экранах
    final showLabel = media.size.width >= 340;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: media.size.width - 32,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.dock),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: height,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1C1C1E).withValues(alpha: 0.82)
                    : Colors.white.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(AppRadius.dock),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.white.withValues(alpha: 0.7),
                  width: 1,
                ),
                boxShadow: AppShadows.dock(Theme.of(context).brightness),
              ),
              child: Align(
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < items.length; i++)
                      _DockButton(
                        item: items[i],
                        selected: selectedIndex == i,
                        showLabel: showLabel,
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
      ),
    );
  }

  /// Нижний отступ для скролла внутри экрана с доком.
  static double scrollBottom(BuildContext context) =>
      totalHeight(context) + 16;
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.item,
    required this.selected,
    required this.showLabel,
    required this.onTap,
  });

  final DockItem item;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inactive = Theme.of(context).brightness == Brightness.dark
        ? AppColors.secondaryDark
        : AppColors.secondaryLight;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: selected && showLabel ? 16 : 18,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.13)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 23, color: selected ? scheme.primary : inactive),
              if (selected && showLabel) ...[
                const SizedBox(width: 8),
                Text(
                  item.label,
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}