import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// Рендер Markdown-описания поста: **жирный**, *курсив*, `код`,
/// - списки, # заголовки, > цитаты, [текст](url), ---.
///
/// Консоль пишет описания в Markdown; HTML в базе больше не будет.
/// ponytail: без flutter_markdown — пакет ради семи конструкций не нужен,
/// здесь ~80 строк и полный контроль стиля (наши AppText и отступы).
///
/// Что НЕ поддерживаем (в описаниях вуза не встречается): таблицы,
/// картинки, вложенные списки, код-блоки ```.
class MarkdownBody extends StatelessWidget {
  const MarkdownBody({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final b in blocks) _buildBlock(context, b),
      ],
    );
  }

  // ---------- Блочная структура ----------

  ({_BlockKind kind, String text})? _heading(String line) {
    if (line.startsWith('### ')) return (kind: _BlockKind.h3, text: line.substring(4));
    if (line.startsWith('## ')) return (kind: _BlockKind.h2, text: line.substring(3));
    if (line.startsWith('# ')) return (kind: _BlockKind.h1, text: line.substring(2));
    return null;
  }

  List<({_BlockKind kind, String text})> _parseBlocks(String source) {
    final lines = source.replaceAll('\r\n', '\n').split('\n');
    final blocks = <({_BlockKind kind, String text})>[];
    final paragraph = <String>[];

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      blocks.add((kind: _BlockKind.paragraph, text: paragraph.join(' ').trim()));
      paragraph.clear();
    }

    for (final raw in lines) {
      final line = raw.trimRight();

      if (line.trim().isEmpty) {
        flushParagraph();
        continue;
      }

      if (line.startsWith('---') && line.replaceAll('-', '').trim().isEmpty) {
        flushParagraph();
        blocks.add((kind: _BlockKind.divider, text: ''));
        continue;
      }

      final h = _heading(line);
      if (h != null) {
        flushParagraph();
        blocks.add(h);
        continue;
      }

      if (line.startsWith('> ')) {
        flushParagraph();
        blocks.add((kind: _BlockKind.quote, text: line.substring(2).trim()));
        continue;
      }

      if (line.startsWith('- ') || line.startsWith('* ')) {
        flushParagraph();
        blocks.add((kind: _BlockKind.bullet, text: line.substring(2).trim()));
        continue;
      }

      paragraph.add(line.trim());
    }
    flushParagraph();
    return blocks;
  }

  Widget _buildBlock(
      BuildContext context, ({_BlockKind kind, String text}) block) {
    switch (block.kind) {
      case _BlockKind.h1:
        return Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: _rich(context, block.text, AppText.title),
        );
      case _BlockKind.h2:
        return Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: _rich(context, block.text, AppText.headline),
        );
      case _BlockKind.h3:
        return Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: _rich(context, block.text, AppText.cardTitle),
        );
      case _BlockKind.quote:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 3, color: AppColors.secondaryLight),
              const SizedBox(width: 12),
              Expanded(
                child: _rich(
                  context,
                  block.text,
                  AppText.footnote.copyWith(fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ),
        );
      case _BlockKind.bullet:
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('•  ', style: AppText.body),
              Expanded(child: _rich(context, block.text, AppText.body)),
            ],
          ),
        );
      case _BlockKind.divider:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Divider(height: 1, color: AppColors.separator(context)),
        );
      case _BlockKind.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _rich(context, block.text, AppText.body),
        );
    }
  }

  // ---------- Инлайновая разметка ----------

  /// Разбирает строку в TextSpan'ы: **bold**, *italic*, `code`,
  /// [текст](url). Вложенность не поддерживается — в описаниях постов
  /// её нет, а парсер остаётся простым.
  Widget _rich(BuildContext context, String text, TextStyle base) {
    return Text.rich(
      TextSpan(children: _inlineSpans(context, text, base)),
    );
  }

  List<InlineSpan> _inlineSpans(
      BuildContext context, String text, TextStyle base) {
    final spans = <InlineSpan>[];

    // Жадный поиск ближайшей конструкции; регулярка одна, порядок
    // альтернатив задаёт приоритет (** до *, **…** не съест * пары).
    final pattern = RegExp(
      r'\*\*(.+?)\*\*' // **жирный**
      r'|\*(.+?)\*' // *курсив*
      r'|`([^`]+)`' // `код`
      r'|\[([^\]]+)\]\(([^)]+)\)', // [текст](url)
    );

    var rest = text;
    while (true) {
      final m = pattern.firstMatch(rest);
      if (m == null) {
        if (rest.isNotEmpty) spans.add(TextSpan(text: rest, style: base));
        break;
      }

      if (m.start > 0) {
        spans.add(TextSpan(text: rest.substring(0, m.start), style: base));
      }

      if (m.group(1) != null) {
        spans.add(TextSpan(
          text: m.group(1),
          style: base.copyWith(fontWeight: FontWeight.w700),
        ));
      } else if (m.group(2) != null) {
        spans.add(TextSpan(
          text: m.group(2),
          style: base.copyWith(fontStyle: FontStyle.italic),
        ));
      } else if (m.group(3) != null) {
        spans.add(TextSpan(
          text: m.group(3),
          style: base.copyWith(
            fontFamily: 'monospace',
            fontSize: (base.fontSize ?? 16) - 1,
          ),
        ));
      } else {
        final label = m.group(4)!;
        final url = m.group(5)!;
        spans.add(TextSpan(
          text: label,
          style: base.copyWith(
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
            decorationColor: Theme.of(context).colorScheme.primary,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              final uri = Uri.tryParse(url);
              if (uri != null) launchUrl(uri);
            },
        ));
      }

      rest = rest.substring(m.end);
    }

    return spans;
  }
}

enum _BlockKind { paragraph, h1, h2, h3, quote, bullet, divider }
