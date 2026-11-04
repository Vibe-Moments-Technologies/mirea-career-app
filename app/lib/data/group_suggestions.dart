import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'app_http_client.dart';

/// Подсказки групп из API расписания вуза.
///
/// GET https://schedule-of.mirea.ru/schedule/api/search?match=ИКБО&limit=20
/// Сервер ищет подстроку по всем типам целей сразу (группы, преподаватели,
/// аудитории) — фильтруем только группы.
///
/// API требует User-Agent; при его отсутствии сервер отвечает ошибкой.
/// Подсказки вспомогательные: нет сети или API изменился — поле просто
/// работает без подсказок, ввод не блокируется.
class GroupSuggestions {
  GroupSuggestions._();

  static const _endpoint =
      'https://schedule-of.mirea.ru/schedule/api/search';

  /// Живой поиск групп по подстроке: «икбо» → [ИКБО-01-23, …].
  /// Пусто/коротко — без запроса. Ошибка — пустой список.
  static Future<List<String>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];

    try {
      final url =
          '$_endpoint?match=${Uri.encodeComponent(q)}&limit=20';
      final client = AppHttpClient.instance;
      final bytes = await client.fetchBytes(
        url,
        userAgent: 'university-app-schedule-fetcher/0.1',
      );
      if (bytes == null) return const [];

      final json = jsonDecode(utf8.decode(bytes));
      final data = (json['data'] as List? ?? const []);
      // В выдаче вперемешку группы/преподаватели/аудитории.
      final groups = [
        for (final e in data)
          if (e is Map &&
              e['type'] == 'group' &&
              e['name'] is String)
            e['name'] as String,
      ];
      // Не более 5 подсказок: строка подсказок короткая.
      return groups.take(5).toList();
    } catch (e) {
      debugPrint('group suggestions failed: $e');
      return const [];
    }
  }
}
