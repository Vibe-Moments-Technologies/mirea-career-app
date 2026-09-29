import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/catalogs.dart';
import '../../data/local_store.dart';
import '../../state/providers.dart';
import '../onboarding/onboarding_screen.dart';

/// «Другое»: профиль, оформление, о приложении (docs/UI.md §9).
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final themeMode = ref.watch(themeModeProvider);
    final store = ref.watch(localStoreProvider);

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppInsets.horizontal(MediaQuery.sizeOf(context).width),
          0,
          AppInsets.horizontal(MediaQuery.sizeOf(context).width),
          AppInsets.scrollBottom(context),
        ),
        children: [
          const SizedBox(height: 8),
          Text('Другое', style: AppText.largeTitle),
          const SizedBox(height: 20),
          _Group(
            children: [
              _Tile(
                icon: Icons.person_rounded,
                title: 'Мой профиль',
                subtitle: _profileSummary(profile),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OnboardingScreen(
                      initial: profile,
                      onDone: (p) {
                        ref.read(profileProvider.notifier).save(p);
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _GroupTitle('Оформление'),
          // RadioGroup управляет выбором на уровне группы: сами плитки
          // в новом Flutter не принимают groupValue/onChanged.
          RadioGroup<ThemeMode>(
            groupValue: themeMode,
            onChanged: (v) {
              if (v != null) ref.read(themeModeProvider.notifier).set(v);
            },
            child: _Group(
              children: [
                for (final m in const [
                  (ThemeMode.system, 'Как в системе'),
                  (ThemeMode.light, 'Светлая'),
                  (ThemeMode.dark, 'Тёмная'),
                ])
                  RadioListTile<ThemeMode>(value: m.$1, title: Text(m.$2)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _GroupTitle('Приложение'),
          _Group(
            children: [
              _Tile(
                icon: Icons.info_outline_rounded,
                title: 'О приложении',
                subtitle: 'Карьера РТУ МИРЭА · версия 0.1.0 (MVP)',
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'Карьера РТУ МИРЭА',
                  applicationVersion: '0.1.0 (MVP)',
                  children: const [
                    Text(
                      'Библиотека вакансий, стажировок и событий вуза и партнёров. '
                      'Работает без регистрации: избранное и интересы хранятся только на устройстве.',
                    ),
                  ],
                ),
              ),
              _Tile(
                icon: Icons.support_agent_rounded,
                title: 'Карьерный центр',
                subtitle: 'Контакты и обратная связь',
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Контакты карьерного центра появятся позже')),
                ),
              ),
              _Tile(
                icon: Icons.delete_outline_rounded,
                title: 'Сбросить локальные данные',
                subtitle: 'Избранное, интересы и кэш ленты',
                danger: true,
                onTap: () => _confirmReset(context, ref, store),
              ),
            ],
          ),
          const SizedBox(height: 32),
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

  static String _profileSummary(StudentProfile p) {
    if (!p.completed) return 'Не заполнен — заполните для подборки «Для вас»';
    final parts = <String>[
      if (p.campus != null) Catalogs.campusTitle(p.campus),
      if (p.institute != null) Catalogs.instituteTitle(p.institute),
      if (p.tags.isNotEmpty) '${p.tags.length} интересов',
    ];
    return parts.isEmpty ? 'Заполнен' : parts.join(' · ');
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref, LocalStore store) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Сбросить данные?'),
        content: const Text('Избранное, интересы и кэш ленты будут удалены с устройства.'),
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
    await store.reset();
    await ref.read(profileProvider.notifier).reset();
    ref.invalidate(favoritesProvider);
    await ref.read(feedProvider.notifier).refresh();
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(children: children),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: AppText.caption.copyWith(color: AppColors.secondaryLight),
        ),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = danger ? AppColors.danger : scheme.primary;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color),
      title: Text(title, style: AppText.headline.copyWith(color: danger ? AppColors.danger : null)),
      subtitle: Text(
        subtitle,
        style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.secondaryLight),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
    );
  }
}