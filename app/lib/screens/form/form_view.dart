import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/markdown_body.dart';
import '../../data/models.dart';
import '../../state/providers.dart';

/// Рендер анкеты в стиле приложения.
///
/// survey_kit пробовали: поэтапный визард с нативными RadioListTile
/// не встроился в дизайн без борьбы с каждым виджетом (свои Scaffold,
/// свой MaterialApp, свой appbar, Lottie). Определение анкеты — наш JSON
/// в БД, поэтому рендерим сами: поля как в онбординге, выбор — плитками
/// как институты, галочки — как в фильтрах.
///
/// **Постраничный режим (контракт 6.5, шаг pagebreak):** разделитель
/// делит опросник на экраны — «заполнил один, нажал «Далее», открылся
/// следующий». Внутри страницы — скролл всех её вопросов. Анкета без
/// pagebreak — одна страница, как раньше. Кнопка на последней странице
/// — «Отправить анкету», на промежуточных — «Далее» (нажимается, когда
/// обязательные вопросы страницы заполнены).
///
/// Поддерживаемые типы вопросов (answerFormat.type, контракт 6.5 справки):
///  text      — поле (hint, maxLines 1|5);
///  single    — один из вариантов (textChoices), плитки или dropdown;
///  multiple  — несколько вариантов, чипы;
///  bool      — да/нет, две плитки;
///  scale     — числовая шкала (scaleMin..scaleMax), опц. style: stars;
///  date/time — выбор даты/времени системными пикерами;
///  integer   — числовое поле;
///  student   — блок полей профиля (fields: fio/group/institute/…),
///              подставляется [studentPrefill], ответ — объект;
///              подстановка считается ответом — не нужно «трогать» поле;
///  pagebreak — разделитель СТРАНИЦ (вопросы до/после — разные экраны);
///  note      — текст автора анкеты без поля ввода, Markdown, в answers
///              не попадает. Тоже без answerFormat (легаси-заметки).
class FormView extends ConsumerStatefulWidget {
  const FormView({
    super.key,
    required this.form,
    required this.onSubmit,
    this.submitting = false,
    this.responsesCount,
    this.studentPrefill = const {},
  });

  final FormDefinition form;

  /// Нажата кнопка «Отправить» (последняя страница). Валидация уже
  /// пройдена. Ошибка отправки (false от репозитория) сбрасывается
  /// в UI снэкбаром — состояние ответов при этом сохраняется.
  final void Function(Map<String, dynamic> answers) onSubmit;

  final bool submitting;

  /// Сколько студентов уже заполнили анкету — подпись ПОД кнопкой
  /// отправки. null = неизвестно (офлайн): подпись скрыта.
  final int? responsesCount;

  /// Значения полей профиля для шагов student: {'fio': '…', …}.
  /// Пустое = профиль пуст, поля вводятся руками.
  final Map<String, String> studentPrefill;

  @override
  ConsumerState<FormView> createState() => _FormViewState();
}

class _FormViewState extends ConsumerState<FormView> {
  final Map<String, dynamic> _answers = {};

  /// Номер текущей страницы (pagebreak делит шаги на экраны).
  int _page = 0;

  // ---------- Шаги ----------

  List<Map<String, dynamic>> get _steps {
    final raw = widget.form.definition['steps'];
    if (raw is! List) return const [];
    return [
      for (final s in raw)
        if (s is Map) Map<String, dynamic>.from(s),
    ];
  }

  Map<String, dynamic>? _answerFormat(Map<String, dynamic> step) {
    final af = step['answerFormat'];
    return af is Map ? Map<String, dynamic>.from(af) : null;
  }

  String _label(Map<String, dynamic> step) {
    final content = step['content'];
    if (content is! List) return '';
    final b = content
        .whereType<Map>()
        .map((c) => c['text'])
        .whereType<String>()
        .firstOrNull;
    return b ?? '';
  }

  bool _isMandatory(Map<String, dynamic> step) =>
      step['isMandatory'] == true;

  /// Вопрос ли шаг (в answers попадает) или декорация.
  bool _isQuestion(Map<String, dynamic> step) {
    final type = _answerFormat(step)?['type'] as String?;
    return switch (type) {
      'pagebreak' => false,
      'note' => false,
      null => false, // текст без answerFormat — заметка
      _ => true,
    };
  }

  // ---------- Страницы (pagebreak) ----------

  /// Шаги, разбитые pagebreak'ами на страницы. Анкета без разделителей —
  /// одна страница из всех шагов. Заголовки pagebreak'а не теряем:
  /// pagebreak с текстом («Этап 2: о себе») — заголовок новой страницы.
  List<List<Map<String, dynamic>>> get _pages {
    final pages = <List<Map<String, dynamic>>>[<Map<String, dynamic>>[]];
    for (final step in _steps) {
      if ((_answerFormat(step)?['type'] as String?) == 'pagebreak') {
        pages.add(<Map<String, dynamic>>[]);
        continue;
      }
      pages.last.add(step);
    }
    // Пустые хвосты не оставляем: подряд идущие pagebreak'ы.
    return pages.where((p) => p.isNotEmpty).toList();
  }

  List<Map<String, dynamic>> get _pageSteps =>
      _pages.isEmpty ? const [] : _pages[_page.clamp(0, _pages.length - 1)];

  bool get _isLastPage => _page >= _pages.length - 1;

  // ---------- Валидация ----------

  /// Ответ на шаг: String (text/single/bool/date/time), num (scale),
  /// List (multiple) или Map (student).
  dynamic _answerOf(String id) => _answers[id];

  bool _stepFilled(Map<String, dynamic> step) {
    if (!_isQuestion(step)) return true;
    if (!_isMandatory(step)) return true;
    final v = _answers[step['id']];
    if (v is String) return v.trim().isNotEmpty;
    if (v is List) return v.isNotEmpty;
    if (v is Map) return v.values.any((e) => '$e'.trim().isNotEmpty);
    if (v is num) return true; // выбранное значение шкалы
    return false;
  }

  /// Student-шаг обязателен ЦЕЛИКОМ (контракт 6.5: у student всегда
  /// isMandatory), но заполняется постепенно: считаем заполненным, когда
  /// хотя бы одно поле введено — окончательную полноту проверит кнопка.
  bool _studentStepsComplete(List<Map<String, dynamic>> steps) {
    for (final step in steps) {
      if ((_answerFormat(step)?['type'] as String?) != 'student') continue;
      final v = _answers[step['id']];
      if (v is! Map) return false;
      // Обязательное поле student: хотя бы одно значение есть —
      // дальше студент дозаполнит перед отправкой (кнопка активна).
      if (v.values.every((e) => '$e'.trim().isEmpty)) return false;
    }
    return true;
  }

  /// Текущая страница заполнена достаточно для перехода дальше.
  bool get _pageFilled =>
      _pageSteps.every(_stepFilled) && _studentStepsComplete(_pageSteps);

  /// Анкета целиком (последняя страница) — можно отправлять.
  bool get _allFilled =>
      _steps.every(_stepFilled) && _studentStepsComplete(_steps);

  void _submit() {
    if (!_allFilled || widget.submitting) return;
    HapticFeedback.mediumImpact();

    // Не-вопросы (pagebreak/note) в answers не попадают.
    final payload = <String, dynamic>{};
    for (final step in _steps) {
      if (!_isQuestion(step)) continue;
      final id = step['id'] as String?;
      if (id == null) continue;
      final v = _answers[id];
      if (v != null) payload[id] = v;
    }
    widget.onSubmit(payload);
  }

  void _setAnswer(String id, dynamic value) =>
      setState(() => _answers[id] = value);

  // ---------- Сборка ----------

  @override
  void initState() {
    super.initState();
    // Подстановка профиля в student-шаги — СРАЗУ в ответы (баг dev.77:
    // поле выглядело заполненным, но ответ был пуст, пока не «трогал»
    // поле руками). Значения профиля — честный ответ.
    for (final step in _steps) {
      if ((_answerFormat(step)?['type'] as String?) != 'student') continue;
      final fields = (_answerFormat(step)?['fields'] as List?)
              ?.whereType<String>()
              .toList() ??
          const <String>[];
      final id = step['id'] as String?;
      if (id == null) continue;
      final pre = <String, dynamic>{};
      for (final f in fields) {
        final v = widget.studentPrefill[f];
        if (v != null && v.trim().isNotEmpty) pre[f] = v;
      }
      if (pre.isNotEmpty) _answers[id] = pre;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    return Column(
      children: [
        Expanded(
          child: _pageSteps.isEmpty
              ? Center(
                  child: Text(
                    'Анкета пуста',
                    style: AppText.footnote
                        .copyWith(color: AppColors.secondaryLight),
                  ),
                )
              : ListView(
                  key: ValueKey('form-page-$_page'),
                  padding: EdgeInsets.fromLTRB(pad, 18, pad, 24),
                  children: [
                    for (var i = 0; i < _pageSteps.length; i++) ...[
                      _Question(
                        index: _numbering(i),
                        step: _pageSteps[i],
                        label: _label(_pageSteps[i]),
                        answerFormat: _answerFormat(_pageSteps[i]),
                        value: _answerOf(_pageSteps[i]['id'] as String? ?? ''),
                        prefill: widget.studentPrefill,
                        // Институты для student-поля «institute»: выбор из
                        // коллекции institutes, а не свободный текст.
                        institutes: _instituteTitles,
                        onChanged: _setAnswer,
                      ),
                      const SizedBox(height: 18),
                    ],
                  ],
                ),
        ),
        // Кнопка — закреплена внизу: на промежуточных страницах «Далее»,
        // на последней — «Отправить анкету». Под ней — сколько студентов
        // уже прошли анкету: подпись относится к отправке.
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, 8, pad, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_pages.length > 1) ...[
                  // Прогресс точками: сколько страниц позади.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _pages.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _page ? 16 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _page
                                ? Theme.of(context).colorScheme.primary
                                : AppColors.separator(context),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: (_isLastPage
                            ? _allFilled
                            : _pageFilled) && !widget.submitting
                        ? (_isLastPage ? _submit : _nextPage)
                        : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                    child: widget.submitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child:
                                CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : Text(_isLastPage ? 'Отправить анкету' : 'Далее'),
                  ),
                ),
                if (widget.responsesCount != null && _isLastPage) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.how_to_reg_rounded,
                          size: 13, color: AppColors.secondaryLight),
                      const SizedBox(width: 4),
                      Text(
                        'Уже прошли: ${widget.responsesCount}',
                        style: AppText.caption
                            .copyWith(color: AppColors.secondaryLight),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _nextPage() {
    if (!_pageFilled) return;
    HapticFeedback.selectionClick();
    setState(() => _page++);
  }

  /// Институты из справочника БД (коллекция institutes, запас офлайн).
  /// Загружаются лениво: нужны только для student-поля «institute».
  List<String> get _instituteTitles {
    final list =
        ref.watch(onboardingCatalogProvider).value?.institutes ?? const <InstituteRef>[];
    return [for (final i in list) i.title];
  }

  /// Номер вопроса на странице: сквозная нумерация по анкете — вопросы
  /// на 2-й странице не начинаются с «1.» заново (контекст не теряется).
  int _numbering(int indexOnPage) {
    var n = 0;
    for (var p = 0; p < _pages.length; p++) {
      for (final s in _pages[p]) {
        if (_isQuestion(s)) n++;
        if (p == _page && identical(s, _pageSteps[indexOnPage])) return n - 1;
      }
    }
    return indexOnPage; // fallback (не должно случиться)
  }
}

/// Один вопрос анкеты: подпись + поле соответствующего типа.
class _Question extends StatelessWidget {
  const _Question({
    required this.index,
    required this.step,
    required this.label,
    required this.answerFormat,
    required this.value,
    required this.onChanged,
    this.prefill = const {},
    this.institutes = const [],
  });

  final int index;
  final Map<String, dynamic> step;
  final String label;
  final Map<String, dynamic>? answerFormat;
  final dynamic value;
  final void Function(String id, dynamic value) onChanged;

  /// Профильные значения для student-шага.
  final Map<String, String> prefill;

  /// Названия институтов из справочника БД: для student-поля
  /// «institute» — выпадающий список вместо свободного текста.
  final List<String> institutes;

  String get id => step['id'] as String? ?? 'q$index';
  bool get mandatory => step['isMandatory'] == true;

  /// Подпись-вопрос мелким шрифтом под текстом (поле description шага).
  String get description => (step['description'] as String?) ?? '';

  @override
  Widget build(BuildContext context) {
    // Шаг БЕЗ answerFormat — заметка (легаси): текст без поля ввода,
    // как note. Баг dev.77: дефолт 'text' рисовал под ней поле ввода.
    final type = answerFormat?['type'] as String? ?? 'note';

    // pagebreak: разделитель секций — линия с отступами, не вопрос.
    if (type == 'pagebreak') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Divider(height: 1, color: AppColors.separator(context)),
      );
    }

    // note / шаг без answerFormat: текст автора анкеты без поля ввода.
    // Форматируется в Markdown — тот же рендер, что у описаний постов.
    if (type == 'note') {
      return MarkdownBody(
        text: label.isNotEmpty ? label : description,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Подпись вопроса: номер + текст + звёздочка обязательности.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${index + 1}. ',
              style: AppText.headline
                  .copyWith(color: Theme.of(context).colorScheme.primary),
            ),
            Expanded(
              child: Text(
                label.isEmpty ? 'Вопрос' : label,
                style: AppText.headline,
              ),
            ),
            if (mandatory)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  '*',
                  style: AppText.headline
                      .copyWith(color: AppColors.warning, fontSize: 18),
                ),
              ),
          ],
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            description,
            style: AppText.footnote.copyWith(
              color: AppColors.secondaryLight,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 10),
        _buildAnswer(context, type),
      ],
    );
  }

  Widget _buildAnswer(BuildContext context, String type) {
    switch (type) {
      case 'single':
        // dropdown — тот же выбор, компактный вид (контракт 6.5).
        if ((answerFormat?['style'] as String?) == 'dropdown') {
          return _buildDropdown(context);
        }
        return _buildSingle(context);
      case 'multiple':
        return _buildMultiple(context);
      case 'bool':
        return _buildBool(context);
      case 'scale':
        return _buildScale(context);
      case 'date':
        return _buildDate(context);
      case 'time':
        return _buildTime(context);
      case 'integer':
        return _buildInteger(context);
      case 'student':
        return _buildStudent(context);
      default:
        return _buildText(context);
    }
  }

  // ---------- Текстовое поле ----------

  Widget _buildText(BuildContext context) {
    final maxLines =
        ((answerFormat?['maxLines'] as num?)?.toInt() ?? 1);
    final hint = (answerFormat?['hint'] as String?) ?? '';
    // Группы и ФИО вводят с заглавной: автоматически через клавиатуру,
    // а не пост-обработкой — студент видит ожидаемый регистр на лету.
    final capitalize = hint.toLowerCase().contains('фио') ||
        hint.toLowerCase().contains('имя') ||
        (id.toLowerCase().contains('fio') ||
            id.toLowerCase().contains('name'));

    return _TextAnswerField(
      key: ValueKey('tf-$index-$id'),
      initial: value as String? ?? '',
      maxLines: maxLines,
      hint: hint,
      capitalize: capitalize,
      // maxLength из answerFormat обрезает ввод (контракт 6.5).
      maxLength: (answerFormat?['maxLength'] as num?)?.toInt(),
      onChanged: (v) => onChanged(id, v),
    );
  }

  // ---------- Числовое поле ----------

  Widget _buildInteger(BuildContext context) {
    return _TextAnswerField(
      key: ValueKey('int-$index-$id'),
      initial: value == null ? '' : '$value',
      maxLines: 1,
      hint: (answerFormat?['hint'] as String?) ?? '0',
      digitsOnly: true,
      // minValue/maxValue: ввод вне границ не проходит в ответ.
      minValue: (answerFormat?['minValue'] as num?),
      maxValue: (answerFormat?['maxValue'] as num?),
      onChanged: (v) => onChanged(id, v),
    );
  }

  // ---------- Один из вариантов: плитки, как институты в онбординге ----------

  Widget _buildSingle(BuildContext context) {
    final choices =
        (answerFormat?['textChoices'] as List?)?.whereType<Map>().toList() ??
            const [];
    final selected = value as String?;

    return Column(
      children: [
        for (final c in choices)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ChoiceTile(
              title: c['text'] as String? ?? '',
              selected:
                  selected == ((c['value'] ?? c['text']) as String? ?? ''),
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(id, (c['value'] ?? c['text']) as String? ?? '');
              },
            ),
          ),
      ],
    );
  }

  // ---------- single + style: dropdown ----------

  Widget _buildDropdown(BuildContext context) {
    final choices =
        (answerFormat?['textChoices'] as List?)?.whereType<Map>().toList() ??
            const [];
    final selected = value as String?;

    final items = [
      for (final c in choices)
        DropdownMenuItem<String>(
          value: (c['value'] ?? c['text']) as String? ?? '',
          child: Text(c['text'] as String? ?? ''),
        ),
    ];

    return DropdownButtonFormField<String>(
      initialValue: items.any((i) => i.value == selected) ? selected : null,
      items: items,
      onChanged: (v) {
        HapticFeedback.selectionClick();
        onChanged(id, v ?? '');
      },
      decoration: InputDecoration(
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
      ),
    );
  }

  // ---------- Несколько: чипы, как интересы ----------

  Widget _buildMultiple(BuildContext context) {
    final choices =
        (answerFormat?['textChoices'] as List?)?.whereType<Map>().toList() ??
            const [];
    final selected = (value as List?)?.cast<String>().toSet() ?? <String>{};

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in choices)
          _choiceChip(
            context,
            c['text'] as String? ?? '',
            (c['value'] ?? c['text']) as String? ?? '',
            selected,
          ),
      ],
    );
  }

  Widget _choiceChip(
      BuildContext context, String title, String val, Set<String> selected) {
    final accent = Theme.of(context).colorScheme.primary;
    final isOn = selected.contains(val);

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        final next = {...selected};
        isOn ? next.remove(val) : next.add(val);
        onChanged(id, next.toList(growable: false));
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          // Выбранный чип НЕ заливается цветом текста: акцентная подложка
          // + белый текст читаются в обеих темах, а «сливание» выбранного
          // варианта (жалоба с устройства) исключено контрастом.
          color: isOn ? accent : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: isOn ? accent : AppColors.separator(context),
            width: isOn ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOn) ...[
              const Icon(Icons.check_rounded,
                  size: 15, color: Colors.white),
              const SizedBox(width: 5),
            ],
            Text(
              title,
              style: AppText.footnote.copyWith(
                color: isOn ? Colors.white : null,
                fontWeight: isOn ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Да/нет: две крупные плитки ----------

  Widget _buildBool(BuildContext context) {
    final pos = (answerFormat?['positiveAnswer'] as String?) ?? 'Да';
    final neg = (answerFormat?['negativeAnswer'] as String?) ?? 'Нет';
    final selected = value as String?;

    return Row(
      children: [
        Expanded(
          child: _ChoiceTile(
            title: pos,
            center: true,
            selected: selected == 'true',
            onTap: () => onChanged(id, 'true'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ChoiceTile(
            title: neg,
            center: true,
            selected: selected == 'false',
            onTap: () => onChanged(id, 'false'),
          ),
        ),
      ],
    );
  }

  // ---------- Шкала: числа или звёзды ----------

  Widget _buildScale(BuildContext context) {
    final min = ((answerFormat?['scaleMin'] as num?)?.toInt() ?? 1);
    final max = ((answerFormat?['scaleMax'] as num?)?.toInt() ?? 5);
    final stars = (answerFormat?['style'] as String?) == 'stars';
    final selected = (value as num?)?.toInt() ?? 0;
    final accent = Theme.of(context).colorScheme.primary;

    final values = [for (var v = min; v <= max; v++) v];

    if (stars) {
      return Row(
        children: [
          for (final v in values)
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(id, v);
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  v <= selected
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: 34,
                  color: v <= selected ? accent : AppColors.secondaryLight,
                ),
              ),
            ),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in values)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(id, v);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: selected == v
                    ? accent
                    : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: selected == v
                      ? accent
                      : AppColors.separator(context),
                  width: selected == v ? 1.6 : 1,
                ),
              ),
              child: Text(
                '$v',
                style: AppText.footnote.copyWith(
                  color: selected == v ? Colors.white : null,
                  fontWeight:
                      selected == v ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ---------- Дата и время: системные пикеры ----------

  Widget _buildDate(BuildContext context) {
    final text = value as String? ?? '';
    return _PickerField(
      icon: Icons.event_rounded,
      text: text.isEmpty ? 'Выберите дату' : text,
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: now,
          firstDate: DateTime(now.year - 1),
          lastDate: DateTime(now.year + 3),
          locale: const Locale('ru'),
        );
        if (picked != null) {
          onChanged(
              id,
              '${_twoDigits(picked.day)}.${_twoDigits(picked.month)}'
              '.${picked.year}');
        }
      },
    );
  }

  Widget _buildTime(BuildContext context) {
    final text = value as String? ?? '';
    return _PickerField(
      icon: Icons.schedule_rounded,
      text: text.isEmpty ? 'Выберите время' : text,
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.now(),
        );
        if (picked != null) {
          onChanged(id, '${_twoDigits(picked.hour)}:${_twoDigits(picked.minute)}');
        }
      },
    );
  }

  static String _twoDigits(int n) => n < 10 ? '0$n' : '$n';

  // ---------- Student: поля профиля ----------

  static const _studentLabels = <String, String>{
    'fio': 'ФИО',
    'group': 'Группа',
    'institute': 'Институт',
    'department': 'Кафедра',
    'course': 'Курс',
  };

  Widget _buildStudent(BuildContext context) {
    final fields = (answerFormat?['fields'] as List?)
            ?.whereType<String>()
            .toList() ??
        const <String>[];
    final answers = (value as Map?)?.cast<String, dynamic>() ?? {};

    return Column(
      children: [
        for (var i = 0; i < fields.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _studentField(context, fields[i], answers),
        ],
      ],
    );
  }

  /// Рекомендованные лимиты student-полей (контракт 6.6 справки):
  /// ФИО ≤ 100, группа ≤ 10 (ХХХХ-00-00), кафедра ≤ 30. Курс/семестр:
  /// поле одно на оба — верхняя граница 12 покрывает семестр.
  static const _studentLimits = <String, int>{
    'fio': 100,
    'group': 10,
    'department': 30,
  };
  static const _courseMin = 1, _courseMax = 12;

  Widget _studentField(
      BuildContext context, String field, Map<String, dynamic> answers) {
    final label = _studentLabels[field] ?? field;
    final current = '${answers[field] ?? prefill[field] ?? ''}';

    // Институт — ВЫБОР из коллекции institutes (не текст): опечатки и
    // «ИТ»/«Институт информационных технологий» в ответах убивают
    // аналитику. Список пуст (офлайн-холодный старт) — поле текстом.
    if (field == 'institute' && institutes.isNotEmpty) {
      final items = [
        for (final t in institutes)
          DropdownMenuItem<String>(value: t, child: Text(t)),
      ];
      return DropdownButtonFormField<String>(
        initialValue: items.any((i) => i.value == current) ? current : null,
        items: items,
        decoration: _fieldDecoration(context, label),
        onChanged: (v) {
          if (v == null) return;
          final next = Map<String, dynamic>.from(answers);
          next[field] = v;
          onChanged(id, next);
        },
      );
    }

    return _TextAnswerField(
      key: ValueKey('student-$index-$field'),
      initial: current,
      maxLines: 1,
      hint: label,
      capitalize: field == 'fio' || field == 'institute',
      digitsOnly: field == 'course',
      maxLength: _studentLimits[field],
      minValue: field == 'course' ? _courseMin : null,
      maxValue: field == 'course' ? _courseMax : null,
      onChanged: (v) {
        // Ответ шага — объект по ключам полей (контракт 6.5).
        final next = Map<String, dynamic>.from(answers);
        next[field] = v;
        onChanged(id, next);
      },
    );
  }

  /// Единая рамка полей: outline + скругление как у всех полей анкеты.
  InputDecoration _fieldDecoration(BuildContext context, String label) =>
      InputDecoration(
        hintText: label,
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
}

/// Текстовое/числовое поле ответа со СТАБИЛЬНЫМ контроллером.
///
/// Раньше TextEditingController создавался в build на каждый rebuild:
/// при двух вопросах с одинаковым id (как в тестовой анкете: «текст» и
/// «текст») ответ общий, и каждый rebuild пересоздавал контроллеры —
/// ввод в одном поле «печатался» и во втором. Теперь контроллер живёт
/// в State и синхронизируется извне только при РЕАЛЬНОМ изменении
/// (подстановка из профиля), не затирая каретку при вводе.
class _TextAnswerField extends StatefulWidget {
  const _TextAnswerField({
    super.key,
    required this.initial,
    required this.maxLines,
    required this.hint,
    required this.onChanged,
    this.capitalize = false,
    this.digitsOnly = false,
    this.maxLength,
    this.minValue,
    this.maxValue,
  });

  final String initial;
  final int maxLines;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool capitalize;
  final bool digitsOnly;

  /// Лимит длины (контракт 6.5): обрезает ввод на уровне TextField —
  /// длиннее физически не ввести.
  final int? maxLength;

  /// Границы для числовых полей: ввод за пределами НЕ проходит в
  /// ответ (введённое значение отвергается, как незаполненное).
  final num? minValue;
  final num? maxValue;

  @override
  State<_TextAnswerField> createState() => _TextAnswerFieldState();
}

class _TextAnswerFieldState extends State<_TextAnswerField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void didUpdateWidget(_TextAnswerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Внешнее значение изменилось (не наш ввод) — подтягиваем: это
    // подстановка профиля или смена варианта. Свой ввод не затираем.
    if (widget.initial != oldWidget.initial &&
        widget.initial != _controller.text) {
      _controller.text = widget.initial;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      maxLines: widget.maxLines,
      minLines: 1,
      // Клавиатура по содержимому: обычные поля — текст (ФИО, группа,
      // ответ), числовая — только числовым полям. Баг dev.77: все
      // однострочные открывали числовую.
      keyboardType: widget.digitsOnly
          ? TextInputType.number
          : (widget.maxLines > 1
              ? TextInputType.multiline
              : TextInputType.text),
      inputFormatters: widget.digitsOnly
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      textCapitalization: widget.capitalize
          ? TextCapitalization.words
          : TextCapitalization.none,
      maxLength: widget.maxLength,
      onChanged: (v) {
        // Числовые границы: значение вне [min, max] — не ответ, поле
        // считается незаполненным (кнопка «Далее» заблокирует переход).
        if (widget.digitsOnly && v.isNotEmpty) {
          final n = num.tryParse(v);
          if (widget.minValue != null && n != null && n < widget.minValue!) {
            return;
          }
          if (widget.maxValue != null && n != null && n > widget.maxValue!) {
            return;
          }
        }
        widget.onChanged(v);
      },
      decoration: InputDecoration(
        hintText: widget.hint,
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
      ),
    );
  }
}

/// Поле-кнопка для date/time: открывает системный пикер.
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        side: BorderSide(color: AppColors.separator(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: AppText.body)),
              const Icon(Icons.expand_more_rounded,
                  size: 20, color: AppColors.secondaryLight),
            ],
          ),
        ),
      ),
    );
  }
}

/// Плитка выбора: рамка + заливка при выборе, как в онбординге.
///
/// Выбранная плитка: акцентная рамка, лёгкая заливка акцентом, галочка.
/// Текст НЕ перекрашивается в акцент — контраст сохраняется в обеих темах.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.center = false,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(
          color: selected ? accent : AppColors.separator(context),
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          color: selected ? accent.withValues(alpha: 0.08) : Colors.transparent,
          child: Row(
            mainAxisAlignment: center
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: AppText.body.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (selected && !center) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_rounded, size: 18, color: accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
