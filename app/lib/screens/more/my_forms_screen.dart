import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_back_button.dart';
import '../../data/form_history.dart';
import '../../state/providers.dart';

/// Дата+время для карточек и снимка: 03.11.2026 · 14:05.
String _formDate(DateTime dt) =>
    '${dt.day.toString().padLeft(2, '0')}.'
    '${dt.month.toString().padLeft(2, '0')}.'
    '${dt.year} · '
    '${dt.hour.toString().padLeft(2, '0')}:'
    '${dt.minute.toString().padLeft(2, '0')}';

/// «Мои анкеты»: история отправленных опросников (файл на устройстве).
///
/// Подстраница «Ещё» (как «Архив»): AppBar со стеклянной кнопкой «назад».
/// Карточка: заголовок поста, название анкеты, дата отправления и сколько
/// ответов. Тап показывает снимок ответов — сервер их не отдаёт (create-only
/// в form_responses), поэтому единственный источник — локальный файл.
class MyFormsScreen extends ConsumerWidget {
  const MyFormsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final submissions = ref.watch(formSubmissionsProvider);
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои анкеты'),
        titleTextStyle: AppText.headline,
        leading: const GlassBackButton(),
      ),
      body: submissions.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.assignment_outlined,
                      size: 56,
                      color: AppColors.secondaryLight,
                    ),
                    const SizedBox(height: 16),
                    Text('Пока пусто', style: AppText.title),
                    const SizedBox(height: 8),
                    Text(
                      'Здесь появятся анкеты мероприятий,\nкоторые вы заполнили',
                      textAlign: TextAlign.center,
                      style:
                          AppText.footnote.copyWith(color: AppColors.secondaryLight),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(
                pad,
                8,
                pad,
                AppInsets.screenBottom(context),
              ),
              children: [
                for (final s in submissions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SubmissionCard(
                      submission: s,
                      onTap: () => _showAnswers(context, s),
                    ),
                  ),
              ],
            ),
    );
  }

  /// Снимок отправленных ответов: ключ → значение.
  static void _showAnswers(BuildContext context, FormSubmission s) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          children: [
            Text(s.formTitle, style: AppText.title),
            const SizedBox(height: 4),
            Text(
              _formDate(s.submittedAt),
              style: AppText.caption.copyWith(color: AppColors.secondaryLight),
            ),
            const SizedBox(height: 16),
            for (final e in s.answers.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.key,
                      style: AppText.caption
                          .copyWith(color: AppColors.secondaryLight),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _answerText(e.value),
                      style: AppText.body,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _answerText(Object? v) => v is List ? v.join(', ') : '$v';
}

/// Карточка отправленной анкеты: пост, анкета, дата, число ответов.
class _SubmissionCard extends StatelessWidget {
  const _SubmissionCard({required this.submission, required this.onTap});

  final FormSubmission submission;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: AppColors.separator(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.task_alt_rounded,
                size: 28,
                color: scheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      submission.postTitle.isEmpty
                          ? submission.formTitle
                          : submission.postTitle,
                      style: AppText.headline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${submission.formTitle} · ${_formDate(submission.submittedAt)}',
                      style: AppText.caption
                          .copyWith(color: AppColors.secondaryLight),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
