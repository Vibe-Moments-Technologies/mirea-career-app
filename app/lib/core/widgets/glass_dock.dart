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

  /// Отступ от нижнего края поверх home-indicator.
  ///
  /// Минимальный: док должен висеть сразу над home-indicator, а не в
  /// середине нижней трети экрана.
  static const gap = 4.0;

  /// Полная высота, которую док занимает у нижнего края ЭКРАНА (body):
  /// нужна экранам, чтобы посчитать нижний отступ скролла.
  ///
  /// ВАЖНО: и док, и контент живут в координатах body, а Scaffold уже
  /// обрезал нижнюю safe-area (home-indicator) у body. Поэтому сюда НЕ
  /// входит padding.bottom — иначе отступ удваивался и док висел в ~70 pt
  /// от края. Так уже было с SafeArea + gap.
  static double totalHeight(BuildContext context) => gap + height;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // подписи скрываем только на очень узких экранах
    final showLabel = media.size.width >= 340;

    // body уже заканчивается над home-indicator (Scaffold обрезал safe-area),
    // поэтому добавляем только маленький визуальный зазор — без padding.bottom.
    return Padding(
      padding: const EdgeInsets.only(bottom: gap),
      child: Center(
        // Center + IntrinsicWidth: док занимает ровно столько, сколько нужно
        // содержимому, но не шире разумного максимума
        heightFactor: 1,
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