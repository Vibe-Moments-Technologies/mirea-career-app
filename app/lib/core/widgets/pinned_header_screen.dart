import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_scroll.dart';

/// Шаблон страницы с закреплённой шапкой.
///
/// Шапка (заголовок + кнопки) прилипает к верху: контент прокручивается
/// ПОД неё, никогда не над ней. Над шапкой — непрозрачная зона safe area
/// (статус-бар), чтобы под вырезом не просвечивал скроллящийся контент.
///
/// Так устроены главная, организации, избранное и архив: одинаковая
/// механика, одинаковые отступы. Любой блок можно закрепить аналогично —
/// [PinnedTabStrip] ниже (сегменты-вкладки) использует ту же схему.
class PinnedHeaderScreen extends StatelessWidget {
  const PinnedHeaderScreen({
    super.key,
    required this.title,
    required this.slivers,
    this.actions = const [],
    this.tabs,
    this.onRefresh,
    this.bottom = 8,
  });

  final String title;

  /// Кнопки справа от заголовка (поиск, фильтры).
  final List<Widget> actions;

  /// Сегменты-вкладки, которые закрепляются под шапкой (PinnedTabStrip).
  final Widget? tabs;

  /// Контент страницы. Первый элемент НЕ должен включать свой заголовок.
  final List<Widget> slivers;

  /// Свайп-обновление; null — прокрутка обычная.
  final Future<void> Function()? onRefresh;

  /// Отступ под закреплённой зоной (шапка+вкладки).
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    // Высоты считаются один раз по контексту: safe area сверху входит в
    // min/maxExtent — иначе Column в delegate переполняется на скролле.
    final top = AppInsets.top(context, extra: 0);
    final tabsHeight = tabs != null ? _kTabsHeight : 0.0;

    return CustomScrollView(
      physics: onRefresh != null ? AppScroll.refreshable : AppScroll.plain,
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _HeaderDelegate(
            title: title,
            actions: actions,
            tabs: tabs,
            topInset: top,
            tabsHeight: tabsHeight,
            bottom: bottom,
            background: bg,
          ),
        ),
        ...slivers,
      ],
    );
  }
}

/// Высота строки заголовка (без safe area сверху и вкладок).
const _kHeaderRow = 56.0;

/// Фиксированная высота закреплённой полосы вкладок.
const _kTabsHeight = 52.0;

class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  _HeaderDelegate({
    required this.title,
    required this.actions,
    required this.topInset,
    required this.tabsHeight,
    required this.bottom,
    required this.background,
    this.tabs,
  });

  final String title;
  final List<Widget> actions;

  /// Safe area сверху: непрозрачная зона над заголовком.
  final double topInset;

  /// Высота полосы вкладок (0 — вкладок нет).
  final double tabsHeight;
  final double bottom;
  final Color background;
  final Widget? tabs;

  @override
  double get minExtent => topInset + _kHeaderRow + tabsHeight + bottom;

  @override
  double get maxExtent => minExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // Контент проезжает под шапкой — добавляем нижнюю границу, иначе
    // карточки «протекают» сквозь заголовок.
    final scrolled = overlapsContent;
    final pad = AppInsets.horizontal(MediaQuery.sizeOf(context).width);
    return Material(
      color: background,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Safe area сверху непрозрачна — контент под вырезом не виден.
          SizedBox(height: topInset),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: SizedBox(
              height: _kHeaderRow,
              child: Row(
                children: [
                  Expanded(child: ScreenTitle(title)),
                  for (final a in actions) a,
                ],
              ),
            ),
          ),
          if (tabs != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: SizedBox(height: tabsHeight, child: tabs),
            ),
          if (scrolled)
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
      old.tabs != tabs ||
      old.background != background ||
      old.bottom != bottom ||
      old.topInset != topInset ||
      old.tabsHeight != tabsHeight;
}

/// Закрепляемая полоса сегментов-вкладок («Для вас / Все / …»).
///
/// Используется внутри [PinnedHeaderScreen.tabs]: экран передаёт список
/// сегментов и колбэк, полоса рисует капсульный переключатель и
/// прилипает под шапкой наравне с ней.
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
