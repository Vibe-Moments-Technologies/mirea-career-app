import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Маршрут перехода между экранами — по платформе.
///
/// iOS: [WideSwipeBackRoute] — переход Cupertino с честным интерактивным
/// жестом «назад» (покадровое перетаскивание, как в нативных приложениях)
/// и расширенной зоной захвата 44 pt от левого края. Системный детектор
/// `CupertinoPageRoute` ловит только 20 pt — в него трудно попасть, и жест
/// «то срабатывает, то нет».
///
/// Android: `MaterialPageRoute`. Жест назад системный (predictive back),
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
/// Устроен как фреймворковый `_CupertinoBackGestureDetector`
/// (cupertino/route.dart), но полоса шире. КРИТИЧНО:
/// - распознаватель — `HorizontalDragGestureRecognizer` в
///   `RawGestureDetector`, а не `GestureDetector`: у распознавателя есть
///   состояние, и его ОБЯЗАТЕЛЬНО надо снять (onCancel), когда арена
///   отдаёт жест списку/карусели — иначе `didStartUserGesture`
///   остаётся незакрытым и навигатор зависает: маршруты перестают
///   отвечать, страницы не листаются. Это и был баг «отодвинул кусок
///   страницы — приложение зависло»;
/// - дельта делится на ШИРИНУ ЭКРАНА (как в iOS): полный свайп через
///   экран = полный отъезд страницы, а не фикс. 300 px.
class _WideBackGesture<T> extends StatefulWidget {
  const _WideBackGesture({required this.route, required this.child});

  final WideSwipeBackRoute<T> route;
  final Widget child;

  @override
  State<_WideBackGesture<T>> createState() => _WideBackGestureState<T>();
}

class _WideBackGestureState<T> extends State<_WideBackGesture<T>> {
  late final HorizontalDragGestureRecognizer _recognizer =
      HorizontalDragGestureRecognizer(debugOwner: this)
        ..onStart = _handleDragStart
        ..onUpdate = _handleDragUpdate
        ..onEnd = _handleDragEnd
        ..onCancel = _handleDragCancel;

  _DragController? _active;

  // Кэш ширины экрана: дельта жеста нормируется на неё.
  double get _screenWidth => context.size?.width ?? 400;

  void _handleDragStart(DragStartDetails details) {
    if (!widget.route.popGestureEnabled) return;
    final controller = widget.route.gestureController();
    if (controller == null) return;
    // Прежний контроллер мог остаться после незакрытого жеста —
    // закрываем, чтобы не «залипал» userGestureInProgress.
    _active?.dispose();
    _active = _DragController(
      navigator: widget.route.navigator!,
      controller: controller,
      getIsCurrent: () => widget.route.isCurrent,
      getIsActive: () => widget.route.isActive,
    );
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    // Свайп вправо (delta > 0) уводит страницу влево — уменьшаем позицию.
    // Нормализация на ширину: полный жест через экран = 1.0.
    _active?.dragUpdate(details.primaryDelta! / _screenWidth);
  }

  void _handleDragEnd(DragEndDetails details) {
    // Скорость — как доля ширины экрана в секунду (фреймворковая метрика).
    final velocity =
        details.velocity.pixelsPerSecond.dx / _screenWidth;
    _active?.dragEnd(velocity);
    _active = null;
  }

  /// Арена отдала жест другому (список, карусель) или палец замер:
  /// ОБЯЗАТЕЛЬНО завершаем пользовательский жест, иначе навигатор
  /// зависает. Досматриваем страницу на место.
  void _handleDragCancel() {
    _active?.dragEnd(0);
    _active = null;
  }

  @override
  void dispose() {
    _recognizer.dispose();
    // Виджет исчез посреди жеста — закрыть жест в кадре, когда навигатор
    // ещё жив (как делает фреймворковый детектор).
    if (_active != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.route.navigator?.mounted ?? false) {
          _active?.dispose();
        }
        _active = null;
      });
    }
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
            child: Listener(
              onPointerDown: _onPointerDown,
              behavior: HitTestBehavior.translucent,
            ),
          ),
      ],
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    if (widget.route.popGestureEnabled) _recognizer.addPointer(event);
  }
}

/// Управление анимацией маршрута во время жеста: drag двигает страницу
/// покадрово, отпускание — досматривает анимацию в сторону жеста.
///
/// Логика с приватного `_CupertinoBackGestureController` фреймворка:
/// порог флинга, кривая fastEaseInToSlowEaseOut, поведение при
/// программном pop во время жеста.
class _DragController {
  _DragController({
    required this.navigator,
    required this.controller,
    required this.getIsCurrent,
    required this.getIsActive,
  }) {
    navigator.didStartUserGesture();
  }

  final NavigatorState navigator;
  final AnimationController controller;
  final ValueGetter<bool> getIsCurrent;
  final ValueGetter<bool> getIsActive;

  static const _minFlingVelocity = 1.0; // ширины экрана в секунду
  static const _droppedDuration = Duration(milliseconds: 350);
  static const _curve = Curves.fastEaseInToSlowEaseOut;

  /// Позиция маршрута: 1.0 — на месте, 0.0 — ушла.
  void dragUpdate(double delta) {
    controller.value = (controller.value - delta).clamp(0.0, 1.0);
  }

  /// Отпускание: скорость или позиция решают, pop это или возврат.
  void dragEnd(double velocity) {
    final isCurrent = getIsCurrent();
    final bool pop; // true — анимация «страница уезжает» (назад)

    if (!isCurrent) {
      // Маршрут уже закрыт программно во время жеста: досматриваем туда,
      // где он есть в стеке, а не туда, куда тянул палец.
      pop = !getIsActive();
    } else if (velocity.abs() >= _minFlingVelocity) {
      // Свайп вправо (v > 0) — назад: страница уезжает.
      pop = velocity > 0;
    } else {
      // Медленное отпускание: досматриваем туда, куда утащили.
      pop = controller.value < 0.5;
    }

    if (!pop) {
      controller.animateTo(1.0, duration: _droppedDuration, curve: _curve);
    } else {
      if (isCurrent) navigator.pop();
      if (controller.isAnimating) {
        controller.animateBack(0.0,
            duration: _droppedDuration, curve: _curve);
      }
    }

    if (controller.isAnimating) {
      // Жест считается «в процессе», пока досматривается анимация — иначе
      // переход переключит линейность на кривую посреди полёта.
      late AnimationStatusListener listener;
      listener = (status) {
        navigator.didStopUserGesture();
        controller.removeStatusListener(listener);
      };
      controller.addStatusListener(listener);
    } else {
      navigator.didStopUserGesture();
    }
  }

  void dispose() => navigator.didStopUserGesture();
}
