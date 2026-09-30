import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Маршрут перехода между экранами — по платформе.
///
/// iOS: `CupertinoPageRoute` даёт интерактивный свайп-назад от левого края.
/// У `MaterialPageRoute` такого жеста нет вообще — только кнопка, и это была
/// настоящая причина, почему с экранов «Настроек», «О приложении» и «Профиля»
/// нельзя было уйти свайпом.
///
/// Android: `MaterialPageRoute`. Жест назад там системный, и включать его
/// принудительно не нужно — большинство его выключает. Переход при этом
/// остаётся iOS-стилем: его задаёт `pageTransitionsTheme` в app_theme.dart,
/// поэтомуMaterialPageRoute на Android рисуется той же анимацией.
Route<T> appRoute<T>(BuildContext context, Widget page) =>
    switch (Theme.of(context).platform) {
      TargetPlatform.iOS => CupertinoPageRoute<T>(builder: (_) => page),
      _ => MaterialPageRoute<T>(builder: (_) => page),
    };
