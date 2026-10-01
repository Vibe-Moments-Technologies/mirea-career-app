import 'package:flutter/material.dart';

/// Общее поведение прокрутки для экранов приложения.
///
/// Правило одно для всех — «листать только в пределах страницы» — и оно не
/// должно разъезжаться между главной, каталогом, избранным и «Ещё».
class AppScroll {
  const AppScroll._();

  /// Физика списка: контент не уезжает за края.
  ///
  /// По умолчанию iOS даёт `BouncingScrollPhysics`, и короткая страница
  /// отклеивалась от краёв: сверху появлялась пустая полоса, содержимое
  /// уходило выше границы. `ClampingScrollPhysics` держит прокрутку в
  /// диапазоне содержимого.
  ///
  /// `AlwaysScrollableScrollPhysics` нужен только там, где есть жест
  /// обновления: без него короткий список не тянется вообще.
  static const ScrollPhysics plain = ClampingScrollPhysics();

  /// Для главной и организаций: сюда добавлен свайп-обновление.
  static const ScrollPhysics refreshable = AlwaysScrollableScrollPhysics(
    parent: ClampingScrollPhysics(),
  );
}
