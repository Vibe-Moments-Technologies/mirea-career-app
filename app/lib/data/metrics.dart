import 'dart:async';

import 'app_http_client.dart';
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

  /// Репозиторий, с которым работает приложение.
  PostsRepo get repo => _repo;

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
  const Bootstrap({
    required this.store,
    required this.metrics,
    required this.configured,
  });
  final LocalStore store;
  final Metrics metrics;

  /// false — PocketBase URL не передан при сборке: приложение работает
  /// на пустом кэше и показывает подсказку вместо падения.
  final bool configured;

  /// Выбранная тема, прочитанная ДО первого кадра.
  String get themeMode => store.themeMode;

  /// Тема из настроек, иначе — системная.
  bool? get prefersDark => switch (store.themeMode) {
        'dark' => true,
        'light' => false,
        _ => null,
      };
}

/// Инициализация PocketBase и локального хранилища.
///
/// Никогда не бросает исключение и НИКОГДА не висит: приложение обязано
/// показать интерфейс даже при недоступной сети или неверном URL.
Future<Bootstrap> bootstrap() async {
  final store = await LocalStore.open();

  if (!PocketBaseConfig.isConfigured) {
    return Bootstrap(
      store: store,
      metrics: Metrics(PostsRepo.offline(), store),
      configured: false,
    );
  }

  final repo = PostsRepo(PocketBaseConfig.url);

  // Проверяем доступность API health endpoint.
  try {
    final bytes = await AppHttpClient.instance
        .fetchBytes('${PocketBaseConfig.url}/api/health',
            timeout: const Duration(seconds: 10));
    if (bytes == null) {
      return Bootstrap(
        store: store,
        metrics: Metrics(PostsRepo.offline(), store),
        configured: false,
      );
    }
  } catch (_) {
    return Bootstrap(
      store: store,
      metrics: Metrics(PostsRepo.offline(), store),
      configured: false,
    );
  }

  final metrics = Metrics(repo, store);
  // Досылаем накопленное офлайн — но не ждём: сеть может быть недоступна.
  unawaited(metrics.flush());
  return Bootstrap(store: store, metrics: metrics, configured: true);
}
