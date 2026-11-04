import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/catalogs.dart';
import '../../data/group_suggestions.dart';
import '../../data/local_store.dart';
import '../../state/providers.dart';

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
    // Курс: если не выбрали вручную — фиксируем вычисленный из группы,
    // чтобы в профиле сразу стояло верное значение.
    final course =
        _p.course ?? StudentProfile.courseFromGroup(_p.group);
    widget.onDone(_p.copyWith(completed: true, course: course));
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
                  // Welcome: «Позже» на одной линии с «Начать опрос»,
                  // а не под текстом.
                  if (effectiveStep == 0 && !_isEditing) ...[
                    TextButton(onPressed: onSkipLater, child: const Text('Позже')),
                    const Spacer(),
                    FilledButton(
                      onPressed: _next,
                      style: _pillButton,
                      child: const Text('Начать опрос'),
                    ),
                  ] else if (effectiveStep == 0) ...[
                    const Spacer(),
                    TextButton(
                      onPressed: () => widget.onDone(_p),
                      child: const Text('Закрыть'),
                    ),
                  ] else ...[
                    if (!_isEditing)
                      TextButton(
                        onPressed: () => _finish(skip: true),
                        child: const Text('Пропустить'),
                      )
                    else
                      TextButton(onPressed: _back, child: const Text('Назад')),
                    const Spacer(),
                    FilledButton(
                      onPressed: _next,
                      style: _pillButton,
                      child: Text(effectiveStep == _questions ? 'Готово' : 'Далее'),
                    ),
                  ],
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

  /// «Позже» на welcome: выйти, не начав опрос.
  void onSkipLater() => _finish(skip: true);

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
                    onPick: (v) {
                      setState(() => _p = _p.copyWith(institute: v));
                      // Выбор плитки — сразу дальше: не заставляем жать
                      // «Далее» (пауза, чтобы увидеть отметку выбора).
                      if (!_isEditing) {
                        Future.delayed(const Duration(milliseconds: 220), () {
                          if (mounted) _next();
                        });
                      }
                    },
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
            'Это «Карьера РТУ МИРЭА» — все вакансии, стажировки и события '
            'университета в одном приложении. Регистрация не нужна.',
            style: AppText.body.copyWith(height: 1.5),
          ),
          const SizedBox(height: 22),
          Text(
            'Ответьте на несколько вопросов — и главная лента станет вашей: '
            'приложение будет показывать сначала то, что подходит вашему '
            'институту, курсу и интересам.',
            style: AppText.footnote
                .copyWith(color: AppColors.secondaryLight, height: 1.5),
          ),
          const SizedBox(height: 12),
          Text(
            'Любой вопрос можно пропустить и ответить позже — '
            'профиль легко дополнить в разделе «Ещё».',
            style: AppText.footnote
                .copyWith(color: AppColors.secondaryLight, height: 1.5),
          ),
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
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: _fieldDecoration(context, 'Фамилия Имя Отчество'),
      ),
    );
  }
}

/// Шаг 4: группа — капс, живые подсказки из API вуза, автокурс.
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

  /// Подсказки групп: живой поиск по API расписания вуза.
  /// debounced — не на каждый символ.
  List<String> _suggestions = [];
  int _requestSeq = 0;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _group.dispose();
    super.dispose();
  }

  void _sync() {
    final value = _group.text.trim();
    widget.onChanged(
      // Курс НЕ пишем здесь: его считает (и даёт поправить) следующий
      // шаг — иначе редактирование группы затирает ручной выбор курса.
      widget.profile.copyWith(group: value.isEmpty ? null : value),
    );

    // Подсказки: с задержкой, чтобы не спрашивать на каждый символ.
    _debounce?.cancel();
    if (value.length < 2) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), _loadSuggestions);
  }

  Future<void> _loadSuggestions() async {
    final seq = ++_requestSeq;
    final results = await GroupSuggestions.search(_group.text);
    // Пришёл не последний запрос — результат устарел.
    if (!mounted || seq != _requestSeq) return;
    // Выбранная группа не должна предлагать сама себя.
    final fresh =
        results.where((g) => g != _group.text.trim()).toList();
    setState(() => _suggestions = fresh);
  }

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: 'Ваша группа?',
      subtitle: 'Группа — самая полезная часть профиля: подставляется '
          'в анкеты автоматически, а по году в номере мы вычислим курс '
          'и предложим то, что подходит вашей программе.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _group,
            onChanged: (_) => _sync(),
            autofocus: true,
            // Номера групп — капсом: ИКБО-01-23.
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              TextInputFormatter.withFunction((oldValue, newValue) =>
                  newValue.copyWith(text: newValue.text.toUpperCase())),
            ],
            decoration: _fieldDecoration(context, 'Например, ИКБО-01-23'),
          ),
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in _suggestions)
                  ActionChip(
                    label: Text(g),
                    onPressed: () {
                      _group.text = g;
                      _sync();
                      // Подсказка выбрана — убираем список.
                      setState(() => _suggestions = []);
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Шаг 3: кафедра — просто поле ввода с примером-подсказкой.
class _StepDepartment extends StatefulWidget {
  const _StepDepartment({
    required this.institute,
    required this.selected,
    required this.onChanged,
  });

  final String? institute;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  State<_StepDepartment> createState() => _StepDepartmentState();
}

class _StepDepartmentState extends State<_StepDepartment> {
  late final _text = TextEditingController(text: widget.selected ?? '');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: 'Кафедра',
      subtitle: 'Уточняет подбор внутри института. Пропустите, если '
          'не помните точно.',
      child: TextField(
        controller: _text,
        onChanged: (v) =>
            widget.onChanged(v.trim().isEmpty ? null : v.trim()),
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [
          // Кафедры в МИРЭА пишутся капсом: КБ-11. Форматируем на лету.
          TextInputFormatter.withFunction((oldValue, newValue) =>
              newValue.copyWith(text: newValue.text.toUpperCase())),
        ],
        decoration: _fieldDecoration(context, 'Например, КБ-11'),
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
    // Вычисляем курс ЗАНОВО из группы: подпись «по группе выходит»
    // должна говорить про расчёт, а не про то, что человек уже выбрал.
    final fromGroup = StudentProfile.courseFromGroup(profile.group);
    final semester = _semesterLabel();

    return _StepScaffold(
      title: 'Уровень и курс',
      subtitle: fromGroup != null
          ? 'По вашей группе получается $fromGroup-й курс '
              '($semester) — если что-то не так, поправьте.'
          : 'Курс не удалось определить по группе — выберите вручную.',
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
                  selected: (profile.course ?? fromGroup) == i,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    onChanged(profile.copyWith(course: i));
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Сейчас идёт $semester.',
            style: AppText.footnote
                .copyWith(color: AppColors.secondaryLight),
          ),
        ],
      ),
    );
  }

  /// Осенний семестр — с 1 сентября по 31 января, весенний — с 1 февраля.
  static String _semesterLabel() {
    final m = DateTime.now().month;
    return (m >= 9 || m == 1) ? '1-й семестр' : '2-й семестр';
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

/// Шаг 6: интересы — теги из БД (коллекция interests, панель настраивает).
class _StepInterests extends ConsumerWidget {
  const _StepInterests({required this.selected, required this.onToggle});
  final List<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final titles = ref.watch(interestsProvider).value ??
        Catalogs.interests.map((i) => i.title).toList();

    return _StepScaffold(
      title: 'Что вам интересно?',
      subtitle: 'Выберите несколько — подбор «Для вас» подстроится',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final t in titles)
            ChoiceChip(
              label: Text(t),
              selected: selected.contains(t),
              onSelected: (_) {
                HapticFeedback.selectionClick();
                onToggle(t);
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
