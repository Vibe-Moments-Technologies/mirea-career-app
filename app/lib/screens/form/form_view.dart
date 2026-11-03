import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
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
/// Поддерживаемые типы вопросов (поле answerFormat.type в БД):
///  text     — текстовое поле (hint, maxLines, capitalize);
///  single   — один из вариантов (textChoices), плитки;
///  multiple — несколько вариантов, чипы;
///  bool     — да/нет, две плитки;
///  info     — шаг без вопроса: текст-вступление.
class FormView extends StatefulWidget {
  const FormView({
    super.key,
    required this.form,
    required this.onSubmit,
    this.submitting = false,
  });

  final FormDefinition form;

  /// Нажата кнопка «Отправить». Валидация уже пройдена.
  /// Ошибка отправки (false от репозитория) сбрасывается в UI
  /// снэкбаром — состояние ответов при этом сохраняется.
  final void Function(Map<String, dynamic> answers) onSubmit;

  final bool submitting;

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

  // ---------- Валидация ----------

  /// Ответ на шаг: `String` (text/single/bool) или `List` (multiple).
  dynamic _answerOf(String id) => _answers[id];

  bool _stepFilled(Map<String, dynamic> step) {
    if (!_isMandatory(step)) return true;
    final v = _answers[step['id']];
    if (v is String) return v.trim().isNotEmpty;
    if (v is List) return v.isNotEmpty;
    return false;
  }

  bool get _allFilled => _steps.every(_stepFilled);

  void _submit() {
    if (!_allFilled || widget.submitting) return;
    HapticFeedback.mediumImpact();
    widget.onSubmit(Map<String, dynamic>.from(_answers));
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
                        onChanged: _setAnswer,
                      ),
                      const SizedBox(height: 18),
                    ],
                  ],
                ),
        ),
        // Кнопка отправки — закреплена внизу: всегда на виду, но не
        // перекрывает контент (в отличие от floatingActionButton).
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, 8, pad, 14),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _allFilled && !widget.submitting ? _submit : null,
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
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : const Text('Отправить анкету'),
              ),
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
  });

  final int index;
  final Map<String, dynamic> step;
  final String label;
  final Map<String, dynamic>? answerFormat;
  final dynamic value;
  final void Function(String id, dynamic value) onChanged;

  String get id => step['id'] as String? ?? 'q$index';
  bool get mandatory => step['isMandatory'] == true;

  @override
  Widget build(BuildContext context) {
    final type = answerFormat?['type'] as String? ?? 'text';

    // Шаг-вступление: просто текст, без поля.
    if (type == 'info' || answerFormat == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty)
            Text(label, style: AppText.footnote.copyWith(height: 1.5)),
        ],
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
        const SizedBox(height: 10),
        _buildAnswer(context, type),
      ],
    );
  }

  Widget _buildAnswer(BuildContext context, String type) {
    switch (type) {
      case 'single':
        return _buildSingle(context);
      case 'multiple':
        return _buildMultiple(context);
      case 'bool':
        return _buildBool(context);
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

    return TextField(
      controller: TextEditingController(text: value as String? ?? '')
        ..selection = TextSelection.collapsed(
            offset: (value as String? ?? '').length),
      maxLines: maxLines,
      minLines: 1,
      keyboardType: maxLines > 1
          ? TextInputType.multiline
          : TextInputType.text,
      textCapitalization:
          capitalize ? TextCapitalization.words : TextCapitalization.none,
      onChanged: (v) => onChanged(id, v),
      decoration: InputDecoration(
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
      ),
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
