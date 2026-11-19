import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../post/post_detail_screen.dart';

class CalendarServiceScreen extends ConsumerStatefulWidget {
  const CalendarServiceScreen({super.key});

  @override
  ConsumerState<CalendarServiceScreen> createState() =>
      _CalendarServiceScreenState();
}

class _CalendarServiceScreenState extends ConsumerState<CalendarServiceScreen> {
  int _tabIndex = 1; // 0 избранные, 1 все, 2 университет, 3 партнёры
  late DateTime _month;
  DateTime? _selectedDay;

  static const _tabs = <String>[
    'Избранные',
    'Все',
    'Университет',
    'Партнёры',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(feedProvider.notifier).ensureLoaded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider);
    final favorites = ref.watch(favoritesProvider);
    final favSet = favorites.toSet();

    final allEvents = feed.posts.where(_hasDate).toList();
    final events = _filterForTab(allEvents, favSet);
    final eventsByDay = _eventsByDay(events);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Календарь'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          _TabsBar(
            tabs: _tabs,
            selected: _tabIndex,
            onSelected: (i) => setState(() {
              _tabIndex = i;
              _selectedDay = null;
            }),
          ),
          const SizedBox(height: 8),
          if (feed.loading && allEvents.isEmpty)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  AppInsets.horizontal(MediaQuery.sizeOf(context).width),
                  0,
                  AppInsets.horizontal(MediaQuery.sizeOf(context).width),
                  AppInsets.scrollBottom(context),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MonthCalendar(
                      month: _month,
                      selectedDay: _selectedDay,
                      eventsByDay: eventsByDay,
                      onPrev: () => setState(() {
                        _month = DateTime(_month.year, _month.month - 1);
                        _selectedDay = null;
                      }),
                      onNext: () => setState(() {
                        _month = DateTime(_month.year, _month.month + 1);
                        _selectedDay = null;
                      }),
                      onSelect: (day) {
                        final d = _dayOnly(day);
                        final dayEvents = eventsByDay[d] ?? const <_DayEvent>[];
                        if (dayEvents.isEmpty) return;
                        setState(() => _selectedDay = d);
                        _showDayEvents(context, d, dayEvents);
                      },
                    ),
                    const SizedBox(height: 12),
                    const _Legend(),
                    const SizedBox(height: 16),
                    if (events.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          _tabIndex == 0
                              ? 'Нет избранных событий с датами'
                              : 'Нет событий с датами',
                          textAlign: TextAlign.center,
                          style: AppText.body
                              .copyWith(color: AppColors.secondaryLight),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _hasDate(Post p) => p.startDate != null;

  List<Post> _filterForTab(List<Post> posts, Set<String> favSet) {
    switch (_tabIndex) {
      case 0:
        return posts.where((p) => favSet.contains(p.id)).toList();
      case 2:
        return posts
            .where((p) => p.organizationType == 'university_dept')
            .toList();
      case 3:
        return posts.where((p) => p.isPartner).toList();
      case 1:
      default:
        return posts;
    }
  }

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  Map<DateTime, List<_DayEvent>> _eventsByDay(List<Post> events) {
    final map = <DateTime, List<_DayEvent>>{};
    for (final p in events) {
      final start = _dayOnly(p.startDate!);
      final rawEnd = _dayOnly(p.endDate ?? p.startDate!);
      final last = rawEnd.isBefore(start) ? start : rawEnd;
      final isSingle = !last.isAfter(start);
      var cur = start;
      while (!cur.isAfter(last)) {
        final isStart = cur == start;
        final isEnd = cur == last;
        map.putIfAbsent(cur, () => []).add(_DayEvent(
              post: p,
              showStart: isStart,
              showEnd: isEnd && !isSingle,
              singleDay: isSingle && isStart,
            ));
        cur = cur.add(const Duration(days: 1));
      }
    }
    return map;
  }

  void _showDayEvents(
      BuildContext context, DateTime day, List<_DayEvent> dayEvents) {
    final seen = <String>{};
    final posts = <Post>[];
    for (final e in dayEvents) {
      if (seen.add(e.post.id)) posts.add(e.post);
    }
    posts.sort((a, b) {
      final da = a.startDate ?? DateTime(2100);
      final db = b.startDate ?? DateTime(2100);
      return da.compareTo(db);
    });
    final title =
        '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.${day.year}';
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.45,
        minChildSize: 0.25,
        maxChildSize: 0.85,
        builder: (_, controller) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('События $title', style: AppText.title),
            ),
            Expanded(
              child: ListView.separated(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: posts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final p = posts[i];
                  return _EventTile(
                    post: p,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).push(
                        appRoute(context, PostDetailScreen(post: p)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayEvent {
  const _DayEvent({
    required this.post,
    required this.showStart,
    required this.showEnd,
    required this.singleDay,
  });
  final Post post;
  final bool showStart;
  final bool showEnd;
  final bool singleDay;
}

class _TabsBar extends StatelessWidget {
  const _TabsBar({
    required this.tabs,
    required this.selected,
    required this.onSelected,
  });
  final List<String> tabs;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: AppInsets.horizontal(MediaQuery.sizeOf(context).width),
        ),
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final active = i == selected;
          final scheme = Theme.of(context).colorScheme;
          return ChoiceChip(
            label: Text(tabs[i]),
            selected: active,
            onSelected: (_) => onSelected(i),
            selectedColor: scheme.primary.withValues(alpha: 0.18),
            labelStyle: TextStyle(
              color: active ? scheme.primary : AppColors.secondaryLight,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            ),
            side: BorderSide(
              color: active ? scheme.primary : AppColors.separator(context),
            ),
            showCheckmark: false,
          );
        },
      ),
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.selectedDay,
    required this.eventsByDay,
    required this.onPrev,
    required this.onNext,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime? selectedDay;
  final Map<DateTime, List<_DayEvent>> eventsByDay;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onSelect;

  static const _weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
  static const _months = [
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final startOffset = first.weekday - 1; // Mon=0
    final totalCells = startOffset + daysInMonth;
    final rows = (totalCells / 7).ceil();
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.separator(context)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: onPrev,
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_months[month.month - 1]} ${month.year}',
                    style: AppText.headline,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: onNext,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final w in _weekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: AppText.caption.copyWith(
                        color: AppColors.secondaryLight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var r = 0; r < rows; r++)
            Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(
                    child: _buildCell(
                      context,
                      r * 7 + c,
                      startOffset,
                      daysInMonth,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildCell(
    BuildContext context,
    int index,
    int startOffset,
    int daysInMonth,
  ) {
    final dayNum = index - startOffset + 1;
    if (dayNum < 1 || dayNum > daysInMonth) {
      return const SizedBox(height: 46);
    }
    final day = DateTime(month.year, month.month, dayNum);
    final key = DateTime(day.year, day.month, day.day);
    final markers = eventsByDay[key] ?? const <_DayEvent>[];
    final hasEvents = markers.isNotEmpty;
    final hasStart = markers.any((m) => m.showStart || m.singleDay);
    final hasEnd = markers.any((m) => m.showEnd);
    final isSelected = selectedDay != null &&
        selectedDay!.year == day.year &&
        selectedDay!.month == day.month &&
        selectedDay!.day == day.day;
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: hasEvents ? () => onSelect(day) : null,
      child: Container(
        height: 46,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$dayNum',
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: hasEvents
                    ? scheme.onSurface
                    : AppColors.secondaryLight.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (hasStart) _dot(const Color(0xFF34C759)),
                  if (hasStart && hasEnd) const SizedBox(width: 3),
                  if (hasEnd) _dot(const Color(0xFFFF3B30)),
                  if (!hasStart && !hasEnd) const SizedBox(width: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _dot(Color color) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _item(const Color(0xFF34C759), 'начало'),
        const SizedBox(width: 16),
        _item(const Color(0xFFFF3B30), 'окончание'),
      ],
    );
  }

  static Widget _item(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style:
                AppText.caption.copyWith(color: AppColors.secondaryLight),
          ),
        ],
      );
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.post, required this.onTap});
  final Post post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final start = post.startDate;
    final end = post.endDate ?? post.startDate;
    String dateText = '';
    if (start != null) {
      final s = _fmt(start);
      if (end != null && !_sameDay(start, end)) {
        dateText = '$s — ${_fmt(end)}';
      } else {
        dateText = s;
      }
    }

    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: AppColors.separator(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.title,
                      style: AppText.headline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (dateText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        dateText,
                        style: AppText.caption
                            .copyWith(color: AppColors.secondaryLight),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.secondaryLight,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
}
