/// Справочники MVP: статические списки в коде клиента и в seed-данных БД.
/// ponytail: без таблиц campuses/institutes в БД — они там не нужны, пока их
/// не редактируют из админки. Тогда завести таблицы и FK (docs/DATABASE.md §1).
library;

class Campus {
  const Campus(this.id, this.title, this.address);
  final String id;
  final String title;
  final String address;
}

class Institute {
  const Institute(this.id, this.title, this.short);
  final String id;
  final String title;
  final String short;
}

class InterestTag {
  const InterestTag(this.id, this.title);
  final String id;
  final String title;
}

class Level {
  const Level(this.id, this.title);
  final String id;
  final String title;
}

class Catalogs {
  const Catalogs._();

  static const campuses = <Campus>[
    Campus('vernadsky78', 'Вернадского, 78', 'пр-т Вернадского, 78'),
    Campus('vernadsky86', 'Вернадского, 86', 'пр-т Вернадского, 86'),
    Campus('stromynka', 'Стромынка', 'ул. Стромынка, 20'),
  ];

  static const institutes = <Institute>[
    Institute('ikb', 'Институт кибербезопасности и цифровых технологий', 'ИКБ'),
    Institute('iii', 'Институт искусственного интеллекта', 'ИИИ'),
    Institute('iit', 'Институт информационных технологий', 'ИИТ'),
    Institute('itu', 'Институт технологий управления', 'ИТУ'),
    Institute('iptip', 'Институт перспективных технологий и индустриального программирования', 'ИПТИП'),
    Institute('itht', 'Институт тонких химических технологий имени М. В. Ломоносова', 'ИТХТ'),
    Institute('iri', 'Институт радиоэлектроники и информатики', 'ИРИ'),
    Institute('kpk', 'Колледж программирования и кибербезопасности', 'КПК'),
    Institute('pish', 'Передовые инженерные школы', 'ПИШ'),
    Institute('fryazino', 'Филиал РТУ МИРЭА в г. Фрязино', 'Фрязино'),
  ];

  static const levels = <Level>[
    Level('applicant', 'Абитуриент'),
    Level('bachelor', 'Бакалавриат'),
    Level('specialist', 'Специалитет'),
    Level('master', 'Магистратура'),
    Level('postgrad', 'Аспирантура'),
    Level('graduate', 'Выпускник'),
    Level('teacher', 'Преподаватель'),
    Level('any', 'Не важно'),
  ];

  static const interests = <InterestTag>[
    InterestTag('it', 'IT и разработка'),
    InterestTag('design', 'Дизайн'),
    InterestTag('science', 'Наука'),
    InterestTag('sport', 'Спорт'),
    InterestTag('volunteering', 'Волонтёрство'),
    InterestTag('internship', 'Стажировки'),
    InterestTag('career', 'Карьера'),
    InterestTag('case', 'Кейс-чемпионаты'),
    InterestTag('hackathon', 'Хакатоны'),
    InterestTag('scholarship', 'Стипендии'),
  ];

  static const postTypes = <String, String>{
    'event': 'Событие',
    'vacancy': 'Вакансия',
    'internship': 'Стажировка',
    'scholarship': 'Стипендия',
    'project': 'Проект',
  };

  static const formats = <String, String>{
    'online': 'Онлайн',
    'offline': 'Офлайн',
    'hybrid': 'Гибрид',
  };

  static String campusTitle(String? id) =>
      campuses.where((c) => c.id == id).map((c) => c.title).firstOrNull ?? 'Все кампусы';

  static String instituteTitle(String? id) =>
      institutes.where((i) => i.id == id).map((i) => i.short).firstOrNull ?? 'Институт не указан';

  static String levelTitle(String? id) =>
      levels.where((l) => l.id == id).map((l) => l.title).firstOrNull ?? 'Уровень не указан';

  static String interestTitle(String id) =>
      interests.where((i) => i.id == id).map((i) => i.title).firstOrNull ?? id;
}