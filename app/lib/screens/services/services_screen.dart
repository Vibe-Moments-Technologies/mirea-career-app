import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// «Сервисы» — вкладка дока: студенческие сервисы университета.
///
/// Пока сервисов нет — честная заглушка вместо пустого экрана:
/// значок вкладки дока (тот же widgets_rounded), заголовок-обещание
/// и подпись. Всё по центру экрана. Когда появятся сервисы (тьюториум,
/// справки, бронирование аудиторий…) — сюда.
class ServicesScreen extends StatelessWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                // Тот же значок, что в доке — вкладка и страница
                // визуально связаны.
                child: Icon(
                  Icons.widgets_rounded,
                  size: 44,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Сервисов пока нет,\nно мы уже пишем код',
                textAlign: TextAlign.center,
                style: AppText.title.copyWith(height: 1.3),
              ),
              const SizedBox(height: 12),
              Text(
                'Скоро тут появятся полезные штуки для студентов.\n'
                'Идеи записаны, спринты запланированы.',
                textAlign: TextAlign.center,
                style: AppText.body
                    .copyWith(color: AppColors.secondaryLight, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
