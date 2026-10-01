import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Маршрут перехода между экранами — по платформе.
///
/// iOS: `CupertinoPageRoute` даёт интерактивный свайп-назад от левого края.
/// У `MaterialPageRoute` такого жеста нет вообще — только кнопка.
///
/// Android: `MaterialPageRoute`. Жест назад там системный, и включать его
/// принудительно не нужно — большинство его выключает. Переход при этом
/// остаётся iOS-стилем: его задаёт `pageTransitionsTheme` в app_theme.dart.
Route<T> appRoute<T>(BuildContext context, Widget page) =>
    switch (Theme.of(context).platform) {
      TargetPlatform.iOS => CupertinoPageRoute<T>(
          builder: (_) => _WideBackArea(child: page),
        ),
      _ => MaterialPageRoute<T>(builder: (_) => page),
    };

/// Расширяет зону жеста «назад» на iOS.
///
/// `CupertinoPageRoute` ловит свайп только в полосе `max(padding.left, 20)`
/// от кромки — эта ширина зашита в фреймворк и через параметры не меняется.
/// На большом экране в 20 pt трудно попасть, поэтому поверх страницы лежит
/// своя прозрачная полоса шириной [width]: свайп влево по ней закрывает экран.
///
/// Это не покадровое перетаскивание (его делает системный детектор, если
/// палец всё-таки попал в его полосу) — а надёжный «дотяг» жеста там, где
/// пользователь ожидал срабатывания.
class _WideBackArea extends StatelessWidget {
  const _WideBackArea({required this.child});

  final Widget child;

  /// Ширина полосы захвата. 44 pt — минимальная тач-цель из гайдлайнов.
  static const width = 44.0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: width,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            // Свайп влево от кромки — назад. Вертикальные движения не трогаем:
            // по этой же полосе прокручиваются списки.
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity != null &&
                  details.primaryVelocity! < 0) {
                Navigator.of(context).maybePop();
              }
            },
          ),
        ),
      ],
    );
  }
}
