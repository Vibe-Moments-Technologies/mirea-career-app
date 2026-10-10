import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'app_http_client.dart';
import 'crash_reporting.dart';
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

  /// false — PocketBase URL не передан при сборке: это ошибка конфигурации
  /// сборки, показываем подсказку разработчику вместо пустого приложения.
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
///
/// Health-запроса на старте НЕТ. Раньше он был, и его таймаут переводил
/// приложение в офлайн-репозиторий на всю сессию и ронял пользователя
/// в экран-заглушку: при холодном старте под VPN или на слабой сети первый
/// запрос легко не успевал за 10 секунд, хотя дальше сеть работала.
/// Доступность API теперь проверяется в каждом запросе отдельно, а сбой
/// показывает офлайн-баннер поверх кэша — приложение остаётся живым.
Future<Bootstrap> bootstrap() async {
  final store = await LocalStore.open();

  if (!PocketBaseConfig.isConfigured) {
    // Ошибка конфигурации сборки: приложение стартует без бэкенда.
    // Это не падение, а ветка кода — без явной отправки Sentry о ней
    // не узнает никогда, а знать нужно сразу.
    unawaited(CrashReporting.message(
      'Сборка без POCKETBASE_URL: приложение стартовало без бэкенда',
      context: 'bootstrap:not_configured',
      level: SentryLevel.fatal,
    ));
    return Bootstrap(
      store: store,
      metrics: Metrics(PostsRepo.offline(), store),
      configured: false,
    );
  }

  final metrics = Metrics(PostsRepo(PocketBaseConfig.url), store);
  // Досылаем накопленное офлайн — но не ждём: сеть может быть недоступна.
  unawaited(metrics.flush());
  // Телеметрия доступности бэкенда: на интерфейс не влияет, но даёт
  // событие в Sentry, когда API не отвечает. Всплеск таких событий =
  // бэкенд лежит, и мы узнаём об этом раньше тестировщиков.
  unawaited(_probeApi());
  return Bootstrap(store: store, metrics: metrics, configured: true);
}

/// Разовая проверка доступности API при старте — только для телеметрии.
///
/// Результат НИ НА ЧТО не влияет: приложение стартует в любом случае,
/// а недоступность сети пользователь увидит в офлайн-баннере. Раньше
/// похожая проверка решала судьбу всей сессии и молча уводила приложение
/// в заглушку — теперь она умеет только рассказывать о себе в Sentry.
Future<void> _probeApi() async {
  try {
    final bytes = await AppHttpClient.instance
        .fetchBytes('${PocketBaseConfig.url}/api/health',
            timeout: const Duration(seconds: 10));
    if (bytes == null) {
      await CrashReporting.message(
        'API PocketBase не ответил при старте',
        context: 'bootstrap:api_unreachable',
      );
    }
  } catch (_) {
    await CrashReporting.message(
      'API PocketBase не ответил при старте',
      context: 'bootstrap:api_unreachable',
    );
  }
}
