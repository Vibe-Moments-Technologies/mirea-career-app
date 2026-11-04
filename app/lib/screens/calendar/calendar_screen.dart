import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/pinned_header_screen.dart';
import '../../core/widgets/post_card.dart';
import '../../state/providers.dart';
import '../post/post_detail_screen.dart';

/// «Календарь» — вкладка дока: события ленты по датам.
///
/// Мероприятия со start_date образуют ленту времени: ближайшие сверху,
/// группировка по месяцам («Ноябрь 2026»). Посты без даты в календарь
/// не попадают. Из имеющихся данных — без отдельного источника.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(feedProvider.notifier).ensureLoaded(),
    );
  }

  static const _monthNames = <String>[
    '', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
  ];

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider);
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);

    // Предстоящие и идущие сейчас события с датой начала, по
    // возрастанию даты. Свежезавершённые (до недели) не показываем:
    // календарь — про «что впереди», прошедшее остаётся в ленте.
    final events = feed.posts
        .where((p) =>
            p.startDate != null &&
            p.startDate!.isAfter(DateTime.now().subtract(const Duration(days: 1))))
        .toList()
      ..sort((a, b) => a.startDate!.compareTo(b.startDate!));

    return PinnedHeaderScreen(
      title: 'Календарь',
      slivers: [
        if (feed.loading)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
            sliver: SliverList.separated(
              itemCount: 3,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, _) => const PostCardSkeleton(),
            ),
          )
        else if (events.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.event_busy_rounded,
                      size: 56,
                      color: AppColors.secondaryLight.withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 12),
                    Text('Событий пока нет', style: AppText.headline),
                    const SizedBox(height: 4),
                    Text(
                      'Как только в расписании появится что-то\nс датой — увидите это здесь',
                      textAlign: TextAlign.center,
                      style: AppText.footnote
                          .copyWith(color: AppColors.secondaryLight),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 8, pad, AppInsets.scrollBottom(context)),
            sliver: SliverList.builder(
              itemCount: events.length,
              itemBuilder: (_, i) {
                final post = events[i];
                // Заголовок месяца — над первым событием месяца.
                final showMonth = i == 0 ||
                    events[i - 1].startDate!.month != post.startDate!.month ||
                    events[i - 1].startDate!.year != post.startDate!.year;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showMonth) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 10),
                        child: Text(
                          '${_monthNames[post.startDate!.month]} ${post.startDate!.year}',
                          style: AppText.cardTitle.copyWith(
                            color: AppColors.secondaryLight,
                          ),
                        ),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: PostCard(
                        post: post,
                        onTap: () => Navigator.of(context).push(
                          appRoute(context, PostDetailScreen(post: post)),
                        ),
                        filledForm: ref.watch(hasSubmittedProvider(post.id)),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}
