import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/widgets/glass_dock.dart';
import '../state/providers.dart';
import 'catalog/catalog_screen.dart';
import 'favorites/favorites_screen.dart';
import 'home/home_screen.dart';
import 'more/more_screen.dart';
import 'onboarding/onboarding_screen.dart';

/// Корневой экран: контент во весь экран + парящий док поверх.
///
/// GlassDock теперь сам позиционируется через Positioned внутри себя.
/// RootShell просто кладёт его в Stack.
class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  int _index = 0;

  static const _items = <DockItem>[
    DockItem(Icons.home_rounded, 'Главная'),
    DockItem(Icons.grid_view_rounded, 'Каталог'),
    DockItem(Icons.bookmark_rounded, 'Избранное'),
    DockItem(Icons.person_rounded, 'Ещё'),
  ];

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
              CatalogScreen(),
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
            child: GlassDock(
              items: _items,
              selectedIndex: _index,
              onSelected: (i) => setState(() => _index = i),
            ),
          ),
        ],
      ),
    );
  }
}