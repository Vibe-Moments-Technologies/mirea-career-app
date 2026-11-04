import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_scroll.dart';
import 'glass_back_button.dart';

/// Шаблон страницы с закреплённой шапкой.
///
/// Шапка (заголовок + кнопки) прилипает к верху: контент прокручивается
/// ПОД неё. Вкладки (PinnedTabStrip) при скролле УЕЗЖАЮТ под шапку:
/// в ленте важен каждый экран высоты, а вернуться к переключателю можно
/// тапом по активной вкладке дока или проскроллив наверх. Над шапкой —
/// непрозрачная зона safe area (статус-бар), чтобы под вырезом
/// не просвечивал скроллящийся контент.
///
/// Так устроены главная, сохранённое, календарь и архив: одинаковая
/// механика, одинаковые отступы.
class PinnedHeaderScreen extends StatelessWidget {
  const PinnedHeaderScreen({
    super.key,
    required this.title,
    required this.slivers,
    this.actions = const [],
    this.tabs,
    this.onRefresh,
    this.bottom = 8,
    this.controller,
    this.showBack = false,
  });

  final String title;

  /// Показать кнопку «назад» слева от заголовка: для ПОДСТРАНИЦ
  /// (организации из «Ещё»), не вкладок дока. Кнопка стеклянная —
  /// контент под ней прокручивается, как на деталях поста.
  final bool showBack;

  /// Кнопки справа от заголовка (поиск, фильтры).
  final List<Widget> actions;

  /// Сегменты-вкладки: закрепляются под шапкой и уезжают при скролле.
  final Widget? tabs;

  /// Контент страницы. Первый элемент НЕ должен включать свой заголовок.
  final List<Widget> slivers;

  /// Свайп-обновление; null — прокрутка обычная.
  final Future<void> Function()? onRefresh;

  /// Отступ под закреплённой зоной (шапка; вкладкам свой отступ).
  final double bottom;

  /// Контроллер прокрутки: по умолчанию — PrimaryScrollController
  /// (сигнал «наверх» из дока скроллит активную вкладку).
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final top = AppInsets.top(context, extra: 0);

    return CustomScrollView(
      // PrimaryScrollController слушает тап по активной вкладке дока
      // (scrollToTopNotifier в root_shell) и скроллит экран наверх.
      controller: controller ?? PrimaryScrollController.maybeOf(context),
      physics: onRefresh != null ? AppScroll.refreshable : AppScroll.plain,
      slivers: [
        // Шапка прилипает всегда: название и кнопки — навигация.
        SliverPersistentHeader(
          pinned: true,
          delegate: _HeaderDelegate(
            title: title,
            actions: actions,
            showBack: showBack,
            topInset: top,
            bottom: bottom,
            background: bg,
          ),
        ),
        // Вкладки НЕ прилипают: уезжают при скролле вниз, возвращаются
        // при скролле наверх. Анимации не нужно — скорость прокрутки сама
        // задаёт темп, а FadeTransition на каждый кадр дорожает.
        if (tabs != null)
          SliverPersistentHeader(
            pinned: false,
            delegate: _TabsDelegate(
              tabs: tabs!,
              bottom: bottom,
              background: bg,
            ),
          ),
        ...slivers,
      ],
    );
  }
}

/// Высота строки заголовка (без safe area сверху).
const _kHeaderRow = 56.0;

/// Высота полосы вкладок.
const _kTabsHeight = 52.0;

class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  _HeaderDelegate({
    required this.title,
    required this.actions,
    required this.showBack,
    required this.topInset,
    required this.bottom,
    required this.background,
  });

  final String title;
  final List<Widget> actions;
  final bool showBack;

  /// Safe area сверху: непрозрачная зона над заголовком.
  final double topInset;
  final double bottom;
  final Color background;

  @override
  double get minExtent => topInset + _kHeaderRow + bottom;

  @override
  double get maxExtent => minExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);
    return Material(
      color: background,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: topInset),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: SizedBox(
              height: _kHeaderRow,
              child: Row(
                children: [
                  if (showBack) ...[
                    const GlassBackButton(),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: ScreenTitle(title)),
                  for (final a in actions) a,
                ],
              ),
            ),
          ),
          if (overlapsContent)
            Container(
              height: 0.5,
              color: AppColors.separator(context),
            ),
          SizedBox(height: bottom),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_HeaderDelegate old) =>
      old.title != title ||
      old.background != background ||
      old.bottom != bottom ||
      old.topInset != topInset ||
      old.showBack != showBack;
}

/// Неприлипающая полоса вкладок: уезжает при прокрутке.
class _TabsDelegate extends SliverPersistentHeaderDelegate {
  _TabsDelegate({
    required this.tabs,
    required this.bottom,
    required this.background,
  });

  final Widget tabs;
  final double bottom;
  final Color background;

  @override
  double get minExtent => _kTabsHeight + bottom;

  @override
  double get maxExtent => minExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);
    return Material(
      color: background,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: pad),
        child: SizedBox(height: _kTabsHeight, child: tabs),
      ),
    );
  }

  @override
  bool shouldRebuild(_TabsDelegate old) =>
      old.tabs != tabs ||
      old.background != background ||
      old.bottom != bottom;
}

/// Закрепляемая полоса сегментов-вкладок («Для вас / Все / …»).
///
/// Используется внутри [PinnedHeaderScreen.tabs]: экран передаёт список
/// сегментов и колбэк, полоса рисует капсульный переключатель.
class PinnedTabStrip<T> extends StatelessWidget {
  const PinnedTabStrip({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelected,
  });

  /// (id, подпись) для каждого сегмента.
  final List<(T, String)> segments;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: _kTabsHeight,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        children: [
          for (final (id, label) in segments)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelected(id),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected == id
                        ? scheme.primary.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.headline.copyWith(
                      fontSize: 14,
                      color: selected == id
                          ? scheme.primary
                          : AppColors.secondaryLight,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
