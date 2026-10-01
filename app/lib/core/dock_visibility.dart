import 'package:flutter/material.dart';

/// Слушает push/pop, чтобы корневой экран знал: перекрыт ли он подстраницей.
///
/// Штатный способ узнать это — `NavigatorObserver`; у `ModalRoute` нет
/// `addListener`, и подписываться на неё напрямую нельзя.
class DockVisibilityObserver extends NavigatorObserver {
  DockVisibilityObserver(this.onCoveredChanged);

  /// true — открыта подстраница, корневой экран перекрыт.
  final ValueChanged<bool> onCoveredChanged;

  int _depth = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    // Первый маршрут — сам RootShell, он не считается перекрытием.
    if (previousRoute != null) _update(1);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _update(-1);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _update(-1);
  }

  void _update(int delta) {
    final was = _depth > 0;
    _depth = (_depth + delta).clamp(0, 99);
    final now = _depth > 0;
    if (was != now) onCoveredChanged(now);
  }
}

/// Признак «корневой экран перекрыт подстраницей».
///
/// Живёт вне дерева: навигатор создаётся раньше RootShell, и observer нужен
/// уже при сборке `MaterialApp`. Отдельный файл — чтобы `main.dart` и
/// `root_shell.dart` не импортировали друг друга.
final dockHideNotifier = ValueNotifier<bool>(false);

final dockCovered = DockVisibilityObserver(
  (covered) => dockHideNotifier.value = covered,
);
