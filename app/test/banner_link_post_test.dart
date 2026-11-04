import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirea_career/data/models.dart';

/// Тест чтения пост-ссылки баннера в двух форматах: link_post (как пишет
/// панель) и "post:XXXXXX" в link_url. Регрессия: баннер с пост-ссылкой
/// приходил без ссылки, тап «не работал».
void main() {
  test('link_post (формат панели) даёт пост-ссылку', () {
    // Реальная запись «ПТУ МИРЭА» с сервера.
    const serverJson = {
      'id': 't3uifaqzufot4bq',
      'title': 'ПТУ МИРЭА',
      'subtitle': 'Опрос о переименовании вуза в ПТУ МИРЭА',
      'image_url': null,
      'link_url': '',
      'link_post': 'PWUBVD',
      'sort_order': 70,
    };

    final banner = SpotlightBanner.tryParse(serverJson);
    expect(banner?.linkPostId, 'PWUBVD',
        reason: 'ссылка на пост должна читаться из link_post');

    // Полный цикл кэша: модель → JSON → модель.
    final restored = SpotlightBanner.tryParse(
      jsonDecode(jsonEncode(banner!.toJson())) as Map<String, dynamic>,
    );
    expect(restored?.linkPostId, 'PWUBVD',
        reason: 'кэш должен сохранять link_post');
  });

  test('link_url с префиксом post: тоже даёт пост-ссылку', () {
    const json = {
      'id': 'b1',
      'title': 'Баннер',
      'link_url': 'post:4Z65U4',
      'link_post': '',
      'sort_order': 1,
    };
    final banner = SpotlightBanner.tryParse(json);
    expect(banner?.linkPostId, '4Z65U4');
  });

  test('обычный link_url — не пост-ссылка', () {
    const json = {
      'id': 'b2',
      'title': 'Баннер',
      'link_url': 'https://mirea.ru',
      'link_post': '',
      'sort_order': 1,
    };
    final banner = SpotlightBanner.tryParse(json);
    expect(banner?.linkPostId, isNull);
    expect(banner?.linkUrl, 'https://mirea.ru');
  });
}
