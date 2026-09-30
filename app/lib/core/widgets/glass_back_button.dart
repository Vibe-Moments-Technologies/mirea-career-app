import 'package:flutter/material.dart';

/// Кнопка «назад» в виде стеклянного круга.
///
/// Общая для всех выталкиваемых экранов. Раньше у деталей была своя
/// круглая кнопка, а «Настройки», «О приложении» и «Профиль» показывали
/// системную `AppBar` со стрелкой Material — из-за чего эти три экрана
/// отличались от рабочих. Теперь одинаково.
class GlassBackButton extends StatelessWidget {
  const GlassBackButton({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(6),
        child: Material(
          color: Colors.black.withValues(alpha: 0.28),
          shape: const CircleBorder(),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 18, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Назад',
          ),
        ),
      );
}
