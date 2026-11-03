import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:survey_kit/survey_kit.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';

/// Id шагов анкеты, которые питаются профилем студента.
///
/// Админ конфигурирует анкету в БД и помечает шаги этими id — приложение
/// узнаёт их и подставляет значения из локального профиля. Синонимы
/// покрывают естественные варианты: админу не нужно помнить точный
/// список, «fio»/«full_name»/«фио» работают одинаково.
const _kFioStepIds = {'fio', 'full_name', 'fullname', 'фио', 'name'};
const _kGroupStepIds = {'group', 'group_number', 'группа'};

/// Экран опросника: анкета, конфигурируемая в БД.
///
/// Определение приходит из PocketBase (expand.form) в JSON-формате
/// survey_kit: `Task.fromJson(definition)`. Результат сериализуется
/// и отправляется в form_responses (анонимно: create открыт, read закрыт).
///
/// **Автозаполнение из профиля:** шаги с id ФИО/группы, для которых в
/// локальном профиле уже есть значение, ИЗЫМАЮТСЯ из анкеты (студент
/// не вводит одно и то же дважды), а сами значения подставляются
/// в ответы при отправке. Если в профиле пусто — шаг остаётся, студент
/// заполняет его руками, и после отправки поле запоминается в профиле
/// для следующих анкет.
///
/// Приоритет над внешней ссылкой: если у поста есть форма,
/// кнопка в деталях открывает её, а не браузер.
class FormScreen extends ConsumerStatefulWidget {
  const FormScreen({
    super.key,
    required this.form,
    this.postId,
  });

  final FormDefinition form;
  final String? postId;

  @override
  ConsumerState<FormScreen> createState() => _FormScreenState();
}

class _FormScreenState extends ConsumerState<FormScreen> {
  bool _submitted = false;

  /// Определение с изъятыми автозаполняемыми шагами (готово к рендеру).
  ///
  /// Вычисляется один раз в build-кэше: definition иммутабелен,
  /// профиль в рамках экрана меняться не должен.
  Map<String, dynamic>? _strippedDefinition;
  Map<String, String> _prefilled = {};

  Map<String, dynamic> _definitionFor() {
    if (_strippedDefinition != null) return _strippedDefinition!;

    final profile = ref.read(profileProvider);
    final definition = Map<String, dynamic>.from(widget.form.definition);
    final rawSteps = (definition['steps'] as List?)?.toList() ?? [];

    final prefilled = <String, String>{};
    final kept = <Map<String, dynamic>>[];
    for (final step in rawSteps) {
      if (step is! Map) {
        kept.add(Map<String, dynamic>.from(step));
        continue;
      }
      final s = Map<String, dynamic>.from(step);
      final id = (s['id'] as String?)?.toLowerCase().trim() ?? '';
      if (_kFioStepIds.contains(id) && profile.fullName != null) {
        prefilled[id] = profile.fullName!;
        continue; // шаг изымается — значение известно
      }
      if (_kGroupStepIds.contains(id) && profile.group != null) {
        prefilled[id] = profile.group!;
        continue;
      }
      kept.add(s);
    }

    // survey_kit требует List<Map<String, dynamic>> (жёсткий каст
    // в OrderedTask.fromJson), поэтому типизируем явно.
    definition['steps'] = kept;
    _prefilled = prefilled;
    _strippedDefinition = definition;
    return definition;
  }

  Future<void> _onResult(SurveyResult result) async {
    if (result.finishReason != FinishReason.completed) return;

    // Компактное представление: id шага → значение ответа.
    // Полный SurveyResult.toJson() избыточен для админа (тайминги,
    // дубли шагов) — оставляем только суть.
    final answers = <String, dynamic>{};
    for (final r in result.results) {
      final value = r.result;
      if (value == null) continue;
      if (value is BooleanResult) {
        answers[r.id] = value.name;
      } else if (value is TextChoice) {
        answers[r.id] = value.value ?? value.text;
      } else if (value is List<TextChoice>) {
        answers[r.id] =
            value.map((c) => c.value ?? c.text).toList(growable: false);
      } else {
        answers[r.id] = value.toString();
      }
    }

    // Автозаполнение: значения профиля занимают свои места ДО ручных
    // ответов (ручные не могут совпасть — шаги с таким id изъяты).
    answers.addAll(_prefilled);

    // Обратное обучение: если студент заполнил ФИО/группу руками,
    // запоминаем в профиль — следующая анкета не спросит их снова.
    await _learnProfileFields(answers);

    final ok = await ref.read(postsRepoProvider).submitFormResponse(
          formId: widget.form.id,
          postId: widget.postId,
          answers: answers,
          deviceId: _deviceId(),
        );

    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Не удалось отправить — попробуйте ещё раз')),
      );
      return;
    }
    setState(() => _submitted = true);
  }

  /// Ручные ответы ФИО/группа сохраняются в профиль (если там пусто).
  Future<void> _learnProfileFields(Map<String, dynamic> answers) async {
    final profile = ref.read(profileProvider);
    var updated = profile;

    for (final entry in answers.entries) {
      final id = entry.key.toLowerCase().trim();
      final value = entry.value;
      if (value is! String || value.trim().isEmpty) continue;

      if (_kFioStepIds.contains(id) && profile.fullName == null) {
        updated = updated.copyWith(fullName: value.trim());
      } else if (_kGroupStepIds.contains(id) && profile.group == null) {
        updated = updated.copyWith(group: value.trim());
      }
    }

    if (updated != profile) {
      await ref.read(profileProvider.notifier).save(updated);
    }
  }

  /// Устойчивый «кто отправил» без персональных данных: device_id из
  /// локального хранилища (тот же, что в метриках просмотров).
  String _deviceId() => ref.read(localStoreProvider).deviceId;

  @override
  Widget build(BuildContext context) {
    final form = widget.form;

    // Отправлено: простой экран подтверждения вместо чьей-либо анкеты.
    // Повторная отправка не нужна — иначе админ увидит дубли.
    if (_submitted) {
      return Scaffold(
        appBar: AppBar(
          title: Text(form.title),
          titleTextStyle: AppText.headline,
          leading: _BackButton(),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text('Анкета отправлена', style: AppText.title),
                if ((form.successText ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    form.successText!,
                    textAlign: TextAlign.center,
                    style: AppText.footnote
                        .copyWith(color: AppColors.secondaryLight),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(form.title),
        titleTextStyle: AppText.headline,
        leading: _BackButton(),
      ),
      body: SurveyKit(
        task: Task.fromJson(_definitionFor()),
        onResult: _onResult,
        // Тёмная тема и фон страницы: survey_kit рисует собственный
        // MaterialApp-подобный контейнер, тема снаружи до него не доходит.
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        // Своя пустая шапка вместо встроенной: SurveyAppBar пакета
        // показывает «Cancel» и прогресс, а при завершении опроса падает
        // (баг: каст SurveyResultState в PresentingSurveyState). Наш AppBar
        // над ним уже даёт заголовок и «назад», дублировать нечего.
        appBar: _EmptyAppBar(),
      ),
    );
  }
}

/// Пустая шапка для SurveyKit: сам экран уже держит AppBar.
class _EmptyAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _EmptyAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(0);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Кнопка «назад»: обычная, а не стеклянная — фон у шапки не картинка.
class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        tooltip: 'Назад',
        onPressed: () => Navigator.of(context).maybePop(),
      );
}
