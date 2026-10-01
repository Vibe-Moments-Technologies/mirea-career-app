/// Модели данных, приходящие из Supabase. Чистые immutable-классы без кодогенерации.
library;

/// Слайд витрины главной.
///
/// Отдельная сущность, а не пост: витрину наполняет администратор в консоли,
/// и она не должна появляться в ленте. Раньше баннер был приоритетным постом,
/// из-за чего приходилось помечать обычную карточку «приоритетной», и она
/// всплывала в ленте.
class SpotlightBanner {
  const SpotlightBanner({
    required this.id,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.linkUrl,
    this.sortOrder = 0,
  });

  final String id;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final String? linkUrl;
  final int sortOrder;

  static SpotlightBanner? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final title = json['title'];
    if (id is! String || title is! String) return null;
    return SpotlightBanner(
      id: id,
      title: title,
      subtitle: json['subtitle'] as String?,
      imageUrl: json['image_url'] as String?,
      linkUrl: json['link_url'] as String?,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  /// Для локального кэша.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'image_url': imageUrl,
        'link_url': linkUrl,
        'sort_order': sortOrder,
      };
}

class Organization {
  const Organization({
    required this.id,
    required this.name,
    required this.type,
    this.description,
    this.logoUrl,
    this.website,
    this.contactEmail,
    this.contactPhone,
    this.contactName,
  });

  final String id;
  final String name;
  final String type; // 'university_dept' | 'partner'
  final String? description;
  final String? logoUrl;
  final String? website;
  final String? contactEmail;
  final String? contactPhone;
  final String? contactName;

  bool get isPartner => type == 'partner';

  static Organization? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || name is! String) return null;
    return Organization(
      id: id,
      name: name,
      type: json['type'] as String? ?? 'partner',
      description: json['description'] as String?,
      logoUrl: json['logo_url'] as String?,
      website: json['website'] as String?,
      contactEmail: json['contact_email'] as String?,
      contactPhone: json['contact_phone'] as String?,
      contactName: json['contact_name'] as String?,
    );
  }
}

class Post {
  const Post({
    required this.id,
    required this.organizationId,
    required this.title,
    required this.description,
    required this.type,
    required this.format,
    required this.status,
    this.organizationName,
    this.organizationType,
    this.organizationLogoUrl,
    this.organizationDescription,
    this.organizationWebsite,
    this.organizationContactEmail,
    this.organizationContactPhone,
    this.organizationContactName,
    this.externalLink,
    this.imageUrl,
    this.eventDate,
    this.publishedAt,
    this.campuses = const [],
    this.institutes = const [],
    this.directions = const [],
    this.tags = const [],
    this.isFeatured = false,
    this.priorityWeight = 0,
    this.viewsCount = 0,
    this.favoritesCount = 0,
  });

  final String id;
  final String organizationId;
  final String title;
  final String description;
  final String type; // event | vacancy | internship | scholarship | project
  final String format; // online | offline | hybrid
  final String status;
  final String? organizationName;
  final String? organizationType;
  final String? organizationLogoUrl;
  final String? organizationDescription;
  final String? organizationWebsite;
  final String? organizationContactEmail;
  final String? organizationContactPhone;
  final String? organizationContactName;
  final String? externalLink;
  final String? imageUrl;
  final DateTime? eventDate;
  final DateTime? publishedAt;
  final List<String> campuses;
  final List<String> institutes;
  final List<String> directions;
  final List<String> tags;
  final bool isFeatured;
  final int priorityWeight;
  final int viewsCount;
  final int favoritesCount;

  bool get isPartner => organizationType == 'partner';

  /// Организация, собранная из вложенных полей поста.
  ///
  /// Нужна профилю организатора: он открывается из карточки, где есть
  /// только эти поля, и отдельный запрос к БД при этом не нужен.
  Organization? get organization => organizationName == null
      ? null
      : Organization(
          id: organizationId,
          name: organizationName!,
          type: organizationType ?? 'partner',
          description: organizationDescription,
          logoUrl: organizationLogoUrl,
          website: organizationWebsite,
          contactEmail: organizationContactEmail,
          contactPhone: organizationContactPhone,
          contactName: organizationContactName,
        );

  /// Пустой список = аудитория «для всех».
  bool matchesCampus(String? campus) =>
      campuses.isEmpty || (campus != null && campuses.contains(campus));
  bool matchesInstitute(String? institute) =>
      institutes.isEmpty || (institute != null && institutes.contains(institute));

  static List<String> _strList(Object? v) =>
      v is List ? v.whereType<String>().toList() : const [];

  static DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;

  /// Парсит строку PostgREST с вложенным `organizations(...)`.
  static Post? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final title = json['title'];
    if (id is! String || title is! String) return null;
    final org = Organization.tryParse(json['organizations']);
    return Post(
      id: id,
      organizationId: json['organization_id'] as String? ?? '',
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
      imageUrl: json['image_url'] as String?,
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

  /// Для локального кэша ленты (shared_preferences хранит JSON).
  Map<String, dynamic> toJson() => {
        'id': id,
        'organization_id': organizationId,
        'title': title,
        'description': description,
        'type': type,
        'format': format,
        'status': status,
        'organizations': {
          'id': organizationId,
          'name': organizationName,
          'type': organizationType,
          'description': organizationDescription,
          'logo_url': organizationLogoUrl,
          'website': organizationWebsite,
          'contact_email': organizationContactEmail,
          'contact_phone': organizationContactPhone,
          'contact_name': organizationContactName,
        },
        'external_link': externalLink,
        'image_url': imageUrl,
        'event_date': eventDate?.toIso8601String(),
        'published_at': publishedAt?.toIso8601String(),
        'campuses': campuses,
        'institutes': institutes,
        'directions': directions,
        'tags': tags,
        'is_featured': isFeatured,
        'priority_weight': priorityWeight,
        'views_count': viewsCount,
        'favorites_count': favoritesCount,
      };

  Post copyWith({int? viewsCount, int? favoritesCount}) => Post(
        id: id,
        organizationId: organizationId,
        title: title,
        description: description,
        type: type,
        format: format,
        status: status,
        organizationName: organizationName,
        organizationType: organizationType,
        organizationLogoUrl: organizationLogoUrl,
        organizationDescription: organizationDescription,
        organizationWebsite: organizationWebsite,
        organizationContactEmail: organizationContactEmail,
        organizationContactPhone: organizationContactPhone,
        organizationContactName: organizationContactName,
        externalLink: externalLink,
        imageUrl: imageUrl,
        eventDate: eventDate,
        publishedAt: publishedAt,
        campuses: campuses,
        institutes: institutes,
        directions: directions,
        tags: tags,
        isFeatured: isFeatured,
        priorityWeight: priorityWeight,
        viewsCount: viewsCount ?? this.viewsCount,
        favoritesCount: favoritesCount ?? this.favoritesCount,
      );
}