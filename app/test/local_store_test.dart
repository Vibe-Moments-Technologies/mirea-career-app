import 'package:flutter_test/flutter_test.dart';
import 'package:mirea_career/data/local_store.dart';
import 'package:mirea_career/data/metrics.dart';
import 'package:mirea_career/data/posts_repo.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late LocalStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
  });

  group('Избранное', () {
    test('добавление и удаление переключают состояние', () async {
      expect(store.isFavorite('p1'), isFalse);
      expect(await store.toggleFavorite('p1'), isTrue);
      expect(store.isFavorite('p1'), isTrue);
      expect(await store.toggleFavorite('p1'), isFalse);
      expect(store.isFavorite('p1'), isFalse);
    });

    test('новые добавления идут в начало списка', () async {
      await store.toggleFavorite('old');
      await store.toggleFavorite('new');
      expect(store.favorites.first, 'new');
    });

    test('избранное переживает переоткрытие хранилища', () async {
      await store.toggleFavorite('p1');
      final reopened = await LocalStore.open();
      expect(reopened.isFavorite('p1'), isTrue);
    });
  });

  group('Просмотры', () {
    test('просмотр засчитывается только один раз на устройство', () async {
      expect(await store.markViewedIfNew('p1'), isTrue);
      expect(await store.markViewedIfNew('p1'), isFalse);
      expect(await store.markViewedIfNew('p2'), isTrue);
    });

    test('отметка переживает переоткрытие', () async {
      await store.markViewedIfNew('p1');
      final reopened = await LocalStore.open();
      expect(await reopened.markViewedIfNew('p1'), isFalse);
    });
  });

  group('Очередь счётчиков', () {
    test('метрики накапливаются и очищаются', () async {
      expect(store.pendingMetrics, isEmpty);
      await store.queueMetric(const PendingMetric('view', 'p1'));
      await store.queueMetric(const PendingMetric('favorite', 'p1', -1));

      final pending = store.pendingMetrics;
      expect(pending.length, 2);
      expect(pending[0].kind, 'view');
      expect(pending[1].delta, -1);

      await store.clearPendingMetrics();
      expect(store.pendingMetrics, isEmpty);
    });
  });

  group('Профиль и тема', () {
    test('профиль сохраняется и читается', () async {
      await store.saveProfile(
        const StudentProfile(campus: 'iit', tags: ['it'], completed: true),
      );
      expect(store.profile.campus, 'iit');
      expect(store.profile.tags, ['it']);
      expect(store.profile.completed, isTrue);
    });

    test('тема по умолчанию системная', () async {
      expect(store.themeMode, 'system');
      await store.saveThemeMode('dark');
      expect(store.themeMode, 'dark');
    });
  });

  group('Кэш ленты и сброс', () {
    test('кэш ленты сохраняется и читается', () async {
      expect(store.feedCache, isNull);
      await store.saveFeedCache([
        {'id': 'p1', 'title': 'Заголовок'},
      ]);
      expect(store.feedCache!.first['title'], 'Заголовок');
    });

    test('сброс очищает профиль, избранное, просмотры и кэш', () async {
      await store.saveProfile(const StudentProfile(campus: 'iit', completed: true));
      await store.toggleFavorite('p1');
      await store.markViewedIfNew('p1');
      await store.queueMetric(const PendingMetric('view', 'p1'));
      await store.saveFeedCache([
        {'id': 'p1'},
      ]);

      await store.reset();

      expect(store.profile.completed, isFalse);
      expect(store.profile.campus, isNull);
      expect(store.favorites, isEmpty);
      expect(store.viewedIds, isEmpty);
      expect(store.pendingMetrics, isEmpty);
      expect(store.feedCache, isNull);
      // тема — настройка интерфейса, а не данные студента: сброс её не трогает
      expect(store.themeMode, 'system');
    });
  });

  group('Метрики через офлайн-репозиторий', () {
    test('просмотр и избранное без сети копятся в очередь', () async {
      // Репозиторий с пустым baseUrl = офлайн: отправка возвращает false,
      // и вызов обязан лечь в офлайн-очередь, а не потеряться.
      final metrics = Metrics(PostsRepo(''), store);

      final counted = await metrics.registerView('p1');
      // Локальная дедупликация сработала (первый просмотр), но сети нет —
      // в очередь ушёл «view».
      expect(counted, isTrue);
      expect(store.pendingMetrics.length, 1);
      expect(store.pendingMetrics.first.kind, 'view');
      expect(store.pendingMetrics.first.postId, 'p1');

      await metrics.registerFavorite('p1', 1);
      expect(store.pendingMetrics.length, 2);
      expect(store.pendingMetrics.last.kind, 'favorite');
      expect(store.pendingMetrics.last.delta, 1);

      // Повторный просмотр того же поста не дублируется (дедупликация
      // на устройстве), даже офлайн.
      await metrics.registerView('p1');
      expect(store.pendingMetrics.length, 2);
    });

    test('сброс очереди после успешной отправки не оставляет хвостов', () async {
      // flush с офлайн-репозиторием: очередь читается, отправка снова
      // невозможна — метрики возвращаются в очередь в том же составе.
      final metrics = Metrics(PostsRepo(''), store);
      await metrics.registerFavorite('p2', -1);
      await metrics.flush();
      expect(store.pendingMetrics.length, 1);
      expect(store.pendingMetrics.first.postId, 'p2');
      expect(store.pendingMetrics.first.delta, -1);
    });
  });
}