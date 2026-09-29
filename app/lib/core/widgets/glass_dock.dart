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
/// отступ снизу учитывает home-indicator. Активный пункт раскрывается
/// в капсулу с подписью.
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

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPad = media.padding.bottom;
    final narrow = media.size.width < 380;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: bottomPad > 0 ? bottomPad + 6 : 16,
        ),
        child: ConstrainedBox(
          // на планшетах док остаётся компактным островком по центру
          constraints: BoxConstraints(maxWidth: media.size.width > 600 ? 480 : 420),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.dock),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E1E1E).withValues(alpha: 0.72)
                      : Colors.white.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(AppRadius.dock),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.white.withValues(alpha: 0.6),
                    width: 1.2,
                  ),
                  boxShadow: AppShadows.dock(Theme.of(context).brightness),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (var i = 0; i < items.length; i++)
                      _DockButton(
                        item: items[i],
                        selected: selectedIndex == i,
                        // на узких экранах подпись активного пункта скрывается
                        showLabel: !narrow,
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
    final accent = Theme.of(context).colorScheme.primary;
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
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 22, color: selected ? accent : inactive),
              if (selected && showLabel) ...[
                const SizedBox(width: 8),
                Text(
                  item.label,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
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