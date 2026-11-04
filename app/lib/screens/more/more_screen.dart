import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scroll.dart';
import '../../core/widgets/settings_list.dart';
import '../../state/providers.dart';
import '../archive/archive_screen.dart';
import '../org/organizations_screen.dart';
import 'about_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

/// «Ещё»: профиль и архив / настройки и «о приложении» / соцсети проекта.
///
/// Три смысловых блока (запрос пользователя) вместо двух: анкеты уехали
/// в «Сохранённое», к ним место рядом с избранным.
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
                  appRoute(context, const ProfileScreen()),
                ),
              ),
              SettingsTile(
                icon: Icons.history_rounded,
                title: 'Архив',
                subtitle: 'Завершённые вакансии, события и стажировки',
                onTap: () => Navigator.of(context).push(
                  appRoute(context, const ArchiveScreen()),
                ),
              ),
              SettingsTile(
                icon: Icons.apartment_rounded,
                title: 'Организации',
                subtitle: 'Компании-партнёры и подразделения вуза',
                onTap: () => Navigator.of(context).push(
                  appRoute(context, const OrganizationsScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SettingsGroup(
            children: [
              SettingsTile(
                icon: Icons.tune_rounded,
                title: 'Настройки',
                subtitle: 'Оформление и данные',
                onTap: () => Navigator.of(context).push(
                  appRoute(context, const SettingsScreen()),
                ),
              ),
              SettingsTile(
                icon: Icons.info_outline_rounded,
                title: 'О приложении',
                subtitle: 'Версия, назначение, контакты',
                onTap: () => Navigator.of(context).push(
                  appRoute(context, const AboutScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _SocialBlock(),
          const SizedBox(height: 24),
          const _Footer(),
        ],
      ),
    );
  }
}

/// Блок-ссылки на соцсети и страницы проекта.
///
/// Открытие — через url_launcher (внешний браузер/приложение). Адреса
/// заполняются по мере готовности сайтов и сообществ; заглушки скрываем.
class _SocialBlock extends StatelessWidget {
  const _SocialBlock();

  static const _links = <(String, String, IconData)>[
    // ('Telegram', 'https://t.me/…', Icons.send_rounded) — добавится
    // вместе с ботом техподдержки.
  ];

  @override
  Widget build(BuildContext context) {
    if (_links.isEmpty) {
      // Пустой блок не занимает экран «Ещё» заглушками: появятся адреса —
      // появятся строки.
      return const SizedBox.shrink();
    }
    return SettingsGroup(
      children: [
        for (final (title, url, icon) in _links)
          SettingsTile(
            icon: icon,
            title: title,
            subtitle: url.replaceFirst('https://', ''),
            onTap: () {},
          ),
      ],
    );
  }
}

/// Подвал «Ещё»: копирайт.
///
/// Год — от даты на устройстве, не меньше 2026 (год запуска): раньше
/// запуск был, значит и раньше копирайт быть не может. Если год меньше
/// или равен 2026 — один год, без диапазона.
class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final deviceYear = DateTime.now().year;
    final year = deviceYear < 2026 ? 2026 : deviceYear;
    final range = deviceYear > 2026 ? '2026 – $year' : '$year';

    return Column(
      children: [
        Text(
          'Сделано Vibe Moments Technologies',
          style: AppText.caption.copyWith(color: AppColors.secondaryLight),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          'для РТУ МИРЭА · $range',
          style: AppText.caption.copyWith(color: AppColors.secondaryLight),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
