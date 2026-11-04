import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scroll.dart';

/// «Сервисы» — вкладка дока: студенческие сервисы университета.
///
/// Пока сервисов нет — честная заглушка в IT-стиле вместо пустого
/// экрана. Пункт «Календарь» из дока убран вместе со вкладкой:
/// событие с датой видно в ленте и в деталях карточки, отдельный
/// экран не оправдал себя. Когда появятся сервисы (запись в тьюториум,
/// справки, бронирование аудиторий…) — сюда.
class ServicesScreen extends StatelessWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    return Scaffold(
      body: ListView(
        physics: AppScroll.plain,
        padding: EdgeInsets.fromLTRB(
          pad,
          AppInsets.top(context, extra: 4),
          pad,
          AppInsets.screenBottom(context),
        ),
        children: [
          const ScreenTitle('Сервисы'),
          const SizedBox(height: 40),
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.terminal_rounded,
                size: 44,
                color: scheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Статус: в разработке',
            textAlign: TextAlign.center,
            style: AppText.footnote.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Сервисов пока нет,\nно мы уже пишем код',
            textAlign: TextAlign.center,
            style: AppText.title.copyWith(height: 1.3),
          ),
          const SizedBox(height: 12),
          Text(
            'Скоро тут появятся полезные штуки для студентов.\n'
            'Идеи записаны, спринты запланированы,\n'
            'релиз собирается по коммиту.',
            textAlign: TextAlign.center,
            style: AppText.body
                .copyWith(color: AppColors.secondaryLight, height: 1.6),
          ),
          const SizedBox(height: 32),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad * 0.5),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.separator(context)),
              ),
              child: Text(
                'services --list        0 found\n'
                'services --bake        in progress\n'
                'deploy                 on every commit',
                style: AppText.footnote.copyWith(
                  height: 1.8,
                  color: AppColors.secondaryLight,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
