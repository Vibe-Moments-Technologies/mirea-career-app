import 'dart:convert';

import 'app_http_client.dart';
import 'local_store.dart';
import 'models.dart';

/// Доступ к данным через PocketBase REST API.
///
/// Анонимный доступ: API rules на стороне PocketBase отдают только
/// published посты и активные баннеры. Авторизация не нужна для чтения.
class PostsRepo {
  PostsRepo(this._baseUrl);

  /// Репозиторий без сети: все запросы возвращают пустые списки.
  PostsRepo.offline() : _baseUrl = '';

  final String _baseUrl;

  bool get isOffline => _baseUrl.isEmpty;

  /// Лента главной: вкладка + поиск + типы, всё фильтруется на сервере.
  ///
  /// Вызывается ПО ДЕЙСТВИЮ пользователя (смена вкладки, поиск, фильтр),
  /// а не при старте. perPage=200 — вся выборка вуза одним запросом;
  /// постраничную пагинацию добавим при росте каталога.
  Future<List<Post>> fetchFeed({
    String tab = 'foryou',
    String query = '',
    Set<String> types = const {},
    bool showArchived = false,
    StudentProfile? profile,
  }) async {
    if (isOffline) return const [];

    final filters = <String>['status="published"', 'published_at<=@now'];

    // Архив: end_date < now, иначе: end_date >= now или пусто.
    // @now БЕЗ кавычек — иначе PocketBase сравнивает как строку.
    if (showArchived) {
      filters.add('end_date<@now');
    } else {
      filters.add('(end_date>@now||end_date="")');
    }

    if (tab == 'university') {
      filters.add('organization.type="university_dept"');
    } else if (tab == 'partner') {
      filters.add('organization.type="partner"');
    }

    if (types.isNotEmpty) {
      // Проверено на живом API: multiple ?= с запятой НЕ работает,
      // работает только OR из отдельных условий.
      filters.add('(${types.map((t) => 'type="${t.replaceAll('"', '')}"').join(' || ')})');
    }

    final q = query.trim();
    if (q.isNotEmpty) {
      final e = q.replaceAll('"', '');
      filters.add('(title~"$e" || description~"$e" || organization.name~"$e")');
    }

    final filterStr = filters.join('&&');
    final url = '$_baseUrl/api/collections/posts/records'
        '?filter=${Uri.encodeComponent(filterStr)}'
        '&expand=organization'
        '&sort=-published_at'
        '&perPage=200';

    final bytes = await AppHttpClient.instance.fetchBytes(url);
    if (bytes == null) return const [];

    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final items = json['items'] as List<dynamic>? ?? [];
      var posts = items.map(_parsePost).whereType<Post>().toList();

      if (tab == 'foryou' && profile != null) {
        posts = _sortForYou(posts, profile);
      }
      // Приоритетные — вверх списка везде, КРОМЕ архива.
      if (!showArchived) {
        posts = _priorityFirst(posts);
      }
      return posts;
    } catch (_) {
      return const [];
    }
  }

  /// Посты одной организации: для её страницы профиля.
  ///
  /// Актуальные и приоритетные сверху — как в ленте.
  Future<List<Post>> fetchPosts({String? organizationId}) async {
    if (isOffline) return const [];

    final filters = <String>[
      'status="published"',
      'published_at<=@now',
      // только актуальные: страница организации — не архив
      '(end_date>@now||end_date="")',
      if (organizationId != null) 'organization="$organizationId"',
    ];

    final filterStr = filters.join('&&');
    final url = '$_baseUrl/api/collections/posts/records'
        '?filter=${Uri.encodeComponent(filterStr)}'
        '&expand=organization'
        '&sort=-published_at'
        '&perPage=100';

    final bytes = await AppHttpClient.instance.fetchBytes(url);
    if (bytes == null) return const [];

    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final items = json['items'] as List<dynamic>? ?? [];
      return _priorityFirst(items.map(_parsePost).whereType<Post>().toList());
    } catch (_) {
      return const [];
    }
  }

  /// Список организаций: отдельный запрос, а не сборка из ленты.
  Future<List<Organization>> fetchOrganizations() async {
    if (isOffline) return const [];

    final url = '$_baseUrl/api/collections/organizations/records'
        '?filter=type!="hidden"'
        '&sort=name'
        '&perPage=100';

    final bytes = await AppHttpClient.instance.fetchBytes(url);
    if (bytes == null) return const [];

    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final items = json['items'] as List<dynamic>? ?? [];
      return items
          .map((e) {
            if (e is! Map) return null;
            final org = Organization.tryParse(e);
            if (org == null) return null;
            // logo_url из прямой выборки — имя файла, не полный URL
            final logo = e['logo_url'];
            if (org.logoUrl != null && logo is String && logo.isNotEmpty) {
              return Organization(
                id: org.id,
                name: org.name,
                type: org.type,
                description: org.description,
                logoUrl: '$_baseUrl/api/files/organizations/${org.id}/$logo',
                website: org.website,
                contactEmail: org.contactEmail,
                contactPhone: org.contactPhone,
                contactName: org.contactName,
              );
            }
            return org;
          })
          .whereType<Organization>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Персональная сортировка: релевантность профилю.
  List<Post> _sortForYou(List<Post> posts, StudentProfile profile) {
    final scored = posts.map((p) => (p, _scoreFor(p, profile))).toList();
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.map((e) => e.$1).toList();
  }

  /// Скоринг поста под профиль.
  int _scoreFor(Post p, StudentProfile profile) {
    var score = 0;
    if (profile.institute != null && p.institutes.contains(profile.institute)) {
      score += 10;
    }
    if (profile.tags.isNotEmpty) {
      final overlap = p.tags.where(profile.tags.contains).length;
      score += overlap * 5;
    }
    if (p.institutes.isEmpty && p.campuses.isEmpty) {
      score += 3; // для всех
    }
    return score;
  }

  /// Приоритетные посты — вверх списка.
  List<Post> _priorityFirst(List<Post> posts) {
    final featured = posts.where((p) => p.isFeatured).toList();
    final normal = posts.where((p) => !p.isFeatured).toList();
    return [...featured, ...normal];
  }

  /// Слайды витрины главной.
  Future<List<SpotlightBanner>> fetchSpotlight() async {
    if (isOffline) return const [];

    final url = '$_baseUrl/api/collections/spotlight_banners/records'
        '?filter=is_active=true'
        '&sort=sort_order'
        '&perPage=20';

    final bytes = await AppHttpClient.instance.fetchBytes(url);
    if (bytes == null) return const [];

    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final items = json['items'] as List<dynamic>? ?? [];
      return items.map(_parseBanner).whereType<SpotlightBanner>().toList();
    } catch (_) {
      return const [];
    }
  }

  /// Инкремент счётчика просмотров.
  Future<void> incrementViews(String postId) async {
    if (isOffline) return;
    // TODO: PATCH views_count+1 через API
  }

  Future<void> modifyFavorites(String postId, int delta) async {
    if (isOffline) return;
    // TODO: PATCH favorites_count+delta через API
  }

  // ---------- Парсинг ----------

  Post? _parsePost(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final title = json['title'];
    if (id is! String || title is! String) return null;

    final expand = json['expand'] as Map<String, dynamic>?;
    final orgJson = expand?['organization'];
    final org = orgJson is Map ? Organization.tryParse(orgJson) : null;

    String? imageUrl;
    final imageField = json['image'];
    if (imageField is String && imageField.isNotEmpty) {
      imageUrl = '$_baseUrl/api/files/posts/$id/$imageField';
    }

    return Post(
      id: id,
      organizationId: json['organization'] as String? ?? org?.id ?? '',
      title: title,
      description: json['description'] as String? ?? '',
      type: json['type'] as String? ?? 'event',
      format: json['format'] as String? ?? 'offline',
      status: json['status'] as String? ?? 'published',
      organizationName: org?.name,
      organizationType: org?.type,
      organizationLogoUrl: org?.logoUrl,
      organizationDescription: org?.description,
      organizationWebsite: org?.website,
      organizationContactEmail: org?.contactEmail,
      organizationContactPhone: org?.contactPhone,
      organizationContactName: org?.contactName,
      externalLink: json['external_link'] as String?,
      imageUrl: imageUrl,
      startDate: _date(json['start_date']),
      endDate: _date(json['end_date']),
      publishedAt: _date(json['published_at']),
      campuses: _strList(json['campuses']),
      institutes: _strList(json['institutes']),
      directions: _strList(json['directions']),
      tags: _strList(json['tags']),
      isFeatured: json['is_featured'] as bool? ?? false,
      priorityWeight: (json['priority_weight'] as num?)?.toInt() ?? 0,
      viewsCount: (json['views_count'] as num?)?.toInt() ?? 0,
      favoritesCount: (json['favorites_count'] as num?)?.toInt() ?? 0,
    );
  }

  SpotlightBanner? _parseBanner(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final title = json['title'];
    if (id is! String || title is! String) return null;

    String? imageUrl;
    final imageField = json['image'];
    if (imageField is String && imageField.isNotEmpty) {
      imageUrl = '$_baseUrl/api/files/spotlight_banners/$id/$imageField';
    }

    return SpotlightBanner(
      id: id,
      title: title,
      subtitle: json['subtitle'] as String?,
      imageUrl: imageUrl,
      linkUrl: json['link_url'] as String?,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  static List<String> _strList(Object? v) =>
      v is List ? v.whereType<String>().toList() : const [];

  static DateTime? _date(Object? v) =>
      v is String ? DateTime.tryParse(v) : null;
}

/// Конфигурация PocketBase.
class PocketBaseConfig {
  const PocketBaseConfig._();

  static final url = const String.fromEnvironment('POCKETBASE_URL').trim();

  static bool get isConfigured =>
      url.isNotEmpty && Uri.tryParse(url)?.hasScheme == true;
}
