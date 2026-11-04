import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/markdown_body.dart';
import '../../data/models.dart';

/// Рендер анкеты в стиле приложения: одна страница со всеми вопросами.
///
/// survey_kit пробовали: поэтапный визард с нативными RadioListTile
/// не встроился в дизайн без борьбы с каждым виджетом (свои Scaffold,
/// свой MaterialApp, свой appbar, Lottie). Определение анкеты — наш JSON
/// в БД, поэтому рендерим сами: поля как в онбординге, выбор — плитками
/// как институты, галочки — как в фильтрах. Всё в одном экране со скроллом:
/// студент видит объём анкеты сразу, а не тыкает «Далее» десять раз.
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
///  pagebreak — разделитель секций (линия + отступ, не вопрос);
///  note      — текст без ввода (info), в answers не попадает.
class FormView extends StatefulWidget {
  const FormView({
    super.key,
    required this.form,
    required this.onSubmit,
    this.submitting = false,
    this.responsesCount,
    this.studentPrefill = const {},
  });

  final FormDefinition form;

  /// Нажата кнопка «Отправить». Валидация уже пройдена.
  /// Ошибка отправки (false от репозитория) сбрасывается в UI
  /// снэкбаром — состояние ответов при этом сохраняется.
  final void Function(Map<String, dynamic> answers) onSubmit;

  final bool submitting;

  /// Сколько студентов уже заполнили анкету — подпись ПОД кнопкой
  /// отправки. null = неизвестно (офлайн): подпись скрыта.
  final int? responsesCount;

  /// Значения полей профиля для шагов student: {'fio': '…', …}.
  /// Пустое = профиль пуст, поля вводятся руками.
  final Map<String, String> studentPrefill;

  @override
  State<FormView> createState() => _FormViewState();
}

class _FormViewState extends State<FormView> {
  final Map<String, dynamic> _answers = {};

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
  bool get _allFilled =>
      _steps.every(_stepFilled) && _studentStepsComplete();

  bool _studentStepsComplete() {
    for (final step in _steps) {
      if ((_answerFormat(step)?['type'] as String?) != 'student') continue;
      final v = _answers[step['id']];
      if (v is! Map) return false;
      // Обязательное поле student: хотя бы одно значение есть —
      // дальше студент дозаполнит перед отправкой (кнопка активна).
      if (v.values.every((e) => '$e'.trim().isEmpty)) return false;
    }
    return true;
  }

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

  // ---------- Сборка ----------

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    return Column(
      children: [
        Expanded(
          child: steps.isEmpty
              ? Center(
                  child: Text(
                    'Анкета пуста',
                    style: AppText.footnote
                        .copyWith(color: AppColors.secondaryLight),
                  ),
                )
              : ListView(
                  padding: EdgeInsets.fromLTRB(pad, 18, pad, 24),
                  children: [
                    for (var i = 0; i < steps.length; i++) ...[
                      _Question(
                        index: i,
                        step: steps[i],
                        label: _label(steps[i]),
                        answerFormat: _answerFormat(steps[i]),
                        value: _answerOf(steps[i]['id'] as String? ?? ''),
                        prefill: widget.studentPrefill,
                        onChanged: _setAnswer,
                      ),
                      const SizedBox(height: 18),
                    ],
                  ],
                ),
        ),
        // Кнопка отправки — закреплена внизу: всегда на виду, но не
        // перекрывает контент (в отличие от floatingActionButton).
        // Под ней — сколько студентов уже прошли анкету: подпись
        // относится к действию «отправить», поэтому стоит у кнопки,
        // а не в шапке.
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, 8, pad, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed:
                        _allFilled && !widget.submitting ? _submit : null,
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
                        : const Text('Отправить анкету'),
                  ),
                ),
                if (widget.responsesCount != null) ...[
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

  void _setAnswer(String id, dynamic value) =>
      setState(() => _answers[id] = value);
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
  });

  final int index;
  final Map<String, dynamic> step;
  final String label;
  final Map<String, dynamic>? answerFormat;
  final dynamic value;
  final void Function(String id, dynamic value) onChanged;

  /// Профильные значения для student-шага.
  final Map<String, String> prefill;

  String get id => step['id'] as String? ?? 'q$index';
  bool get mandatory => step['isMandatory'] == true;

  /// Подпись-вопрос мелким шрифтом под текстом (поле description шага).
  String get description => (step['description'] as String?) ?? '';

  @override
  Widget build(BuildContext context) {
    final type = answerFormat?['type'] as String? ?? 'text';

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

  Widget _studentField(
      BuildContext context, String field, Map<String, dynamic> answers) {
    final label = _studentLabels[field] ?? field;
    final current = '${answers[field] ?? prefill[field] ?? ''}';

    return _TextAnswerField(
      key: ValueKey('student-$index-$field'),
      initial: current,
      maxLines: 1,
      hint: label,
      capitalize: field == 'fio' || field == 'institute',
      digitsOnly: field == 'course',
      onChanged: (v) {
        // Ответ шага — объект по ключам полей (контракт 6.5).
        final next = Map<String, dynamic>.from(answers);
        next[field] = v;
        onChanged(id, next);
      },
    );
  }
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
  });

  final String initial;
  final int maxLines;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool capitalize;
  final bool digitsOnly;

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
      keyboardType: widget.maxLines > 1
          ? TextInputType.multiline
          : TextInputType.number,
      inputFormatters: widget.digitsOnly
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      textCapitalization: widget.capitalize
          ? TextCapitalization.words
          : TextCapitalization.none,
      onChanged: widget.onChanged,
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
