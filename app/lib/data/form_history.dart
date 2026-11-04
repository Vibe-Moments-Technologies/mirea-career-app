import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Запись об отправленной анкете.
///
/// Хранится локально на устройстве (см. [FormHistoryStore]): приложение
/// показывает «уже заполнено» на карточке и в деталях, блокирует повтор
/// и собирает раздел «Мои анкеты» в «Ещё».
@immutable
class FormSubmission {
  const FormSubmission({
    required this.formId,
    required this.postId,
    required this.postTitle,
    required this.formTitle,
    required this.submittedAt,
    this.answers = const {},
    this.successText,
    this.questions = const [],
  });

  final String formId;
  final String postId;

  /// Снимок заголовка поста на момент отправки: пост может уйти в архив
  /// или быть удалён на сервере, а карточка «Мои анкеты» должна остаться
  /// осмысленной без сети.
  final String postTitle;

  /// Заголовок анкеты на момент отправки.
  final String formTitle;
  final DateTime submittedAt;

  /// Ответы: id шага → значение. Храним локально, чтобы раздел «Мои
  /// анкеты» показывал, ЧТО именно студент отправил — серверные ответы
  /// закрыты даже от него самого (create-only в form_responses).
  final Map<String, dynamic> answers;
  final String? successText;

  /// Снимок вопросов на момент отправки: (id шага, текст вопроса).
  ///
  /// Без него снимок показывал бы технические id («вам_нравится_новое_
  /// назва») вместо вопросов: определение анкеты могло измениться
  /// в БД, а история должна читаться человеком и офлайн.
  final List<(String, String)> questions;

  /// Человекочитаемая подпись вопроса по id: текст из снимка, иначе —
  /// сам id (старые записи до появления снимка).
  String questionLabel(String id) =>
      questions.where((q) => q.$1 == id).map((q) => q.$2).firstOrNull ?? id;

  /// Ответ в человекочитаемом виде: bool → «Да»/«Нет», список →
  /// через запятую, остальное — как есть. Голубые «true» в снимке
  /// никто читать не должен.
  static String answerText(Object? v) => switch (v) {
        null => '—',
        bool() => v ? 'Да' : 'Нет',
        List() => v.isEmpty ? '—' : v.join(', '),
        _ => '$v',
      };

  Map<String, dynamic> toJson() => {
        'form_id': formId,
        'post_id': postId,
        'post_title': postTitle,
        'form_title': formTitle,
        'submitted_at': submittedAt.toIso8601String(),
        'answers': answers,
        'success_text': successText,
        'questions': [
          for (final q in questions) {'id': q.$1, 'text': q.$2},
        ],
      };

  static FormSubmission? tryParse(Object? json) {
    if (json is! Map) return null;
    final formId = json['form_id'];
    final postId = json['post_id'];
    if (formId is! String || postId is! String) return null;
    final at = DateTime.tryParse(json['submitted_at'] as String? ?? '');
    if (at == null) return null;
    return FormSubmission(
      formId: formId,
      postId: postId,
      postTitle: json['post_title'] as String? ?? '',
      formTitle: json['form_title'] as String? ?? '',
      submittedAt: at,
      answers:
          (json['answers'] as Map?)?.cast<String, dynamic>() ?? const {},
      successText: json['success_text'] as String?,
      questions: [
        for (final q in (json['questions'] as List? ?? const []))
          if (q is Map && q['id'] is String && q['text'] is String)
            (q['id'] as String, q['text'] as String),
      ],
    );
  }
}

/// История отправленных анкет — файл в папке приложения на устройстве.
///
/// SharedPreferences не подходит: история содержит сами ответы (JSON
/// произвольного размера), и это данные пользователя, а не настройки.
/// Файл живёт в getApplicationSupportDirectory() (iOS:
/// NSApplicationSupportDirectory, Android: filesDir) — приватная папка
/// приложения, не видна в системном файловом менеджере и не чистится ОС.
///
/// Одна анкета на пост: повторная отправка блокируется на уровне UI,
/// поэтому ключ — postId.
class FormHistoryStore {
  FormHistoryStore._(this._file);

  /// История в памяти, без файла — для тестов и сред без файловой системы.
  FormHistoryStore.inMemory([List<FormSubmission> submissions = const []])
      : _file = _memOnlyFile {
    for (final s in submissions) {
      _byPost[s.postId] = s;
    }
  }

  /// Маркер «файл не используется»: writeAsString на нём не вызывается.
  static final _memOnlyFile = File('');

  static const _fileName = 'form_history.json';

  final File _file;
  final Map<String, FormSubmission> _byPost = {};

  /// Открывает (или создаёт) историю. Сбой чтения — не повод падать:
  /// начинаем с пустой истории.
  static Future<FormHistoryStore> open() async {
    late File file;
    try {
      final dir = await getApplicationSupportDirectory();
      file = File('${dir.path}${Platform.pathSeparator}$_fileName');
    } catch (_) {
      // Нет доступа к файловой системе (тесты, exotic-платформы):
      // история живёт в памяти, ничего не ломается.
      file = File(_fileName);
    }
    final store = FormHistoryStore._(file);
    await store._load();
    return store;
  }

  Future<void> _load() async {
    try {
      final raw = await _file.readAsString();
      final list = jsonDecode(raw) as List?;
      for (final e in list ?? const []) {
        final s = FormSubmission.tryParse(e);
        if (s != null) _byPost[s.postId] = s;
      }
    } catch (_) {
      // нет файла или битый JSON — пустая история
    }
  }

  Future<void> _save() async {
    if (identical(_file, _memOnlyFile)) return; // память, файл не пишем
    try {
      final json = jsonEncode(
          [for (final s in _byPost.values) s.toJson()]); // порядок вставки
      await _file.writeAsString(json, flush: true);
    } catch (_) {
      // запись не удалась — история останется в памяти до перезапуска;
      // ронять отправку анкеты из-за локального кэша нельзя
    }
  }

  List<FormSubmission> get all {
    final list = _byPost.values.toList();
    list.sort((a, b) => b.submittedAt.compareTo(a.submittedAt)); // новые сверху
    return list;
  }

  FormSubmission? forPost(String postId) => _byPost[postId];

  bool hasForPost(String postId) => _byPost.containsKey(postId);

  Future<void> add(FormSubmission submission) async {
    _byPost[submission.postId] = submission;
    await _save();
  }
}
