import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Локальный профиль студента — результат онбординг-опроса.
/// Живёт ТОЛЬКО на устройстве: приложение работает без регистрации.
class StudentProfile {
  const StudentProfile({
    this.campus,
    this.institute,
    this.level,
    this.tags = const [],
    this.completed = false,
  });

  final String? campus;
  final String? institute;
  final String? level;
  final List<String> tags;
  final bool completed;

  /// Есть ли хотя бы один настоящий ответ.
  ///
  /// Отдельно от [completed]: тот выставляется и при пропуске опроса,
  /// чтобы экран не показывался снова. Проверять «заполненность» по нему
  /// нельзя — интерфейс подписывал пустой профиль как заполненный.
  bool get hasAnswers =>
      institute != null || level != null || tags.isNotEmpty;

  /// `copyWith` умеет и сбрасывать поле: передайте `null` явно через
  /// `clearCampus: true` (иначе, как обычно в Dart, null = «не менять»).
  StudentProfile copyWith({
    String? campus,
    String? institute,
    String? level,
    List<String>? tags,
    bool? completed,
    bool clearCampus = false,
    bool clearInstitute = false,
    bool clearLevel = false,
  }) =>
      StudentProfile(
        campus: clearCampus ? null : campus ?? this.campus,
        institute: clearInstitute ? null : institute ?? this.institute,
        level: clearLevel ? null : level ?? this.level,
        tags: tags ?? this.tags,
        completed: completed ?? this.completed,
      );

  Map<String, dynamic> toJson() =>
      {'campus': campus, 'institute': institute, 'level': level, 'tags': tags, 'completed': completed};

  static const empty = StudentProfile();

  factory StudentProfile.fromJson(Map<String, dynamic> j) => StudentProfile(
        campus: j['campus'] as String?,
        institute: j['institute'] as String?,
        level: j['level'] as String?,
        tags: (j['tags'] as List?)?.cast<String>() ?? const [],
        completed: j['completed'] as bool? ?? false,
      );
}

/// Ожидающий отправки инкремент счётчика (офлайн-очередь).
class PendingMetric {
  const PendingMetric(this.kind, this.postId, [this.delta = 1]);
  final String kind; // 'view' | 'favorite'
  final String postId;
  final int delta;

  Map<String, dynamic> toJson() => {'kind': kind, 'post_id': postId, 'delta': delta};

  factory PendingMetric.fromJson(Map<String, dynamic> j) =>
      PendingMetric(j['kind'] as String, j['post_id'] as String, j['delta'] as int? ?? 1);
}

/// Всё локальное состояние студента в одном месте.
///
/// `shared_preferences` достаточно: профиль + список UUID + JSON-кэш ленты.
/// ponytail: без БД на устройстве; если кэш ленты вырастет или понадобится
/// сложный офлайн-запрос — перейти на Isar (docs/ARCHITECTURE.md §1).
class LocalStore {
  LocalStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<LocalStore> open() async => LocalStore(await SharedPreferences.getInstance());

  static const _kProfile = 'profile';
  static const _kFavorites = 'favorites';
  static const _kViewed = 'viewed_ids';
  static const _kPending = 'pending_metrics';
  static const _kFeedCache = 'feed_cache';
  static const _kTheme = 'theme_mode';
  static const _kCatalog = 'catalog_state';
  static const _kSpotlight = 'spotlight_cache';
  static const _kDoh = 'doh_enabled';

  // ---------- Профиль ----------
  StudentProfile get profile {
    final raw = _prefs.getString(_kProfile);
    if (raw == null) return StudentProfile.empty;
    return StudentProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveProfile(StudentProfile p) => _prefs.setString(_kProfile, jsonEncode(p.toJson()));

  // ---------- Тема ----------
  /// 'system' | 'light' | 'dark'
  String get themeMode => _prefs.getString(_kTheme) ?? 'system';
  Future<void> saveThemeMode(String mode) => _prefs.setString(_kTheme, mode);

  // ---------- DNS-over-HTTPS ----------
  /// Использовать ли DoH (Comss DNS) вместо системного DNS.
  ///
  /// В РФ провайдеры блокируют/замедляют DNS для некоторых доменов
  /// (*.supabase.co). DoH обходит эту блокировку. По умолчанию выключено:
  /// в большинстве стран системный DNS работает нормально.
  bool get dohEnabled => _prefs.getBool(_kDoh) ?? false;
  Future<void> saveDohEnabled(bool value) => _prefs.setBool(_kDoh, value);

  // ---------- Состояние каталога (фильтры, вкладка, сортировка) ----------

  Map<String, dynamic>? get catalogState {
    final raw = _prefs.getString(_kCatalog);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> saveCatalogState(Map<String, dynamic> value) =>
      _prefs.setString(_kCatalog, jsonEncode(value));

  // ---------- Кэш витрины главной ----------
  //
  // Витрина — отдельная сущность (не посты), поэтому и кэш свой: она должна
  // показываться офлайн при запуске, ещё до первого запроса.
  List<Map<String, dynamic>>? get spotlightCache {
    final raw = _prefs.getString(_kSpotlight);
    if (raw == null) return null;
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> saveSpotlightCache(List<Map<String, dynamic>> banners) =>
      _prefs.setString(_kSpotlight, jsonEncode(banners));

  // ---------- Избранное ----------
  List<String> get favorites => _prefs.getStringList(_kFavorites) ?? const [];
  bool isFavorite(String postId) => favorites.contains(postId);

  /// Возвращает новый статус: true — добавлен, false — удалён.
  Future<bool> toggleFavorite(String postId) async {
    final list = [...favorites];
    final added = !list.remove(postId);
    if (added) list.insert(0, postId); // новые сверху
    await _prefs.setStringList(_kFavorites, list);
    return added;
  }

  // ---------- Просмотры (дедупликация: 1 просмотр на устройство) ----------
  List<String> get viewedIds => _prefs.getStringList(_kViewed) ?? const [];

  /// true, если просмотр нужно засчитать (впервые видим этот пост).
  Future<bool> markViewedIfNew(String postId) async {
    final list = [...viewedIds];
    if (list.contains(postId)) return false;
    list.add(postId);
    await _prefs.setStringList(_kViewed, list);
    return true;
  }

  // ---------- Очередь счётчиков (офлайн) ----------
  List<PendingMetric> get pendingMetrics {
    final raw = _prefs.getString(_kPending);
    if (raw == null) return const [];
    return (jsonDecode(raw) as List)
        .map((e) => PendingMetric.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> queueMetric(PendingMetric m) => _prefs.setString(
        _kPending,
        jsonEncode([...pendingMetrics.map((e) => e.toJson()), m.toJson()]),
      );

  Future<void> clearPendingMetrics() => _prefs.remove(_kPending);

  // ---------- Кэш ленты (мгновенный старт без сети) ----------
  List<Map<String, dynamic>>? get feedCache {
    final raw = _prefs.getString(_kFeedCache);
    if (raw == null) return null;
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> saveFeedCache(List<Map<String, dynamic>> posts) =>
      _prefs.setString(_kFeedCache, jsonEncode(posts));

  // ---------- Сброс ----------
  Future<void> reset() async {
    for (final k in [_kProfile, _kFavorites, _kViewed, _kPending, _kFeedCache, _kCatalog, _kSpotlight]) {
      await _prefs.remove(k);
    }
  }
}