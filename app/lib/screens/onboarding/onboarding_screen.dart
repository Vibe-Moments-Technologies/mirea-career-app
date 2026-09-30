import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../data/catalogs.dart';
import '../../data/local_store.dart';

/// Онбординг: 4 шага, пропускаемые (docs/UI.md §3).
/// Результат живёт только на устройстве и питает фильтр «Для вас».
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.initial, required this.onDone});

  final StudentProfile initial;
  final ValueChanged<StudentProfile> onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late StudentProfile _p = widget.initial;
  final _controller = PageController();
  int _step = 0;

  /// Шага три: институт, уровень, интересы.
  /// Кампус из опроса убран — адрес не нужен для подбора, а вопрос
  /// «где вы учитесь» на старте только удлинял анкету.
  static const _steps = 3;

  /// В режиме редактирования (открыт из настроек) шаги не пролистываем
  /// заново — экран сразу показывает уже заполненные ответы.
  bool get _isEditing => widget.initial.completed;

  void _next() {
    if (_step < _steps - 1) {
      _controller.nextPage(duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
    } else {
      widget.onDone(_p.copyWith(completed: true));
    }
  }

  void _back() {
    if (_step == 0) {
      // «Пропустить»: онбординг пройден формально, чтобы экран не возвращался
      // при каждом запуске. Ответы при этом не выдумываем — профиль остаётся
      // пустым, и подбор покажет приглашение заполнить его.
      widget.onDone(_p.copyWith(completed: true));
    } else {
      _controller.previousPage(duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
    }
  }

  /// Шаги с единственным выбором (институт, уровень) после выбора листаем
  /// дальше сами — не заставляем пользователя жать «Далее» лишний раз.
  /// Небольшая пауза: видно, что выбор отметился, и переход не «дёргается».
  /// При редактировании профиля автоскролла нет: там выбор меняется
  /// осознанно, и неожиданная прокрутка мешала бы.
  void _maybeAdvance(bool changed) {
    if (!changed || _isEditing || _step >= _steps - 1) return;
    Future.delayed(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      _controller.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // В режиме редактирования (открыт из настроек) показываем
            // заголовок и кнопку закрытия — иначе экран выглядит как
            // онбординг и непонятно, как выйти без потери ответов.
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
            // точки прогресса
            Padding(
              padding: EdgeInsets.fromLTRB(pad, _isEditing ? 4 : 12, pad, 0),
              child: Row(
                children: [
                  for (var i = 0; i < _steps; i++)
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        height: 4,
                        margin: EdgeInsets.only(right: i == _steps - 1 ? 0 : 6),
                        decoration: BoxDecoration(
                          color: i <= _step
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _step = i),
                children: [
                  _StepInstitute(
                    selected: _p.institute,
                    onPick: (v) {
                      // запоминаем до изменения: листаем вперёд только
                      // при выборе НОВОГО значения, а не при отмене
                      final changed = v != _p.institute;
                      setState(
                        () => _p = changed
                            ? _p.copyWith(institute: v)
                            : _p.copyWith(clearInstitute: true),
                      );
                      _maybeAdvance(changed);
                    },
                  ),
                  _StepLevel(
                    selected: _p.level,
                    onPick: (v) {
                      final changed = v != _p.level;
                      setState(
                        () => _p = changed
                            ? _p.copyWith(level: v)
                            : _p.copyWith(clearLevel: true),
                      );
                      _maybeAdvance(changed);
                    },
                  ),
                  _StepInterests(
                    selected: _p.tags,
                    onToggle: (v) => setState(() {
                      final t = [..._p.tags];
                      t.contains(v) ? t.remove(v) : t.add(v);
                      _p = _p.copyWith(tags: t);
                    }),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _back,
                    // при редактировании профиль уже пройден — «Пропустить»
                    // здесь не имеет смысла, остаётся только «Назад»
                    child: Text(_step == 0 && !_isEditing ? 'Пропустить' : 'Назад'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                    child: Text(_step == _steps - 1 ? 'Готово' : 'Далее'),
                  ),
                ],
              ),
            ),
          ],
        ),
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

class _StepLevel extends StatelessWidget {
  const _StepLevel({required this.selected, required this.onPick});
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: 'Уровень обучения',
      subtitle: 'Поможет отсеять неподходящие предложения',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final l in Catalogs.levels)
            ChoiceChip(
              label: Text(l.title),
              selected: selected == l.id,
              onSelected: (_) {
                HapticFeedback.selectionClick();
                onPick(l.id);
              },
            ),
        ],
      ),
    );
  }
}

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
            FilterChip(
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

class _Tile extends StatelessWidget {
  const _Tile({required this.title, required this.subtitle, required this.selected, required this.onTap});
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
        borderRadius: BorderRadius.circular(AppRadius.card),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          // Рамка выбора анимируется: при выборе плитка подсвечивается
          // акцентом, при снятии — гаснет, а не переключается мгновенно.
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
          highlightColor: accent.withValues(alpha: 0.06),
          splashColor: accent.withValues(alpha: 0.08),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            color: selected ? accent.withValues(alpha: 0.06) : Colors.transparent,
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
                        style: AppText.footnote.copyWith(color: AppColors.secondaryLight),
                      ),
                    ],
                  ),
                ),
                // Галочка появляется/исчезает плавно, а не скачком.
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