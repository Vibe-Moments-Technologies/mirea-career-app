import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:survey_kit/survey_kit.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';

/// Экран опросника: анкета, конфигурируемая в БД.
///
/// Определение приходит из PocketBase (expand.form) в JSON-формате
/// survey_kit: `Task.fromJson(definition)`. Результат сериализуется
/// и отправляется в form_responses (анонимно: create открыт, read закрыт).
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

  /// Устойчивый «кто отправил» без персональных данных:.device_id из
  /// локального хранилища (тот же, что в метриках просмотров).
  String _deviceId() =>
      ref.read(localStoreProvider).deviceId;

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
        task: Task.fromJson(form.definition),
        onResult: _onResult,
        // Тёмная тема и фон страницы: survey_kit рисует собственный
        // MaterialApp-подобный контейнер, тема снаружи до него не доходит.
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
