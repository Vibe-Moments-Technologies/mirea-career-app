import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scroll.dart';
import '../../core/widgets/settings_list.dart';
import '../../state/providers.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

/// «Ещё»: вход в профиль и настройки.
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
                subtitle: 'Оформление, данные, о приложении',
                onTap: () => Navigator.of(context).push(
                  appRoute(context, const SettingsScreen())
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Данные профиля не покидают устройство',
              style: AppText.caption.copyWith(color: AppColors.secondaryLight),
            ),
          ),
        ],
      ),
    );
  }
}
