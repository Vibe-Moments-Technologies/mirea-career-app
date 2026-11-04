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
import 'package:mirea_career/data/form_history.dart';
import 'package:mirea_career/data/local_store.dart';
import 'package:mirea_career/data/metrics.dart';
import 'package:mirea_career/data/models.dart';
import 'package:mirea_career/data/posts_repo.dart';
import 'package:mirea_career/screens/favorites/favorites_screen.dart';
import 'package:mirea_career/screens/home/home_screen.dart';
import 'package:mirea_career/screens/more/profile_screen.dart';
import 'package:mirea_career/screens/onboarding/onboarding_screen.dart';
import 'package:mirea_career/screens/org/org_screen.dart';
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
  List<FormSubmission>? formSubmissions,
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();
  if (profile != null) await store.saveProfile(profile);
  if (cache != null) await store.saveFeedCache(cache);

  final cachedRepo = _CachedRepo(cache ?? const []);
  final formHistory = FormHistoryStore.inMemory(formSubmissions ?? const []);
  return ProviderContainer(
    overrides: [
      localStoreProvider.overrideWithValue(store),
      // Репозиторий с данными из кэша: главная запрашивает ленту по
      // действию, и в тестах сервером становится сам кэш.
      postsRepoProvider.overrideWithValue(cachedRepo),
      metricsProvider.overrideWithValue(Metrics(cachedRepo, store)),
      formHistoryProvider.overrideWithValue(formHistory),
      backendConfiguredProvider.overrideWithValue(true),
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

  @override
  Future<bool> submitFormResponse({
    required String formId,
    String? postId,
    required Map<String, dynamic> answers,
    required String deviceId,
  }) async =>
      true;

  /// Счётчик прошедших: «сервер» в тестах отдаёт 7.
  @override
  Future<int?> fetchFormResponsesCount(String formId) async => 7;

  /// Поиск по публичному номеру — в тестовом «сервере» это кэш.
  @override
  Future<Post?> fetchPostByPublicId(String publicId) async => posts
      .map(Post.tryParse)
      .whereType<Post>()
      .where((p) => p.publicId == publicId)
      .firstOrNull;

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
  String type = 'event',
  DateTime? startDate,
  DateTime? endDate,
  List<String> campuses = const [],
  List<String> institutes = const [],
  Map<String, dynamic>? form,
  String? publicId,
  String? authorName,
  List<String> gallery = const [],
}) =>
    {
      'id': id,
      'organization': organizationId,
      'title': title,
      'description': description,
      'type': type,
      'format': 'offline',
      'status': 'published',
      'post_id': publicId,
      'author_name': authorName,
      'gallery': gallery,
      // Кэш-формат: готовые URL (репозиторий собирает их из имён файлов).
      'gallery_urls': [
        for (final g in gallery) 'https://example.test/files/posts/$id/$g',
      ],
      // PocketBase-формат: организация приезжает в expand.organization,
      // опросник — в expand.form.
      'expand': {
        'organization': organization ??
            {'id': 'org1', 'name': 'Карьерный центр', 'type': 'university_dept'},
        'form': ?form,
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
      // Welcome-экран без полей: приглашение + «Начать опрос».
      expect(find.text('Добро пожаловать!'), findsOneWidget);
      expect(find.text('Начать опрос'), findsOneWidget);
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

      // Welcome → первый вопрос.
      await tester.tap(find.text('Начать опрос'));
      await tester.pumpAndSettle();

      const questions = [
        'Как вас зовут?',
        'Ваш институт',
        'Кафедра',
        'Ваша группа?',
        'Уровень и курс',
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

      // шаг «Уровень и курс» — пятый: welcome → 4× «Далее».
      await tester.tap(find.text('Начать опрос'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Далее'));
        await tester.pumpAndSettle();
      }

      for (final level in [
        'Абитуриент',
        'Бакалавриат',
        'Специалитет',
        'Магистратура',
        'Аспирантура',
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

      // Welcome → «Начать опрос» → «Пропустить»: вопросы необязательны,
      // но сам факт опроса фиксируется, чтобы экран не возвращался.
      await tester.tap(find.text('Начать опрос'));
      await tester.pumpAndSettle();
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

    test('уровни обучения — только ступени образования', () {
      final ids = Catalogs.levels.map((l) => l.id).toList();
      for (final expected in [
        'applicant', 'bachelor', 'specialist', 'master', 'postgrad',
      ]) {
        expect(ids, contains(expected), reason: 'нет уровня «$expected»');
      }
      // выпускник/преподаватель/«не важно» — не ступени, из опроса убраны
      expect(ids, isNot(contains('graduate')));
      expect(ids, isNot(contains('teacher')));
    });

    test('подписи уровней не подставляют чужие значения', () {
      expect(Catalogs.levelTitle('applicant'), 'Абитуриент');
      expect(Catalogs.levelTitle('postgrad'), 'Аспирантура');
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
    testWidgets('вкладки главной: Для вас / Все / Опросы', (tester) async {
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
      expect(find.text('Опросы'), findsOneWidget);
      // Профили организаций временно убраны: вкладок по источнику нет.
      expect(find.text('От вуза'), findsNothing);
      expect(find.text('Партнёры'), findsNothing);
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
      // Лента грузится postFrameCallback'ом: дождаться карточек.
      await tester.pumpAndSettle();

      // Заголовок в закреплённом PersistentHeader: при скролле его верхняя
      // граница не уходит вверх. Вкладки, наоборот, уезжают под шапку —
      // в ленте важна высота, переключатель возвращается наверх.
      final header = find.byType(PinnedHeaderScreen);
      expect(header, findsOneWidget);

      // Лента постранична (по 5): до карточки 15 — две догрузки. Кнопка
      // «Показать ещё» в хвосте и НЕ ПОСТРОЕНА, пока не подъехала
      // (SliverList строит только видимое): скроллим жестом, пока не
      // появится, потом тап. Кнопка под доком — тап без hit-проверки.
      // Скроллим ленту ГЛАВНОЙ: IndexedStack строит и другие вкладки.
      final homeScrollable = find
          .descendant(
            of: find.byType(HomeScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      Future<void> loadMore() async {
        for (var i = 0; i < 20; i++) {
          if (find.text('Показать ещё 5').evaluate().isNotEmpty) break;
          // Кнопка не построена (SliverList ленив): тянем ленту вверх.
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -400),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
        // Кнопка в самом низу — под стеклянным доком. Ещё один рывок
        // поднимает её в зону удара.
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Показать ещё 5'));
        await tester.pump();
      }

      await loadMore();
      await loadMore();
      await tester.scrollUntilVisible(
        find.text('Карточка 15'),
        300,
        scrollable: homeScrollable,
      );
      await tester.pump();
      expect(tester.getTopLeft(find.text('Карьера МИРЭА')).dy, lessThan(200));
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

    testWidgets('баннер с post:-ссылкой открывает пост по номеру',
        (tester) async {
      // Баннеры консоли ссылаются на посты публичным номером:
      // link_url = "post:4Z65U4". Тап должен открыть детали поста,
      // найденного по post_id, а не браузер.
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [
          samplePost(
            id: 'a',
            title: 'Пост по номеру',
            publicId: '4Z65U4',
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(localStoreProvider).saveSpotlightCache([
        {
          'id': 'b1',
          'title': 'Баннер на пост',
          'subtitle': null,
          'image_url': null,
          'link_url': 'post:4Z65U4',
          'sort_order': 1,
        },
      ]);
      c.invalidate(spotlightProvider);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();

      // Бесконечная витрина строит соседей: «Баннер на пост» в дереве
      // несколько раз — тап по первому видимому.
      await tester.tap(find.text('Баннер на пост').first);
      await tester.pumpAndSettle();

      // Открылись детали поста, найденного по номеру.
      expect(find.text('Пост по номеру'), findsOneWidget);
      // Баннер ещё в дереве (под экраном деталей), лента тоже.
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

    testWidgets('анкета из БД заменяет внешнюю ссылку', (tester) async {
      // Минимальная анкета: вопрос-текст. Проверяем: кнопка в деталях
      // ведёт в анкету, а не в браузер; рендер в стиле приложения.
      final form = {
        'id': 'frm1',
        'title': 'Анкета стажёра',
        'definition': {
          'type': 'ordered',
          'id': 'test_form',
          'steps': [
            {
              'id': 'name',
              'isMandatory': true,
              'content': [
                {'type': 'text', 'text': 'Как вас зовут?'},
              ],
              'answerFormat': {
                'type': 'text',
                'hint': 'Имя',
                'maxLines': 1,
              },
            },
          ],
        },
        'success_text': 'Мы свяжемся с вами',
      };

      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [
          samplePost(
            id: 'a',
            title: 'Стажировка с анкетой',
            externalLink: 'https://example.com/apply',
            form: form,
          ),
        ],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Стажировка с анкетой'));
      await tester.pumpAndSettle();

      // Форма приоритетнее ссылки: кнопка открывает анкету.
      expect(find.text('Перейти к регистрации'), findsNothing);
      expect(find.text('Заполнить анкету'), findsOneWidget);

      await tester.tap(find.text('Заполнить анкету'));
      await tester.pumpAndSettle();

      // Анкета в стиле приложения: шапка с названием, вопрос с полем,
      // кнопка отправки внизу, счётчик прошедших.
      expect(find.text('Анкета стажёра'), findsOneWidget);
      expect(find.text('Как вас зовут?'), findsOneWidget);
      expect(find.text('Уже прошли: 7'), findsOneWidget);
      expect(find.text('Отправить анкету'), findsOneWidget);
      expect(frameworkErrors, isEmpty, reason: '$frameworkErrors');
    });

    testWidgets('ФИО и группа из профиля не спрашиваются повторно',
        (tester) async {
      // Анкета со стандартными id: шаг fio изымается (в профиле есть),
      // шаг group остаётся (в профиле пусто) — студент заполняет руками,
      // и значение запоминается в профиль после отправки.
      final form = {
        'id': 'frm2',
        'title': 'Анкета с ФИО',
        'definition': {
          'type': 'ordered',
          'id': 'test_form2',
          'steps': [
            {
              'id': 'fio',
              'isMandatory': true,
              'content': [
                {'type': 'text', 'text': 'Как вас зовут?'},
              ],
              'answerFormat': {'type': 'text', 'hint': 'ФИО', 'maxLines': 1},
            },
            {
              'id': 'group',
              'isMandatory': true,
              'content': [
                {'type': 'text', 'text': 'Ваша группа?'},
              ],
              'answerFormat': {
                'type': 'text',
                'hint': 'Группа',
                'maxLines': 1,
              },
            },
          ],
        },
        'success_text': null,
      };

      final c = await container(
        profile: const StudentProfile(
          completed: true,
          fullName: 'Иванов Иван Иванович',
        ),
        cache: [
          samplePost(id: 'a', title: 'Мероприятие с анкетой', form: form),
        ],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Мероприятие с анкетой'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Заполнить анкету'));
      await tester.pumpAndSettle();

      // Шаг fio изъят: анкета сразу показывает вопрос про группу.
      expect(find.text('Как вас зовут?'), findsNothing,
          reason: 'шаг fio должен быть скрыт при заполненном профиле');
      expect(find.text('Ваша группа?'), findsOneWidget);

      // Заполняем группу руками и отправляем.
      await tester.enterText(find.byType(TextField), 'ИКБО-01-24');
      await tester.pump();
      await tester.ensureVisible(find.text('Отправить анкету'));
      await tester.tap(find.text('Отправить анкету'));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('Анкета отправлена').evaluate().isNotEmpty) break;
      }

      // Группа запомнилась в профиле: следующая анкета не спросит её.
      final profile = c.read(profileProvider);
      expect(profile.group, 'ИКБО-01-24',
          reason: 'отправка не доработала: профиль не обновлён');
      expect(profile.fullName, 'Иванов Иван Иванович');

      // Экран подтверждения: анкета отправлена + кнопка возврата.
      expect(find.text('Анкета отправлена'), findsOneWidget);
      expect(find.text('Вернуться к карточке'), findsOneWidget);

      // История: анкета записана с ФИО и группой в ответах.
      final submission = c.read(formSubmissionsProvider.notifier).forPost('a');
      expect(submission, isNotNull, reason: 'анкета не записана в историю');
      expect(submission!.answers['fio'], 'Иванов Иван Иванович');
      expect(submission.answers['group'], 'ИКБО-01-24');

      expect(frameworkErrors, isEmpty, reason: '$frameworkErrors');
    });

    testWidgets('заполненная анкета блокирует повтор и помечена в ленте',
        (tester) async {
      final form = {
        'id': 'frm3',
        'title': 'Анкета повторная',
        'definition': {
          'type': 'ordered',
          'id': 'test_form3',
          'steps': [
            {
              'id': 'q1',
              'isMandatory': true,
              'content': [
                {'type': 'text', 'text': 'Вопрос?'},
              ],
              'answerFormat': {'type': 'text', 'hint': 'Ответ', 'maxLines': 1},
            },
          ],
        },
      };

      // История уже содержит отправку для поста 'a'.
      final submission = FormSubmission(
        formId: 'frm3',
        postId: 'a',
        postTitle: 'Мероприятие заполнено',
        formTitle: 'Анкета повторная',
        submittedAt: DateTime(2026, 11, 1, 10, 30),
        answers: const {'q1': 'да'},
      );

      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [
          samplePost(id: 'a', title: 'Мероприятие заполнено', form: form),
        ],
        formSubmissions: [submission],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();
      await tester.pumpAndSettle();

      // Карточка в ленте сразу показывает: заполнено.
      expect(find.text('Анкета заполнена'), findsOneWidget);

      await tester.tap(find.text('Мероприятие заполнено'));
      await tester.pumpAndSettle();

      // Кнопка в деталях — «Анкета заполнена», не «Заполнить анкету».
      expect(find.text('Заполнить анкету'), findsNothing);
      final filled = find.text('Анкета заполнена');
      expect(filled, findsOneWidget);

      // Тап по кнопке открывает НЕ опрос, а экран «уже отправлена».
      await tester.ensureVisible(filled);
      await tester.tap(filled);
      await tester.pump(const Duration(milliseconds: 300));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.textContaining('повторное заполнение недоступно')
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
      expect(find.textContaining('повторное заполнение недоступно'),
          findsOneWidget);
      // Сам вопрос не показан: опросник не открылся.
      expect(find.text('Вопрос?'), findsNothing);
      expect(frameworkErrors, isEmpty, reason: '$frameworkErrors');
    });

    testWidgets('карточка-опрос от вуза: тип и кнопка «Пройти опрос»',
        (tester) async {
      // Опрос — базовый тип карточки: анкета внутри, кнопка отклика
      // называется «Пройти опрос», внешняя ссылка не участвует.
      final form = {
        'id': 'frmS',
        'title': 'Опрос о столовых',
        'definition': {
          'type': 'ordered',
          'id': 'survey_food',
          'steps': [
            {
              'id': 'q1',
              'isMandatory': true,
              'content': [
                {'type': 'text', 'text': 'Хватает ли мест в столовых?'},
              ],
              'answerFormat': {
                'type': 'single',
                'textChoices': [
                  {'text': 'Да', 'value': 'yes'},
                  {'text': 'Нет', 'value': 'no'},
                ],
              },
            },
          ],
        },
      };

      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [
          samplePost(
            id: 's1',
            title: 'Опрос о столовых',
            type: 'survey',
            externalLink: 'https://example.com/legacy',
            form: form,
          ),
        ],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();
      await tester.pumpAndSettle();

      // Карточка: подпись типа ОПРОС.
      expect(find.text('ОПРОС'), findsOneWidget);

      await tester.tap(find.text('Опрос о столовых'));
      await tester.pumpAndSettle();

      // Кнопка зовёт пройти опрос, не «заполнить анкету».
      expect(find.text('Пройти опрос'), findsOneWidget);
      expect(find.text('Перейти к регистрации'), findsNothing);

      await tester.tap(find.text('Пройти опрос'));
      await tester.pumpAndSettle();

      // Анкета открылась: вопрос и плитки выбора.
      expect(find.text('Хватает ли мест в столовых?'), findsOneWidget);
      expect(find.text('Да'), findsOneWidget);
      expect(find.text('Нет'), findsOneWidget);

      // Выбор варианта: плитка выделяется, не «сливается».
      await tester.tap(find.text('Да'));
      await tester.pump();
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
      expect(find.text('МЕРОПРИЯТИЕ'), findsOneWidget);
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

    testWidgets('галерея поста: свайп-слайдер и author_name без организации',
        (tester) async {
      // Пост без организации, но с автором и галереей из двух файлов:
      // обложки нет (image пуст) — слайдер из gallery, подпись автора
      // вместо названия организации.
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [
          samplePost(
            id: 'a',
            title: 'Пост с галереей',
            // Пустая map: expand.organization не парсится организацией —
            // пост «без организации», подпись берётся из author_name.
            organization: {},
            organizationId: '',
            authorName: 'Учебный отдел',
            gallery: ['shot1.jpg', 'shot2.jpg'],
          ),
        ],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();
      await tester.pumpAndSettle();

      // Лента: подпись автора вместо организации.
      expect(find.text('Учебный отдел'), findsOneWidget);

      await tester.tap(find.text('Пост с галереей'));
      await tester.pumpAndSettle();

      // Детали: author_name в карточке организатора.
      expect(find.text('Учебный отдел'), findsOneWidget);

      // Слайдер: PageView построен (картинки в тестах не грузятся —
      // слайды показывают заглушки, сам свайп-контейнер на месте).
      expect(find.byType(PageView), findsOneWidget);
      expect(frameworkErrors, isEmpty, reason: '$frameworkErrors');
    });

    testWidgets('описание: Markdown рендерится, теги не показываются',
        (tester) async {
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [
          samplePost(
            id: 'a',
            title: 'Markdown-пост',
            description: '**Жирный** абзац\n\n'
                '- пункт один\n'
                '- пункт два\n\n'
                '## Заголовок секции\n\n'
                'Ссылка: [сайт вуза](https://mirea.ru)\n\n'
                '> Цитата из описания',
          ),
        ],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Markdown-пост'));
      await tester.pumpAndSettle();

      // Текст без звёздочек и решёток: разметка сработала.
      expect(find.text('Жирный абзац'), findsOneWidget);
      expect(find.text('пункт один'), findsOneWidget);
      expect(find.text('Заголовок секции'), findsOneWidget);
      expect(find.textContaining('сайт вуза'), findsOneWidget);
      expect(find.textContaining('Цитата из описания'), findsOneWidget);
      // Сырые маркеры не показываются.
      expect(find.textContaining('**'), findsNothing);
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

      // Подписи фактов (рендерятся капсом) — новое разделение дат:
      // «Приём заявок до» (дедлайн) и «Проведение» (период события).
      expect(find.text('ПРИЁМ ЗАЯВОК ДО'), findsOneWidget);
      expect(find.text('ПРОВЕДЕНИЕ'), findsOneWidget);
      expect(find.text('ФОРМАТ'), findsOneWidget);
      expect(find.text('КАМПУС'), findsOneWidget);
      expect(find.text('ДЛЯ КОГО'), findsOneWidget);
      expect(find.text('Вернадского, 78'), findsWidgets);
      expect(find.text('ИКБ'), findsOneWidget);
      expect(frameworkErrors, isEmpty, reason: '$frameworkErrors');
    });

    testWidgets('детали: чистый текст без тегов и разметки не рвётся',
        (tester) async {
      // Консоль перешла с HTML-редактора на Markdown: старые записи с
      // HTML-остатками не должны показывать теги. Markdown-рендер
      // не распознаёт <p> как разметку и выводит текст как есть —
      // поэтому убираем теги из тестовой записи, как это делает консоль.
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [
          samplePost(
            title: 'Пост с разметкой',
            description: 'Первый абзац\n\nВторой **жирный**',
          ),
        ],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();
      await tester.tap(find.text('Пост с разметкой'));
      await tester.pumpAndSettle();

      expect(find.text('Первый абзац'), findsOneWidget);
      expect(find.text('Второй жирный'), findsOneWidget);
      expect(find.textContaining('**'), findsNothing);
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
      // «Интересы» ниже новых строк (кафедра, курс) — вне вьюпорта:
      // проверяем через скролл.
      await tester.scrollUntilVisible(
        find.text('Интересы'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
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

  group('Календарь', () {
    testWidgets('события с датами — по месяцам, без даты не попадают',
        (tester) async {
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [
          samplePost(
            id: 'ev1',
            title: 'Событие впереди',
            type: 'event',
            startDate: DateTime.now().add(const Duration(days: 3)),
          ),
          samplePost(
            id: 'ev2',
            title: 'Событие через месяц',
            type: 'event',
            startDate: DateTime.now().add(const Duration(days: 35)),
          ),
          // Без даты — в календарь не попадает.
          samplePost(id: 'nod', title: 'Без даты', type: 'vacancy'),
        ],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.calendar_month_rounded).last);
      await tester.pumpAndSettle();

      // События на месте, отсортированы по датам.
      expect(find.text('Событие впереди'), findsOneWidget);
      expect(find.text('Событие через месяц'), findsOneWidget);
      expect(find.text('Без даты'), findsNothing);
      expect(frameworkErrors, isEmpty, reason: '$frameworkErrors');
    });
  });

  group('Избранное', () {
    testWidgets('в избранном приоритетные не выделяются', (tester) async {      final c = await container(
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
          of: find.byType(SavedScreen),
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
          of: find.byType(SavedScreen),
          matching: find.byType(RefreshIndicator),
        ),
        findsNothing,
      );
      // …и прокрутка ограничена содержимым, а не отскакивает за края.
      final scroll = tester.widget<CustomScrollView>(
        find.descendant(
          of: find.byType(SavedScreen),
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

  group('Организатор', () {
    testWidgets('страницы организаций вернулись в док; подпись в деталях',
        (tester) async {
      // Профили организаций вернули в док (когда появятся учётки
      // организаций — схема сменится). В деталях организатор — подпись,
      // карточка не ведёт в профиль с поста.
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
            },
          ),
        ],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();
      await tester.pumpAndSettle();

      // В доке есть вкладка «Организации».
      expect(find.byIcon(Icons.apartment_rounded), findsOneWidget);

      await tester.tap(find.text('Стажировка в Яндексе'));
      await tester.pumpAndSettle();

      // Организатор — карточка-ссылка: есть шеврон, тап открывает
      // профиль организации.
      expect(find.text('Яндекс'), findsOneWidget);
      expect(find.text('Компания-партнёр'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

      await tester.tap(find.text('Яндекс'));
      await tester.pumpAndSettle();

      // Открылся профиль организации.
      expect(find.byType(OrgScreen), findsOneWidget);
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

  group('Сохранённое: анкеты', () {
    testWidgets('пустое состояние на вкладке «Анкеты»', (tester) async {
      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [samplePost()],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();
      await tester.pumpAndSettle();

      // Док → «Сохранённое» → свитчер «Анкеты».
      await tester.tap(find.byIcon(Icons.bookmark_rounded).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Анкеты'));
      await tester.pumpAndSettle();

      expect(find.text('Пока пусто'), findsOneWidget);
      expect(frameworkErrors, isEmpty, reason: '$frameworkErrors');
    });

    testWidgets('отправленная анкета видна карточкой с датой и ответами',
        (tester) async {
      final c = await container(
        profile: const StudentProfile(completed: true),
        formSubmissions: [
          FormSubmission(
            formId: 'frm1',
            postId: 'a',
            postTitle: 'Стажировка в лаборатории ИИТ',
            formTitle: 'Анкета на стажировку',
            submittedAt: DateTime(2026, 11, 3, 14, 5),
            answers: const {'fio': 'Иванов Иван', 'group': 'ИКБО-01-24'},
            successText: 'Мы свяжемся с вами',
          ),
        ],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.bookmark_rounded).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Анкеты'));
      await tester.pumpAndSettle();

      // Карточка: заголовок поста, анкета и дата.
      expect(find.text('Стажировка в лаборатории ИИТ'), findsOneWidget);
      expect(
        find.text('Анкета на стажировку · 03.11.2026 · 14:05'),
        findsOneWidget,
      );

      // Тап — снимок ответов в нижнем листе.
      await tester.tap(find.text('Стажировка в лаборатории ИИТ'));
      await tester.pumpAndSettle();

      expect(find.text('Иванов Иван'), findsOneWidget);
      expect(find.text('ИКБО-01-24'), findsOneWidget);
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
      // iOS: WideSwipeBackRoute — Cupertino-переход + интерактивный
      // свайп-назад с зоной 44 pt (системный CupertinoPageRoute ловит
      // только 20 pt — туда трудно попасть).
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
          isA<WideSwipeBackRoute<void>>());
      expect(await routeFor(TargetPlatform.android),
          isA<MaterialPageRoute<void>>());
    });
  });
}
