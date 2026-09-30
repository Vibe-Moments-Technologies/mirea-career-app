import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/settings_list.dart';
import '../../data/catalogs.dart';
import '../../data/local_store.dart';
import '../../state/providers.dart';
import '../onboarding/onboarding_screen.dart';
import 'settings_screen.dart';

/// «Ещё»: вход в профиль и настройки.
///
/// Раздел сознательно короткий: оформление, сброс данных и отладка переехали
/// в отдельный экран настроек, а не лежали вперемешку с профилем.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    return Scaffold(
      body: ListView(
        // Верхний отступ учитывает safe area: без него крупный заголовок
        // упирался в вырез/статус-бар и выглядел обрезанным.
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
              SettingsTile(
                icon: Icons.tune_rounded,
                title: 'Настройки',
                subtitle: 'Оформление, данные, о приложении',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
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

/// Сводка профиля для подписи в списке.
///
/// Ключевое: раньше при пропущенном опросе здесь стояло «Заполнен» — потому
/// что проверялся флаг `completed`, а он выставляется и при пропуске.
/// Теперь «заполнен» означает «есть хотя бы один ответ».
String profileSummary(StudentProfile profile) {
  if (!profile.hasAnswers) return 'Не заполнен — нажмите, чтобы заполнить';

  final parts = <String>[
    if (profile.institute != null) Catalogs.instituteTitle(profile.institute),
    if (profile.level != null) Catalogs.levelTitle(profile.level),
    if (profile.tags.isNotEmpty) '${profile.tags.length} интересов',
  ];
  return parts.isEmpty ? 'Заполнен' : parts.join(' · ');
}