import 'dart:convert';

import 'app_http_client.dart';
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

  /// Опубликованные посты с расширенной организацией.
  ///
  /// PocketBase expand: `?expand=organization` подтягивает связанную
  /// коллекцию organizations в поле `expand.organization`.
  Future<List<Post>> fetchPublished() async {
    if (isOffline) return const [];

    final url = '$_baseUrl/api/collections/posts/records'
        '?filter=status="published"&&publishedAt<="@now"'
        '&expand=organization'
        '&sort=-priorityWeight,-publishedAt'
        '&perPage=300';

    final bytes = await AppHttpClient.instance.fetchBytes(url);
    if (bytes == null) return const [];

    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final items = json['items'] as List<dynamic>? ?? [];
      return items.map((e) => _parsePost(e)).whereType<Post>().toList();
    } catch (_) {
      return const [];
    }
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
      return items.map((e) => _parseBanner(e)).whereType<SpotlightBanner>().toList();
    } catch (_) {
      return const [];
    }
  }

  /// Инкремент счётчика просмотров.
  ///
  /// PocketBase поддерживает атомарные операции: `views_count+1`.
  /// Но для анонимного доступа нужен custom endpoint или API rule.
  /// Пока используем PATCH с auth token (или уберём счётчики).
  Future<void> incrementViews(String postId) async {
    if (isOffline) return;
    // TODO: реализовать через custom API endpoint или auth token
    // Patch: PATCH /api/collections/posts/records/{id} {"views_count+": 1}
  }

  Future<void> modifyFavorites(String postId, int delta) async {
    if (isOffline) return;
    // TODO: реализовать через custom API endpoint или auth token
  }

  // ---------- Парсинг ----------

  /// Парсит пост из PocketBase JSON (snake_case поля).
  Post? _parsePost(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final title = json['title'];
    if (id is! String || title is! String) return null;

    // Expand: organization — вложенный объект в expand.organization
    final expand = json['expand'] as Map<String, dynamic>?;
    final orgJson = expand?['organization'];
    final org = orgJson is Map ? Organization.tryParse(orgJson) : null;

    // Image URL: PocketBase file field = имя файла
    // Полный URL: {baseUrl}/api/files/{collectionName}/{recordId}/{filename}
    String? imageUrl;
    final imageField = json['image'];
    if (imageField is String && imageField.isNotEmpty) {
      imageUrl = '$_baseUrl/api/files/posts/$id/$imageField';
    } else if (imageField is List && imageField.isNotEmpty && imageField[0] is String) {
      imageUrl = '$_baseUrl/api/files/posts/$id/${imageField[0]}';
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
      eventDate: _date(json['event_date']),
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

  /// Парсит баннер витрины из PocketBase JSON.
  SpotlightBanner? _parseBanner(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final title = json['title'];
    if (id is! String || title is! String) return null;

    // Image URL: file field → полный URL
    String? imageUrl;
    final imageField = json['image'];
    if (imageField is String && imageField.isNotEmpty) {
      imageUrl = '$_baseUrl/api/files/spotlight_banners/$id/$imageField';
    } else if (imageField is List && imageField.isNotEmpty && imageField[0] is String) {
      imageUrl = '$_baseUrl/api/files/spotlight_banners/$id/${imageField[0]}';
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
///
/// URL передаётся через --dart-define при сборке:
///   flutter build apk --dart-define=POCKETBASE_URL=https://vmt-mireacareer.l1ratch.ru
class PocketBaseConfig {
  const PocketBaseConfig._();

  static final url =
      const String.fromEnvironment('POCKETBASE_URL').trim();

  static bool get isConfigured =>
      url.isNotEmpty && Uri.tryParse(url)?.hasScheme == true;
}
