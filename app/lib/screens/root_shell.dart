import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/dock_visibility.dart';
import '../core/widgets/glass_dock.dart';
import '../state/providers.dart';
import 'favorites/favorites_screen.dart';
import 'home/home_screen.dart';
import 'more/more_screen.dart';
import 'onboarding/onboarding_screen.dart';
import 'services/services_screen.dart';

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

  /// Общий контроллер прокрутки вкладок: тап по активной кнопке дока
  /// скроллит экран к началу.
  final _scrollController = ScrollController();

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

  /// 4 вкладки. Календарь убран (запрос): событие с датой видно в
  /// ленте и деталях карточки. Вместо него — «Сервисы»: заглушка
  /// до появления сервисов вуза. Организации — раздел «Ещё».
  static const _items = <DockItem>[
    DockItem(Icons.home_rounded, 'Главная'),
    DockItem(Icons.widgets_rounded, 'Сервисы'),
    DockItem(Icons.bookmark_rounded, 'Сохранённое'),
    DockItem(Icons.person_rounded, 'Ещё'),
  ];

  @override
  void initState() {
    super.initState();
    // Признак приходит от NavigatorObserver: у ModalRoute нет addListener,
    // а observer — штатный способ узнать про push/pop.
    dockHideNotifier.addListener(_syncDock);
    _syncDock();
    // Сверка профиля со справочниками БД: панель могла удалить институт/
    // уровень/тег — вычищаем их из локального профиля при старте.
    _sanitizeProfile();
  }

  Future<void> _sanitizeProfile() async {
    final store = ref.read(localStoreProvider);
    final repo = ref.read(postsRepoProvider);
    final cleaned = await sanitizeProfileAgainstCatalogs(store.profile, repo);
    if (cleaned == store.profile) return;
    await ref.read(profileProvider.notifier).save(cleaned);
  }

  void _syncDock() {
    if (!mounted) return;
    dockHideNotifier.value ? _dockVisibility.reverse() : _dockVisibility.forward();
  }

  @override
  void dispose() {
    dockHideNotifier.removeListener(_syncDock);
    _dockVisibility.dispose();
    _scrollController.dispose();
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
      body: PrimaryScrollController(
        // Тап по активной вкладке дока — «наверх» как в нативных
        // таб-барах. Контроллер общий, но у каждого экрана свой
        // ScrollPosition (CustomScrollView.attach); слушатель скроллит
        // позицию АКТИВНОГО экрана — она одна подключена.
        controller: _scrollController,
        child: Stack(
        children: [
          IndexedStack(
            index: _index,
            children: const [
              HomeScreen(),
              ServicesScreen(),
              SavedScreen(),
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
                onSelected: (i) {
                  if (i == _index) {
                    // Тап по активной вкладке — промотать её наверх
                    // (стандартное поведение iOS/Android таб-баров).
                    _scrollToTop();
                  } else {
                    setState(() => _index = i);
                  }
                },
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  /// Скролл активной вкладки наверх: плавно, с системной кривой.
  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }
}
