import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/widgets/glass_dock.dart';
import '../state/providers.dart';
import 'catalog/catalog_screen.dart';
import 'favorites/favorites_screen.dart';
import 'home/home_screen.dart';
import 'more/more_screen.dart';
import 'onboarding/onboarding_screen.dart';

/// Корневой экран: контент во весь экран + парящий док поверх (docs/UI.md §2).
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
    DockItem(Icons.person_rounded, 'Другое'),
  ];

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);

    // Первый запуск — мини-опрос. «Пропустить» тоже считается пройденным
    // состоянием: приложение остаётся пригодным без единого ответа.
    if (!profile.completed) {
      return OnboardingScreen(
        initial: profile,
        onDone: (p) => ref.read(profileProvider.notifier).save(p),
      );
    }

    return Scaffold(
      extendBody: true, // док парит поверх контента
      body: IndexedStack(
        index: _index,
        children: const [
          HomeScreen(),
          CatalogScreen(),
          FavoritesScreen(),
          MoreScreen(),
        ],
      ),
      bottomNavigationBar: GlassDock(
        items: _items,
        selectedIndex: _index,
        onSelected: (i) => setState(() => _index = i),
      ),
    );
  }
}