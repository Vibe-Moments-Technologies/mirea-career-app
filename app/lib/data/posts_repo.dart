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

  /// Вложенные поля организации нужны вместе с `id`: Organization.tryParse
  /// требует его, иначе возвращает null — и тогда organizationType пустой,
  /// из-за чего фильтр «От вуза / От партнёров» отсекает ВСЕ карточки.
  /// Именно поэтому каталог был пуст, а главная (там фильтра по источнику
  /// нет) показывала посты.
  ///
  /// Контакты нужны профилю организатора (org_screen): экран открывается
  /// с одним лишь id, а данных о компании в посте нет.
  static const _select = '*, organizations('
      'id, name, type, description, logo_url, website, '
      'contact_email, contact_phone, contact_name)';

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
  /// ВАЖНО: сам `.stream()` (postgres_changes) отдаёт только колонки таблицы
  /// posts — вложенные `organizations` в нём НЕ приходят. Если отдавать эти
  /// строки в интерфейс, organizationType станет null и фильтр «От вуза /
  /// От партнёров» опустеет (так уже было). Поэтому событие realtime —
  /// лишь сигнал перечитать полные данные через fetchPublished().
  Stream<List<Post>> watchPublished() {
    if (!_realtime) return const Stream.empty();

    return _client
        .from('posts')
        .stream(primaryKey: ['id'])
        .eq('status', 'published')
        .asyncMap((_) => fetchPublished());
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

  /// trim() обязателен: значение из CI-секрета легко приходит с BOM
  /// (U+FEFF) или переводом строки в начале. Такой URL выглядит непустым,
  /// но инициализация с ним не работает — приложение показывает пустой
  /// экран вместо интерфейса. Один раз это уже случилось.
  static final url = const String.fromEnvironment('SUPABASE_URL').trim();
  static final anonKey = const String.fromEnvironment('SUPABASE_ANON_KEY').trim();

  static bool get isConfigured =>
      url.isNotEmpty && anonKey.isNotEmpty && Uri.tryParse(url)?.hasScheme == true;
}