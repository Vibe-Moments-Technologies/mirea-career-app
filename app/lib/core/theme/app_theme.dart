import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../widgets/glass_dock.dart';

/// Дизайн-токены из docs/UI.md §1. Единственный источник правды по стилю.
class AppColors {
  const AppColors._();

  static const accent = Color(0xFF0A84FF);
  static const accentDark = Color(0xFF64B5FF);
  static const success = Color(0xFF34C759);
  static const warning = Color(0xFFFF9F0A);
  static const danger = Color(0xFFFF453A);

  // светлая
  static const bgLight = Color(0xFFF2F2F7);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const labelLight = Color(0xFF000000);
  static const secondaryLight = Color(0xFF8E8E93);

  // тёмная
  static const bgDark = Color(0xFF000000);
  static const surfaceDark = Color(0xFF1C1C1E);
  static const labelDark = Color(0xFFFFFFFF);
  static const secondaryDark = Color(0xFF8E8E93);

  /// Тонкая разделительная линия / неактивные точки индикатора.
  /// iOS systemGray5 для светлой темы и её тёмный аналог.
  static Color separator(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF38383A)
          : const Color(0xFFE5E5EA);

  /// Цвет бейджа по типу поста.
  ///
  /// Палитра намеренно сдержанная: пять ярких цветов на каждой карточке
  /// превращали ленту в пёстрое месиво, а разницу между «вакансией» и
  /// «стажировкой» всё равно несёт подпись, а не цвет.
  /// Оставляем один акцент плюс два смысловых тона.
  static Color forPostType(String type, Brightness b) {
    final accent = b == Brightness.dark ? accentDark : AppColors.accent;
    switch (type) {
      case 'vacancy':
      case 'internship':
        return accent;
      case 'event':
      case 'project':
        return success;
      case 'scholarship':
        return warning;
      default:
        return secondaryLight;
    }
  }

  /// Нейтральная подложка карточки без картинки.
  ///
  /// Раньше здесь был цветной градиент по типу поста — те самые
  /// «непонятные цветные кусочки» в ленте. Теперь это спокойная
  /// поверхность с иконкой: информации столько же, шума нет.
  static Color placeholder(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF2C2C2E) : const Color(0xFFE9E9EE);
}

/// Радиусы (UI.md §1).
class AppRadius {
  const AppRadius._();
  static const card = 22.0;
  static const dock = 32.0;
  static const pill = 999.0;
  static const field = 14.0;
  static const thumb = 16.0;
}

/// Отступы экрана по ширине (UI.md §11).
class AppInsets {
  const AppInsets._();
  static double horizontal(double width) {
    if (width < 360) return 12;
    if (width < 400) return 16;
    if (width < 600) return 20;
    return 24;
  }

  /// Верхний отступ для заголовка экрана.
  ///
  /// Складывается из safe area и воздуха. Без этого крупный заголовок
  /// упирался в верхнюю кромку экрана (вырез/статус-бар) — на iPhone
  /// это выглядело как обрезанный текст.
  ///
  /// `viewPadding`, а не `padding`: у экранов с клавиатурой `padding`
  /// сжимается до нуля, и заголовок запрыгивал под статус-бар.
  static double top(BuildContext context, {double extra = 8}) =>
      MediaQuery.viewPaddingOf(context).top + extra;

  /// Нижний отступ скролла: контент не должен прятаться под доком.
  /// Док сам сообщает свою высоту — берём её отсюда же, чтобы зазор
  /// не разъезжался при правке размеров.
  static double scrollBottom(BuildContext context) =>
      GlassDock.scrollBottom(context);

  /// Нижний отступ для выталкиваемого экрана (детали, профиль, настройки).
  ///
  /// Там дока нет, поэтому [scrollBottom] резервировал бы лишнюю высоту
  /// дока: контент уезжал от низа экрана, а кнопка «внизу» висела выше
  /// системной панели.
  static double screenBottom(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).bottom + 24;
}

/// Тени: мягкие, диффузные, никогда не чёрные (UI.md §1).
class AppShadows {
  const AppShadows._();
  static List<BoxShadow> card(Brightness b) => [
        // Двухслойная тень — как в iOS: плотный маленький слой держит контур,
        // мягкий большой даёт объём. Одиночный слой выглядит «плоско-грязным».
        BoxShadow(
          color: Colors.black.withValues(alpha: b == Brightness.dark ? 0.3 : 0.05),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: b == Brightness.dark ? 0.35 : 0.07),
          blurRadius: 28,
          offset: const Offset(0, 12),
        ),
      ];

  static List<BoxShadow> dock(Brightness b) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: b == Brightness.dark ? 0.3 : 0.06),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: b == Brightness.dark ? 0.35 : 0.09),
          blurRadius: 30,
          offset: const Offset(0, 12),
        ),
      ];
}

/// Типографика SF-подобная: плотный трекинг у заголовков.
class AppText {
  const AppText._();
  static const largeTitle = TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.8);
  static const title = TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5);
  static const cardTitle = TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.25);
  static const section = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.4);
  static const headline = TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.3);
  static const body = TextStyle(fontSize: 16, fontWeight: FontWeight.w400);
  static const footnote = TextStyle(fontSize: 13, fontWeight: FontWeight.w400);
  static const caption = TextStyle(fontSize: 11, fontWeight: FontWeight.w500);
}

/// Крупный заголовок экрана.
///
/// Отдельный виджет, потому что название вуза длинное («Карьера РТУ МИРЭА»)
/// и на 32 pt не влезает на узкий экран: FittedBox уменьшает кегль ровно
/// настолько, чтобы строка не обрезалась и не переносилась.
class ScreenTitle extends StatelessWidget {
  const ScreenTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(text, style: AppText.largeTitle),
      ),
    );
  }
}

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: brightness,
  ).copyWith(
    primary: dark ? AppColors.accentDark : AppColors.accent,
    surface: dark ? AppColors.surfaceDark : AppColors.surfaceLight,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? AppColors.bgDark : AppColors.bgLight,
    // InkRipple, а не InkSparkle: у спаркла своя палитра чернил, и на
    // тёмной теме тап по карточке вспыхивал белым пятном.
    splashFactory: InkRipple.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: dark ? AppColors.labelDark : AppColors.labelLight,
    ),
    textTheme: TextTheme(
      headlineMedium: AppText.title,
      titleMedium: AppText.headline,
      bodyMedium: AppText.body,
      bodySmall: AppText.footnote,
      labelSmall: AppText.caption,
    ).apply(
      bodyColor: dark ? AppColors.labelDark : AppColors.labelLight,
      displayColor: dark ? AppColors.labelDark : AppColors.labelLight,
    ),
    // iOS-переходы на всех платформах: новый экран выезжает справа,
    // предыдущий слегка уходит влево и гаснет. Дефолтный Material-«подъём»
    // на Android выглядит дёргано рядом с нашим iOS-стилем.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    // Чипсы и кнопки — единые скругления, без «разнобоя радиусов».
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
      side: BorderSide.none,
      labelStyle: AppText.footnote.copyWith(fontWeight: FontWeight.w500),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
        textStyle: AppText.headline,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
        textStyle: AppText.headline,
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
  );
}