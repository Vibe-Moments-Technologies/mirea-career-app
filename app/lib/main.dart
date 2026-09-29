import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'data/metrics.dart';
import 'screens/root_shell.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final boot = await bootstrap();

  runApp(
    ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(boot.store),
        metricsProvider.overrideWithValue(boot.metrics),
        supabaseConfiguredProvider.overrideWithValue(boot.configured),
      ],
      child: const MireaCareerApp(),
    ),
  );
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