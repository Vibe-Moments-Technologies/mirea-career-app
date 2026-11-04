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

    // Вкладка «Опросы» — карточки типа survey (опросы от вуза).
    // Вкладки «От вуза»/«Партнёры» убраны вместе с профилями организаций:
    // организатора указывает админ, источник больше не режет ленту.
    if (tab == 'survey') {
      filters.add('type="survey"');
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
        '&expand=organization,form'
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
        '&expand=organization,form'
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
  ///
  /// hidden и system не показываем: hidden — служебная маскировка,
  /// system («Администрация проекта») — техническая организация консоли.
  Future<List<Organization>> fetchOrganizations() async {
    if (isOffline) return const [];

    final filter = Uri.encodeComponent('(type!="hidden" && type!="system")');
    final url = '$_baseUrl/api/collections/organizations/records'
        '?filter=$filter'
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

  /// Теги интересов: настраиваются из веб-панели (коллекция interests).
  ///
  /// value тега = его заголовок: профиль хранит строки, и правка
  /// переименования в панели применится к новым заполнениям.
  Future<List<String>> fetchInterests() async {
    final titles = await _fetchTitles('interests', titleOnly: true);
    return titles;
  }

  /// Институты из БД (коллекция institutes): панель управляет составом
  /// и порядком. Пусто/офлайн — пустой список, вызывающий берёт запас
  /// из Catalogs.
  Future<List<InstituteRef>> fetchInstitutes() async {
    final rows = await _fetchCatalog('institutes');
    return [
      for (final r in rows)
        if (r['code'] is String && r['title'] is String)
          InstituteRef(
            code: r['code'] as String,
            title: r['title'] as String,
            short: (r['short'] as String?) ?? r['code'] as String,
          ),
    ];
  }

  /// Уровни обучения из БД (коллекция levels).
  Future<List<LevelRef>> fetchLevels() async {
    final rows = await _fetchCatalog('levels');
    return [
      for (final r in rows)
        if (r['code'] is String && r['title'] is String)
          LevelRef(code: r['code'] as String, title: r['title'] as String),
    ];
  }

  /// Общая выборка справочника: активные, по sort_order.
  Future<List<Map<String, dynamic>>> _fetchCatalog(String collection) async {
    if (isOffline) return const [];
    final url = '$_baseUrl/api/collections/$collection/records'
        '?filter=is_active=true'
        '&sort=sort_order'
        '&perPage=100';
    final bytes = await AppHttpClient.instance.fetchBytes(url);
    if (bytes == null) return const [];
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      return [
        for (final e in (json['items'] as List? ?? const []))
          if (e is Map) Map<String, dynamic>.from(e),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<List<String>> _fetchTitles(String collection,
      {bool titleOnly = false}) async {
    if (isOffline) return const [];
    final url = '$_baseUrl/api/collections/$collection/records'
        '?filter=is_active=true'
        '&sort=sort_order'
        '&perPage=100';
    final bytes = await AppHttpClient.instance.fetchBytes(url);
    if (bytes == null) return const [];
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      return [
        for (final e in (json['items'] as List? ?? const []))
          if (e is Map && e['title'] is String) e['title'] as String,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Инкремент счётчика просмотров.
  ///
  /// Дедупликация на СЕРВЕРЕ (хук pb_hooks/metrics.pb.js): маршрут помнит
  /// пару (post_id, visitor) в служебной таблице и игнорирует повторные
  /// просмотры с того же устройства. [visitorId] — анонимный deviceId из
  /// LocalStore: персональных данных нет, это просто «кто уже видел».
  /// Прямой PATCH коллекции недоступен анониму — накрутить счётчик
  /// напрямую нельзя, только через маршрут с дедупликацией.
  ///
  /// false — сети нет/ошибка: Metrics положит вызов в офлайн-очередь.
  Future<bool> incrementViews(String postId,
      {required String visitorId}) async {
    if (isOffline) return false;

    return AppHttpClient.instance.postJson(
      '$_baseUrl/api/metrics/view/$postId',
      const {},
      visitorId: visitorId,
    );
  }

  /// Изменение счётчика избранного: delta = 1 (добавили) | -1 (убрали).
  ///
  /// Тоже через маршрут хука: аноним не может править записи постов,
  /// а сервер дополнительно не даёт счётчику уйти ниже нуля (clamp).
  ///
  /// false — сети нет/ошибка: вызов повторится из офлайн-очереди.
  Future<bool> modifyFavorites(String postId, int delta) async {
    if (isOffline) return false;

    return AppHttpClient.instance.postJson(
      '$_baseUrl/api/metrics/favorite',
      {'post_id': postId, 'delta': delta},
    );
  }

  /// Отправка ответов опросника.
  ///
  /// [answers] — компактный map «id шага → значение». createRule формы
  /// открыт анонимно, чтение закрыто: студент отправляет, но не может
  /// вытащить чужие ответы.
  ///
  /// Отправляем и device_id: анонимный «кто» без персональных данных —
  /// по нему админ видит дубли, а мы считаем уникальных респондентов.
  Future<bool> submitFormResponse({
    required String formId,
    String? postId,
    required Map<String, dynamic> answers,
    required String deviceId,
  }) async {
    if (isOffline) return false;

    return AppHttpClient.instance.postJson(
      '$_baseUrl/api/collections/form_responses/records',
      {
        'form': formId,
        'post': ?postId,
        'answers': answers,
        'device_id': deviceId,
      },
    );
  }

  /// Сколько студентов уже заполнили анкету.
  ///
  /// Ответы закрыты для чтения (create-only), поэтому число приходит
  /// из отдельного маршрута хука (pb_hooks/forms.pb.js) и только число —
  /// без самих ответов. null = не удалось узнать (офлайн, ошибка).
  Future<int?> fetchFormResponsesCount(String formId) async {
    if (isOffline) return null;

    final bytes = await AppHttpClient.instance
        .fetchBytes('$_baseUrl/api/forms/responses-count/$formId');
    if (bytes == null) return null;
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final count = json['count'];
      return count is num ? count.toInt() : null;
    } catch (_) {
      return null;
    }
  }

  /// Пост по публичному номеру (post_id вида 4Z65U4).
  ///
  /// Так баннеры ссылаются на посты (link_url = "post:XXXXXX"): студент
  /// видит номер, но внутренний record id не знает. Ищем по filter,
  /// раскрывая организацию и анкету — как в ленте.
  /// null = не найден или сети нет.
  Future<Post?> fetchPostByPublicId(String publicId) async {
    if (isOffline) return null;

    final filter = Uri.encodeComponent('post_id="$publicId"');
    final url = '$_baseUrl/api/collections/posts/records'
        '?filter=$filter'
        '&expand=organization,form'
        '&perPage=1';

    final bytes = await AppHttpClient.instance.fetchBytes(url);
    if (bytes == null) return null;
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final items = json['items'] as List<dynamic>? ?? [];
      return items.map(_parsePost).whereType<Post>().firstOrNull;
    } catch (_) {
      return null;
    }
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
    final formJson = expand?['form'];
    final form = formJson is Map ? FormDefinition.tryParse(formJson) : null;

    String? imageUrl;
    final imageField = json['image'];
    if (imageField is String && imageField.isNotEmpty) {
      imageUrl = '$_baseUrl/api/files/posts/$id/$imageField';
    }

    // Галерея: обложка первым слайдом + файлы gallery за ней.
    // Пустая галерея → список из одной обложки (или пустой, если и её нет).
    final galleryFiles = _strList(json['gallery']);
    final galleryUrls = [
      ?imageUrl,
      for (final f in galleryFiles) '$_baseUrl/api/files/posts/$id/$f',
    ];

    return Post(
      id: id,
      organizationId: json['organization'] as String? ?? org?.id ?? '',
      title: title,
      description: json['description'] as String? ?? '',
      type: json['type'] as String? ?? 'event',
      format: json['format'] as String? ?? 'offline',
      status: json['status'] as String? ?? 'published',
      publicId: _nonEmpty(json['post_id']),
      authorName: _nonEmpty(json['author_name']),
      gallery: galleryFiles,
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
      galleryUrls: json['gallery_urls'] is List
          ? _strList(json['gallery_urls'])
          : galleryUrls,
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
      formId: form?.id ?? (json['form'] as String?),
      formTitle: form?.title,
      formDefinition: form?.definition,
      formSuccessText: form?.successText,
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
      // Панель пишет номер поста отдельным полем link_post
      // («PWUBVD»): без него баннер с пост-ссылкой был некликабельным.
      linkPost: json['link_post'] as String?,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  static List<String> _strList(Object? v) =>
      v is List ? v.whereType<String>().toList() : const [];

  static DateTime? _date(Object? v) =>
      v is String ? DateTime.tryParse(v) : null;

  static String? _nonEmpty(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
}

/// Конфигурация PocketBase.
class PocketBaseConfig {
  const PocketBaseConfig._();

  static final url = const String.fromEnvironment('POCKETBASE_URL').trim();

  static bool get isConfigured =>
      url.isNotEmpty && Uri.tryParse(url)?.hasScheme == true;
}
