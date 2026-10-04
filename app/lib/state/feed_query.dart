import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import 'providers.dart';

/// Лента по запросу: данные запрашиваются у PocketBase только по действию
/// пользователя (открытие вкладки, применение фильтров, pull-to-refresh),
/// а не выкачиваются целиком на старте.
///
/// [FeedQuery] — параметры запроса: вкладка + фильтры. Одинаковые параметры
/// не перезапускают запрос (проверка ==).
@immutable
class FeedQuery {
  const FeedQuery({
    this.tab = 'foryou',
    this.filters = const FeedFiltersLite(),
  });

  /// 'foryou' | 'all' | 'university' | 'partner'
  final String tab;
  final FeedFiltersLite filters;

  @override
  bool operator ==(Object other) =>
      other is FeedQuery && other.tab == tab && other.filters == filters;

  @override
  int get hashCode => Object.hash(tab, filters);
}

/// Упрощённые фильтры ленты — то, что реально уходит в запрос PocketBase.
/// Поиск, вкладки и типы фильтруются на сервере.
@immutable
class FeedFiltersLite {
  const FeedFiltersLite({
    this.query = '',
    this.types = const {},
    this.showArchived = false,
  });

  final String query;
  final Set<String> types;
  final bool showArchived;

  @override
  bool operator ==(Object other) =>
      other is FeedFiltersLite &&
      other.query == query &&
      other.types.length == types.length &&
      other.types.containsAll(types) &&
      other.showArchived == showArchived;

  @override
  int get hashCode => Object.hash(query, Object.hashAllUnordered(types), showArchived);
}

/// Состояние ленты для конкретного запроса.
@immutable
class FeedViewState {
  const FeedViewState({
    this.posts = const [],
    this.loading = false,
    this.offline = false,
    this.exhausted = false,
  });

  final List<Post> posts;
  final bool loading;
  final bool offline;

  /// Дальше страниц нет: для «Для вас» это повод показать CTA «Открыть все».
  final bool exhausted;

  FeedViewState copyWith({
    List<Post>? posts,
    bool? loading,
    bool? offline,
    bool? exhausted,
  }) =>
      FeedViewState(
        posts: posts ?? this.posts,
        loading: loading ?? this.loading,
        offline: offline ?? this.offline,
        exhausted: exhausted ?? this.exhausted,
      );
}

/// Нотификатор ленты с запросом по действию.
///
/// `feedQueryProvider` хранит текущие параметры (вкладка+фильтры).
/// [load] вызывается при их изменении; одинаковый запрос не повторяется.
class FeedQueryNotifier extends Notifier<FeedQuery> {
  @override
  FeedQuery build() => const FeedQuery();

  void set(FeedQuery q) {
    state = q;
    // Загрузку запускает только сам feedNotifier (см. load): он один
    // решает, повторять ли запрос, — иначе guard в двух местах путается.
    ref.read(feedNotifierProvider.notifier).load(q);
  }
}

final feedQueryProvider =
    NotifierProvider<FeedQueryNotifier, FeedQuery>(FeedQueryNotifier.new);

class FeedQueryFeedNotifier extends Notifier<FeedViewState> {
  /// Последний успешно выполненный запрос: guard от повторов.
  /// null = ни один запрос ещё не выполнялся.
  FeedQuery? _lastLoaded;
  int _seq = 0;

  @override
  FeedViewState build() => const FeedViewState();

  /// Загружает ленту под запрос. Вызывается ТОЛЬКО по действию
  /// пользователя (смена вкладки/фильтра, поиск, обновление).
  Future<void> load(FeedQuery q) async {
    // null — запросов ещё не было; дефолтный FeedQuery при первом открытии
    // главной обязан загрузить данные, поэтому == недостаточно.
    if (_lastLoaded == q) return;
    _lastLoaded = q;
    final seq = ++_seq;
    state = state.copyWith(loading: true, posts: []);
    try {
      final result = await ref.read(postsRepoProvider).fetchFeed(
            tab: q.tab,
            query: q.filters.query,
            types: q.filters.types,
            showArchived: q.filters.showArchived,
            profile: q.tab == 'foryou' ? ref.read(profileProvider) : null,
          );
      if (!ref.mounted || seq != _seq) return;
      state = FeedViewState(
        posts: result,
        loading: false,
        offline: false,
        exhausted: true, // PocketBase отдал всё по этому фильтру (perPage=200)
      );
    } catch (_) {
      if (!ref.mounted || seq != _seq) return;
      state = state.copyWith(loading: false, offline: true, exhausted: true);
    }
  }

  /// Принудительное обновление (pull-to-refresh).
  Future<void> refresh() async {
    _lastLoaded = null;
    await load(ref.read(feedQueryProvider));
  }
}

final feedNotifierProvider =
    NotifierProvider<FeedQueryFeedNotifier, FeedViewState>(
        FeedQueryFeedNotifier.new);
