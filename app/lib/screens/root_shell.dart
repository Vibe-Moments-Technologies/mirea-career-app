import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/dock_visibility.dart';
import '../core/widgets/glass_dock.dart';
import '../state/providers.dart';
import 'archive/archive_screen.dart';
import 'favorites/favorites_screen.dart';
import 'home/home_screen.dart';
import 'more/more_screen.dart';
import 'onboarding/onboarding_screen.dart';
import 'org/organizations_screen.dart';

/// Корневой экран: контент во весь экран + парящий док поверх.
///
/// Док сам позиционируется через `Positioned` внутри себя, а RootShell
/// кладёт его в Stack и прячет, пока открыта подстраница.
class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell>
    with SingleTickerProviderStateMixin {
  int _index = 0;

  /// Пока открыта подстраница, док уезжает вниз и гаснет.
  ///
  /// Он всё равно перекрыт новым маршрутом, но при возврате виден сразу на
  /// месте — а при уходе вложенный экран выезжает поверх дока, и без этой
  /// анимации док «торчит» из-под края неподвижным.
  late final AnimationController _dockVisibility = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 1,
  );

  static const _items = <DockItem>[
    DockItem(Icons.home_rounded, 'Главная'),
    DockItem(Icons.inventory_2_rounded, 'Архив'),
    DockItem(Icons.apartment_rounded, 'Организации'),
    DockItem(Icons.bookmark_rounded, 'Избранное'),
    DockItem(Icons.person_rounded, 'Ещё'),
  ];

  @override
  void initState() {
    super.initState();
    // Признак приходит от NavigatorObserver: у ModalRoute нет addListener,
    // а observer — штатный способ узнать про push/pop.
    dockHideNotifier.addListener(_syncDock);
    _syncDock();
  }

  void _syncDock() {
    if (!mounted) return;
    dockHideNotifier.value ? _dockVisibility.reverse() : _dockVisibility.forward();
  }

  @override
  void dispose() {
    dockHideNotifier.removeListener(_syncDock);
    _dockVisibility.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);

    if (!profile.completed) {
      return OnboardingScreen(
        initial: profile,
        onDone: (p) => ref.read(profileProvider.notifier).save(p),
      );
    }

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          IndexedStack(
            index: _index,
            children: const [
              HomeScreen(),
              ArchiveScreen(),
              OrganizationsScreen(),
              FavoritesScreen(),
              MoreScreen(),
            ],
          ),
          // Отступ от системной панели задаётся ЗДЕСЬ, а не внутри дока:
          // с left+right+bottom у Positioned жёсткие ограничения, и внутренний
          // отступ растягивался, а док уезжал на home-indicator.
          Positioned(
            left: 0,
            right: 0,
            bottom: GlassDock.bottomInset(context),
            child: AnimatedBuilder(
              animation: _dockVisibility,
              builder: (context, child) => IgnorePointer(
                // Пока док уезжает, он не должен ловить нажатия — иначе тап
                // по уезжающей капсуле открывает вкладку под подстраницей.
                ignoring: _dockVisibility.value < 1,
                child: SlideTransition(
                  // begin — скрытое положение (ниже экрана), end — рабочее.
                  // Значение 1 = док на месте: если поменять местами, при
                  // единице док уезжает вниз и висит за краем экрана.
                  position: Tween<Offset>(
                    begin: const Offset(0, 1.4),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: _dockVisibility,
                    curve: Curves.easeOutCubic,
                  )),
                  child: FadeTransition(
                    opacity: _dockVisibility,
                    child: child,
                  ),
                ),
              ),
              child: GlassDock(
                items: _items,
                selectedIndex: _index,
                onSelected: (i) => setState(() => _index = i),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
