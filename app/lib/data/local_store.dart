import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Локальный профиль студента — результат онбординг-опроса.
/// Живёт ТОЛЬКО на устройстве: приложение работает без регистрации.
class StudentProfile {
  const StudentProfile({
    this.fullName,
    this.group,
    this.campus,
    this.institute,
    this.department,
    this.level,
    this.course,
    this.tags = const [],
    this.completed = false,
  });

  final String? fullName;
  final String? group;
  final String? campus;
  final String? institute;

  /// Кафедра (КБ-2, КБ-11…): уточняет подбор внутри института.
  final String? department;
  final String? level;

  /// Курс (1–6). Вычисляется из года поступления в номере группы
  /// (ИКБО-01-23 → 2023 → курс = текущий год − 2023 + 1), но студент
  /// может поправить вручную.
  final int? course;
  final List<String> tags;
  final bool completed;

  /// Есть ли хотя бы один настоящий ответ.
  ///
  /// Отдельно от [completed]: тот выставляется и при пропуске опроса,
  /// чтобы экран не показывался снова. Проверять «заполненность» по нему
  /// нельзя — интерфейс подписывал пустой профиль как заполненный.
  bool get hasAnswers =>
      fullName != null ||
      group != null ||
      institute != null ||
      level != null ||
      department != null ||
      course != null ||
      tags.isNotEmpty;

  /// Курс из номера группы: суффикс «-NN» после дефиса — год поступления.
  ///
  /// «БИСО-02-23» → 2023 → курс от сентября 2026 = 4. До сентября
  /// считается, что старший курс ещё не закончился. null — год не
  /// распознан (группы бывают без года: «АСП-1»).
  static int? courseFromGroup(String? group, {DateTime? now}) {
    if (group == null) return null;
    final m = RegExp(r'-(\d{2})$').firstMatch(group.trim());
    if (m == null) return null;
    final year = 2000 + int.parse(m.group(1)!);
    final today = now ?? DateTime.now();
    // Учебный год начинается 1 сентября: до него предыдущий курс ещё длится.
    final academicStart = DateTime(today.year, 9, 1);
    final elapsedYears =
        today.isBefore(academicStart) ? today.year - year : today.year - year + 1;
    if (elapsedYears < 1 || elapsedYears > 8) return null;
    return elapsedYears;
  }

  /// `copyWith` умеет и сбрасывать поле: передайте `null` явно через
  /// `clearCampus: true` (иначе, как обычно в Dart, null = «не менять»).
  StudentProfile copyWith({
    String? fullName,
    String? group,
    String? campus,
    String? institute,
    String? department,
    String? level,
    int? course,
    List<String>? tags,
    bool? completed,
    bool clearFullName = false,
    bool clearGroup = false,
    bool clearCampus = false,
    bool clearInstitute = false,
    bool clearDepartment = false,
    bool clearLevel = false,
    bool clearCourse = false,
  }) =>
      StudentProfile(
        fullName: clearFullName ? null : fullName ?? this.fullName,
        group: clearGroup ? null : group ?? this.group,
        campus: clearCampus ? null : campus ?? this.campus,
        institute: clearInstitute ? null : institute ?? this.institute,
        department: clearDepartment ? null : department ?? this.department,
        level: clearLevel ? null : level ?? this.level,
        course: clearCourse ? null : course ?? this.course,
        tags: tags ?? this.tags,
        completed: completed ?? this.completed,
      );

  Map<String, dynamic> toJson() => {
        'full_name': fullName,
        'group': group,
        'campus': campus,
        'institute': institute,
        'department': department,
        'level': level,
        'course': course,
        'tags': tags,
        'completed': completed,
      };

  static const empty = StudentProfile();

  factory StudentProfile.fromJson(Map<String, dynamic> j) => StudentProfile(
        fullName: j['full_name'] as String?,
        group: j['group'] as String?,
        campus: j['campus'] as String?,
        institute: j['institute'] as String?,
        department: j['department'] as String?,
        level: j['level'] as String?,
        course: (j['course'] as num?)?.toInt(),
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
  static const _kDeviceId = 'device_id';

  // ---------- Устройство ----------

  /// Анонимный идентификатор установки: случайная строка при первом
  /// запуске, дальше неизменна. Персональных данных нет — это «кто
  /// отправил» для ответов анкет и счётчиков, по нему админ видит дубли.
  String get deviceId {
    final existing = _prefs.getString(_kDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final generated = DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
        (DateTime.now().millisecondsSinceEpoch % 100000).toString();
    _prefs.setString(_kDeviceId, generated);
    return generated;
  }

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