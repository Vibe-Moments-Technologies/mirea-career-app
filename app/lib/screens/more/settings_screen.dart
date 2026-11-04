import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scroll.dart';
import '../../core/widgets/glass_back_button.dart';
import '../../core/widgets/settings_list.dart';
import '../../state/providers.dart';

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
          // Сброс локальных данных убран по просьбе владельца: студенту
          // незачем стирать профиль/избранное из приложения, а отладочные
          // сценарии решаются переустановкой. «О приложении» переехал
          // в «Ещё» — редкое действие не место в настройках.
          const SizedBox(height: 8),
        ],
      ),
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
