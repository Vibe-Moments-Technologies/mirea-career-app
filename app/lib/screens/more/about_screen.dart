import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/settings_list.dart';
import '../../data/crash_reporting.dart';

/// Версия приложения. Совпадает с pubspec.yaml; CI подставляет свою.
const _appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0');
const _appBuild = String.fromEnvironment('APP_BUILD', defaultValue: '1');

/// «О приложении»: назначение, версия, контакты.
///
/// Экран полноценный, а не системный диалог: раньше здесь открывался
/// `showAboutDialog`, где нельзя было ни разместить контакты, ни спрятать
/// отладочный вход.
class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  /// Счётчик нажатий на версию.
  ///
  /// 8 нажатий подряд открывают отладочный экран — стандартный приём,
  /// чтобы инструменты были доступны тестировщику и не видны студенту.
  int _versionTaps = 0;

  void _onVersionTap() {
    _versionTaps++;
    if (_versionTaps >= 8) {
      _versionTaps = 0;
      HapticFeedback.mediumImpact();
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DebugScreen()),
      );
      return;
    }
    // подсказываем, что осталось немного — иначе трюк неоткрываем
    if (_versionTaps >= 4) {
      final left = 8 - _versionTaps;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(milliseconds: 700),
            content: Text('До отладочного меню: $left'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    return Scaffold(
      appBar: AppBar(
        title: const Text('О приложении'),
        titleTextStyle: AppText.headline,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          pad,
          8,
          pad,
          AppInsets.scrollBottom(context),
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
          const _Section('ЧТО ЭТО'),
          Text(
            'Вакансии, стажировки, стипендии и события РТУ МИРЭА и компаний-партнёров '
            'в одном месте. Карточки публикуют сотрудники университета и партнёров '
            'после проверки модератором.',
            style: AppText.body.copyWith(height: 1.5),
          ),
          const SizedBox(height: 5),
          Text(
            'Приложение работает без регистрации: смотреть и искать можно сразу. '
            'Избранное, профиль и интересы хранятся только на вашем устройстве.',
            style: AppText.body.copyWith(height: 1.5),
          ),
          const SizedBox(height: 24),
          const _Section('КАК ЭТО РАБОТАЕТ'),
          SettingsGroup(
            children: [
              _HowTile(
                icon: Icons.search_rounded,
                title: 'Ищите',
                body: 'Каталог с фильтрами по типу, формату, институту и тегам.',
              ),
              _HowTile(
                icon: Icons.auto_awesome_rounded,
                title: 'Подбирайте',
                body: 'Раздел «Для вас» учитывает институт, уровень и интересы '
                    'из профиля — всё считается на устройстве.',
              ),
              _HowTile(
                icon: Icons.bookmark_rounded,
                title: 'Сохраняйте',
                body: 'Избранное доступно офлайн и не требует аккаунта.',
              ),
              _HowTile(
                icon: Icons.open_in_new_rounded,
                title: 'Записывайтесь',
                body: 'Кнопка на карточке ведёт на форму регистрации организатора.',
                last: true,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _Section('ПОДДЕРЖКА'),
          SettingsGroup(
            children: [
              SettingsTile(
                icon: Icons.mail_outline_rounded,
                title: 'Написать в карьерный центр',
                subtitle: 'career@mirea.ru',
                onTap: () => _openLink('mailto:career@mirea.ru'),
              ),
              SettingsTile(
                icon: Icons.language_rounded,
                title: 'Сайт университета',
                subtitle: 'mirea.ru',
                onTap: () => _openLink('https://mirea.ru'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SettingsGroup(
            footer: 'Данные профиля не покидают устройство. '
                'Просмотры и добавления в избранное передаются обезличенно — '
                'без идентификаторов пользователя.',
            children: [
              // 8 нажатий подряд открывают отладочное меню
              ListTile(
                onTap: _onVersionTap,
                title: Text('Версия', style: AppText.headline),
                trailing: Text(
                  '$_appVersion ($_appBuild)',
                  style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
                ),
              ),
              const SettingsValueTile(title: 'Платформа', value: 'Flutter'),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '© РТУ МИРЭА, ${DateTime.now().year}',
              style: AppText.caption.copyWith(color: AppColors.secondaryLight),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    // canLaunchUrl может вернуть false без явной регистрации схемы,
    // поэтому пробуем запуск напрямую и сообщаем, если не получилось
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть ссылку')),
      );
    }
  }
}

/// Отладочное меню: открывается 8 нажатиями по версии.
///
/// В релизной сборке инструментов здесь нет — без них экран покажет
/// только пояснение, чтобы было понятно, почему он пуст.
class DebugScreen extends StatelessWidget {
  const DebugScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Отладка'),
        titleTextStyle: AppText.headline,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(pad, 8, pad, AppInsets.scrollBottom(context)),
        children: [
          SettingsGroup(
            title: 'Диагностика',
            footer: 'Телеметрия помогает узнать о сбоях у тестировщиков. '
                'Без неё release-сборка не сообщает об ошибках вообще.',
            children: [
              SettingsValueTile(
                title: 'Sentry DSN',
                value: CrashReporting.isEnabled ? 'задан' : 'не задан',
              ),
              const SettingsValueTile(
                title: 'Окружение',
                value: String.fromEnvironment('SENTRY_ENVIRONMENT', defaultValue: '—'),
              ),
              const SettingsValueTile(
                title: 'Канал',
                value: String.fromEnvironment('APP_CHANNEL', defaultValue: '—'),
              ),
            ],
          ),
          if (CrashReporting.isEnabled) ...[
            const SizedBox(height: 24),
            SettingsGroup(
              title: 'Проверка',
              children: [
                Builder(
                  builder: (context) => SettingsTile(
                    icon: Icons.bug_report_outlined,
                    title: 'Отправить тестовую ошибку',
                    subtitle: 'Событие появится в Sentry в течение минуты',
                    onTap: () async {
                      try {
                        throw StateError('Отладочная проверка из приложения');
                      } catch (e, st) {
                        await CrashReporting.report(e, st, context: 'debug_screen');
                      }
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Ошибка отправлена')),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HowTile extends StatelessWidget {
  const _HowTile({
    required this.icon,
    required this.title,
    required this.body,
    this.last = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, last ? 14 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 10),
              Text(title, style: AppText.headline),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: AppText.footnote.copyWith(color: AppColors.secondaryLight, height: 1.45),
          ),
          if (!last) const SizedBox(height: 14),
        ],
      ),
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