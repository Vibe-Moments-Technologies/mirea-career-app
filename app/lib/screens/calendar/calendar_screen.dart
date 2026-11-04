import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/pinned_header_screen.dart';
import '../../core/widgets/post_card.dart';
import '../../state/providers.dart';
import '../post/post_detail_screen.dart';

/// «Календарь» — вкладка дока: настоящий календарь-месяц.
///
/// Сетка месяца с точками в днях с событиями; тап по дню раскрывает
/// список событий этого дня под сеткой. Месяц листается стрелками
/// (жест-свайп по сетке конфликтует с вертикальной прокруткой экрана).
/// События: посты с датами — предстоящие и идущие.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  /// Показанный месяц: DateTime первого дня (время обнулено).
  late DateTime _month = _monthOf(DateTime.now());

  /// Выбранный день (только день, время обнулено). null — день не
  /// выбран: показываем события ближайших дней.
  DateTime? _selectedDay;

  /// Будни месяца, с которых начинается неделя — понедельник.
  static const _weekdays = ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ', 'ВС'];

  static const _monthNames = [
    '', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
  ];

  static DateTime _monthOf(DateTime d) => DateTime(d.year, d.month);

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(feedProvider.notifier).ensureLoaded(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider);
    final now = DateTime.now();

    // События по дням: предстоящие (start в будущем) и идущие
    // (start в прошлом, end в будущем). Идущие попадают и в СЕГОДНЯ:
    // студенту важнее всего «что живо прямо сейчас», а не «когда
    // началось».
    final dayEvents = <DateTime, List<dynamic>>{};
    for (final p in feed.posts) {
      if (p.startDate == null) continue;
      final startDay = _dayOf(p.startDate!);
      final ongoing = p.endDate != null && p.endDate!.isAfter(now);
      final upcoming = p.startDate!.isAfter(now);
      if (!upcoming && !ongoing) continue;
      dayEvents[startDay] = [...(dayEvents[startDay] ?? []), p];
      // Идущее давно: дублируем в сегодня, чтобы оно не терялось
      // из «ближайших».
      final today = _dayOf(now);
      if (ongoing && startDay.isBefore(today)) {
        dayEvents[today] = [...(dayEvents[today] ?? []), p];
      }
    }

    final eventsShown = _selectedDay == null
        ? _nearestEvents(dayEvents, now)
        : (dayEvents[_selectedDay] ?? const []);

    return PinnedHeaderScreen(
      title: 'Календарь',
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              _MonthHeader(
                label: '${_monthNames[_month.month]} ${_month.year}',
                onPrev: () => _shiftMonth(-1),
                onNext: () => _shiftMonth(1),
              ),
              _MonthGrid(
                month: _month,
                today: _dayOf(now),
                selected: _selectedDay,
                dayEvents: dayEvents,
                onPick: (day) => setState(() => _selectedDay = day),
              ),
              if (_selectedDay != null) ...[
                const SizedBox(height: 6),
                _SelectedDayLabel(day: _selectedDay!),
              ],
            ],
          ),
        ),
        if (feed.loading && dayEvents.isEmpty)
          const SliverToBoxAdapter(child: SizedBox(height: 120))
        else if (eventsShown.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _selectedDay == null
                    ? 'Событий с датами пока нет — добавьте дату карточке, '
                        'и она появится в календаре'
                    : 'В этот день событий нет',
                textAlign: TextAlign.center,
                style: AppText.footnote
                    .copyWith(color: AppColors.secondaryLight),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppInsets.horizontal(MediaQuery.sizeOf(context).width),
              8,
              AppInsets.horizontal(MediaQuery.sizeOf(context).width),
              AppInsets.scrollBottom(context),
            ),
            sliver: SliverList.builder(
              itemCount: eventsShown.length,
              itemBuilder: (_, i) {
                final post = eventsShown[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: PostCard(
                    post: post,
                    onTap: () => Navigator.of(context).push(
                      appRoute(context, PostDetailScreen(post: post)),
                    ),
                    filledForm: ref.watch(hasSubmittedProvider(post.id)),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  /// Ближайшие события: от сегодня вперёд, два первых дня с событиями.
  /// Идущие уже продублированы в «сегодня» (см. build) — они первые.
  List<dynamic> _nearestEvents(
      Map<DateTime, List<dynamic>> dayEvents, DateTime now) {
    final days = dayEvents.keys
        .where((d) => !d.isBefore(_dayOf(now)))
        .toList()
      ..sort();
    if (days.isEmpty) return const [];
    return [
      for (final d in days.take(2)) ...dayEvents[d]!,
    ];
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _selectedDay = null;
    });
  }
}

/// Заголовок месяца со стрелками.
class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.label,
    required this.onPrev,
    required this.onNext,
  });

  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: onPrev,
            tooltip: 'Прошлый месяц',
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppText.headline,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: onNext,
            tooltip: 'Следующий месяц',
          ),
        ],
      ),
    );
  }
}

/// Сетка месяца: 7 столбцов, недели строками, точки в днях с событиями.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.today,
    required this.selected,
    required this.dayEvents,
    required this.onPick,
  });

  final DateTime month;
  final DateTime today;
  final DateTime? selected;
  final Map<DateTime, List> dayEvents;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    // Первый день сетки: понедельник недели, где начинается месяц.
    final first = DateTime(month.year, month.month, 1);
    var gridStart = first.subtract(Duration(days: first.weekday - 1));

    final cells = <DateTime>[];
    while (cells.length < 42) {
      cells.add(gridStart);
      gridStart = gridStart.add(const Duration(days: 1));
      // Хватит 6 недель: если дошли до следующего месяца и уже
      // заполнили хотя бы 5 недель — стоп.
      if (cells.length >= 35 && gridStart.month != month.month) break;
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pad - 4),
      child: Column(
        children: [
          Row(
            children: [
              for (final w in _CalendarScreenState._weekdays)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      w,
                      textAlign: TextAlign.center,
                      style: AppText.caption
                          .copyWith(color: AppColors.secondaryLight),
                    ),
                  ),
                ),
            ],
          ),
          for (var week = 0; week < cells.length ~/ 7; week++)
            Row(
              children: [
                for (final day in cells.skip(week * 7).take(7))
                  Expanded(
                    child: _DayCell(
                      day: day,
                      inMonth: day.month == month.month,
                      isToday: day == today,
                      isSelected: day == selected,
                      hasEvents: dayEvents.containsKey(day),
                      onTap: day.month == month.month
                          ? () => onPick(day)
                          : null,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Один день сетки.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.hasEvents,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final bool hasEvents;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isSelected
                ? accent.withValues(alpha: 0.14)
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${day.day}',
                style: AppText.footnote.copyWith(
                  color: !inMonth
                      ? AppColors.secondaryLight.withValues(alpha: 0.4)
                      : isToday
                          ? accent
                          : null,
                  fontWeight: isToday || isSelected ? FontWeight.w700 : null,
                ),
              ),
              if (hasEvents && inMonth)
                Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Подпись выбранного дня над списком.
class _SelectedDayLabel extends StatelessWidget {
  const _SelectedDayLabel({required this.day});
  final DateTime day;

  static const _months = [
    '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '${day.day} ${_months[day.month]}',
        style: AppText.cardTitle.copyWith(color: AppColors.secondaryLight),
      ),
    );
  }
}
