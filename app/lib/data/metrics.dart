import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_store.dart';
import 'posts_repo.dart';

/// Отправка счётчиков интереса: просмотры и добавления в избранное.
///
/// Правила (docs/ARCHITECTURE.md §3):
///  * просмотр засчитывается один раз на устройство (дедупликация в LocalStore);
///  * без сети вызов уходит в очередь и повторяется при следующем старте;
///  * интерфейс никогда не ждёт сеть — fire-and-forget.
class Metrics {
  Metrics(this._repo, this._store);

  final PostsRepo _repo;
  final LocalStore _store;

  /// Отмечает просмотр, если он первый для этого устройства.
  /// true — просмотр засчитан, счётчик в интерфейсе стоит поднять.
  Future<bool> registerView(String postId) async {
    if (!await _store.markViewedIfNew(postId)) return false;
    await _send(PendingMetric('view', postId));
    return true;
  }

  Future<void> registerFavorite(String postId, int delta) =>
      _send(PendingMetric('favorite', postId, delta));

  Future<void> _send(PendingMetric m) async {
    try {
      await _apply(m);
    } catch (_) {
      await _store.queueMetric(m);
    }
  }

  /// Повторяет накопленные офлайн-вызовы (вызывается при старте).
  Future<void> flush() async {
    final pending = _store.pendingMetrics;
    if (pending.isEmpty) return;
    await _store.clearPendingMetrics();
    for (final m in pending) {
      try {
        await _apply(m);
      } catch (_) {
        await _store.queueMetric(m); // сеть всё ещё недоступна
      }
    }
  }

  Future<void> _apply(PendingMetric m) => switch (m.kind) {
        'view' => _repo.incrementViews(m.postId),
        'favorite' => _repo.modifyFavorites(m.postId, m.delta),
        _ => Future.value(),
      };
}

/// Итог старта приложения.
class Bootstrap {
  const Bootstrap({required this.store, required this.metrics, required this.configured});
  final LocalStore store;
  final Metrics metrics;

  /// false — ключи Supabase не переданы при сборке: приложение работает
  /// на пустом кэше и показывает подсказку вместо падения.
  final bool configured;
}

/// Инициализация Supabase и локального хранилища.
Future<Bootstrap> bootstrap() async {
  final store = await LocalStore.open();

  if (!SupabaseConfig.isConfigured) {
    return Bootstrap(store: store, metrics: Metrics(PostsRepo(_offline), store), configured: false);
  }

  await Supabase.initialize(url: SupabaseConfig.url, publishableKey: SupabaseConfig.anonKey);
  final metrics = Metrics(PostsRepo(Supabase.instance.client), store);
  await metrics.flush(); // досылаем накопленное офлайн
  return Bootstrap(store: store, metrics: metrics, configured: true);
}

/// Флаг «сети нет»: клиент-заглушка отвечает ошибкой на любой запрос,
/// поэтому лента берётся из кэша, а счётчики копятся в очереди.
final _offline = SupabaseClient(
  'http://localhost:1',
  'offline',
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);