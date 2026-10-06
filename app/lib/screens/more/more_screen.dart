import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scroll.dart';
import '../../core/widgets/settings_list.dart';
import '../../state/providers.dart';
import '../archive/archive_screen.dart';
import 'about_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

/// «Ещё»: вход в профиль, настройки, архив и информацию о приложении.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    return Scaffold(
      body: ListView(
        // Прокрутка только в пределах страницы: короткий список не тянется
        // за края. Обновления тут нет — данные локальные.
        physics: AppScroll.plain,
        padding: EdgeInsets.fromLTRB(
          pad,
          AppInsets.top(context, extra: 4),
          pad,
          AppInsets.scrollBottom(context),
        ),
        children: [
          ScreenTitle('Ещё'),
          const SizedBox(height: 18),
          SettingsGroup(
            children: [
              SettingsTile(
                icon: Icons.person_rounded,
                title: 'Профиль',
                subtitle: profileSummary(profile),
                onTap: () => Navigator.of(context).push(
                  appRoute(context, const ProfileScreen())
                ),
              ),
              SettingsTile(
                icon: Icons.tune_rounded,
                title: 'Настройки',
                subtitle: 'Оформление и данные',
                onTap: () => Navigator.of(context).push(
                  appRoute(context, const SettingsScreen())
                ),
              ),
              SettingsTile(
                icon: Icons.history_rounded,
                title: 'Архив',
                subtitle: 'Завершённые вакансии, события и стажировки',
                onTap: () => Navigator.of(context).push(
                  appRoute(context, const ArchiveScreen())
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SettingsGroup(
            children: [
              SettingsTile(
                icon: Icons.info_outline_rounded,
                title: 'О приложении',
                subtitle: 'Версия, назначение, контакты',
                onTap: () => Navigator.of(context).push(
                  appRoute(context, const AboutScreen())
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _Footer(),
        ],
      ),
    );
  }
}

/// Подвал «Ещё»: копирайт с математической датой.
///
/// Σₖ₌₁³ (k² − k) = 0 + 2 + 6 = 8 → 2025 + 8 = 2027 — следующий год
/// от нынешнего. Формула честная: каждый может пересчитать.
class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Сделано Vibe Moments Technologies',
          style: AppText.caption.copyWith(color: AppColors.secondaryLight),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          'для РТУ МИРЭА · 2025 + Σₖ₌₁³ (k² − k)',
          style: AppText.caption.copyWith(color: AppColors.secondaryLight),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
