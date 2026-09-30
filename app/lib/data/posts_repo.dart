import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// Доступ к данным через Supabase. Анонимный клиент, без авторизации:
/// RLS на стороне БД отдаёт только `published` (docs/DATABASE.md §4).
class PostsRepo {
  PostsRepo(this._client) : _realtime = true;

  /// Репозиторий без сети: запросы падают, realtime-поток не открывается.
  ///
  /// Нужен, когда Supabase недоступен (нет ключей, не удалась инициализация,
  /// тесты). Важно, что такой репозиторий НЕ открывает realtime-соединение:
  /// иначе клиент бесконечно переподключается к несуществующему серверу,
  /// оставляя за собой таймеры, и приложение не может корректно завершиться.
  PostsRepo.offline(this._client) : _realtime = false;

  final SupabaseClient _client;
  final bool _realtime;

  static const _select = '*, organizations(name, type, logo_url)';

  /// Опубликованные посты: приоритетные выше, затем по дате события.
  Future<List<Post>> fetchPublished() async {
    final rows = await _client
        .from('posts')
        .select(_select)
        .eq('status', 'published')
        .lte('published_at', DateTime.now().toUtc().toIso8601String())
        .order('priority_weight', ascending: false)
        .order('published_at', ascending: false)
        .limit(300);
    return rows.map(Post.tryParse).whereType<Post>().toList();
  }

  /// Realtime-поток: публикация в админке появляется в ленте без обновления.
  ///
  /// `.stream()` присылает ПОЛНЫЙ набор строк при каждом изменении — это и
  /// есть нужный нам снимок, никакого `.expand` не требуется. Анонимный ключ
  /// получает только `published` (RLS), фильтр по дате — на всякий случай:
  /// отложенная публикация не должна просочиться раньше времени.
  Stream<List<Post>> watchPublished() {
    if (!_realtime) return const Stream.empty();

    return _client
        .from('posts')
        .stream(primaryKey: ['id'])
        .eq('status', 'published')
        .order('published_at')
        .map((rows) {
          final now = DateTime.now();
          return rows
              .map(Post.tryParse)
              .whereType<Post>()
              .where((p) => p.publishedAt == null || !p.publishedAt!.isAfter(now))
              .toList();
        });
  }

  /// Счётчики — только через RPC (у анонима нет UPDATE на posts).
  Future<void> incrementViews(String postId) =>
      _client.rpc('increment_post_views', params: {'target_post_id': postId});

  Future<void> modifyFavorites(String postId, int delta) =>
      _client.rpc('modify_post_favorites', params: {'target_post_id': postId, 'delta': delta});
}

/// Конфигурация Supabase: значения приходят через --dart-define,
/// чтобы ключи не оказались в репозитории (docs/ARCHITECTURE.md §5).
class SupabaseConfig {
  const SupabaseConfig._();

  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}