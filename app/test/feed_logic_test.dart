import 'package:flutter_test/flutter_test.dart';
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
      publishedAt: DateTime.now(),
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
}