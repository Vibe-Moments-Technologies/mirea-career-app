import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../data/catalogs.dart';
import '../../data/local_store.dart';

/// Онбординг: welcome-экран + 6 вопросов по одному с анимацией смены.
///
/// Первый запуск показывает welcome без полей: красивый экран-приглашение.
/// Дальше — «Давайте познакомимся»: вопросы появляются по одному;
/// ответивший вопрос уезжает, следующий приезжает (AnimatedSwitcher).
/// Все шаги пропускаемы: «Пропустить» завершает опрос сразу, «Позже»
/// на welcome — тоже; дозаполнить можно в профиле.
///
/// Результат живёт только на устройстве и питает подбор «Для вас»
/// и автозаполнение анкет (ФИО, группа).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.initial, required this.onDone});

  final StudentProfile initial;
  final ValueChanged<StudentProfile> onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late StudentProfile _p = widget.initial;
  int _step = 0; // 0 = welcome, 1..6 = вопросы

  /// В режиме редактирования (открыт из профиля) welcome не показываем.
  bool get _isEditing => widget.initial.completed;

  static const _questions = 6;

  void _finish({bool skip = false}) {
    if (skip) {
      // «Пропустить»: онбординг пройден формально, чтобы экран не
      // возвращался при каждом запуске. Ответы не выдумываем.
      widget.onDone(_p.copyWith(completed: true));
      return;
    }
    widget.onDone(_p.copyWith(completed: true));
  }

  void _next() {
    if (_step < _questions) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  void _back() {
    if (_step > 1) {
      setState(() => _step--);
    } else if (!_isEditing) {
      _finish(skip: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);
    final effectiveStep = _isEditing && _step == 0 ? 1 : _step;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (_isEditing)
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 8, pad - 8, 0),
                child: Row(
                  children: [
                    Text('Профиль', style: AppText.title),
                    const Spacer(),
                    IconButton(
                      onPressed: () => widget.onDone(_p),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Закрыть',
                    ),
                  ],
                ),
              ),
            if (effectiveStep > 0)
              Padding(
                padding: EdgeInsets.fromLTRB(pad, _isEditing ? 4 : 12, pad, 0),
                child: Row(
                  children: [
                    for (var i = 0; i < _questions; i++)
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          height: 4,
                          margin:
                              EdgeInsets.only(right: i == _questions - 1 ? 0 : 6),
                          decoration: BoxDecoration(
                            color: i < effectiveStep
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              // Анимация смены: вопрос уезжает влево, следующий приезжает
              // справа — по одному, как просили. welcome → вопрос 1 тем же
              // переходом.
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => SlideTransition(
                  position: Tween(
                    begin: const Offset(0.12, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: _stepFor(effectiveStep),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, 16),
              child: Row(
                children: [
                  if (effectiveStep > 0 && !_isEditing)
                    TextButton(
                      onPressed: () => _finish(skip: true),
                      child: const Text('Пропустить'),
                    )
                  else if (effectiveStep > 0)
                    TextButton(onPressed: _back, child: const Text('Назад')),
                  const Spacer(),
                  if (effectiveStep == 0 && !_isEditing)
                    FilledButton(
                      onPressed: _next,
                      style: _pillButton,
                      child: const Text('Начать опрос'),
                    )
                  else if (effectiveStep == 0)
                    TextButton(
                      onPressed: () => widget.onDone(_p),
                      child: const Text('Закрыть'),
                    )
                  else
                    FilledButton(
                      onPressed: _next,
                      style: _pillButton,
                      child: Text(effectiveStep == _questions ? 'Готово' : 'Далее'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  ButtonStyle get _pillButton => FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      );

  /// Экран по номеру шага. Ключ — номер шага: AnimatedSwitcher меняет
  /// детей по ключу.
  Widget _stepFor(int step) {
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);
    return KeyedSubtree(
      key: ValueKey(step),
      child: step == 0
          ? _Welcome(onStart: _next, onSkip: () => _finish(skip: true))
          : SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: pad, vertical: 24),
              child: switch (step) {
                1 => _StepIdentity(
                    profile: _p,
                    onChanged: (p) => setState(() => _p = p),
                  ),
                2 => _StepInstitute(
                    selected: _p.institute,
                    onPick: (v) => setState(
                        () => _p = _p.copyWith(institute: v)),
                  ),
                3 => _StepDepartment(
                    institute: _p.institute,
                    selected: _p.department,
                    onChanged: (v) => setState(
                        () => _p = v == null
                            ? _p.copyWith(clearDepartment: true)
                            : _p.copyWith(department: v)),
                  ),
                4 => _StepGroup(
                    profile: _p,
                    onChanged: (p) => setState(() => _p = p),
                  ),
                5 => _StepLevelAndCourse(
                    profile: _p,
                    onChanged: (p) => setState(() => _p = p),
                  ),
                _ => _StepInterests(
                    selected: _p.tags,
                    onToggle: (v) => setState(() {
                      final t = [..._p.tags];
                      t.contains(v) ? t.remove(v) : t.add(v);
                      _p = _p.copyWith(tags: t);
                    }),
                  ),
              },
            ),
    );
  }
}

/// Welcome-экран: без полей, только приглашение.
class _Welcome extends StatelessWidget {
  const _Welcome({required this.onStart, required this.onSkip});

  final VoidCallback onStart;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pad),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Эмблема: крупная, спокойная — не спорит с текстом.
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(Icons.school_rounded,
                size: 44, color: scheme.primary),
          ),
          const SizedBox(height: 28),
          Text('Добро пожаловать!',
              style: AppText.largeTitle.copyWith(fontSize: 34)),
          const SizedBox(height: 14),
          Text(
            '«Карьера РТУ МИРЭА» — вакансии, стажировки и события вуза '
            'и компаний-партнёров — в одном приложении, без регистрации.',
            style: AppText.body.copyWith(height: 1.5),
          ),
          const SizedBox(height: 22),
          Text(
            'Пройдите короткий опрос — и лента подстроится под вас: '
            'институт, курс и интересы учитываются в подборе «Для вас». '
            'ФИО и группу запоминать не обязательно, но удобно: анкеты '
            'мероприятий заполнятся сами.',
            style: AppText.footnote
                .copyWith(color: AppColors.secondaryLight, height: 1.5),
          ),
          const SizedBox(height: 22),
          Text(
            'Не хотите — пропустите все или часть вопросов: вернуться '
            'к ним можно в любой момент в профиле.',
            style: AppText.footnote
                .copyWith(color: AppColors.secondaryLight, height: 1.5),
          ),
          const SizedBox(height: 28),
          TextButton(onPressed: onSkip, child: const Text('Позже')),
        ],
      ),
    );
  }
}

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({required this.title, required this.subtitle, required this.child});
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: pad, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.largeTitle),
          const SizedBox(height: 8),
          Text(subtitle, style: AppText.body.copyWith(color: AppColors.secondaryLight)),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }
}

/// Шаг 1: ФИО — объясняем Зачем: автозаполнение анкет.
class _StepIdentity extends StatefulWidget {
  const _StepIdentity({required this.profile, required this.onChanged});
  final StudentProfile profile;
  final ValueChanged<StudentProfile> onChanged;

  @override
  State<_StepIdentity> createState() => _StepIdentityState();
}

class _StepIdentityState extends State<_StepIdentity> {
  late final _name =
      TextEditingController(text: widget.profile.fullName ?? '');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _sync() => widget.onChanged(
        widget.profile.copyWith(
          fullName: _name.text.trim().isEmpty ? null : _name.text.trim(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: 'Как вас зовут?',
      subtitle: 'ФИО запомнится на устройстве и будет автоматически '
          'подставляться в анкеты мероприятий — вводить его придётся '
          'один раз. Данные не покидают телефон.',
      child: TextField(
        controller: _name,
        onChanged: (_) => _sync(),
        textCapitalization: TextCapitalization.words,
        decoration: _fieldDecoration(context, 'Фамилия Имя Отчество'),
      ),
    );
  }
}

/// Шаг 4: группа — с объяснением пользы и автокурсом.
class _StepGroup extends StatefulWidget {
  const _StepGroup({required this.profile, required this.onChanged});
  final StudentProfile profile;
  final ValueChanged<StudentProfile> onChanged;

  @override
  State<_StepGroup> createState() => _StepGroupState();
}

class _StepGroupState extends State<_StepGroup> {
  late final _group =
      TextEditingController(text: widget.profile.group ?? '');

  @override
  void dispose() {
    _group.dispose();
    super.dispose();
  }

  void _sync() {
    final value = _group.text.trim();
    widget.onChanged(
      widget.profile.copyWith(
        group: value.isEmpty ? null : value,
        // Курс пересчитываем из года в номере группы, если его ещё
        // не правили вручную (следующий шаг предложит поправить).
        course: StudentProfile.courseFromGroup(value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: 'Ваша группа?',
      subtitle: 'Группа — самая полезная часть профиля: подставляется '
          'в анкеты автоматически, а по году в номере мы вычислим курс '
          'и предложим то, что подходит вашей программе.',
      child: TextField(
        controller: _group,
        onChanged: (_) => _sync(),
        decoration: _fieldDecoration(context, 'Например, ИКБО-01-23'),
      ),
    );
  }
}

/// Шаг 3: кафедра — чипы из справочника института + свободный ввод.
class _StepDepartment extends StatelessWidget {
  const _StepDepartment({
    required this.institute,
    required this.selected,
    required this.onChanged,
  });

  final String? institute;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final departments =
        Catalogs.departments[institute] ?? const <String>[];

    return _StepScaffold(
      title: 'Кафедра',
      subtitle: departments.isEmpty
          ? 'Выберите институт на предыдущем шаге — предложим кафедры. '
              'Или впишите свою.'
          : 'Уточняет подбор внутри института. Не нашли свою — впишите.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in departments)
                ChoiceChip(
                  label: Text(d),
                  selected: selected == d,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    onChanged(selected == d ? null : d);
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            onChanged: (v) => onChanged(v.trim().isEmpty ? null : v.trim()),
            decoration: _fieldDecoration(context, 'Своя кафедра'),
          ),
        ],
      ),
    );
  }
}

/// Шаг 5: уровень + курс (подсказан группой, правится чипами).
class _StepLevelAndCourse extends StatelessWidget {
  const _StepLevelAndCourse({
    required this.profile,
    required this.onChanged,
  });

  final StudentProfile profile;
  final ValueChanged<StudentProfile> onChanged;

  @override
  Widget build(BuildContext context) {
    final suggested = profile.course;

    return _StepScaffold(
      title: 'Уровень и курс',
      subtitle: suggested != null
          ? 'По группе выходит $suggested-й курс — если что-то не так, '
              'поправьте.'
          : 'Курс не удалось угадать по группе — выберите вручную.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Уровень обучения', style: AppText.cardTitle),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final l in Catalogs.levels)
                ChoiceChip(
                  label: Text(l.title),
                  selected: profile.level == l.id,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    onChanged(profile.copyWith(level: l.id));
                  },
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Курс', style: AppText.cardTitle),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 1; i <= 6; i++)
                ChoiceChip(
                  label: Text('$i'),
                  selected: profile.course == i,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    onChanged(profile.copyWith(course: i));
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Шаг 2: институт — плитки.
class _StepInstitute extends StatelessWidget {
  const _StepInstitute({required this.selected, required this.onPick});
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: 'Ваш институт',
      subtitle: 'Можно изменить в любой момент',
      child: Column(
        children: [
          for (final i in Catalogs.institutes)
            _Tile(
              title: i.short,
              subtitle: i.title,
              selected: selected == i.id,
              onTap: () => onPick(i.id),
            ),
        ],
      ),
    );
  }
}

/// Шаг 6: интересы.
class _StepInterests extends StatelessWidget {
  const _StepInterests({required this.selected, required this.onToggle});
  final List<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: 'Что вам интересно?',
      subtitle: 'Выберите несколько — подбор «Для вас» подстроится',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final t in Catalogs.interests)
            ChoiceChip(
              label: Text(t.title),
              selected: selected.contains(t.id),
              onSelected: (_) {
                HapticFeedback.selectionClick();
                onToggle(t.id);
              },
            ),
        ],
      ),
    );
  }
}

InputDecoration _fieldDecoration(BuildContext context, String hint) =>
    InputDecoration(
      hintText: hint,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: BorderSide(color: AppColors.separator(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: BorderSide(color: AppColors.separator(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );

class _Tile extends StatelessWidget {
  const _Tile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(
            color: selected ? accent : AppColors.separator(context),
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            color:
                selected ? accent.withValues(alpha: 0.06) : Colors.transparent,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppText.headline),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppText.footnote
                            .copyWith(color: AppColors.secondaryLight),
                      ),
                    ],
                  ),
                ),
                AnimatedScale(
                  scale: selected ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  child: Icon(Icons.check_circle_rounded, color: accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
