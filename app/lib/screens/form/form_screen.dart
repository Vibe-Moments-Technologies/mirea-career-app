import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/form_history.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import 'form_view.dart';

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
/// Определение приходит из PocketBase (expand.form) в JSON — шаги,
/// подписи, типы ответов. Рендер — [FormView] в стиле приложения.
/// Ответы уходят в form_responses (анонимно: create открыт, read закрыт).
///
/// **Автозаполнение из профиля:** шаги с id ФИО/группы, для которых в
/// локальном профиле уже есть значение, ИЗЫМАЮТСЯ из анкеты (студент
/// не вводит одно и то же дважды), а сами значения подставляются
/// в ответы при отправке. Если в профиле пусто — шаг остаётся, студент
/// заполняет его руками, и после отправки поле запоминается в профиле.
///
/// Приоритет над внешней ссылкой: если у поста есть форма,
/// кнопка в деталях открывает её, а не браузер.
class FormScreen extends ConsumerStatefulWidget {
  const FormScreen({
    super.key,
    required this.form,
    this.postId,
    this.postTitle,
  });

  final FormDefinition form;
  final String? postId;

  /// Заголовок поста — для снимка в истории анкет.
  final String? postTitle;

  @override
  ConsumerState<FormScreen> createState() => _FormScreenState();
}

class _FormScreenState extends ConsumerState<FormScreen> {
  bool _submitting = false;

  /// Определение с изъятыми автозаполняемыми шагами (готово к рендеру).
  ///
  /// Вычисляется один раз в build-кэше: definition иммутабелен,
  /// профиль в рамках экрана меняться не должен.
  Map<String, dynamic>? _strippedDefinition;
  Map<String, String> _prefilled = {};

  /// Сколько студентов уже заполнили анкету (хук PocketBase).
  int? _responsesCount;

  @override
  void initState() {
    super.initState();
    _loadResponsesCount();
  }

  Future<void> _loadResponsesCount() async {
    final n = await ref.read(postsRepoProvider)
        .fetchFormResponsesCount(widget.form.id);
    if (!mounted) return;
    setState(() => _responsesCount = n);
  }

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

    definition['steps'] = kept;
    _prefilled = prefilled;
    _strippedDefinition = definition;
    return definition;
  }

  Future<void> _onSubmit(Map<String, dynamic> answers) async {
    setState(() => _submitting = true);

    // Автозаполнение: значения профиля занимают свои места ДО ручных
    // ответов (ручные не могут совпасть — шаги с таким id изъяты).
    answers.addAll(_prefilled);

    // Обратное обучение: если студент заполнил ФИО/группу руками,
    // запоминаем в профиль — следующая анкета не спросит их снова.
    await _learnProfileFields(answers);

    final form = FormDefinition(
      id: widget.form.id,
      title: widget.form.title,
      definition: widget.form.definition,
      successText: widget.form.successText,
    );

    final ok = await ref.read(postsRepoProvider).submitFormResponse(
          formId: form.id,
          postId: widget.postId,
          answers: answers,
          deviceId: _deviceId(),
        );

    if (!mounted) return;
    if (!ok) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Не удалось отправить — попробуйте ещё раз')),
      );
      return;
    }

    // История на устройстве: «Мои анкеты», метка «заполнено» на карточке
    // и блокировка повторного заполнения. Пишем снимок (заголовки поста
    // и анкеты, ВОПРОСЫ и ответы) — пост может уйти в архив или
    // удалиться на сервере, а карточка истории должна остаться
    // осмысленной и читаемой человеком.
    final submission = FormSubmission(
      formId: form.id,
      postId: widget.postId ?? '',
      postTitle: widget.postTitle ?? '',
      formTitle: form.title,
      submittedAt: DateTime.now(),
      answers: Map<String, dynamic>.from(answers),
      successText: form.successText,
      questions: [
        for (final step in form.stepMaps)
          (step['id'] as String? ?? '', FormDefinition.stepQuestion(step)),
      ],
    );
    await ref.read(formSubmissionsProvider.notifier).add(submission);

    // Счётчик прошедших +1: локально, чтобы не ждать перезагрузки.
    if (!mounted) return;
    setState(() {
      _responsesCount = (_responsesCount ?? 0) + 1;
      _submitted = submission;
    });
  }

  FormSubmission? _submitted;

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

    // Уже заполнено раньше (файл истории на устройстве): блокируем
    // повтор — иначе админ увидит дубли ответов. Показываем снимок:
    // когда отправлено и что ответили.
    final existing = _submitted ??
        (widget.postId != null && ref.watch(hasSubmittedProvider(widget.postId!))
            ? ref.read(formSubmissionsProvider.notifier).forPost(widget.postId!)
            : null);

    if (existing != null) {
      return _DoneScreen(
        formTitle: form.title,
        submission: existing,
        responsesCount: _responsesCount,
      );
    }

    final definition = _definitionFor();

    return Scaffold(
      appBar: AppBar(
        title: Text(form.title),
        titleTextStyle: AppText.headline,
        leading: _BackButton(),
      ),
      body: FormView(
        form: FormDefinition(
          id: form.id,
          title: form.title,
          definition: definition,
          successText: form.successText,
        ),
        onSubmit: _onSubmit,
        submitting: _submitting,
        responsesCount: _responsesCount,
      ),
    );
  }
}

/// Экран «отправлено»: подтверждение сразу после анкеты и блокировка
/// повторного входа. Один и тот же для обоих случаев — меньше кода,
/// одинаковый вид.
///
/// Кнопка «Вернуться к карточке» обязательна: раньше экран заканчивался
/// текстом, и выйти можно было только системным «назад».
class _DoneScreen extends StatelessWidget {
  const _DoneScreen({
    required this.formTitle,
    required this.submission,
    required this.responsesCount,
  });

  final String formTitle;
  final FormSubmission submission;
  final int? responsesCount;

  @override
  Widget build(BuildContext context) {
    final date = _formatDate(submission.submittedAt);

    return Scaffold(
      appBar: AppBar(
        title: Text(formTitle),
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
              const SizedBox(height: 8),
              Text(
                '$date · повторное заполнение недоступно',
                textAlign: TextAlign.center,
                style:
                    AppText.footnote.copyWith(color: AppColors.secondaryLight),
              ),
              if (responsesCount != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Всего прошло: $responsesCount',
                  style: AppText.footnote
                      .copyWith(color: AppColors.secondaryLight),
                ),
              ],
              if ((submission.successText ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  submission.successText!,
                  textAlign: TextAlign.center,
                  style: AppText.footnote
                      .copyWith(color: AppColors.secondaryLight),
                ),
              ],
              const SizedBox(height: 28),
              // Явный выход к карточке: не заставляем искать системную
              // кнопку «назад» и не оставляем «висеть» на экране.
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                  child: const Text('Вернуться к карточке'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.'
      '${dt.month.toString().padLeft(2, '0')}.'
      '${dt.year}';
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
