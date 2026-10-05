import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scroll.dart';
import '../../core/widgets/glass_back_button.dart';
import '../../core/widgets/settings_list.dart';
import '../../state/providers.dart';
import 'about_screen.dart';

/// Настройки: оформление, данные, вход в «О приложении».
///
/// Отдельный экран (раньше всё лежало в «Ещё» вперемешку с профилем):
/// так «Ещё» остаётся коротким списком, а редкие действия не мозолят глаза.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
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
          const _GroupTitle('Оформление'),
          // RadioGroup управляет выбором на уровне группы: сами плитки
          // в новом Flutter не принимают groupValue/onChanged.
          RadioGroup<ThemeMode>(
            groupValue: themeMode,
            onChanged: (v) {
              if (v != null) ref.read(themeModeProvider.notifier).set(v);
            },
            child: const SettingsGroup(
              children: [
                _ThemeTile(ThemeMode.system, 'Как в системе'),
                _ThemeTile(ThemeMode.light, 'Светлая'),
                _ThemeTile(ThemeMode.dark, 'Тёмная'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _GroupTitle('Приложение'),
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
          // Сброс — последним пунктом: действие необратимое, не должно
          // попадаться под палец раньше остальных.
          const _GroupTitle('Данные'),
          SettingsGroup(
            footer: 'Удаляются только данные на этом устройстве. '
                'Отправленные счётчики просмотров остаются обезличенными.',
            children: [
              SettingsTile(
                icon: Icons.delete_outline_rounded,
                title: 'Сбросить локальные данные',
                subtitle: 'Избранное, профиль и кэш ленты',
                danger: true,
                onTap: () => _confirmReset(context, ref),
              ),
            ],
          ),
          // Отладочные инструменты намеренно НЕ здесь: они живут в скрытом
          // меню (8 нажатий по версии в «О приложении»). Постоянный пункт
          // «Отладка» подразумевал бы, что кнопка есть у всех студентов.
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Сбросить данные?'),
        content: const Text(
          'Профиль, избранное и кэш ленты будут удалены с устройства. '
          'Приложение вернётся к первому запуску.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await ref.read(localStoreProvider).reset();
    await ref.read(profileProvider.notifier).reset();
    ref.invalidate(favoritesProvider);
    await ref.read(feedProvider.notifier).refresh();

    if (!context.mounted) return;
    // Сообщаем результат: молчаливый сброс выглядит как «ничего не произошло»
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Данные удалены')),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile(this.mode, this.label);
  final ThemeMode mode;
  final String label;

  @override
  Widget build(BuildContext context) => RadioListTile<ThemeMode>(
        value: mode,
        title: Text(label, style: AppText.headline),
      );
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: AppText.section.copyWith(color: AppColors.secondaryLight),
        ),
      );
}
