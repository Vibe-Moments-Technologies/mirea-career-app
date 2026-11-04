import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Маршрут перехода между экранами — по платформе.
///
/// iOS: [WideSwipeBackRoute] — переход Cupertino с честным интерактивным
/// жестом «назад» (покадровое перетаскивание, как в нативных приложениях)
/// и расширенной зоной захвата 44 pt от левого края. Системный детектор
/// `CupertinoPageRoute` ловит только 20 pt — в него трудно попасть, и жест
/// «то срабатывает, то нет». Прежняя попытка расширить зону прозрачной
/// полосой с обычным pop была сломана: вызывала pop при свайпе ВЛЕВО
/// (противоположная сторона) и без анимации — отсюда «ломаные» возвраты.
///
/// Android: `MaterialRoute`e. Жест назад системный (predictive back),
/// а переход остаётся iOS-стилем — его задаёт `pageTransitionsTheme`.
Route<T> appRoute<T>(BuildContext context, Widget page) =>
    switch (Theme.of(context).platform) {
      TargetPlatform.iOS => WideSwipeBackRoute<T>(builder: (_) => page),
      _ => MaterialPageRoute<T>(builder: (_) => page),
    };

/// PageRoute с Cupertino-переходом и широким интерактивным свайпом «назад».
///
/// Смесь [CupertinoRouteTransitionMixin] (переходы и вторичная анимация —
/// страница под новой уезжает влево и гаснет ровно как в iOS) и СОБСТВЕННОГО
/// детектора жеста: фреймворковый ловит свайп только в полосе 20 pt.
class WideSwipeBackRoute<T> extends PageRouteBuilder<T>
    with CupertinoRouteTransitionMixin<T> {
  WideSwipeBackRoute({required WidgetBuilder builder})
      : _builder = builder,
        super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionDuration: const Duration(milliseconds: 350),
          reverseTransitionDuration: const Duration(milliseconds: 300),
        );

  final WidgetBuilder _builder;

  @override
  Widget buildContent(BuildContext context) => _builder(context);

  @override
  String? get title => null;

  /// Ширина зоны захвата жеста «назад» (тач-цель из гайдлайнов).
  static const dragWidth = 44.0;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // В середине интерактивного жеста переход линейный — страница следует
    // за пальцем, а не проигрывает кривую поверх движения.
    return CupertinoPageTransition(
      primaryRouteAnimation: animation,
      secondaryRouteAnimation: secondaryAnimation,
      linearTransition: popGestureInProgress,
      child: _WideBackGesture<T>(route: this, child: child),
    );
  }

  /// controller — protected в TransitionRoute; для жеста отдаём через
  /// метод самого маршрута (законный доступ из подкласса).
  AnimationController? gestureController() => controller;
}

/// Детектор интерактивного свайпа «назад» с зоной 44 pt.
///
/// Логика — как у фреймворкового `_CupertinoBackGestureDetector`
/// (cupertino/route.dart), но полоса шире. Вертикальные движения не
/// перехватываем: вдоль левого края прокручиваются списки.
class _WideBackGesture<T> extends StatefulWidget {
  const _WideBackGesture({required this.route, required this.child});

  final WideSwipeBackRoute<T> route;
  final Widget child;

  @override
  State<_WideBackGesture<T>> createState() => _WideBackGestureState<T>();
}

class _WideBackGestureState<T> extends State<_WideBackGesture<T>> {
  _DragController? _active;

  void _onHorizontalDragStart(DragStartDetails details) {
    if (!widget.route.popGestureEnabled) return;
    final controller = widget.route.gestureController();
    if (controller == null) return;
    setState(() {
      _active = _DragController(
        navigator: widget.route.navigator!,
        controller: controller,
        getIsCurrent: () => widget.route.isCurrent,
      );
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    _active?.dragUpdate(details.primaryDelta ?? 0);
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    // Свайп вправо (положительная скорость) — назад: жест iOS.
    _active?.dragEnd(details.primaryVelocity ?? 0);
    setState(() => _active = null);
  }

  @override
  void dispose() {
    _active?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        if (widget.route.popGestureEnabled)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: WideSwipeBackRoute.dragWidth,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: _onHorizontalDragStart,
              onHorizontalDragUpdate: _onHorizontalDragUpdate,
              onHorizontalDragEnd: _onHorizontalDragEnd,
              excludeFromSemantics: true,
            ),
          ),
      ],
    );
  }
}

/// Управление анимацией маршрута во время жеста: drag двигает страницу
/// покадрово, отпускание — досматривает анимацию в сторону жеста.
///
/// Переписано с приватного `_CupertinoBackGestureController` фреймворка.
class _DragController {
  _DragController({
    required this.navigator,
    required this.controller,
    required this.getIsCurrent,
  }) {
    navigator.didStartUserGesture();
  }

  final NavigatorState navigator;
  final AnimationController controller;
  final ValueGetter<bool> getIsCurrent;

  void dragUpdate(double delta) {
    // Логические координаты: 1.0 — страница на месте, 0.0 — ушла.
    // Свайп вправо (delta > 0) уводит страницу влево — уменьшаем позицию.
    final next = controller.value - delta / 300; // полный свайп ≈ 300pt
    controller.value = next.clamp(0.0, 1.0);
  }

  void dragEnd(double velocity) {
    final bool pop;
    if (velocity.abs() >= 100) {
      // Флик: направление задаёт скорость.
      pop = velocity > 0;
    } else {
      // Медленное отпускание: досматриваем туда, куда утащили.
      pop = controller.value < 0.5;
    }

    if (pop && getIsCurrent()) {
      navigator.pop();
    } else {
      // Возврат на место — с кривой, не линейно.
      controller.animateTo(1.0, duration: const Duration(milliseconds: 240));
    }
    navigator.didStopUserGesture();
  }

  void dispose() => navigator.didStopUserGesture();
}
