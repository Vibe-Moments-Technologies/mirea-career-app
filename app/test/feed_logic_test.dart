import 'package:flutter_test/flutter_test.dart';
import 'package:mirea_career/core/widgets/spotlight_gallery.dart';
import 'package:mirea_career/data/catalogs.dart';
import 'package:mirea_career/data/local_store.dart';
import 'package:mirea_career/data/models.dart';
import 'package:mirea_career/state/feed_filters.dart';

Post post({
  String id = 'p1',
  String type = 'event',
  String? orgType = 'partner',
  List<String> tags = const [],
  List<String> campuses = const [],
  List<String> institutes = const [],
  int daysAhead = 5,
  int views = 0,
  int weight = 0,
  bool featured = false,
  String? orgName = 'Яндекс',
  int publishedDaysAgo = 0,
}) =>
    Post(
      id: id,
      organizationId: 'org1',
      title: 'Заголовок $id',
      description: 'описание',
      type: type,
      format: 'offline',
      status: 'published',
      organizationName: orgName,
      organizationType: orgType,
      tags: tags,
      campuses: campuses,
      institutes: institutes,
      eventDate: DateTime.now().add(Duration(days: daysAhead)),
      publishedAt: DateTime.now().subtract(Duration(days: publishedDaysAgo)),
      viewsCount: views,
      priorityWeight: weight,
      isFeatured: featured,
    );

void main() {
  group('Фильтры ленты', () {
    test('пустой список аудиторий означает «для всех»', () {
      final p = post(campuses: [], institutes: []);
      expect(p.matchesCampus('stromynka'), isTrue);
      expect(p.matchesInstitute('iit'), isTrue);
    });

    test('заданная аудитория отсекает чужие кампусы', () {
      final p = post(campuses: ['vernadsky78']);
      expect(p.matchesCampus('vernadsky78'), isTrue);
      expect(p.matchesCampus('stromynka'), isFalse);
      // профиль без кампуса не должен проходить таргетированный пост
      expect(p.matchesCampus(null), isFalse);
    });

    test('фильтр по источнику разделяет вуз и партнёров', () {
      final posts = [
        post(id: 'a', orgType: 'partner'),
        post(id: 'b', orgType: 'university_dept'),
      ];
      expect(
        applyFilters(posts, const FeedFilters(source: 'partner')).map((p) => p.id),
        ['a'],
      );
      expect(
        applyFilters(posts, const FeedFilters(source: 'university_dept')).map((p) => p.id),
        ['b'],
      );
    });

    test('тип и теги работают совместно (И)', () {
      final posts = [
        post(id: 'a', type: 'internship', tags: ['it']),
        post(id: 'b', type: 'internship', tags: ['design']),
        post(id: 'c', type: 'event', tags: ['it']),
      ];
      final result = applyFilters(
        posts,
        const FeedFilters(types: {'internship'}, tags: {'it'}),
      );
      expect(result.map((p) => p.id), ['a']);
    });

    test('поиск ищет по заголовку, тегам и организатору', () {
      final posts = [post(id: 'a', orgName: 'Яндекс'), post(id: 'b', orgName: 'Сбер')];
      expect(applyFilters(posts, const FeedFilters(query: 'яндекс')).map((p) => p.id), ['a']);
      expect(applyFilters(posts, const FeedFilters(query: 'сбер')).map((p) => p.id), ['b']);
      expect(applyFilters(posts, const FeedFilters(query: 'неттакого')), isEmpty);
    });

    test('«ближайшие» отсекают прошедшие события', () {
      final posts = [post(id: 'past', daysAhead: -3), post(id: 'soon', daysAhead: 2)];
      final result = applyFilters(posts, const FeedFilters(onlyUpcoming: true));
      expect(result.map((p) => p.id), ['soon']);
    });

    test('сортировка по популярности ставит просматриваемые выше', () {
      final posts = [post(id: 'a', views: 1), post(id: 'b', views: 99)];
      final result = applyFilters(
        posts,
        const FeedFilters(sortByPopularity: true),
      );
      expect(result.map((p) => p.id), ['b', 'a']);
    });

    test('activeCount считает только реально заданные фильтры', () {
      expect(const FeedFilters().activeCount, 0);
      expect(
        const FeedFilters(types: {'event'}, campus: 'stromynka', query: 'хакатон').activeCount,
        3,
      );
      // источник не считается «фильтром» — это переключатель вкладки
      expect(const FeedFilters(source: 'partner').activeCount, 0);
    });
  });

  group('Скоринг «Для вас»', () {
    test('совпадение кампуса и института поднимает пост выше', () {
      const profile = StudentProfile(
        campus: 'vernadsky78',
        institute: 'iit',
        tags: ['it'],
        completed: true,
      );
      final exact = post(id: 'exact', campuses: ['vernadsky78'], institutes: ['iit'], tags: ['it']);
      final broad = post(id: 'broad'); // для всех

      expect(scoreFor(exact, profile), greaterThan(scoreFor(broad, profile)));
      expect(
        forYou([broad, exact], profile).map((p) => p.id),
        ['exact', 'broad'],
      );
    });

    test('без пройденного опроса секция пуста', () {
      const profile = StudentProfile();
      expect(forYou([post()], profile), isEmpty);
    });

    test('приоритетный вес двигает пост вверх', () {
      const profile = StudentProfile(completed: true);
      final weighted = post(id: 'w', weight: 100);
      final normal = post(id: 'n');
      expect(forYou([normal, weighted], profile).first.id, 'w');
    });
  });

  group('Приоритетные карточки (priorityFirst)', () {
    test('приоритетные поднимаются наверх, остальные сохраняют порядок', () {
      final input = [
        post(id: 'n1'),
        post(id: 'f1', featured: true),
        post(id: 'n2'),
        post(id: 'f2', featured: true),
      ];
      expect(priorityFirst(input).map((p) => p.id), ['f1', 'f2', 'n1', 'n2']);
    });

    test('порядок внутри групп не перемешивается', () {
      // Именно ради этого разбиение, а не sort: сортировка в Dart нестабильна
      // и переставила бы посты с одинаковым признаком произвольно.
      final input = [for (var i = 0; i < 20; i++) post(id: 'n$i')];
      expect(priorityFirst(input).map((p) => p.id),
          [for (var i = 0; i < 20; i++) 'n$i']);
    });

    test('пустой список и список без приоритетных не ломаются', () {
      expect(priorityFirst(const []), isEmpty);
      expect(priorityFirst([post(id: 'a'), post(id: 'b')]).map((p) => p.id),
          ['a', 'b']);
    });
  });

  group('Витрина (spotlightIndex)', () {
    test('после последнего слайда идёт первый, а не упор в край', () {
      expect([for (var i = 0; i < 7; i++) spotlightIndex(i, 3)], [0, 1, 2, 0, 1, 2, 0]);
      expect(spotlightIndex(-1, 3), 2);
    });

    test('из двух карточек сосед есть с ОБЕИХ сторон', () {
      // Раньше при двух слайдах первая карточка прижималась к краю:
      // слева щели не было, справа — большая. Теперь индекс циклический,
      // поэтому на позиции N-1 и N+1 всегда разные посты.
      const count = 2;
      for (var i = 0; i < 6; i++) {
        expect(spotlightIndex(i, count), isNot(spotlightIndex(i + 1, count)));
      }
    });
  });

  group('Сохранение фильтров', () {
    test('фильтры переживают круговой обход через JSON', () {
      const f = FeedFilters(
        query: 'хакатон',
        types: {'event'},
        campus: 'stromynka',
        institute: 'iit',
        format: 'online',
        organizationId: 'org1',
        tags: {'it', 'design'},
        source: 'partner',
        onlyUpcoming: true,
        sortByPopularity: true,
      );
      final back = FeedFilters.fromJson(f.toJson());
      expect(back.query, 'хакатон');
      expect(back.types, {'event'});
      expect(back.tags, {'it', 'design'});
      expect(back.campus, 'stromynka');
      expect(back.institute, 'iit');
      expect(back.format, 'online');
      expect(back.organizationId, 'org1');
      expect(back.source, 'partner');
      expect(back.onlyUpcoming, isTrue);
      expect(back.sortByPopularity, isTrue);
    });

    test('пустой JSON даёт пустые фильтры, а не исключение', () {
      final f = FeedFilters.fromJson(const {});
      expect(f.query, isEmpty);
      expect(f.types, isEmpty);
      expect(f.tags, isEmpty);
      expect(f.sortByPopularity, isFalse);
    });
  });

  group('Поиск', () {
    test('находит по тегу и по организатору', () {
      final posts = [
        post(id: 'a', tags: ['хакатон'], orgName: 'Яндекс'),
        post(id: 'b', orgName: 'Сбер'),
      ];
      expect(
        applyFilters(posts, const FeedFilters(query: 'хакатон')).map((p) => p.id),
        ['a'],
      );
      expect(
        applyFilters(posts, const FeedFilters(query: 'сбер')).map((p) => p.id),
        ['b'],
      );
    });

    test('поиск нечувствителен к регистру и лишним пробелам', () {
      final posts = [post(id: 'a', tags: ['Хакатон'])];
      expect(
        applyFilters(posts, const FeedFilters(query: '  хакатон ')).map((p) => p.id),
        ['a'],
      );
    });

    test('пустой запрос не отсекает ничего', () {
      final posts = [post(id: 'a'), post(id: 'b')];
      expect(applyFilters(posts, const FeedFilters()).length, 2);
    });

    test('пустой запрос не отсекает ничего даже при пробелах', () {
      final posts = [post(id: 'a')];
      expect(applyFilters(posts, const FeedFilters(query: '   ')).length, 1);
    });
  });

  group('Лента главной (homeFeed)', () {
    const profile = StudentProfile(
      institute: 'iit',
      tags: ['it'],
      completed: true,
    );

    test('приоритетное поднимается вверх списка, даже если оно старое', () {
      final old = post(id: 'old', publishedDaysAgo: 30);
      final featuredOld = post(id: 'featured', featured: true, publishedDaysAgo: 30);
      final fresh = post(id: 'fresh');

      // приоритетное встаёт выше свежего, несмотря на возраст
      expect(homeFeed([fresh, old, featuredOld], profile).first.id, 'featured');
    });

    test('релевантность профилю поднимает пост выше нерелевантного', () {
      final relevant = post(id: 'rel', institutes: ['iit'], tags: ['it']);
      final irrelevant = post(id: 'irr', orgType: 'partner');
      // обе не приоритетные, одинаково свежие — решает скоринг
      expect(
        homeFeed([irrelevant, relevant], profile).first.id,
        'rel',
        reason: 'релевантный профильному посту должен быть выше',
      );
    });

    test('при равном приоритете и скоринге свежее выше', () {
      final older = post(id: 'older', publishedDaysAgo: 5);
      final newer = post(id: 'newer', publishedDaysAgo: 1);
      expect(homeFeed([older, newer], profile).first.id, 'newer');
    });

    test('приоритетные не исключаются из ленты и остаются в общем потоке', () {
      final featured = post(id: 'f', featured: true);
      final normal = post(id: 'n');
      final ids = homeFeed([normal, featured], profile).map((p) => p.id).toList();
      expect(ids, containsAll(['f', 'n']));
      expect(ids.first, 'f');
    });
  });

  group('Справочники', () {
    test('каждый кампус и институт имеет непустое название', () {
      for (final c in Catalogs.campuses) {
        expect(c.title, isNotEmpty);
        expect(c.id, isNotEmpty);
      }
      for (final i in Catalogs.institutes) {
        expect(i.short, isNotEmpty);
      }
    });

    test('названия типов и форматов покрывают все значения БД', () {
      for (final t in ['event', 'vacancy', 'internship', 'scholarship', 'project']) {
        expect(Catalogs.postTypes[t], isNotNull, reason: 'нет названия для типа $t');
      }
      for (final f in ['online', 'offline', 'hybrid']) {
        expect(Catalogs.formats[f], isNotNull, reason: 'нет названия для формата $f');
      }
    });

    test('подписи не сломаны на неизвестных значениях', () {
      expect(Catalogs.campusTitle(null), 'Все кампусы');
      expect(Catalogs.campusTitle('нет-такого'), 'Все кампусы');
      expect(Catalogs.instituteTitle('iit'), 'ИИТ');
    });
  });

  group('Профиль студента', () {
    test('copyWith сохраняет и сбрасывает поля', () {
      const p = StudentProfile(campus: 'stromynka', institute: 'iit', completed: true);
      expect(p.copyWith(level: 'master').campus, 'stromynka');
      expect(p.copyWith(clearCampus: true).campus, isNull);
      // без явного сброса null означает «не менять»
      expect(p.copyWith(campus: null).campus, 'stromynka');
    });

    test('сериализация переживает круговой обход', () {
      const p = StudentProfile(
        campus: 'vernadsky86',
        institute: 'iii',
        level: 'bachelor',
        tags: ['it', 'design'],
        completed: true,
      );
      final restored = StudentProfile.fromJson(p.toJson());
      expect(restored.campus, 'vernadsky86');
      expect(restored.tags, ['it', 'design']);
      expect(restored.completed, isTrue);
    });
  });

  group('Модель поста', () {
    test('парсит вложенную организацию из PostgREST', () {
      final p = Post.tryParse({
        'id': 'x',
        'title': 'Тест',
        'type': 'vacancy',
        'organizations': {'id': 'o1', 'name': 'Сбер', 'type': 'partner'},
        'tags': ['it'],
        'views_count': 7,
      })!;
      expect(p.organizationName, 'Сбер');
      expect(p.isPartner, isTrue);
      expect(p.viewsCount, 7);
      expect(p.tags, ['it']);
    });

    test('битые данные не роняют парсер', () {
      expect(Post.tryParse(null), isNull);
      expect(Post.tryParse('строка'), isNull);
      expect(Post.tryParse({'id': 'x'}), isNull); // нет обязательного title
    });

    test('отсутствие organizations не ломает карточку', () {
      final p = Post.tryParse({'id': 'x', 'title': 'Т', 'type': 'event'})!;
      expect(p.organizationName, isNull);
      expect(p.tags, isEmpty);
      expect(p.isFeatured, isFalse);
    });
  });

  group('Актуальность по дате события', () {
    // Фиксированное «сейчас»: правило должно зависеть от переданного времени,
    // а не от часов машины, иначе тест плавает по ночам.
    final now = DateTime(2026, 5, 20, 15, 30);
    final today = DateTime(2026, 5, 20);

    Post dated(String id, DateTime? eventDate) => Post(
          id: id,
          organizationId: 'org1',
          title: 'Заголовок $id',
          description: '',
          type: 'event',
          format: 'offline',
          status: 'published',
          eventDate: eventDate,
        );

    test('будущее и сегодняшнее событие не истекло', () {
      expect(isPast(dated('a', DateTime(2026, 5, 21)), now: now), isFalse);
      // сегодняшнее начало суток равно границе — ещё актуально
      expect(isPast(dated('b', today), now: now), isFalse);
    });

    test('событие вчерашним днём уже истекло', () {
      expect(
        isPast(dated('c', DateTime(2026, 5, 19, 23, 59)), now: now),
        isTrue,
      );
    });

    test('без даты события пост остаётся актуальным', () {
      expect(isPast(dated('d', null), now: now), isFalse);
    });

    test('relevantOnly и archiveOnly делят список без потерь', () {
      final posts = [
        dated('past', DateTime(2026, 5, 1)),
        dated('future', DateTime(2026, 6, 1)),
        dated('nodate', null),
      ];
      expect(relevantOnly(posts, now: now).map((p) => p.id),
          ['future', 'nodate']);
      expect(archiveOnly(posts, now: now).map((p) => p.id), ['past']);
    });

    test('архив отсортирован от недавних к давним', () {
      final posts = [
        dated('old', DateTime(2026, 1, 10)),
        dated('recent', DateTime(2026, 5, 15)),
        dated('mid', DateTime(2026, 3, 1)),
      ];
      expect(archiveOnly(posts, now: now).map((p) => p.id),
          ['recent', 'mid', 'old']);
    });

    test('«ближайшие» в фильтрах совпадают с isPast', () {
      final posts = [
        dated('past', DateTime(2026, 5, 19)),
        dated('nodate', null),
        dated('future', DateTime(2026, 6, 1)),
      ];
      expect(
        applyFilters(posts, const FeedFilters(onlyUpcoming: true), now: now)
            .map((p) => p.id),
        ['future', 'nodate'],
      );
    });
  });
}
