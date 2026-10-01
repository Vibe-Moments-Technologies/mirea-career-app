import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scroll.dart';
import '../../core/widgets/glass_back_button.dart';
import '../../core/widgets/settings_list.dart';
import '../../data/catalogs.dart';
import '../../data/local_store.dart';
import '../../state/providers.dart';

/// Локальный профиль студента. Каждая строка открывается и правится отдельно.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
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
          const _Section('ОБРАЗОВАНИЕ'),
          SettingsGroup(
            children: [
              SettingsTile(
                icon: Icons.school_rounded,
                title: 'Институт',
                subtitle: Catalogs.instituteTitle(profile.institute),
                onTap: () => _pickInstitute(context, ref, profile),
              ),
              SettingsTile(
                icon: Icons.layers_rounded,
                title: 'Уровень обучения',
                subtitle: Catalogs.levelTitle(profile.level),
                onTap: () => _pickLevel(context, ref, profile),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const _Section('ИНТЕРЕСЫ'),
          SettingsGroup(
            children: [
              SettingsTile(
                icon: Icons.auto_awesome_rounded,
                title: 'Интересы',
                subtitle: profile.tags.isEmpty
                    ? 'Не выбраны'
                    : profile.tags.map(Catalogs.interestTitle).join(' · '),
                onTap: () => _pickInterests(context, ref, profile),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Данные профиля хранятся только на этом устройстве.',
            style: AppText.caption.copyWith(color: AppColors.secondaryLight),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Пустая строка = «не указывать»: снимаем поле, а не молча оставляем старое.
  static Future<void> _pickInstitute(
    BuildContext context,
    WidgetRef ref,
    StudentProfile profile,
  ) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => _ChoiceSheet(
        title: 'Институт',
        selected: profile.institute,
        choices: [for (final i in Catalogs.institutes) (i.id, i.short)],
      ),
    );
    if (value == null || !context.mounted) return;
    await ref.read(profileProvider.notifier).save(
          value.isEmpty ? profile.copyWith(clearInstitute: true) : profile.copyWith(institute: value),
        );
  }

  static Future<void> _pickLevel(
    BuildContext context,
    WidgetRef ref,
    StudentProfile profile,
  ) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => _ChoiceSheet(
        title: 'Уровень обучения',
        selected: profile.level,
        choices: [for (final l in Catalogs.levels) (l.id, l.title)],
      ),
    );
    if (value == null || !context.mounted) return;
    await ref.read(profileProvider.notifier).save(
          value.isEmpty ? profile.copyWith(clearLevel: true) : profile.copyWith(level: value),
        );
  }

  static Future<void> _pickInterests(
    BuildContext context,
    WidgetRef ref,
    StudentProfile profile,
  ) async {
    final value = await showModalBottomSheet<List<String>>(
      context: context,
      showDragHandle: true,
      builder: (_) => _InterestsSheet(selected: profile.tags),
    );
    if (value == null || !context.mounted) return;
    await ref.read(profileProvider.notifier).save(profile.copyWith(tags: value));
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          text,
          style: AppText.section.copyWith(color: AppColors.secondaryLight),
        ),
      );
}

/// Список вариантов с «Не указывать» в конце.
class _ChoiceSheet extends StatelessWidget {
  const _ChoiceSheet({
    required this.title,
    required this.selected,
    required this.choices,
  });

  final String title;
  final String? selected;
  final List<(String, String)> choices;

  @override
  Widget build(BuildContext context) {
    // RadioGroup владеет значением и обработкой нажатий: сами RadioListTile
    // в Flutter 3.47 groupValue/onChanged больше не принимают (deprecated).
    // Пустая строка = «не указывать», поэтому незаполненное поле и подсвечено
    // правильно, и снимается одним нажатием.
    return RadioGroup<String>(
      groupValue: selected ?? '',
      onChanged: (value) {
        if (value != null) Navigator.of(context).pop(value);
      },
      child: SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(title, style: AppText.title),
            ),
            for (final c in choices)
              RadioListTile<String>(value: c.$1, title: Text(c.$2)),
            const RadioListTile<String>(value: '', title: Text('Не указывать')),
          ],
        ),
      ),
    );
  }
}

class _InterestsSheet extends StatefulWidget {
  const _InterestsSheet({required this.selected});
  final List<String> selected;

  @override
  State<_InterestsSheet> createState() => _InterestsSheetState();
}

class _InterestsSheetState extends State<_InterestsSheet> {
  late final Set<String> chosen = widget.selected.toSet();

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Интересы', style: AppText.title),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in Catalogs.interests)
                    FilterChip(
                      label: Text(t.title),
                      selected: chosen.contains(t.id),
                      onSelected: (on) => setState(() {
                        on ? chosen.add(t.id) : chosen.remove(t.id);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(chosen.toList()),
                child: const Text('Готово'),
              ),
            ],
          ),
        ),
      );
}

/// Короткая сводка для строки в «Ещё».
///
/// Проверяется [StudentProfile.hasAnswers], а не `completed`: флаг ставится
/// и при пропуске опроса, и тогда подпись врала «Заполнен».
String profileSummary(StudentProfile profile) {
  if (!profile.hasAnswers) return 'Не заполнен — нажмите, чтобы настроить';
  return [
    if (profile.institute != null) Catalogs.instituteTitle(profile.institute),
    if (profile.level != null) Catalogs.levelTitle(profile.level),
    if (profile.tags.isNotEmpty) '${profile.tags.length} интересов',
  ].join(' · ');
}
