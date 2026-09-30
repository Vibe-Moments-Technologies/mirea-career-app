import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirea_career/core/theme/app_theme.dart';
import 'package:mirea_career/core/widgets/glass_dock.dart';
import 'package:mirea_career/data/crash_reporting.dart';
import 'package:mirea_career/data/local_store.dart';
import 'package:mirea_career/data/metrics.dart';
import 'package:mirea_career/data/posts_repo.dart';
import 'package:mirea_career/screens/onboarding/onboarding_screen.dart';
import 'package:mirea_career/screens/root_shell.dart';
import 'package:mirea_career/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Тесты построения интерфейса.
///
/// Зачем: компилятор не ловит ошибки времени выполнения — например, запись
/// в состояние Riverpod во время построения провайдера. В release это даёт
/// пустой экран вместо ленты, а узнаётся только на устройстве.
/// Эти тесты проходят реальный путь построения дерева и падают сразу.

/// Клиент-заглушка: сеть недоступна, приложение должно работать на кэше.
SupabaseClient offlineClient() => SupabaseClient(
      'http://localhost:1',
      'offline',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );

Future<ProviderContainer> container({
  StudentProfile? profile,
  List<Map<String, dynamic>>? cache,
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();
  if (profile != null) await store.saveProfile(profile);
  if (cache != null) await store.saveFeedCache(cache);

  return ProviderContainer(
    overrides: [
      localStoreProvider.overrideWithValue(store),
      // именно офлайн-вариант: он не открывает realtime-соединение,
      // поэтому тест завершается без висящих таймеров
      metricsProvider.overrideWithValue(
        Metrics(PostsRepo.offline(offlineClient()), store),
      ),
      supabaseConfiguredProvider.overrideWithValue(true),
    ],
  );
}

Map<String, dynamic> samplePost({
  String id = 'p1',
  String title = 'Осенняя ярмарка вакансий',
  bool featured = false,
  List<String> tags = const ['карьера'],
}) =>
    {
      'id': id,
      'organization_id': 'org1',
      'title': title,
      'description': 'Описание',
      'type': 'event',
      'format': 'offline',
      'status': 'published',
      'organizations': {'id': 'org1', 'name': 'Карьерный центр', 'type': 'university_dept'},
      'tags': tags,
      'campuses': <String>[],
      'institutes': <String>[],
      'directions': <String>[],
      'is_featured': featured,
      'priority_weight': 0,
      'views_count': 0,
      'favorites_count': 0,
      'published_at': DateTime.now().toIso8601String(),
    };

Widget wrap(ProviderContainer c, Widget child) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildAppTheme(Brightness.light), home: child),
    );

void main() {
  // Ловим «тихие» ошибки фреймворка: в release они не видны,
  // а в тестах любая из них валит прогон.
  final frameworkErrors = <String>[];

  setUp(() {
    frameworkErrors.clear();
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      frameworkErrors.add(details.exceptionAsString());
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
  });

  group('Старт приложения', () {
    testWidgets('первый запуск показывает онбординг, а не пустой экран', (tester) async {
      final c = await container();
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();

      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('Где вы учитесь?'), findsOneWidget);
      expect(frameworkErrors, isEmpty, reason: 'фреймворк сообщил об ошибке: $frameworkErrors');
    });

    testWidgets('с пройденным опросом показывается док', (tester) async {
      final c = await container(profile: const StudentProfile(completed: true));
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();

      expect(find.byType(GlassDock), findsOneWidget);
      expect(frameworkErrors, isEmpty, reason: '$frameworkErrors');
    });

    testWidgets('лента строится из кэша без сети', (tester) async {
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [samplePost()],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump(); // микрозадача инициализации

      expect(find.text('Осенняя ярмарка вакансий'), findsOneWidget);
      expect(frameworkErrors, isEmpty, reason: '$frameworkErrors');
    });

    testWidgets('недоступная сеть не ломает построение', (tester) async {
      final c = await container(profile: const StudentProfile(completed: true));
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();

      // приложение живо: док на месте
      expect(find.byType(GlassDock), findsOneWidget);
      expect(frameworkErrors, isEmpty, reason: '$frameworkErrors');
    });
  });

  group('Онбординг', () {
    // Шаги лежат в PageView, поэтому одновременно построена только текущая
    // страница. Проверяем каждый шаг, пролистывая вперёд «Далее».
    testWidgets('шаги проходятся по порядку и вопросы на месте', (tester) async {
      final c = await container();
      addTearDown(c.dispose);

      await tester.pumpWidget(
        wrap(
          c,
          OnboardingScreen(initial: const StudentProfile(), onDone: (_) {}),
        ),
      );
      await tester.pump();

      const questions = [
        'Где вы учитесь?',
        'Ваш институт',
        'Уровень обучения',
        'Что вам интересно?',
      ];

      for (var i = 0; i < questions.length; i++) {
        expect(find.text(questions[i]), findsOneWidget,
            reason: 'шаг ${i + 1}: нет вопроса «${questions[i]}»');

        if (i < questions.length - 1) {
          await tester.tap(find.text('Далее'));
          await tester.pumpAndSettle();
        }
      }
      expect(frameworkErrors, isEmpty, reason: '$frameworkErrors');
    });

    testWidgets('«Пропустить» сообщает о пройденном онбординге', (tester) async {
      final c = await container();
      addTearDown(c.dispose);

      StudentProfile? result;
      await tester.pumpWidget(
        wrap(
          c,
          OnboardingScreen(
            initial: const StudentProfile(),
            onDone: (p) => result = p,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Пропустить'));
      await tester.pump();

      // иначе онбординг будет показываться при каждом запуске
      expect(result?.completed, isTrue);
    });
  });

  group('Провайдеры', () {
    test('лента инициализируется без записи в состояние во время build', () async {
      final c = await container(profile: const StudentProfile(completed: true));
      addTearDown(c.dispose);

      // именно здесь проявлялась ошибка Riverpod «modify a provider
      // while the widget tree was building»
      expect(() => c.read(feedProvider), returnsNormally);

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(c.read(feedProvider), isA<FeedState>());
    });

    test('избранное переключается и отражается в состоянии', () async {
      final c = await container();
      addTearDown(c.dispose);

      expect(c.read(favoritesProvider), isEmpty);
      final added = await c.read(favoritesProvider.notifier).toggle('p1');
      expect(added, isTrue);
      expect(c.read(favoritesProvider), ['p1']);
    });

    test('тема по умолчанию системная и переключается', () async {
      final c = await container();
      addTearDown(c.dispose);

      expect(c.read(themeModeProvider), ThemeMode.system);
      await c.read(themeModeProvider.notifier).set(ThemeMode.dark);
      expect(c.read(themeModeProvider), ThemeMode.dark);
    });
  });

  group('Конфигурация', () {
    test('без ключей приложение сообщает об этом, а не падает', () {
      expect(SupabaseConfig.isConfigured, isFalse,
          reason: 'в тестах ключи не передаются — так и должно быть');
    });

    test('Sentry выключен без DSN и не мешает запуску', () {
      // В тестах DSN не передаётся: телеметрия должна молчать,
      // иначе тесты начнут отправлять события в реальный Sentry.
      expect(CrashReporting.isEnabled, isFalse);
      expect(CrashReporting.showTestTools, isFalse,
          reason: 'без DSN кнопка проверки не должна появляться в интерфейсе');
    });

    test('run() вызывает приложение даже без Sentry', () async {
      var started = false;
      await CrashReporting.run(() async => started = true);
      expect(started, isTrue);
    });

    test('report() не бросает, когда телеметрия выключена', () async {
      // вызывается из обработчика ошибок: собственная неудача
      // не должна превращаться во второе падение
      await expectLater(
        CrashReporting.report(StateError('тест'), StackTrace.current),
        completes,
      );
    });
  });
}