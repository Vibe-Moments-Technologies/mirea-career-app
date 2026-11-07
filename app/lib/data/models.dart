/// Модели данных, приходящие из Supabase. Чистые immutable-классы без кодогенерации.
library;

/// Институт из справочника БД (коллекция institutes).
///
/// Справочник настраивается панелью: состав, порядок и названия.
/// code — стабильный идентификатор (его хранит профиль и посты);
/// short — аббревиатура для плиток, title — полное название.
class InstituteRef {
  const InstituteRef({required this.code, required this.title, required this.short});
  final String code;
  final String title;
  final String short;
}

/// Уровень обучения из справочника БД (коллекция levels).
class LevelRef {
  const LevelRef({required this.code, required this.title});
  final String code;
  final String title;
}

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
    this.linkPost,
    this.linkForm,
    this.sortOrder = 0,
  });

  final String id;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final String? linkUrl;
  final int sortOrder;

  /// Прямое поле link_post (чистый номер поста, без префикса).
  final String? linkPost;

  /// Прямое поле link_form: публичный номер анкеты (form_id).
  /// Баннер открывает анкету СРАЗУ, без карточки поста.
  final String? linkForm;

  /// Ссылка на пост: публичный номер (post_id), если баннер ведёт
  /// на внутренний экран.
  ///
  /// Два источника в БД: консоль может писать чистый номер в `link_post`
  /// или строку "post:XXXXXX" в `link_url`. Приложение понимает оба —
  /// иначе тап по баннеру молча ничего не делал.
  String? get linkPostId {
    final link = linkUrl;
    if (link != null && link.startsWith('post:')) {
      final id = link.substring(5).trim();
      if (id.isNotEmpty) return id;
    }
    final direct = linkPost;
    if (direct != null && direct.trim().isNotEmpty) return direct.trim();
    return null;
  }

  /// Ссылка на анкету: form_id (приоритет ниже post, выше URL —
  /// контракт 6.3 справки: link_post → link_form → link_url).
  String? get linkFormId {
    final direct = linkForm;
    if (direct != null && direct.trim().isNotEmpty) return direct.trim();
    // Легаси-формат в link_url: "form:XXXXXX".
    final link = linkUrl;
    if (link != null && link.startsWith('form:')) {
      final id = link.substring(5).trim();
      if (id.isNotEmpty) return id;
    }
    return null;
  }

  /// Есть ли вообще цель у баннера.
  bool get hasLink =>
      linkPostId != null || linkFormId != null || (linkUrl ?? '').isNotEmpty;

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
      linkPost: json['link_post'] as String?,
      linkForm: json['link_form'] as String?,
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
        'link_post': linkPost,
        'link_form': linkForm,
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

/// Чем закончилась отправка анкеты.
enum FormSubmitResult {
  /// Ушло, сервер записал.
  ok,

  /// Хук «один ответ с устройства» отклонил: 400 «Вы уже отвечали…».
  duplicate,

  /// Опрос завершён (закрыт вручную или срок вышел): сервер вернул 400
  /// «Опрос завершён — отвечать больше нельзя.» (контракт 6.4).
  closed,

  /// Сети нет или сервер недоступен: повторить позже.
  networkError,
}

/// Опросник, конфигурируемый в БД.
///
/// `definition` — JSON: `{type, id, steps: [{id, content, answerFormat,
/// isMandatory}]}`. Формат совместим с прежним survey_kit-определением,
/// но рендерится собственным [FormView] в стиле приложения.
/// Хранится в отдельной коллекции `forms` и приходит в посте
/// через `expand.form`.
class FormDefinition {
  const FormDefinition({
    required this.id,
    required this.title,
    required this.definition,
    this.successText,
    this.kind,
    this.formId,
    this.oneResponsePerDevice = false,
    this.authorName,
    this.imageUrl,
    this.endDate,
    this.status,
    this.resultText,
  });

  final String id;
  final String title;

  /// JSON-определение опроса: шаги, подписи, типы ответов.
  final Map<String, dynamic> definition;

  /// Текст после отправки: показываем на экране «готово».
  final String? successText;

  /// Тип анкеты (поле forms.kind консоли):
  ///  ''/null → 'application' — из карточки поста (легаси);
  ///  'survey' — элемент ленты: карточка как пост, но тап сразу
  ///             открывает опрос (контракт 6.4);
  ///  'anon_survey' — то же, анонимный: вопросы о студенте запрещены.
  final String? kind;

  /// Публичный 6-символьный номер анкеты (forms.form_id, как post_id
  /// у постов): по нему баннеры (link_form) и шаринг ссылаются на анкету.
  final String? formId;

  /// «Один ответ с устройства»: хук вернёт 400 «Вы уже отвечали…»
  /// при повторной отправке (forms.one_response_per_device).
  /// false — повторный проход разрешён (локальная блокировка НЕ нужна).
  final bool oneResponsePerDevice;

  /// Автор/организатор опроса (forms.author_name): подпись в карточке
  /// опроса в ленте — компания или человек, который составляет опрос
  /// и отвечает за него.
  final String? authorName;

  /// Обложка опроса в ленте (forms.image) — ОДНА картинка, галереи у
  /// опросов нет. Полный URL собирает репозиторий; пусто → заглушка.
  final String? imageUrl;

  /// Дата завершения опроса (forms.end_date, конец дня). Прошла →
  /// опрос в архиве: отвечать нельзя, сервер отдаёт 400.
  final DateTime? endDate;

  /// Жизненный цикл (forms.status): 'active' | 'closed'.
  /// ''/null трактуем как active (легаси-записи без поля).
  final String? status;

  /// Итог завершённого опроса (forms.result_text): показываем ВМЕСТО
  /// формы, когда status = 'closed'.
  final String? resultText;

  /// Анонимный опрос?
  bool get isAnonSurvey => kind == 'anon_survey';

  /// Это опрос ленты (survey/anon_survey), а не заявка из карточки?
  bool get isSurveyKind =>
      kind == 'survey' || kind == 'anon_survey';

  /// Завершён вручную в консоли («Завершить и подвести итог»):
  /// вместо формы показываем [resultText], ответы не принимаются.
  bool get isClosed => status == 'closed';

  /// Срок вышел (end_date в прошлом) и опрос не закрыт вручную:
  /// архив — из активной ленты опросов убирается, отвечать нельзя.
  /// Конец дня: дата «5 ноября» действительна до 23:59:59 включительно.
  bool get isExpired {
    if (isClosed) return false;
    final end = endDate;
    if (end == null) return false;
    final endOfDay = DateTime(end.year, end.month, end.day, 23, 59, 59);
    return DateTime.now().isAfter(endOfDay);
  }

  /// Опрос закрыт (вручную или по сроку): форму не показываем.
  bool get isFinished => isClosed || isExpired;

  /// Идёт приём ответов.
  bool get isOpen => !isFinished;

  static FormDefinition? tryParse(Object? json, {String baseUrl = ''}) {
    if (json is! Map) return null;
    final id = json['id'];
    final title = json['title'];
    if (id is! String || title is! String) return null;
    final definition = json['definition'];
    if (definition is! Map) return null;

    // Обложка: имя файла → полный URL (как у постов). Без baseUrl
    // (expand.form у поста) картинка опроса не нужна — у поста своя.
    String? imageUrl;
    final imageField = json['image'];
    if (imageField is String && imageField.isNotEmpty && baseUrl.isNotEmpty) {
      imageUrl = '$baseUrl/api/files/forms/$id/$imageField';
    }

    return FormDefinition(
      id: id,
      title: title,
      definition: Map<String, dynamic>.from(definition),
      successText: json['success_text'] as String?,
      kind: (json['kind'] as String?)?.trim(),
      formId: _nonEmptyString(json['form_id']),
      oneResponsePerDevice: json['one_response_per_device'] == true,
      authorName: _nonEmptyString(json['author_name']),
      imageUrl: _nonEmptyString(json['image_url']) ?? imageUrl,
      endDate: _date(json['end_date']),
      status: _nonEmptyString(json['status']),
      resultText: _nonEmptyString(json['result_text']),
    );
  }

  static String? _nonEmptyString(Object? v) {
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  static DateTime? _date(Object? v) =>
      v is String ? DateTime.tryParse(v) : null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'definition': definition,
        'success_text': successText,
        'kind': kind,
        'form_id': formId,
        'one_response_per_device': oneResponsePerDevice,
        'author_name': authorName,
        'image_url': imageUrl,
        'end_date': endDate?.toIso8601String(),
        'status': status,
        'result_text': resultText,
      };

  /// Текст вопроса шага: первый text-блок в content.
  ///
  /// Общий для формы (подпись над полем) и истории анкет (снимок
  /// «что спрашивали»): одно место — одинаковый результат.
  static String stepQuestion(Map<String, dynamic> step) {
    final content = step['content'];
    if (content is! List) return '';
    return content
            .whereType<Map>()
            .map((c) => c['text'])
            .whereType<String>()
            .firstOrNull ??
        '';
  }

  /// Шаги определения как список map (сырой JSON — не модель).
  List<Map<String, dynamic>> get stepMaps {
    final raw = definition['steps'];
    if (raw is! List) return const [];
    return [
      for (final s in raw)
        if (s is Map) Map<String, dynamic>.from(s),
    ];
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
    this.publicId,
    this.authorName,
    this.gallery = const [],
    this.externalLink,
    this.imageUrl,
    this.galleryUrls = const [],
    this.startDate,
    this.endDate,
    this.publishedAt,
    this.campuses = const [],
    this.institutes = const [],
    this.directions = const [],
    this.tags = const [],
    this.isFeatured = false,
    this.priorityWeight = 0,
    this.viewsCount = 0,
    this.favoritesCount = 0,
    this.formId,
    this.formTitle,
    this.formDefinition,
    this.formSuccessText,
    this.formKind,
    this.formPublicId,
    this.formOncePerDevice = false,
    this.formAuthorName,
    this.formEndDate,
    this.formStatus,
    this.formResultText,
  });

  final String id;
  final String organizationId;
  final String title;
  final String description;
  final String type; // internship | vacancy | event | survey (+легаси)
  final String format; // online | offline | hybrid

  /// Строка, не enum: консоль добавляет значения (draft, pending_review,
  /// rejected, withdrawn…) раньше, чем приложение успевает обновиться.
  /// Приложение показывает только published — остальное просто не доезжает.
  final String status;

  /// Публичный номер поста (6 символов, вида 4Z65U4): по нему баннеры
  /// ссылаются на посты (link_url = "post:XXXXXX") и его видит студент.
  final String? publicId;

  /// Автор поста, если организация не указана: консоль позволяет
  /// посты без организации — тогда подпись автора вместо её названия.
  final String? authorName;

  /// Имена файлов галереи (до 8): слайдер на экране поста за обложкой.
  final List<String> gallery;
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

  /// Полные URL галереи (обложка + gallery): собирает репозиторий,
  /// зная базу и record id. Пустая галерея → только обложка.
  final List<String> galleryUrls;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? publishedAt;
  final List<String> campuses;
  final List<String> institutes;
  final List<String> directions;
  final List<String> tags;
  final bool isFeatured;
  final int priorityWeight;
  final int viewsCount;
  final int favoritesCount;
  final String? formId;
  final String? formTitle;
  final Map<String, dynamic>? formDefinition;
  final String? formSuccessText;

  /// Тип привязанной анкеты (forms.kind) и флаг «один ответ с
  /// устройства» — из expand.form, чтобы Post.form не терял их.
  final String? formKind;
  final String? formPublicId;
  final bool formOncePerDevice;

  /// Жизненный цикл привязанной анкеты — из expand.form.
  final String? formAuthorName;
  final DateTime? formEndDate;
  final String? formStatus;
  final String? formResultText;

  bool get isPartner => organizationType == 'partner';

  /// Имя, которым подписываем автора поста: организация, иначе author_name.
  /// Пусто — «Организатор не указан» на месте подписи.
  String? get authorLabel => organizationName ?? authorName;

  /// Опросник, привязанный к посту: открывается вместо внешней ссылки.
  ///
  /// kind/one_response_per_device/form_id переносятся из expand.form:
  /// без этого пост-анкеты теряли флаг «один ответ с устройства» и
  /// тип — блокировка повтора не срабатывала из карточки поста.
  /// Жизненный цикл (status/end_date/result_text) — тоже: закрытый
  /// опрос не должен открывать форму даже через пост.
  FormDefinition? get form => formId == null || formDefinition == null
      ? null
      : FormDefinition(
          id: formId!,
          title: formTitle ?? '',
          definition: formDefinition!,
          successText: formSuccessText,
          kind: formKind,
          formId: (formPublicId != null && formPublicId!.trim().isNotEmpty)
              ? formPublicId!.trim()
              : null,
          oneResponsePerDevice: formOncePerDevice,
          authorName: formAuthorName,
          endDate: formEndDate,
          status: formStatus,
          resultText: formResultText,
        );

  /// Пост актуален если end_date ещё не наступил (или не указан).
  bool get isActual => endDate == null || endDate!.isAfter(DateTime.now());

  /// Пост в архиве если end_date прошёл.
  bool get isArchived => endDate != null && endDate!.isBefore(DateTime.now());

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

  /// Парсит запись PocketBase (snake_case, expand.organization).
  static Post? tryParse(Object? json) {
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
      imageUrl = imageField;
    }

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
      gallery: _strList(json['gallery']),
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
      galleryUrls: _strList(json['gallery_urls']),
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
      formKind: form?.kind,
      formPublicId: form?.formId,
      formOncePerDevice: form?.oneResponsePerDevice ?? false,
      formAuthorName: form?.authorName,
      formEndDate: form?.endDate,
      formStatus: form?.status,
      formResultText: form?.resultText,
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
        'image': imageUrl,
        'post_id': publicId,
        'author_name': authorName,
        'gallery': gallery,
        'gallery_urls': galleryUrls,
        'start_date': startDate?.toIso8601String(),
        'end_date': endDate?.toIso8601String(),
        'published_at': publishedAt?.toIso8601String(),
        'campuses': campuses,
        'institutes': institutes,
        'directions': directions,
        'tags': tags,
        'is_featured': isFeatured,
        'priority_weight': priorityWeight,
        'views_count': viewsCount,
        'favorites_count': favoritesCount,
        // Опросник хранится в кэше как JSON-объект — expand-формат,
        // чтобы tryParse читал его тем же путём, что и серверный ответ.
        ...?_formCacheJson,
      };

  /// Кэш-представление формы: null → ничего не добавляется в JSON.
  Map<String, dynamic>? get _formCacheJson {
    final f = form;
    if (f == null) return null;
    return {
      'form': f.id,
      'expand': {'form': f.toJson()},
    };
  }

  Post copyWith({int? viewsCount, int? favoritesCount}) => Post(
        id: id,
        organizationId: organizationId,
        title: title,
        description: description,
        type: type,
        format: format,
        status: status,
        publicId: publicId,
        authorName: authorName,
        gallery: gallery,
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
        galleryUrls: galleryUrls,
        startDate: startDate,
        endDate: endDate,
        publishedAt: publishedAt,
        campuses: campuses,
        institutes: institutes,
        directions: directions,
        tags: tags,
        isFeatured: isFeatured,
        priorityWeight: priorityWeight,
        viewsCount: viewsCount ?? this.viewsCount,
        favoritesCount: favoritesCount ?? this.favoritesCount,
        formId: formId,
        formTitle: formTitle,
        formDefinition: formDefinition,
        formSuccessText: formSuccessText,
      );

  static String? _nonEmpty(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
}