import 'package:flutter/material.dart';

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

  /// Цвет бейджа по типу поста.
  static Color forPostType(String type, Brightness b) {
    switch (type) {
      case 'vacancy':
        return b == Brightness.dark ? accentDark : accent;
      case 'internship':
        return success;
      case 'event':
        return warning;
      case 'scholarship':
        return const Color(0xFFBF5AF2);
      case 'project':
        return const Color(0xFFFF375F);
      default:
        return secondaryLight;
    }
  }
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
    if (width < 380) return 14;
    if (width < 600) return 20;
    return 24;
  }

  /// Нижний отступ скролла: док парит поверх контента.
  /// 64 (док) + 16 (зазор) + safe area.
  static double scrollBottom(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom + 96;
}

/// Тени: мягкие, диффузные, никогда не чёрные (UI.md §1).
class AppShadows {
  const AppShadows._();
  static List<BoxShadow> card(Brightness b) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: b == Brightness.dark ? 0.4 : 0.08),
          blurRadius: 30,
          offset: const Offset(0, 10),
        ),
      ];

  static List<BoxShadow> dock(Brightness b) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: b == Brightness.dark ? 0.4 : 0.08),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ];
}

/// Типографика SF-подобная: плотный трекинг у заголовков.
class AppText {
  const AppText._();
  static const largeTitle = TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.8);
  static const title = TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5);
  static const headline = TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.3);
  static const body = TextStyle(fontSize: 16, fontWeight: FontWeight.w400);
  static const footnote = TextStyle(fontSize: 13, fontWeight: FontWeight.w400);
  static const caption = TextStyle(fontSize: 11, fontWeight: FontWeight.w500);
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
    splashFactory: InkSparkle.splashFactory,
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
  );
}