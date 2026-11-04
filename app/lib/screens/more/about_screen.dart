import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_route.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scroll.dart';
import '../../core/widgets/glass_back_button.dart';
import '../../core/widgets/settings_list.dart';
import 'licenses_screen.dart';

/// Версия приложения. Совпадает с pubspec.yaml; CI подставляет свою.
const _appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0');
const _appBuild = String.fromEnvironment('APP_BUILD', defaultValue: '1');

/// «О приложении»: о нас, поддержка, версия и лицензии, копирайт.
///
/// Экран полноценный, а не системный диалог: в `showAboutDialog` нельзя ни
/// разместить контакты, ни показать копирайт командной разработки.
/// Блок «Как это работает» убран (запрос пользователя): экран о проекте,
/// а не инструкция — назначение объясняет раздел «О нас».
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    return Scaffold(
      appBar: AppBar(
        title: const Text('О приложении'),
        titleTextStyle: AppText.headline,
        leading: const GlassBackButton(),
      ),
      body: ListView(
        physics: AppScroll.plain,
        padding: EdgeInsets.fromLTRB(
          pad,
          8,
          pad,
          AppInsets.screenBottom(context),
        ),
        children: [
          const SizedBox(height: 8),
          Center(
            child: Column(
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.work_outline_rounded,
                    size: 40,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Text('Карьера РТУ МИРЭА', style: AppText.title),
                const SizedBox(height: 4),
                Text(
                  'Библиотека возможностей университета',
                  style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const _Section('О НАС'),
          Text(
            '«Карьера РТУ МИРЭА» — проект команды Vibe Moments Technologies '
            'совместно с университетом: мы соединяем студентов и их будущую '
            'карьеру в одном приложении. Вакансии, стажировки, стипендии и '
            'события собираются в единую ленту — без поиска по десятку '
            'каналов и рассылок.',
            style: AppText.body.copyWith(height: 1.5),
          ),
          const SizedBox(height: 5),
          Text(
            'Карточки публикуют сотрудники университета и компаний-партнёров '
            'после проверки. Приложение работает без регистрации: избранное '
            'и профиль хранятся только на вашем устройстве.',
            style: AppText.body.copyWith(height: 1.5),
          ),
          const SizedBox(height: 24),
          const _Section('ПОДДЕРЖКА'),
          // Почта карьерного центра убрана (запрос пользователя): каналы
          // поддержки будут свои — бот в Telegram, сайт проекта, почта
          // ответственного. Пока оставляем сайт вуза.
          SettingsGroup(
            children: [
              SettingsTile(
                icon: Icons.language_rounded,
                title: 'Сайт университета',
                subtitle: 'mirea.ru',
                onTap: () => _openLink(context, 'https://mirea.ru'),
              ),
              // Появятся — добавим строками сюда:
              // «Написать в поддержку» (бот Telegram), «Сайт приложения».
            ],
          ),
          const SizedBox(height: 24),
          SettingsGroup(
            children: [
              SettingsTile(
                // Значок «обновить»: строка выглядит как действие —
                // и станет им, когда появится система контроля версий.
                icon: Icons.refresh_rounded,
                title: 'Версия',
                subtitle: '$_appVersion ($_appBuild)',
                onTap: () {},
              ),
              SettingsTile(
                icon: Icons.description_outlined,
                title: 'Лицензии',
                subtitle: 'Используемые компоненты',
                onTap: () => Navigator.of(context).push(
                  appRoute(context, const LicensesScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: _Copyright(),
          ),
        ],
      ),
    );
  }

  /// Контекст передаётся явно: метод виджета не имеет поля `context`,
  /// а ScaffoldMessenger нужен именно этому экрану.
  Future<void> _openLink(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    // canLaunchUrl может вернуть false без явной регистрации схемы,
    // поэтому пробуем запуск напрямую
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть ссылку')),
      );
    }
  }
}

/// Копирайт: год запуска — 2026; далее — диапазон до года устройства.
/// Часы на телефоне могут врать в прошлое: меньше 2026 не показываем,
/// а равный год печатается одиночным значением, без «2026 – 2026».
class _Copyright extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final deviceYear = DateTime.now().year;
    final year = deviceYear < 2026 ? 2026 : deviceYear;
    final range = deviceYear > 2026 ? '2026 – $year' : '$year';

    return Text(
      '© РТУ МИРЭА, $range\n© Vibe Moments Technologies, $range',
      textAlign: TextAlign.center,
      style: AppText.caption.copyWith(color: AppColors.secondaryLight, height: 1.5),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(
          text,
          style: AppText.caption.copyWith(color: AppColors.secondaryLight),
        ),
      );
}
