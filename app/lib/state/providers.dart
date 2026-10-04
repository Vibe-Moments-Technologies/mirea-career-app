import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../data/metrics.dart';
import '../data/models.dart';
import '../data/posts_repo.dart';

/// LocalStore открывается один раз при старте (main переопределяет провайдер).
final localStoreProvider = Provider<LocalStore>((ref) => throw UnimplementedError());

/// Отправка счётчиков интереса (main переопределяет готовым экземпляром).
final metricsProvider = Provider<Metrics>((ref) => throw UnimplementedError());

/// true, если PocketBase сконфигурирован (иначе показываем подсказку).
final supabaseConfiguredProvider = Provider<bool>((ref) => true);

/// Репозиторий карточек. Берётся из Metrics — тем самым исключается
/// обращение к Supabase.instance напрямую: она существует только при
/// успешной инициализации, а лента должна открываться и без неё
/// (офлайн, тестовая сборка без ключей, недоступная сеть).
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