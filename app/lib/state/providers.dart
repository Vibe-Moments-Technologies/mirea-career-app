import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/local_store.dart';
import '../data/metrics.dart';
import '../data/models.dart';
import '../data/posts_repo.dart';

/// LocalStore открывается один раз при старте (main переопределяет провайдер).
final localStoreProvider = Provider<LocalStore>((ref) => throw UnimplementedError());

/// Отправка счётчиков интереса (main переопределяет готовым экземпляром).
final metricsProvider = Provider<Metrics>((ref) => throw UnimplementedError());

/// true, если Supabase сконфигурирован (иначе показываем подсказку).
final supabaseConfiguredProvider = Provider<bool>((ref) => true);

final postsRepoProvider = Provider<PostsRepo>((ref) {
  return PostsRepo(Supabase.instance.client);
});

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

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => _decode(ref.watch(localStoreProvider).themeMode);

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

  FeedState copyWith({List<Post>? posts, bool? loading, bool? offline}) => FeedState(
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
    _init();
    return const FeedState();
  }

  Future<void> _init() async {
    final store = ref.read(localStoreProvider);

    // 1) мгновенно — кэш с диска
    final cached = store.feedCache;
    if (cached != null) {
      final posts = cached.map(Post.tryParse).whereType<Post>().toList();
      if (posts.isNotEmpty) state = state.copyWith(posts: posts);
    }
    await refresh();
    _subscribe();
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true);
    try {
      final posts = await ref.read(postsRepoProvider).fetchPublished();
      state = state.copyWith(posts: _applyDeltas(posts), loading: false, offline: false);
      await ref.read(localStoreProvider).saveFeedCache(posts.map((p) => p.toJson()).toList());
    } catch (_) {
      // нет сети — остаёмся на кэше, показываем баннер
      state = state.copyWith(loading: false, offline: true);
    }
  }

  /// Realtime: опубликованная в админке карточка появляется сама.
  /// Поток отдаёт полный снимок — просто заменяем список.
  void _subscribe() {
    ref.read(postsRepoProvider).watchPublished().listen((posts) {
      if (posts.isEmpty) return; // не затираем кэш пустотой от неудачной подписки
      state = state.copyWith(posts: _applyDeltas(posts), offline: false);
      ref.read(localStoreProvider).saveFeedCache(posts.map((p) => p.toJson()).toList());
    }, onError: (_) {/* realtime не критичен — есть pull-to-refresh */});
  }

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