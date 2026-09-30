import '../data/models.dart';
import '../data/local_store.dart';

/// Состояние фильтров каталога и ленты. Всё — клиентская фильтрация:
/// лента вуза целиком помещается в память.
/// ponytail: при росте каталога (>~1000 постов) перенести в RPC/View
/// с пагинацией (docs/ARCHITECTURE.md §3).
class FeedFilters {
  const FeedFilters({
    this.query = '',
    this.types = const {},
    this.campus,
    this.institute,
    this.format,
    this.organizationId,
    this.tags = const {},
    this.source, // null = все, 'university_dept' | 'partner'
    this.onlyUpcoming = false,
    this.sortByPopularity = false,
  });

  final String query;
  final Set<String> types;
  final String? campus;
  final String? institute;
  final String? format;
  final String? organizationId;
  final Set<String> tags;
  final String? source;
  final bool onlyUpcoming;
  final bool sortByPopularity;

  int get activeCount =>
      (query.isEmpty ? 0 : 1) +
      types.length +
      tags.length +
      (campus != null ? 1 : 0) +
      (institute != null ? 1 : 0) +
      (format != null ? 1 : 0) +
      (organizationId != null ? 1 : 0);

  FeedFilters copyWith({
    String? query,
    Set<String>? types,
    Object? campus = _unset,
    Object? institute = _unset,
    Object? format = _unset,
    Object? organizationId = _unset,
    Set<String>? tags,
    Object? source = _unset,
    bool? onlyUpcoming,
    bool? sortByPopularity,
  }) =>
      FeedFilters(
        query: query ?? this.query,
        types: types ?? this.types,
        campus: campus == _unset ? this.campus : campus as String?,
        institute: institute == _unset ? this.institute : institute as String?,
        format: format == _unset ? this.format : format as String?,
        organizationId:
            organizationId == _unset ? this.organizationId : organizationId as String?,
        tags: tags ?? this.tags,
        source: source == _unset ? this.source : source as String?,
        onlyUpcoming: onlyUpcoming ?? this.onlyUpcoming,
        sortByPopularity: sortByPopularity ?? this.sortByPopularity,
      );

  static const _unset = Object();

  FeedFilters cleared() => FeedFilters(source: source);
}

/// Применяет фильтры к ленте. Чистая функция — тестируется без сети.
List<Post> applyFilters(List<Post> posts, FeedFilters f, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final q = f.query.trim().toLowerCase();

  final out = posts.where((p) {
    if (f.source != null && p.organizationType != f.source) return false;
    if (f.types.isNotEmpty && !f.types.contains(p.type)) return false;
    if (f.format != null && p.format != f.format) return false;
    if (f.organizationId != null && p.organizationId != f.organizationId) return false;
    if (f.campus != null && !p.matchesCampus(f.campus)) return false;
    if (f.institute != null && !p.matchesInstitute(f.institute)) return false;
    if (f.tags.isNotEmpty && !f.tags.any(p.tags.contains)) return false;
    if (f.onlyUpcoming) {
      final d = p.eventDate;
      if (d != null && d.isBefore(DateTime(today.year, today.month, today.day))) return false;
    }
    if (q.isNotEmpty) {
      final haystack = '${p.title} ${p.tags.join(' ')} ${p.organizationName ?? ''}'.toLowerCase();
      if (!haystack.contains(q)) return false;
    }
    return true;
  }).toList();

  out.sort((a, b) {
    if (f.sortByPopularity) {
      final c = b.viewsCount.compareTo(a.viewsCount);
      if (c != 0) return c;
    }
    // по дате события (бездатные — в конец), затем по весу приоритета
    final ad = a.eventDate, bd = b.eventDate;
    if (ad != null && bd != null) {
      final c = ad.compareTo(bd);
      if (c != 0) return c;
    } else if (ad != null) {
      return -1;
    } else if (bd != null) {
      return 1;
    }
    return b.priorityWeight.compareTo(a.priorityWeight);
  });
  return out;
}

/// Веса скоринга «Для вас» (docs/ARCHITECTURE.md §3).
class ScoreWeights {
  const ScoreWeights({this.campus = 3, this.institute = 3, this.tag = 2, this.targetAll = 1});
  final int campus;
  final int institute;
  final int tag;
  final int targetAll;
}

/// Скоринг релевантности. Полностью локальный: профиль не покидает устройство.
int scoreFor(Post p, StudentProfile profile, {ScoreWeights w = const ScoreWeights()}) {
  var score = p.priorityWeight;
  if (profile.campus != null && p.campuses.contains(profile.campus)) score += w.campus;
  if (profile.institute != null && p.institutes.contains(profile.institute)) {
    score += w.institute;
  }
  score += w.tag * profile.tags.where(p.tags.contains).length;
  if (p.campuses.isEmpty && p.institutes.isEmpty) score += w.targetAll;
  return score;
}

/// Посты для секции «Для вас»: сначала релевантные, затем остальные.
/// Профиль не пройден — секция пустая (экран покажет плейсхолдер).
List<Post> forYou(List<Post> posts, StudentProfile profile, {int limit = 10}) {
  if (!profile.completed) return const [];
  final scored = posts.map((p) => (p, scoreFor(p, profile))).toList();
  scored.sort((a, b) {
    final c = b.$2.compareTo(a.$2);
    if (c != 0) return c;
    return (b.$1.publishedAt ?? DateTime(0)).compareTo(a.$1.publishedAt ?? DateTime(0));
  });
  final relevant = scored.where((e) => e.$2 > 0).map((e) => e.$1).toList();
  return relevant.take(limit).toList();
}

/// Приоритетные карточки (is_featured) — вверх, порядок внутри групп
/// сохраняется.
///
/// Именно разбиение, а не `sort`: сортировка в Dart НЕ стабильная, и посты
/// с одинаковым признаком «приходили бы в случайном порядке» — в избранном
/// это ломало «сначала недавно добавленные», в каталоге — порядок фильтра.
List<Post> priorityFirst(List<Post> posts) => [
      for (final p in posts.where((p) => p.isFeatured)) p,
      for (final p in posts.where((p) => !p.isFeatured)) p,
    ];

/// Лента главной: приоритетное + подходящее по профилю + свежее — одним
/// списком (docs/UI.md §4).
///
/// Порядок слагаемых совпадает с приоритетом:
///   1. is_featured — метка главного модератора, всегда сверху;
///   2. релевантность профилю (scoreFor) — институт, теги, приоритетный вес;
///   3. новизна — при равных остальных.
///
/// Featured НЕ исключаются из ленты (как раньше, где карусель их «съедала»):
/// карусель сверху остаётся витриной, но пост должен оставаться доступным
/// и в общем потоке — иначе пользователь, пропустивший карусель, его не найдёт.
List<Post> homeFeed(List<Post> posts, StudentProfile profile) {
  final scored = posts.map((p) => (p, scoreFor(p, profile))).toList();
  scored.sort((a, b) {
    // 1) приоритетное — всегда выше
    if (a.$1.isFeatured != b.$1.isFeatured) return a.$1.isFeatured ? -1 : 1;
    // 2) релевантность профилю
    final c = b.$2.compareTo(a.$2);
    if (c != 0) return c;
    // 3) свежее — выше
    return (b.$1.publishedAt ?? DateTime(0)).compareTo(a.$1.publishedAt ?? DateTime(0));
  });
  return scored.map((e) => e.$1).toList();
}