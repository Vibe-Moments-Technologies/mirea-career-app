/// Форматирование дат, диапазонов и «срочности» для карточек и деталей.
///
/// Один источник правды: раньше короткая дата была в post_card.dart,
/// полная — в post_detail_screen.dart, и подписи разъезжались.
///
/// Даты приходят из PocketBase в UTC и показываются как введены админом
/// (без перевода в локальную зону): администратор ставит «09:00» и видит
/// «09:00». Сравнения с текущим моментом Dart считает по абсолютным
/// значениям времени, поэтому на корректность «актуально/архив» это не влияет.
library;

const _monthsShort = [
  'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
  'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
];

const _monthsFull = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

/// «15 окт» — для компактных мест (карточка в ленте).
String dateShort(DateTime d) => '${d.day} ${_monthsShort[d.month - 1]}';

/// «15 октября» — для развёрнутых мест (страница деталей).
String dateFull(DateTime d) => '${d.day} ${_monthsFull[d.month - 1]}';

/// «15 октября 2026» — когда важен год (архив, дальние даты).
String dateFullYear(DateTime d) =>
    '${d.day} ${_monthsFull[d.month - 1]} ${d.year}';

/// «09:00».
String timeOf(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

bool _hasTime(DateTime d) => d.hour != 0 || d.minute != 0;

/// Дата и время, если оно задано: «15 октября, 09:00».
String dateWithTime(DateTime d) =>
    _hasTime(d) ? '${dateFull(d)}, ${timeOf(d)}' : dateFull(d);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Человекочитаемый период: «15 октября, 09:00 — 18:00»,
/// «15 — 20 октября», «15 октября — 3 ноября».
///
/// Возвращает null, если дат нет вовсе.
String? dateRange(DateTime? start, DateTime? end) {
  if (start == null) {
    return end == null ? null : dateWithTime(end);
  }
  if (end == null) return dateWithTime(start);

  if (_sameDay(start, end)) {
    if (!_hasTime(start) || !_hasTime(end)) return dateFull(start);
    return '${dateFull(start)}, ${timeOf(start)} — ${timeOf(end)}';
  }
  if (start.year == end.year && start.month == end.month) {
    return '${start.day} — ${dateFull(end)}';
  }
  return '${dateFull(start)} — ${dateFull(end)}';
}

/// Русская множественная форма: plural(2, 'день', 'дня', 'дней') → «дня».
String plural(int n, String one, String few, String many) {
  final m10 = n % 10;
  final m100 = n % 100;
  if (m10 == 1 && m100 != 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}

/// Подпись срочности: «Осталось 3 дня», «Осталось 5 часов»,
/// «Заканчивается сегодня».
///
/// null — если дедлайна нет, он уже прошёл или до него больше недели:
/// плашка «осталось 40 дней» не мотивирует, а только шумит.
String? urgencyLabel(DateTime? end) {
  if (end == null) return null;
  final diff = end.difference(DateTime.now());
  if (diff.isNegative) return null;
  if (diff.inDays > 7) return null;
  if (diff.inDays >= 1) {
    final d = diff.inDays;
    return 'Осталось $d ${plural(d, 'день', 'дня', 'дней')}';
  }
  if (diff.inHours >= 1) {
    final h = diff.inHours;
    return 'Осталось $h ${plural(h, 'час', 'часа', 'часов')}';
  }
  return 'Заканчивается сегодня';
}

/// Подпись для завершившегося: «Завершилось 3 дня назад».
///
/// Используется на странице деталей, где срочность уже не нужна,
/// но понятно «насколько давно» — полезно.
String? pastLabel(DateTime? end) {
  if (end == null) return null;
  final diff = DateTime.now().difference(end);
  if (diff.isNegative) return null;
  final days = diff.inDays;
  if (days < 1) return 'Завершилось сегодня';
  if (days > 365) return null; // слишком давно — дата важнее подписи
  return 'Завершилось $days ${plural(days, 'день', 'дня', 'дней')} назад';
}
