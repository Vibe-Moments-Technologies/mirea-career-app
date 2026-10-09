import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirea_career/core/theme/app_theme.dart';
import 'package:mirea_career/core/app_route.dart';
import 'package:mirea_career/core/widgets/glass_back_button.dart';
import 'package:mirea_career/core/widgets/glass_dock.dart';
import 'package:mirea_career/core/widgets/pinned_header_screen.dart';
import 'package:mirea_career/core/widgets/screen_header.dart';
import 'package:mirea_career/data/catalogs.dart';
import 'package:mirea_career/data/crash_reporting.dart';
import 'package:mirea_career/data/local_store.dart';
import 'package:mirea_career/data/metrics.dart';
import 'package:mirea_career/data/models.dart';
import 'package:mirea_career/data/posts_repo.dart';
import 'package:mirea_career/screens/favorites/favorites_screen.dart';
import 'package:mirea_career/screens/home/home_screen.dart';
import 'package:mirea_career/screens/more/profile_screen.dart';
import 'package:mirea_career/screens/org/organizations_screen.dart';
import 'package:mirea_career/screens/onboarding/onboarding_screen.dart';
import 'package:mirea_career/screens/root_shell.dart';
import 'package:mirea_career/state/feed_query.dart';
import 'package:mirea_career/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Тесты построения интерфейса.
///
/// Зачем: компилятор не ловит ошибки времени выполнения — например, запись
/// в состояние Riverpod во время построения провайдера. В release это даёт
/// пустой экран вместо ленты, а узнаётся только на устройстве.
/// Эти тесты проходят реальный путь построения дерева и падают сразу.

Future<ProviderContainer> container({
  StudentProfile? profile,
  List<Map<String, dynamic>>? cache,
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();
  if (profile != null) await store.saveProfile(profile);
  if (cache != null) await store.saveFeedCache(cache);

  final cachedRepo = _CachedRepo(cache ?? const []);
  return ProviderContainer(
    overrides: [
      localStoreProvider.overrideWithValue(store),
      // Репозиторий с данными из кэша: главная запрашивает ленту по
      // действию, и в тестах сервером становится сам кэш.
      postsRepoProvider.overrideWithValue(cachedRepo),
      metricsProvider.overrideWithValue(Metrics(cachedRepo, store)),
      supabaseConfiguredProvider.overrideWithValue(true),
    ],
  );
}

/// Тестовый «сервер»: отдаёт содержимое кэша на любой запрос ленты.
class _CachedRepo extends PostsRepo {
  _CachedRepo(this.posts) : super('');

  final List<Map<String, dynamic>> posts;

  @override
  Future<List<Post>> fetchFeed({
    String tab = 'foryou',
    String query = '',
    Set<String> types = const {},
    bool showArchived = false,
    StudentProfile? profile,
  }) async =>
      posts.map(Post.tryParse).whereType<Post>().toList();

  @override
  Future<List<Post>> fetchPosts({String? organizationId}) async => posts
      .map(Post.tryParse)
      .whereType<Post>()
      .where((p) => organizationId == null || p.organizationId == organizationId)
      .toList();

  /// Организации собираются из expand постов — как отдельный запрос.
  @override
  Future<List<Organization>> fetchOrganizations() async => [
        for (final p in posts.map(Post.tryParse).whereType<Post>())
          if (p.organization != null) p.organization!
      ].fold<List<Organization>>(
        [],
        (acc, org) => acc.any((o) => o.id == org.id) ? acc : [...acc, org],
      );
}

Map<String, dynamic> samplePost({
  String id = 'p1',
  String title = 'Осенняя ярмарка вакансий',
  bool featured = false,
  List<String> tags = const ['карьера'],
  DateTime? publishedAt,
  Map<String, dynamic>? organization,
  String organizationId = 'org1',
  String? externalLink,
  String description = 'Описание',
  DateTime? startDate,
  DateTime? endDate,
  List<String> campuses = const [],
  List<String> institutes = const [],
}) =>
    {
      'id': id,
      'organization': organizationId,
      'title': title,
      'description': description,
      'type': 'event',
      'format': 'offline',
      'status': 'published',
      // PocketBase-формат: организация приезжает в expand.organization.
      'expand': {
        'organization': organization ??
            {'id': 'org1', 'name': 'Карьерный центр', 'type': 'university_dept'},
      },
      'external_link': externalLink,
      'tags': tags,
      'campuses': campuses,
      'institutes': institutes,
      'directions': <String>[],
      'start_date': startDate?.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'is_featured': featured,
      'priority_weight': 0,
      'views_count': 0,
      'favorites_count': 0,
      // Явная дата важна: лента сортируется по published_at, и при
      // одинаковых значениях (DateTime.now() в одном тике) порядок
      // недетерминирован — тест начинает падать случайным образом.
      'published_at': (publishedAt ?? DateTime.now()).toIso8601String(),
    };

Widget wrap(
  ProviderContainer c,
  Widget child, {
  TargetPlatform platform = TargetPlatform.android,
}) =>
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light).copyWith(platform: platform),
        home: child,
      ),
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
      // первый шаг теперь «Ваш институт»: шаг с адресом убран из анкеты
      expect(find.text('Ваш институт'), findsOneWidget);
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

    testWidgets('лента запрашивается при открытии главной', (tester) async {
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [samplePost()],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      // postFrameCallback срабатывает в этом кадре, запрос стартует.
      await tester.pump();
      // Запрос выполняется мгновенно (тестовый репозиторий без сети) —
      // после settle карточка из «сервера» появилась на главной.
      await tester.pumpAndSettle();

      expect(find.text('Осенняя ярмарка вакансий'), findsOneWidget);
      expect(c.read(feedNotifierProvider).loading, isFalse);
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

    testWidgets('шага про кампус больше нет', (tester) async {
      final c = await container();
      addTearDown(c.dispose);

      await tester.pumpWidget(
        wrap(c, OnboardingScreen(initial: const StudentProfile(), onDone: (_) {})),
      );
      await tester.pump();

      // адрес обучения убран из анкеты: для подбора он не нужен
      expect(find.text('Где вы учитесь?'), findsNothing);
      expect(find.text('Вернадского, 78'), findsNothing);
    });

    testWidgets('в уровнях есть абитуриент, специалитет, выпускник, преподаватель',
        (tester) async {
      final c = await container();
      addTearDown(c.dispose);

      await tester.pumpWidget(
        wrap(c, OnboardingScreen(initial: const StudentProfile(), onDone: (_) {})),
      );
      await tester.pump();

      // шаг уровня — второй
      await tester.tap(find.text('Далее'));
      await tester.pumpAndSettle();

      for (final level in [
        'Абитуриент',
        'Бакалавриат',
        'Специалитет',
        'Магистратура',
        'Аспирантура',
        'Выпускник',
        'Преподаватель',
      ]) {
        expect(find.text(level), findsOneWidget, reason: 'нет уровня «$level»');
      }
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

    test('при пропуске профиль не считается заполненным', () {
      // Реальная жалоба: подпись в «Ещё» писала «Заполнен», хотя ответов
      // не было — проверялся флаг completed, а его выставляет и пропуск.
      const skipped = StudentProfile(completed: true);
      expect(skipped.completed, isTrue);
      expect(skipped.hasAnswers, isFalse,
          reason: 'completed ≠ заполнен: ответов нет');
      expect(profileSummary(skipped), contains('Не заполнен'));
    });

    test('после ответов профиль считается заполненным', () {
      const filled = StudentProfile(
        completed: true,
        institute: 'iit',
        level: 'bachelor',
        tags: ['it', 'career'],
      );
      expect(filled.hasAnswers, isTrue);
      expect(profileSummary(filled), contains('ИИТ'));
      expect(profileSummary(filled), isNot(contains('Не заполнен')));
    });
  });

  group('Справочники', () {
    test('институты — реальные подразделения РТУ МИРЭА', () {
      final shorts = Catalogs.institutes.map((i) => i.short).toList();
      for (final expected in [
        'ИКБ', 'ИИИ', 'ИИТ', 'ИТУ', 'ИПТИП', 'ИТХТ', 'ИРИ', 'КПК', 'ПИШ', 'Фрязино',
      ]) {
        expect(shorts, contains(expected), reason: 'нет института «$expected»');
      }
      // этих подразделений в МИРЭА нет — они остались от чернового списка
      expect(shorts, isNot(contains('ИПМ')));
      expect(shorts, isNot(contains('ИЭП')));
    });

    test('у каждого института есть полное название', () {
      for (final i in Catalogs.institutes) {
        expect(i.title.trim(), isNotEmpty, reason: '${i.short}: пустое название');
        expect(i.title.length, greaterThan(i.short.length),
            reason: '${i.short}: название короче аббревиатуры');
      }
    });

    test('уровни обучения включают новые категории', () {
      final ids = Catalogs.levels.map((l) => l.id).toList();
      for (final expected in [
        'applicant', 'bachelor', 'specialist', 'master',
        'postgrad', 'graduate', 'teacher',
      ]) {
        expect(ids, contains(expected), reason: 'нет уровня «$expected»');
      }
    });

    test('подписи уровней не подставляют чужие значения', () {
      expect(Catalogs.levelTitle('applicant'), 'Абитуриент');
      expect(Catalogs.levelTitle('teacher'), 'Преподаватель');
      // неизвестный id не должен молча стать «Не важно»
      expect(Catalogs.levelTitle('нет-такого'), contains('не указан'));
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
    test('без URL PocketBase приложение сообщает об этом, а не падает', () {
      expect(PocketBaseConfig.isConfigured, isFalse,
          reason: 'в тестах URL не передаётся — так и должно быть');
    });

    test('значения из окружения очищаются от BOM и пробелов', () {
      const withBom = '\uFEFFhttps://example.com';
      const withSpaces = '  https://example.com\n';

      for (final raw in [withBom, withSpaces]) {
        final cleaned = raw.trim();
        expect(cleaned[0], 'h', reason: 'BOM и пробелы должны быть срезаны');
        expect(Uri.tryParse(cleaned)?.hasScheme, isTrue,
            reason: 'после очистки URL должен быть валидным');
      }
    });

    test('URL со BOM не проходит проверку конфигурации сам по себе', () {
      // Dart документирует, что trim() срезает BOM (U+FEFF, он же
      // ZERO WIDTH NO_BREAK SPACE) — см. lib/core/string.dart.
      // Поэтому проверка конфигурации обязана очищать значения: без trim()
      // строка непустая и «похожа на URL», но HTTP-клиент получит мусор
      // в начале адреса.
      const broken = '\uFEFFhttps://example.supabase.co';
      expect(broken.isNotEmpty, isTrue, reason: 'проверка isNotEmpty обманывается');
      expect(broken.codeUnitAt(0), 0xFEFF, reason: 'первый символ — BOM');
      expect(broken.trim().codeUnitAt(0), 'h'.codeUnitAt(0),
          reason: 'trim() обязан снять BOM');
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

  group('Лента', () {
    testWidgets('вкладки главной: Для вас / Все / От вуза / Партнёры',
        (tester) async {
      final c = await container(
        profile: const StudentProfile(completed: true, tags: ['it']),
        cache: [samplePost()],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();

      // Сегменты-вкладки встроены в закреплённую шапку главной.
      expect(find.text('Для вас'), findsOneWidget);
      expect(find.text('Все'), findsOneWidget);
      expect(find.text('От вуза'), findsOneWidget);
      expect(find.text('Партнёры'), findsOneWidget);
      expect(frameworkErrors, isEmpty, reason: '$frameworkErrors');
    });

    testWidgets('шапка главной закреплена: контент уезжает под неё',
        (tester) async {
      final base = DateTime(2026, 1, 1);
      final cache = [
        for (var i = 0; i < 20; i++)
          samplePost(
            id: 'p$i',
            title: 'Карточка $i',
            publishedAt: base.subtract(Duration(minutes: i)),
          ),
      ];

      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: cache,
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();

      // Заголовок и вкладки в закреплённом PersistentHeader: при скролле
      // их верхняя граница не уходит вверх.
      final header = find.byType(PinnedHeaderScreen);
      expect(header, findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Карточка 15'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(tester.getTopLeft(find.text('Для вас')).dy, lessThan(200));
      expect(frameworkErrors, isEmpty, reason: '$frameworkErrors');
    });

    testWidgets('на узком экране ничего не вылезает за границы', (tester) async {
      // Реальная ошибка раскладки: подсказка поиска и подписи в баннерах
      // были Text без Expanded/Flexible и переполняли строку на узком
      // экране — текст пропадал за краем. RenderFlex overflow теперь
      // должен валить тест, а не проходить незамеченным.
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [samplePost(title: 'Очень длинное название карточки для проверки')],
      );
      addTearDown(c.dispose);

      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();

      // ищем именно переполнение — прочие ошибки фреймворка не мешают
      final overflows =
          frameworkErrors.where((e) => e.contains('overflowed')).toList();
      expect(overflows, isEmpty, reason: 'переполнение раскладки: $overflows');
    });
  });

  group('Док', () {
    testWidgets('на iOS док стоит у нижнего края, а не в воздухе',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewPadding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.reset);

      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [samplePost()],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(
        wrap(c, const RootShell(), platform: TargetPlatform.iOS),
      );
      await tester.pump();

      final bottom = tester.getRect(find.byType(GlassDock)).bottom;
      // Нижний край дока на 22 pt выше низа экрана: чуть выше полоски
      // Home, но без прежнего парения в воздухе.
      expect(bottom, equals(844 - 22));
    });

    testWidgets('на Android док перекрывает панель навигации', (tester) async {
      // Кнопочная навигация — 48 pt, жестовая — 24 pt. Высота берётся из
      // системного inset, поэтому док не уезжает под кнопки ни на одном
      // из вариантов, а не только на «айфоновских» 34 pt.
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewPadding = const FakeViewPadding(bottom: 48);
      addTearDown(tester.view.reset);

      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [samplePost()],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();

      final dockBottom = tester.getRect(find.byType(GlassDock)).bottom;
      expect(
        dockBottom,
        lessThanOrEqualTo(915 - 48),
        reason: 'док ($dockBottom) уходит под кнопки навигации (867)',
      );
    });

    testWidgets('док не растянут на всю ширину экрана', (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final c = await container(profile: const StudentProfile(completed: true));
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();

      final capsule = find.byType(BackdropFilter);
      expect(capsule, findsOneWidget);

      final rect = tester.getRect(capsule);
      // жмётся под значки (5 кнопок), а не под экран
      expect(rect.width, lessThan(300), reason: 'док растянут: $rect');
      expect(rect.center.dx, moreOrLessEquals(430 / 2, epsilon: 1));
    });

    testWidgets('пункты дока не переполняются при выборе', (tester) async {
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [samplePost()],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();

      for (final icon in [
        Icons.apartment_rounded,
        Icons.bookmark_rounded,
        Icons.person_rounded,
        Icons.home_rounded,
      ]) {
        await tester.tap(find.byIcon(icon).last);
        await tester.pumpAndSettle();
        final overflows =
            frameworkErrors.where((e) => e.contains('overflowed')).toList();
        expect(overflows, isEmpty, reason: 'переполнение дока на $icon: $overflows');
      }
    });
    testWidgets('в доке только значки, без названий страниц', (tester) async {
      // Подписи раздували док и выталкивали соседние кнопки. Название
      // остаётся в Semantics для а11ы, но на экране его нет.
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [samplePost()],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();

      expect(find.text('Главная'), findsNothing);
      expect(find.text('Ещё'), findsNothing);

      final sem = tester.widget<Semantics>(
        find.descendant(
          of: find.byType(GlassDock),
          matching: find.byType(Semantics),
        ).first,
      );
      expect(sem.properties.label, isNotEmpty);
    });
  });

  group('Приоритетные карточки', () {
    testWidgets('приоритетная просто идёт первой, без меток и обводки',
        (tester) async {
      final base = DateTime(2026, 1, 1);
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [
          samplePost(id: 'a', title: 'Свежая обычная', publishedAt: base),
          samplePost(
            id: 'b',
            title: 'Старая приоритетная',
            featured: true,
            publishedAt: base.subtract(const Duration(days: 30)),
          ),
        ],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();

      expect(find.text('Старая приоритетная'), findsWidgets);
      expect(find.text('Свежая обычная'), findsOneWidget);

      // Приоритет — это только порядок: ни метки, ни звезды, ни особой
      // обводки на карточке нет.
      expect(find.text('Приоритет'), findsNothing);
      expect(find.text('Важное'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(HomeScreen),
          matching: find.byIcon(Icons.star_rounded),
        ),
        findsNothing,
      );
      expect(frameworkErrors, isEmpty, reason: '$frameworkErrors');
    });
  });

  group('Витрина главной', () {
    testWidgets('слайды не берутся из постов и живут отдельно',
        (tester) async {
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [
          samplePost(id: 'a', title: 'Обычный пост', featured: true),
        ],
      );
      addTearDown(c.dispose);
      // Слайд витрины — отдельная сущность, у него нет id поста.
      await c.read(localStoreProvider).saveSpotlightCache([
        {
          'id': 'b1',
          'title': 'Баннер витрины',
          'subtitle': 'Отдельный слайд',
          'image_url': null,
          'link_url': null,
          'sort_order': 1,
        },
      ]);
      c.invalidate(spotlightProvider);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();

      expect(find.text('Баннер витрины'), findsWidgets);
      // Бесконечный PageView держит текущего и соседних виртуальных соседей
      // смонтированными: один логический слайд повторяется в дереве.
      expect(find.text('Отдельный слайд'), findsWidgets);
      // Пост с приоритетом остаётся в ленте и НЕ становится слайдом.
      expect(find.text('Обычный пост'), findsOneWidget);
      expect(frameworkErrors, isEmpty, reason: '$frameworkErrors');
    });
  });

  group('Кнопка регистрации', () {
    testWidgets('в ленте её нет, на деталях — в конце контента', (tester) async {
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [
          samplePost(
            id: 'a',
            title: 'Стажировка с регистрацией',
            externalLink: 'https://example.com/apply',
            organization: {
              'id': 'org1',
              'name': 'Яндекс',
              'type': 'partner',
            },
          ),
        ],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();

      // В ленте кнопка занимала место и ровно там не нужна — карточка должна
      // оставаться компактной и вести на детали.
      expect(find.text('Регистрация'), findsNothing);
      expect(find.text('Стажировка с регистрацией'), findsOneWidget);

      await tester.tap(find.text('Стажировка с регистрацией'));
      await tester.pumpAndSettle();

      expect(find.text('Перейти к регистрации'), findsOneWidget);
      expect(frameworkErrors, isEmpty, reason: '$frameworkErrors');
    });
  });

  group('Карточка и детали', () {
    testWidgets('карточка: тип, организатор, дата, формат и срочность',
        (tester) async {
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [
          samplePost(
            title: 'Хакатон осенью',
            startDate: DateTime.now().add(const Duration(days: 1)),
            // Запас в часах: inDays округляет вниз, и ровно 3 суток,
            // отсчитанные до сборки виджета, успевали стать «2 дня».
            endDate: DateTime.now().add(const Duration(days: 3, hours: 2)),
            campuses: ['vernadsky78'],
          ),
        ],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Хакатон осенью'), findsOneWidget);
      // Тип — подписью, организация — отдельной строкой.
      expect(find.text('СОБЫТИЕ'), findsOneWidget);
      expect(find.text('Карьерный центр'), findsOneWidget);
      // Короткие факты: формат и кампус видны прямо в ленте.
      expect(find.text('Офлайн'), findsOneWidget);
      expect(find.text('Вернадского, 78'), findsOneWidget);
      // Дедлайн близко — плашка срочности с числом и правильной формой.
      expect(find.text('Осталось 3 дня'), findsOneWidget);
      // Кнопки избранного в карточке намеренно нет: сохранение живёт
      // в закреплённой шапке деталей, а в списке избранного — свайп.
      expect(find.byTooltip('В избранное'), findsNothing);
      expect(frameworkErrors, isEmpty, reason: '$frameworkErrors');
    });

    testWidgets('детали: панель «Ключевое» с подписями фактов',
        (tester) async {
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [
          samplePost(
            title: 'День карьеры',
            startDate: DateTime.now().add(const Duration(days: 1)),
            endDate: DateTime.now().add(const Duration(days: 40)),
            campuses: ['vernadsky78'],
            institutes: ['ikb'],
          ),
        ],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();
      await tester.tap(find.text('День карьеры'));
      await tester.pumpAndSettle();

      // Подписи фактов (рендерятся капсом) — главное отличие новой панели
      // от прежних обезличенных чипов.
      expect(find.text('КОГДА'), findsOneWidget);
      expect(find.text('ЗАКАНЧИВАЕТСЯ'), findsOneWidget);
      expect(find.text('ФОРМАТ'), findsOneWidget);
      expect(find.text('КАМПУС'), findsOneWidget);
      expect(find.text('ДЛЯ КОГО'), findsOneWidget);
      expect(find.text('Вернадского, 78'), findsWidgets);
      expect(find.text('ИКБ'), findsOneWidget);
      expect(frameworkErrors, isEmpty, reason: '$frameworkErrors');
    });

    testWidgets('детали: HTML описания не показывается тегами',
        (tester) async {
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [
          samplePost(
            title: 'Пост с разметкой',
            description:
                '<p>Первый абзац</p><p>Второй <strong>жирный</strong></p>',
          ),
        ],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();
      await tester.tap(find.text('Пост с разметкой'));
      await tester.pumpAndSettle();

      // Поле description в БД — editor (HTML): студент должен видеть текст,
      // а не разметку администратора.
      expect(find.text('Первый абзац'), findsOneWidget);
      expect(find.text('Второй жирный'), findsOneWidget);
      expect(find.textContaining('<p>'), findsNothing);
      expect(find.textContaining('<strong>'), findsNothing);
      expect(frameworkErrors, isEmpty, reason: '$frameworkErrors');
    });

    testWidgets('детали: кнопка действия видна без прокрутки', (tester) async {
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [
          samplePost(
            title: 'Стажировка с закреплённой кнопкой',
            externalLink: 'https://example.com/apply',
            // Длинное описание: раньше кнопка уезжала за несколько экранов.
            description: List.filled(12, 'Абзац про условия участия.').join('\n\n'),
          ),
        ],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();
      await tester.tap(find.text('Стажировка с закреплённой кнопкой'));
      await tester.pumpAndSettle();

      final button = find.text('Перейти к регистрации');
      expect(button, findsOneWidget);
      // Кнопка стоит в потоке сразу за блоком организатора — выше длинного
      // описания, поэтому видна на первом экране без прокрутки.
      final bottom = tester.getBottomLeft(button).dy;
      expect(bottom, lessThanOrEqualTo(tester.view.physicalSize.height /
              tester.view.devicePixelRatio +
          1));
      expect(frameworkErrors, isEmpty, reason: '$frameworkErrors');
    });
  });

  group('Профиль студента', () {
    testWidgets('открывается отдельной страницей и правится по строкам',
        (tester) async {
      final c = await container(profile: const StudentProfile(completed: true));
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();

      // док → «Ещё»
      await tester.tap(find.byIcon(Icons.person_rounded));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Профиль'));
      await tester.pumpAndSettle();

      expect(find.text('Институт'), findsOneWidget);
      expect(find.text('Уровень обучения'), findsOneWidget);
      expect(find.text('Интересы'), findsOneWidget);

      // строка открывается и выбранный институт сохраняется
      await tester.tap(find.text('Институт'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ИИТ'));
      await tester.pumpAndSettle();

      expect(c.read(profileProvider).institute, 'iit');
      expect(find.text('ИИТ'), findsOneWidget);
      expect(frameworkErrors, isEmpty, reason: '$frameworkErrors');
    });
  });

  group('Избранное', () {
    testWidgets('в избранном приоритетные не выделяются', (tester) async {
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [samplePost(id: 'a', title: 'Приоритетная', featured: true)],
      );
      addTearDown(c.dispose);

      await c.read(favoritesProvider.notifier).toggle('a');

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.bookmark_rounded).last);
      await tester.pumpAndSettle();

      // Карточка на месте и выглядит как любая другая: приоритет на ней
      // больше ничем не отмечен.
      expect(find.text('Приоритетная'), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(FavoritesScreen),
          matching: find.text('Приоритет'),
        ),
        findsNothing,
      );
    });
  });

  group('Прокрутка', () {
    testWidgets('избранное не листается за границы и без обновления',
        (tester) async {
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [samplePost()],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.bookmark_rounded).last);
      await tester.pumpAndSettle();

      // На избранном нет свайпа-обновления. Проверяем ВНУТРИ вкладки:
      // IndexedStack держит главную в дереве, и её RefreshIndicator
      // находился бы через глобальный поиск.
      expect(
        find.descendant(
          of: find.byType(FavoritesScreen),
          matching: find.byType(RefreshIndicator),
        ),
        findsNothing,
      );
      // …и прокрутка ограничена содержимым, а не отскакивает за края.
      final scroll = tester.widget<CustomScrollView>(
        find.descendant(
          of: find.byType(FavoritesScreen),
          matching: find.byType(CustomScrollView),
        ),
      );
      expect(scroll.physics, isA<ClampingScrollPhysics>());
    });

    testWidgets('на главной обновление жестом осталось', (tester) async {
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [samplePost()],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(HomeScreen),
          matching: find.byType(RefreshIndicator),
        ),
        findsOneWidget,
      );
      final scroll = tester.widget<CustomScrollView>(
        find.descendant(
          of: find.byType(HomeScreen),
          matching: find.byType(CustomScrollView),
        ),
      );
      expect(scroll.physics, isA<AlwaysScrollableScrollPhysics>());
    });

    testWidgets('организации обновляются жестом, как главная', (tester) async {
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [samplePost()],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.apartment_rounded).last);
      await tester.pumpAndSettle();

      final scroll = tester.widget<CustomScrollView>(
        find.descendant(
          of: find.byType(OrganizationsScreen),
          matching: find.byType(CustomScrollView),
        ),
      );
      expect(scroll.physics, isA<AlwaysScrollableScrollPhysics>());
    });
  });

  group('Поиск', () {
    testWidgets('клавиатура не вылезает сама и гасится при закрытии',
        (tester) async {
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [samplePost()],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();

      // закрытый поиск не строит поле вообще: иначе оно держало фокус и
      // клавиатура вылезала ещё на старте приложения
      expect(find.byType(TextField), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.testTextInput.isVisible, isTrue,
          reason: 'поле открылось, но клавиатура не поднялась');

      // Поле живёт под закреплённой шапкой (заголовок + safe area),
      // поэтому чуть ниже строки кнопок — но в пределах высоты шапки.
      final fieldTop = tester.getTopLeft(find.byType(TextField)).dy;
      final actionTop =
          tester.getTopLeft(find.byType(HeaderAction).first).dy;
      expect(fieldTop, greaterThanOrEqualTo(actionTop));
      expect(fieldTop, lessThanOrEqualTo(actionTop + 60));

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse,
          reason: 'клавиатура осталась висеть после закрытия поиска');
    });

    testWidgets('сабмит гасит клавиатуру, поле остаётся плавать',
        (tester) async {
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [samplePost()],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'хакатон');
      await tester.pumpAndSettle();

      // Сабмит (кнопка «Поиск» на клавиатуре): клавиатура уходит…
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      // …затемнение исчезло, а ПОЛЕ ОСТАЛОСЬ с текстом: из этого режима
      // выход только крестиком или возврат к вводу.
      expect(tester.testTextInput.isVisible, isFalse,
          reason: 'после сабмита клавиатура обязана уйти и не вернуться');
      expect(find.byType(TextField), findsOneWidget,
          reason: 'поле должно остаться плавать поверх ленты');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'хакатон',
      );
    });

    testWidgets('сабмит не поднимает клавиатуру обратно (мигание)',
        (tester) async {
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [samplePost()],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'стаж');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      // Несколько кадров подряд: клавиатура не должна «мигнуть» обратно
      // (прежний баг: затемнение убиралось из Stack → поле пересоздавалось
      // → autofocus снова поднимал клавиатуру).
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.testTextInput.isVisible, isFalse,
            reason: 'клавиатура мигнула обратно на кадре $i');
      }
    });
  });

  group('Организации', () {
    testWidgets('страница в доке: список и фильтр вуз/партнёры',
        (tester) async {
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [
          samplePost(
            id: 'a',
            title: 'Стажировка',
            organization: {
              'id': 'org1',
              'name': 'Яндекс',
              'type': 'partner',
              'description': 'Технологическая компания',
            },
          ),
          samplePost(
            id: 'b',
            title: 'Олимпиада',
            organizationId: 'org2',
            organization: {
              'id': 'org2',
              'name': 'Карьерный центр',
              'type': 'university_dept',
            },
          ),
        ],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.apartment_rounded));
      await tester.pumpAndSettle();

      // Организации приходят прямым запросом (не из ленты) — обе на месте.
      expect(find.text('Яндекс'), findsOneWidget);
      expect(find.text('Карьерный центр'), findsOneWidget);
      expect(find.text('Найдено организаций: 2'), findsOneWidget);

      // Фильтры — в bottom sheet: открываем кнопкой в шапке.
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      expect(find.text('ИСТОЧНИК'), findsOneWidget);

      // фильтр по партнёрам убирает подразделение вуза
      await tester.tap(find.text('Партнёры'));
      await tester.pump();
      await tester.tap(find.text('Показать'));
      await tester.pumpAndSettle();
      expect(find.text('Карьерный центр'), findsNothing);
      expect(find.text('Яндекс'), findsOneWidget);

      // тап ведёт в профиль организации
      await tester.tap(find.text('Яндекс'));
      await tester.pumpAndSettle();
      expect(find.text('Предложения'), findsOneWidget);
      expect(frameworkErrors, isEmpty, reason: '$frameworkErrors');
    });
  });

  group('Фильтры', () {
    testWidgets('фильтр-шторка открывается кнопкой в шапке главной',
        (tester) async {
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [samplePost()],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();

      // Шторка: сегмент актуальности и типы. Заголовок секции —
      // в верхнем регистре (CollapsibleSection делает toUpperCase).
      expect(find.text('АКТУАЛЬНОСТЬ'), findsOneWidget);
      expect(find.text('Актуальное'), findsOneWidget);
      expect(find.text('Архивное'), findsOneWidget);
      expect(find.text('ТИП'), findsOneWidget);
      expect(find.text('Показать'), findsOneWidget);
      expect(frameworkErrors, isEmpty, reason: '$frameworkErrors');
    });
  });

  group('Архив', () {
    testWidgets('открывается из «Ещё» отдельной страницей', (tester) async {
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [samplePost()],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.person_rounded).last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Архив'));
      await tester.pumpAndSettle();

      expect(find.text('Архив'), findsWidgets);
      // На архиве нет переключателя актуальности: архив принудителен.
      expect(find.text('АКТУАЛЬНОСТЬ'), findsNothing);
      expect(frameworkErrors, isEmpty, reason: '$frameworkErrors');
    });

    testWidgets('архив не ломает ленту главной при возврате', (tester) async {
      // Реальный баг: архив писал в общий feedNotifier архивный фильтр —
      // вернувшись на главную, пользователь видел пустой раздел (архивные
      // посты отсеивались фильтром актуальности) до переключения вкладки.
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [samplePost()],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();
      await tester.pumpAndSettle();

      // На главной лента построилась.
      expect(find.text('Осенняя ярмарка вакансий'), findsOneWidget);

      // Уходим в «Ещё» → Архив.
      await tester.tap(find.byIcon(Icons.person_rounded).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Архив'));
      await tester.pumpAndSettle();

      // Возвращаемся на главную (стеклянная кнопка «назад»).
      await tester.tap(find.byType(GlassBackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.home_rounded).last);
      await tester.pumpAndSettle();

      // Лента главной НЕ пострадала: карточка на месте без переключения
      // вкладок.
      expect(find.text('Осенняя ярмарка вакансий'), findsOneWidget,
          reason: 'архив затёр общее состояние ленты');
      expect(frameworkErrors, isEmpty, reason: '$frameworkErrors');
    });
  });

  group('Маршруты', () {
    testWidgets('на iOS маршрут интерактивный, на Android — системный',
        (tester) async {
      // iOS: свайп-назад от левого края умеет только CupertinoPageRoute.
      // Android: жест системный, принудительно его не включаем.
      // Платформу задаём явно: по умолчанию в тестах android, и iOS-ветка
      // никогда бы не проверялась.
      Future<Route<void>> routeFor(TargetPlatform platform) async {
        late Route<void> route;
        await tester.pumpWidget(MaterialApp(
          home: Theme(
            data: ThemeData(platform: platform),
            child: Builder(
              builder: (c) {
                route = appRoute<void>(c, const SizedBox());
                return const SizedBox();
              },
            ),
          ),
        ));
        return route;
      }

      expect(await routeFor(TargetPlatform.iOS),
          isA<CupertinoPageRoute<void>>());
      expect(await routeFor(TargetPlatform.android),
          isA<MaterialPageRoute<void>>());
    });
  });

  group('Профиль организации', () {
    testWidgets('открывается из деталей и показывает контакты и предложения',
        (tester) async {
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [
          samplePost(
            id: 'a',
            title: 'Стажировка в Яндексе',
            organization: {
              'id': 'org1',
              'name': 'Яндекс',
              'type': 'partner',
              'description': 'Технологическая компания',
              'website': 'https://yandex.ru/yaintern',
              'contact_email': 'interns@yandex-team.ru',
              'contact_name': 'Рекрутинг-команда',
            },
          ),
        ],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();

      // открываем детали
      await tester.tap(find.text('Стажировка в Яндексе'));
      await tester.pumpAndSettle();

      // организатор кликабелен и ведёт в профиль
      await tester.tap(find.text('Яндекс'));
      await tester.pumpAndSettle();

      expect(find.text('Организация'), findsOneWidget);
      expect(find.text('Предложения'), findsOneWidget);
      expect(find.text('Рекрутинг-команда'), findsOneWidget);
      expect(find.text('interns@yandex-team.ru'), findsOneWidget);
      // предложение организации видно в её профиле
      expect(find.text('Стажировка в Яндексе'), findsOneWidget);
      expect(frameworkErrors, isEmpty, reason: '$frameworkErrors');
    });
  });
}
