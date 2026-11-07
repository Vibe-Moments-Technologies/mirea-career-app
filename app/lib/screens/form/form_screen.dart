import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/markdown_body.dart';
import '../../data/catalogs.dart';
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

  /// Сервер ответил «Опрос завершён» на отправку: форма закрыта,
  /// показываем итог. Локальное состояние, потому что форма пришла
  /// в виджет иммутабельной — перечитывать её с сервера избыточно.
  bool _serverClosed = false;

  /// Определение с изъятыми автозаполняемыми шагами (готово к рендеру).
  ///
  /// Вычисляется один раз в build-кэше: definition иммутабелен,
  /// профиль в рамках экрана меняться не должен.
  Map<String, dynamic>? _strippedDefinition;
  Map<String, String> _prefilled = {};

  /// Подстановка для student-шага: значения профиля по ключам полей
  /// (fio/group/institute/department/course). Пустое значение — поле
  /// студент заполняет руками (контракт 6.5 справки).
  Map<String, String> _studentPrefill({bool isAnon = false}) {
    if (isAnon) return const {}; // анонимный опрос: профиль не подставляем
    final profile = ref.read(profileProvider);
    final instituteTitle = profile.institute == null
        ? ''
        : (Catalogs.instituteTitle(profile.institute) == 'Институт не указан'
            ? ''
            : Catalogs.instituteTitle(profile.institute));
    return {
      if (profile.fullName != null) 'fio': profile.fullName!,
      if (profile.group != null) 'group': profile.group!,
      if (instituteTitle.isNotEmpty) 'institute': instituteTitle,
      if (profile.department != null) 'department': profile.department!,
      if (profile.course != null) 'course': '${profile.course}',
    };
  }

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

    final result = await ref.read(postsRepoProvider).submitFormResponse(
          formId: form.id,
          postId: widget.postId,
          answers: answers,
          deviceId: _deviceId(),
        );

    if (!mounted) return;
    if (result == FormSubmitResult.duplicate) {
      // Хук «один ответ с устройства»: сервер отклонил повтор. Худший
      // вариант — молча показать «не удалось»: студент бы тыкал снова.
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Вы уже отвечали на эту анкету.')),
      );
      return;
    }
    if (result == FormSubmitResult.closed) {
      // Опрос закрыли (или срок вышел), пока студент заполнял форму:
      // сервер вернул 400 «Опрос завершён…». Перезапрашиваем форму —
      // экран покажет итог вместо формы.
      setState(() {
        _submitting = false;
        _serverClosed = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Опрос завершён — отвечать больше нельзя.')),
      );
      return;
    }
    if (result != FormSubmitResult.ok) {
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

    // Жизненный цикл опроса (контракт 6.4): закрыт вручную в консоли
    // или сервер отказал при отправке — вместо формы показываем итог
    // (result_text), ответы не принимаются. Просроченный (end_date
    // прошла) — то же: сервер всё равно вернёт 400.
    if (form.isClosed || _serverClosed || form.isExpired) {
      return _ClosedScreen(
        formTitle: form.title,
        resultText: form.resultText,
        expired: form.isExpired && !form.isClosed && !_serverClosed,
      );
    }

    // Уже заполнено раньше (файл истории на устройстве): блокируем
    // повтор — иначе админ увидит дубли ответов. Показываем снимок:
    // когда отправлено и что ответили.
    //
    // Блокируем ТОЛЬКО при one_response_per_device (флаг формы в БД):
    // повторные прохождения разрешены, если галочка снята в консоли.
    // Остаётся страховка сервера: хук вернёт 400 на дубль, если флаг
    // всё же стоит.
    final onceOnly = form.oneResponsePerDevice;
    final existing = _submitted ??
        (onceOnly &&
                widget.postId != null &&
                ref.watch(hasSubmittedProvider(widget.postId!))
            ? ref.read(formSubmissionsProvider.notifier).forPost(widget.postId!)
            : onceOnly && ref.watch(hasSubmittedFormProvider(form.id))
                ? ref.read(formSubmissionsProvider.notifier).forForm(form.id)
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
          kind: form.kind,
          oneResponsePerDevice: form.oneResponsePerDevice,
        ),
        onSubmit: _onSubmit,
        submitting: _submitting,
        responsesCount: _responsesCount,
        studentPrefill:
            _studentPrefill(isAnon: form.isAnonSurvey),
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

/// Экран завершённого опроса: итог вместо формы (контракт 6.4).
///
/// Два случая: закрыт вручную в консоли («Завершить и подвести итог» —
/// показываем result_text) и срок вышел (end_date прошла — итога может
/// не быть, показываем нейтральное «опрос завершён»). Ответы не
/// принимаются ни там, ни там: сервер вернёт 400.
class _ClosedScreen extends StatelessWidget {
  const _ClosedScreen({
    required this.formTitle,
    required this.resultText,
    this.expired = false,
  });

  final String formTitle;
  final String? resultText;
  final bool expired;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final result = (resultText ?? '').trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(formTitle),
        titleTextStyle: AppText.headline,
        leading: _BackButton(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                expired
                    ? Icons.event_busy_rounded
                    : Icons.flag_circle_rounded,
                size: 40,
                color: scheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            expired ? 'Срок опроса истёк' : 'Опрос завершён',
            textAlign: TextAlign.center,
            style: AppText.title,
          ),
          const SizedBox(height: 8),
          Text(
            expired
                ? 'Отвечать больше нельзя — ответы не принимаются.'
                : 'Приём ответов закрыт. Спасибо всем участникам!',
            textAlign: TextAlign.center,
            style:
                AppText.footnote.copyWith(color: AppColors.secondaryLight),
          ),
          if (result.isNotEmpty) ...[
            const SizedBox(height: 24),
            // Итог — текст автора в Markdown: тот же рендер, что у
            // описаний постов и заметок анкеты.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.separator(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.emoji_events_rounded,
                          size: 16, color: scheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Итоги опроса',
                        style: AppText.headline
                            .copyWith(color: scheme.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  MarkdownBody(text: result),
                ],
              ),
            ),
          ],
          const SizedBox(height: 28),
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
              child: const Text('Вернуться'),
            ),
          ),
        ],
      ),
    );
  }
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
