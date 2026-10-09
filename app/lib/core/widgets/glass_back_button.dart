import 'package:flutter/material.dart';

/// Стеклянная круглая кнопка поверх контента.
///
/// Общий вид для кнопок, лежащих на картинке: тёмный полупрозрачный круг
/// держит контраст на любой обложке. Используется для «назад»
/// ([GlassBackButton]) и для действий в шапке деталей поста (избранное).
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.color,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  /// Цвет иконки; по умолчанию белый — на тёмном стекле читается всегда.
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(6),
        child: Material(
          color: Colors.black.withValues(alpha: 0.28),
          shape: const CircleBorder(),
          child: IconButton(
            icon: Icon(icon, size: 18, color: color ?? Colors.white),
            onPressed: onTap,
            tooltip: tooltip,
          ),
        ),
      );
}

/// Кнопка «назад» в виде стеклянного круга.
///
/// Общая для всех выталкиваемых экранов. Раньше у деталей была своя
/// круглая кнопка, а «Настройки», «О приложении» и «Профиль» показывали
/// системную `AppBar` со стрелкой Material — из-за чего эти три экрана
/// отличались от рабочих. Теперь одинаково.
class GlassBackButton extends StatelessWidget {
  const GlassBackButton({super.key});

  @override
  Widget build(BuildContext context) => GlassIconButton(
        icon: Icons.arrow_back_ios_new_rounded,
        tooltip: 'Назад',
        onTap: () => Navigator.of(context).maybePop(),
      );
}
