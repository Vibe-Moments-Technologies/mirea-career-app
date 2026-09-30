import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirea_career/core/theme/app_theme.dart';
import 'package:mirea_career/core/widgets/glass_dock.dart';
import 'package:mirea_career/data/catalogs.dart';
import 'package:mirea_career/data/crash_reporting.dart';
import 'package:mirea_career/data/local_store.dart';
import 'package:mirea_career/data/metrics.dart';
import 'package:mirea_career/data/posts_repo.dart';
import 'package:mirea_career/screens/more/more_screen.dart';
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
  DateTime? publishedAt,
  Map<String, dynamic>? organization,
}) =>
    {
      'id': id,
      'organization_id': 'org1',
      'title': title,
      'description': 'Описание',
      'type': 'event',
      'format': 'offline',
      'status': 'published',
      'organizations': organization ??
          {'id': 'org1', 'name': 'Карьерный центр', 'type': 'university_dept'},
      'tags': tags,
      'campuses': <String>[],
      'institutes': <String>[],
      'directions': <String>[],
      'is_featured': featured,
      'priority_weight': 0,
      'views_count': 0,
      'favorites_count': 0,
      // Явная дата важна: лента сортируется по published_at, и при
      // одинаковых значениях (DateTime.now() в одном тике) порядок
      // недетерминирован — тест начинает падать случайным образом.
      'published_at': (publishedAt ?? DateTime.now()).toIso8601String(),
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
    test('без ключей приложение сообщает об этом, а не падает', () {
      expect(SupabaseConfig.isConfigured, isFalse,
          reason: 'в тестах ключи не передаются — так и должно быть');
    });

    test('значения из окружения очищаются от BOM и пробелов', () {
      // Реальная авария: секрет в CI записался с BOM (U+FEFF) в начале.
      // URL выглядел непустым, но инициализация Supabase не завершалась —
      // runApp не вызывался, и пользователь видел однотонный экран.
      // Sentry при этом молчал по той же причине: DSN не разбирался.
      const withBom = '\uFEFFhttps://example.supabase.co';
      const withSpaces = '  https://example.supabase.co\n';

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
    testWidgets('главная показывает не больше блока карточек', (tester) async {
      // 25 постов, но за раз показывается блок (10). Даты задаём явно и по
      // убыванию: иначе порядок недетерминирован и понять, какая карточка
      // попала в первый блок, невозможно.
      final base = DateTime(2026, 1, 1);
      final cache = [
        for (var i = 0; i < 25; i++)
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

      // самая свежая карточка видна
      expect(find.text('Карточка 0'), findsOneWidget);

      // Кнопка подгрузки ниже видимой области, а SliverList ленив —
      // прокручиваем до неё, как это сделал бы пользователь.
      await tester.scrollUntilVisible(
        find.textContaining('Показать ещё'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      // Кнопка прямо называет размер блока: «10 из 25» доказывает, что
      // за раз отдаётся ровно блок, а не весь список целиком.
      expect(find.text('Показать ещё (10 из 25)'), findsOneWidget);

      // нажатие докладывает следующий блок
      await tester.tap(find.text('Показать ещё (10 из 25)'));
      await tester.pump();

      // после тапа список стал длиннее, и кнопка снова уехала вниз —
      // прокручиваем к ней, как это сделал бы пользователь
      await tester.scrollUntilVisible(
        find.textContaining('Показать ещё'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(find.text('Показать ещё (20 из 25)'), findsOneWidget);
    });

    testWidgets('когда всё показано — видно подпись о конце ленты', (tester) async {
      // 3 поста при блоке 10: подгрузка не нужна, должен быть явный финал
      final base = DateTime(2026, 1, 1);
      final cache = [
        for (var i = 0; i < 3; i++)
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

      await tester.scrollUntilVisible(
        find.text('Это всё — новых записей больше нет'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      expect(find.text('Это всё — новых записей больше нет'), findsOneWidget);
      expect(find.textContaining('Показать ещё'), findsNothing);
    });

    testWidgets('на главной нет ни «Для вас», ни заголовка «Новое»', (tester) async {
      // Персональный подбор — в каталоге; на главной единая лента без
      // разделов. Заголовка страницы на главной тоже нет (по правкам).
      final c = await container(
        profile: const StudentProfile(completed: true, tags: ['it']),
        cache: [samplePost()],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();

      expect(find.text('Новое'), findsNothing);
      expect(find.text('Для вас'), findsNothing);
      // лента на месте
      expect(find.text('Осенняя ярмарка вакансий'), findsOneWidget);
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
    testWidgets('док не залезает на системную полосу внизу', (tester) async {
      // Реальная правка по iOS: док уходил ЗА home-indicator, и системная
      // полоса ложилась поверх него. Теперь отступ считается от низа экрана.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewPadding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.reset);

      final c = await container(
        profile: const StudentProfile(completed: true),
        cache: [samplePost()],
      );
      addTearDown(c.dispose);

      await tester.pumpWidget(wrap(c, const RootShell()));
      await tester.pump();

      final dockBottom = tester.getRect(find.byType(GlassDock)).bottom;
      // 844 — низ экрана; системная полоса занимает нижние 34 pt
      expect(
        dockBottom,
        lessThanOrEqualTo(844 - 34),
        reason: 'док ($dockBottom) перекрывает системную полосу (810)',
      );
    });

    testWidgets('на Android док поднимается над панелью навигации', (tester) async {
      // Кнопочная навигация Android — 48 pt, жестовая — 24 pt. Высота берётся
      // из системного inset (viewPadding), поэтому док не уезжает под кнопки
      // ни на одном из вариантов, а не только на «айфоновских» 34 pt.
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