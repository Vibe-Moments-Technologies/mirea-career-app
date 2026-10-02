import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/dock_visibility.dart';
import 'core/theme/app_theme.dart';
import 'data/app_http_client.dart';
import 'data/crash_reporting.dart';
import 'data/metrics.dart';
import 'screens/root_shell.dart';
import 'state/providers.dart';

Future<void> main() async {
  // release-сборка не показывает ни красного экрана, ни сообщений: при сбое
  // пользователь видит однотонную заливку, и на устройстве не остаётся
  // следов. Мы уже дважды искали причину вслепую — поэтому здесь сразу
  // три уровня защиты:
  //   1) видимая ошибка вместо пустоты (ErrorWidget.builder);
  //   2) Sentry — чтобы узнать о сбое, не переспрашивая тестировщика;
  //   3) try/catch, чтобы показать причину, если упал старт.
  WidgetsFlutterBinding.ensureInitialized();

  // DoH включён по умолчанию. Флаг «system_dns» в настройках выключает его.
  // Инициализация ДО любого сетевого кода (Supabase, Sentry).
  final prefs = await SharedPreferences.getInstance();
  final systemDns = prefs.getBool('system_dns') ?? false;
  await AppHttpClient.instance.init(systemDns: systemDns);

  // По умолчанию Flutter в release рисует на месте упавшего виджета
  // серый прямоугольник без объяснений. Показываем текст ошибки.
  ErrorWidget.builder = (details) => _VisibleError(
        error: details.exceptionAsString(),
        stack: details.stack?.toString(),
      );

  await CrashReporting.run(_start);
}

Future<void> _start() async {
  Bootstrap boot;
  try {
    boot = await bootstrap();
  } catch (e, st) {
    debugPrint('bootstrap упал: $e\n$st');
    // Падение на старте — самое опасное: приложение вообще не открывается.
    // Отправляем отдельно, потому что здесь Sentry уже поднят, но UI ещё нет.
    await CrashReporting.report(e, st, context: 'bootstrap');
    runApp(_StartupFailureScreen(error: '$e'));
    return;
  }

  runApp(
    ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(boot.store),
        metricsProvider.overrideWithValue(boot.metrics),
        supabaseConfiguredProvider.overrideWithValue(boot.configured),
        // Тема из хранилища — до первого кадра: иначе стартовала светлая
        // по умолчанию, и на тёмном устройстве вспыхивал белый экран.
        initialThemeModeProvider.overrideWithValue(
          switch (boot.themeMode) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          },
        ),
      ],
      child: const MireaCareerApp(),
    ),
  );
}

/// Экран на случай, если приложение не смогло даже инициализироваться:
/// лучше показать причину, чем пустоту.
class _StartupFailureScreen extends StatelessWidget {
  const _StartupFailureScreen({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 56, color: AppColors.danger),
                const SizedBox(height: 16),
                Text('Не удалось запустить', style: AppText.title, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text(error, textAlign: TextAlign.center, style: AppText.footnote),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MireaCareerApp extends ConsumerWidget {
  const MireaCareerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'Карьера РТУ МИРЭА',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: themeMode,
      // Док прячется, когда открыта подстраница (см. RootShell).
      navigatorObservers: [dockCovered],
      home: const _Gate(),
    );
  }
}

/// Если сборка сделана без ключей Supabase — показываем инструкцию,
/// а не роняем приложение на старте.
class _Gate extends ConsumerWidget {
  const _Gate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configured = ref.watch(supabaseConfiguredProvider);
    return configured ? const RootShell() : const _NotConfiguredScreen();
  }
}

class _NotConfiguredScreen extends StatelessWidget {
  const _NotConfiguredScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.settings_suggest_rounded,
                size: 56,
                color: AppColors.secondaryLight,
              ),
              const SizedBox(height: 16),
              Text('Нужна настройка', style: AppText.title, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                'Сборка выполнена без ключей Supabase.\n'
                'Запустите приложение так:\n\n'
                'flutter run \\\n'
                '  --dart-define=SUPABASE_URL=… \\\n'
                '  --dart-define=SUPABASE_ANON_KEY=…',
                textAlign: TextAlign.center,
                style: AppText.footnote.copyWith(height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Показывает текст ошибки вместо серого прямоугольника, которым release
/// обычно заменяет упавший виджет.
///
/// Зачем: при первом запуске мы получили однотонный экран без подробностей
/// и искали причину «на ощупь» — по бинарнику собранного APK. С этим виджетом
/// причина видна прямо на устройстве.
///
/// Стили заданы явно: в момент ошибки дерево тем может быть недоступно,
/// поэтому полагаться на Theme нельзя.
class _VisibleError extends StatelessWidget {
  const _VisibleError({required this.error, this.stack});

  final String error;
  final String? stack;

  @override
  Widget build(BuildContext context) {
    // короткий stack: первые строки указывают на место падения
    final shortStack = stack?.split('\n').take(6).join('\n');

    return Material(
      color: const Color(0xFFFFF3F3),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ошибка в интерфейсе',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFB3261E),
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                error,
                style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
              ),
              if (shortStack != null) ...[
                const SizedBox(height: 16),
                SelectableText(
                  shortStack,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF5F6368)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}