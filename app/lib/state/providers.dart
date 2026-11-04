import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalogs.dart';
import '../data/form_history.dart';
import '../data/local_store.dart';
import '../data/metrics.dart';
import '../data/models.dart';
import '../data/posts_repo.dart';

/// LocalStore открывается один раз при старте (main переопределяет провайдер).
final localStoreProvider = Provider<LocalStore>((ref) => throw UnimplementedError());

/// История отправленных анкет из файла на устройстве
/// (main переопределяет провайдер после старта).
final formHistoryProvider = Provider<FormHistoryStore>((ref) => throw UnimplementedError());

/// Отправка счётчиков интереса (main переопределяет готовым экземпляром).
final metricsProvider = Provider<Metrics>((ref) => throw UnimplementedError());

/// true, если URL PocketBase передан при сборке (иначе показываем подсказку).
///
/// Это проверка КОНФИГУРАЦИИ СБОРКИ, а не сети: доступность API проверяется
/// в каждом запросе отдельно, и её сбой не должен мешать старту.
final backendConfiguredProvider = Provider<bool>((ref) => true);

/// Репозиторий карточек. Берётся из Metrics — единая точка доступа к данным:
/// лента открывается и без сети (кэш + офлайн-баннер), поэтому репозиторий
/// существует всегда, а не только при успешном старте.
final postsRepoProvider = Provider<PostsRepo>(
  (ref) => ref.watch(metricsProvider).repo,
);

// ---------------- Профиль студента ----------------

class ProfileNotifier extends Notifier<StudentProfile> {
  @override
  StudentProfile build() => ref.watch(localStoreProvider).profile;

  Future<void> save(StudentProfile p) async {
    await ref.read(localStoreProvider).saveProfile(p.copyWith(completed: true));
    state = ref.read(localStoreProvider).profile;
  }

  Future<void> reset() async {
    await ref.read(localStoreProvider).saveProfile(StudentProfile.empty);
    state = ref.read(localStoreProvider).profile;
  }
}

final profileProvider =
    NotifierProvider<ProfileNotifier, StudentProfile>(ProfileNotifier.new);

// ---------------- Чистка профиля от удалённых справочников ----------------

/// Вычищает из профиля значения, которых больше нет в справочниках.
///
/// Панель может удалить институт/уровень/тег из БД — профиль студента
/// хранит их коды локально и не узнает об удалении сам. Раз в старт
/// сверяем: исчезло — снимаем поле (институт/уровень) и выкидываем
/// теги. Сверка идёт по справочникам из БД, а офлайн — по запасу из
/// кода: удалённое в панели исчезнет из профиля при первом запуске
/// с сетью.
Future<StudentProfile> sanitizeProfileAgainstCatalogs(
  StudentProfile profile,
  PostsRepo repo,
) async {
  if (!profile.hasAnswers) return profile;

  final institutes = await repo.fetchInstitutes();
  final levels = await repo.fetchLevels();
  final interests = await repo.fetchInterests();

  // Пустые ответы БД = офлайн или пустые коллекции: сверять нечем,
  // поля не трогаем (запас ниже — источник не строгий).
  if (institutes.isEmpty && levels.isEmpty && interests.isEmpty) {
    return profile;
  }

  var changed = false;
  String? institute = profile.institute;
  String? level = profile.level;
  var tags = profile.tags;

  if (institute != null && institutes.isNotEmpty) {
    final alive = institutes.any((i) => i.code == institute);
    if (!alive) {
      institute = null;
      changed = true;
    }
  }
  if (level != null && levels.isNotEmpty) {
    final alive = levels.any((l) => l.code == level);
    if (!alive) {
      level = null;
      changed = true;
    }
  }
  if (interests.isNotEmpty && tags.isNotEmpty) {
    final kept = tags.where(interests.contains).toList();
    if (kept.length != tags.length) {
      tags = kept;
      changed = true;
    }
  }

  if (!changed) return profile;
  return profile.copyWith(
    clearInstitute: institute == null,
    institute: institute,
    clearLevel: level == null,
    level: level,
    tags: tags,
  );
}

// ---------------- Тема ----------------

/// Начальное значение темы, прочитанное при старте ДО первого кадра.
///
/// Провайдер темы всё равно читает то же хранилище, но строится уже после
/// первого кадра, и до этого `MaterialApp` рисовался светлой темой — на
/// тёмном телефоне это была белая вспышка. main() переопределяет значение
/// тем же чтением из LocalStore.
final initialThemeModeProvider = Provider<ThemeMode>((ref) => ThemeMode.system);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    // Значение со старта приоритетнее: оно прочитано из того же хранилища,
    // поэтому тема не «переключается» на глазах при первом кадре.
    final seeded = ref.watch(initialThemeModeProvider);
    if (seeded != ThemeMode.system) return seeded;
    return _decode(ref.watch(localStoreProvider).themeMode);
  }

  static ThemeMode _decode(String v) => switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _encode(ThemeMode m) => switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  Future<void> set(ThemeMode m) async {
    await ref.read(localStoreProvider).saveThemeMode(_encode(m));
    state = m;
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

// ---------------- Лента ----------------

/// Лента: сеть + кэш на диске. При офлайне показывается кэш.
class FeedState {
  const FeedState({this.posts = const [], this.loading = false, this.offline = false});
  final List<Post> posts;
  final bool loading;
  final bool offline;

  FeedState copyWith({List<Post>? posts, bool? loading, bool? offline}) =>
      FeedState(
        posts: posts ?? this.posts,
        loading: loading ?? this.loading,
        offline: offline ?? this.offline,
      );
}

class FeedNotifier extends Notifier<FeedState> {
  /// Счётчики, которые пользователь только что накрутил локально.
  /// Realtime-снимок приходит с сервера и затирает их — пока сервер не успел
  /// применить RPC. Держим дельты, чтобы не мигали цифры.
  final Map<String, int> _viewDelta = {};
  final Map<String, int> _favDelta = {};

  @override
  FeedState build() {
    // Главная теперь запрашивает ленту ПО ДЕЙСТВИЮ (feedQueryProvider) —
    // этот провайдер остаётся как «полный список» для избранного и
    // профилей организаций. Мгновенно отдаём кэш с диска; сеть трогаем
    // только при первом обращении экрана (ensureLoaded).
    final cached = ref.watch(localStoreProvider).feedCache;
    if (cached != null) {
      final posts = cached.map(Post.tryParse).whereType<Post>().toList();
      if (posts.isNotEmpty) return FeedState(posts: posts);
    }
    return const FeedState();
  }

  /// Загрузка при первом обращении (избранное, профиль организации).
  /// Повторные вызовы не ходят в сеть, пока её не попросили явно.
  Future<void> ensureLoaded() async {
    if (state.posts.isNotEmpty || state.loading) return;
    await refresh();
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true);
    try {
      final posts = await ref.read(postsRepoProvider).fetchPosts();
      if (!ref.mounted) return;
      // Не перезаписываем кэш пустым списком: если сервер вернул пусто
      // (офлайн, ошибка), оставляем старые данные и показываем offline-баннер.
      if (posts.isEmpty && state.posts.isNotEmpty) {
        state = state.copyWith(loading: false, offline: true);
        return;
      }
      state = state.copyWith(
        posts: _applyDeltas(posts),
        loading: false,
        offline: false,
      );
      await ref.read(localStoreProvider).saveFeedCache(posts.map((p) => p.toJson()).toList());
    } catch (_) {
      // нет сети — остаёмся на кэше, показываем баннер
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, offline: true);
    }
  }

  /// Realtime убран: PocketBase SSE требует авторизации, а pull-to-refresh
  /// достаточно для обновления ленты.

  /// Возвращает ленту с учётом локальных дельт счётчиков.
  List<Post> _applyDeltas(List<Post> posts) => [
        for (final p in posts)
          if (_viewDelta.containsKey(p.id) || _favDelta.containsKey(p.id))
            p.copyWith(
              viewsCount: p.viewsCount + (_viewDelta[p.id] ?? 0),
              favoritesCount: p.favoritesCount + (_favDelta[p.id] ?? 0),
            )
          else
            p,
      ];

  /// Локальный инкремент счётчика для мгновенной реакции интерфейса.
  void bumpViews(String postId) {
    _viewDelta[postId] = (_viewDelta[postId] ?? 0) + 1;
    state = state.copyWith(posts: _applyDeltas(state.posts));
  }

  void bumpFavorites(String postId, int delta) {
    _favDelta[postId] = (_favDelta[postId] ?? 0) + delta;
    state = state.copyWith(posts: _applyDeltas(state.posts));
  }
}

final feedProvider = NotifierProvider<FeedNotifier, FeedState>(FeedNotifier.new);

// ---------------- Организации ----------------

/// Список организаций: прямой запрос к коллекции, БЕЗ ленты.
///
/// Раньше собирался из постов (тяжёлый запрос с expand), из-за чего
/// страница организаций открывалась медленно. Теперь — лёгкий список
/// организаций одним запросом.
class OrgsState {
  const OrgsState({this.orgs = const [], this.loading = false, this.offline = false});
  final List<Organization> orgs;
  final bool loading;
  final bool offline;

  OrgsState copyWith({List<Organization>? orgs, bool? loading, bool? offline}) =>
      OrgsState(
        orgs: orgs ?? this.orgs,
        loading: loading ?? this.loading,
        offline: offline ?? this.offline,
      );
}

class OrganizationsNotifier extends Notifier<OrgsState> {
  @override
  OrgsState build() => const OrgsState();

  /// Загрузка при первом обращении (открытие вкладки организаций).
  Future<void> ensureLoaded() async {
    if (state.orgs.isNotEmpty || state.loading) return;
    await refresh();
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true);
    try {
      final orgs = await ref.read(postsRepoProvider).fetchOrganizations();
      if (!ref.mounted) return;
      if (orgs.isEmpty && state.orgs.isNotEmpty) {
        state = state.copyWith(loading: false, offline: true);
        return;
      }
      state = state.copyWith(orgs: orgs, loading: false, offline: false);
    } catch (_) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, offline: true);
    }
  }
}

final organizationsProvider = NotifierProvider<OrganizationsNotifier, OrgsState>(
    OrganizationsNotifier.new);

// ---------------- Витрина главной ----------------

/// Слайды витрины: отдельная сущность, которую наполняет администратор.
///
/// Раньше витрина собиралась из приоритетных постов, и баннер был обычной
/// карточкой с меткой — теперь это независимый список (`spotlight_banners`),
/// а приоритет влияет только на порядок в ленте.
class SpotlightNotifier extends Notifier<List<SpotlightBanner>> {
  @override
  List<SpotlightBanner> build() {
    final cached = ref.watch(localStoreProvider).spotlightCache;
    final initial = cached == null
        ? const <SpotlightBanner>[]
        : cached.map(SpotlightBanner.tryParse).whereType<SpotlightBanner>().toList();
    Future.microtask(refresh);
    return initial;
  }

  Future<void> refresh() async {
    try {
      final banners = await ref.read(postsRepoProvider).fetchSpotlight();
      if (!ref.mounted) return;
      // Пустой ответ не затираем: это может быть неудачная выборка, а не
      // «администратор всё удалил».
      if (banners.isEmpty && state.isNotEmpty) return;
      state = banners;
      await ref
          .read(localStoreProvider)
          .saveSpotlightCache(banners.map((b) => b.toJson()).toList());
    } catch (_) {
      // нет сети — остаёмся на кэше, витрина просто не обновится
    }
  }
}

final spotlightProvider =
    NotifierProvider<SpotlightNotifier, List<SpotlightBanner>>(SpotlightNotifier.new);

// ---------------- Интересы ----------------

/// Теги для онбординга из БД (коллекция interests, настраивается панелью).
///
/// Пусто (нет сети/коллекция пуста) — встроенный набор из Catalogs:
/// опрос не должен терять вопросы из-за недоступности БД.
final interestsProvider = FutureProvider<List<String>>((ref) async {
  final repo = ref.watch(postsRepoProvider);
  final remote = await repo.fetchInterests();
  return remote.isNotEmpty ? remote : Catalogs.interests.map((i) => i.title).toList();
});

// ---------------- Справочники онбординга ----------------

/// Справочники опроса из БД: институты (коллекция institutes) и уровни
/// (levels) настраиваются панелью, интересы — interestsProvider.
///
/// Пусто/офлайн — запас из Catalogs: вопросы не должны пропадать
/// из-за недоступности БД. Один провайдер на оба списка: они грузятся
/// вместе при показе опроса.
final onboardingCatalogProvider =
    FutureProvider<({List<InstituteRef> institutes, List<LevelRef> levels})>(
        (ref) async {
  final repo = ref.watch(postsRepoProvider);
  final remoteInstitutes = await repo.fetchInstitutes();
  final remoteLevels = await repo.fetchLevels();

  final institutes = remoteInstitutes.isNotEmpty
      ? remoteInstitutes
      : [
          for (final i in Catalogs.institutes)
            InstituteRef(code: i.id, title: i.title, short: i.short),
        ];
  final levels = remoteLevels.isNotEmpty
      ? remoteLevels
      : [for (final l in Catalogs.levels) LevelRef(code: l.id, title: l.title)];

  return (institutes: institutes, levels: levels);
});

// ---------------- Избранное ----------------

class FavoritesNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => ref.watch(localStoreProvider).favorites;

  /// Возвращает true, если пост добавлен в избранное.
  Future<bool> toggle(String postId) async {
    final store = ref.read(localStoreProvider);
    final added = await store.toggleFavorite(postId);
    state = store.favorites;
    ref.read(feedProvider.notifier).bumpFavorites(postId, added ? 1 : -1);
    return added;
  }
}

final favoritesProvider =
    NotifierProvider<FavoritesNotifier, List<String>>(FavoritesNotifier.new);

// ---------------- История анкет ----------------

/// Список отправленных анкет + уведомление UI о новых записях.
class FormHistoryNotifier extends Notifier<List<FormSubmission>> {
  @override
  List<FormSubmission> build() => ref.watch(formHistoryProvider).all;

  /// Записать отправленную анкету в файл и обновить состояние.
  Future<void> add(FormSubmission submission) async {
    await ref.read(formHistoryProvider).add(submission);
    state = ref.read(formHistoryProvider).all;
  }

  /// Есть ли отправка для поста. Реактивно: читает state (список),
  /// поэтому экран, построенный на watch, обновится сразу после add —
  /// без перезахода на карточку.
  FormSubmission? forPost(String postId) {
    for (final s in state) {
      if (s.postId == postId) return s;
    }
    return null;
  }

  /// Опросы без поста (раздел «Опросы»): история по formId.
  FormSubmission? forForm(String formId) {
    for (final s in state) {
      if (s.formId == formId) return s;
    }
    return null;
  }
}

final formSubmissionsProvider =
    NotifierProvider<FormHistoryNotifier, List<FormSubmission>>(
        FormHistoryNotifier.new);

/// Есть ли отправленная анкета у поста — для watch в виджетах:
/// `ref.watch(hasSubmittedProvider(postId))`. Обновляется сразу после
/// отправки (add меняет state), экрану не нужен перезаход.
final hasSubmittedProvider = Provider.family<bool, String>(
  (ref, postId) => ref
      .watch(formSubmissionsProvider)
      .any((s) => s.postId == postId),
);

/// Отвечал ли студент на форму (по formId): опросы раздела «Опросы»
/// живут без поста — блокировка повторного входа идёт по форме.
final hasSubmittedFormProvider = Provider.family<bool, String>(
  (ref, formId) => ref
      .watch(formSubmissionsProvider)
      .any((s) => s.formId == formId),
);

/// Опросы раздела «Опросы» (forms.kind = survey/anon_survey):
/// список с ленты главной, обновляется pull-to-refresh.
final surveyFormsProvider =
    FutureProvider<List<FormDefinition>>((ref) async {
  return ref.watch(postsRepoProvider).fetchSurveyForms();
});