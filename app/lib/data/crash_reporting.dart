import 'package:sentry_flutter/sentry_flutter.dart';

/// Отлов крашей и ошибок на устройствах тестировщиков.
///
/// Почему это важно именно здесь: release-сборка Flutter не показывает
/// ошибок — при сбое построения интерфейса пользователь видит просто пустой
/// экран, и без телеметрии причину узнать неоткуда. Именно так и произошло
/// с первым белым экраном: сборка запускалась, интерфейс не строился,
/// и никаких следов на устройстве не оставалось.
///
/// DSN передаётся через --dart-define и в репозитории не хранится.
/// Без DSN приложение работает как обычно, просто без телеметрии —
/// это нужно и тестам, и локальному запуску без настройки.
class CrashReporting {
  const CrashReporting._();

  static const _dsn = String.fromEnvironment('SENTRY_DSN');
  static const _environment = String.fromEnvironment(
    'SENTRY_ENVIRONMENT',
    defaultValue: 'dev',
  );
  static const _release = String.fromEnvironment('SENTRY_RELEASE');
  static const _dist = String.fromEnvironment('SENTRY_DIST');

  static bool get isEnabled => _dsn.isNotEmpty;

  /// Показывать ли инструменты проверки телеметрии.
  ///
  /// Только в тестовых сборках: студенту кнопка «вызвать ошибку» не нужна,
  /// а тестировщику — нужна, иначе проверить Sentry можно лишь дожидаясь
  /// настоящего падения.
  static bool get showTestTools => isEnabled && _environment != 'stable';

  /// Запускает приложение внутри зоны Sentry.
  ///
  /// Оборачивать обязательно: без этого исключения в асинхронном коде
  /// останутся незамеченными, а именно там у нас живут сеть и хранилище.
  static Future<void> run(Future<void> Function() appRunner) async {
    if (!isEnabled) {
      await appRunner();
      return;
    }

    await SentryFlutter.init(
      (options) {
        options.dsn = _dsn;
        options.environment = _environment;
        if (_release.isNotEmpty) options.release = _release;
        if (_dist.isNotEmpty) options.dist = _dist;

        // Stack trace к каждому событию: без него непонятно, где упало.
        options.attachStacktrace = true;

        // Производительность сэмплируем: 100% быстро съедает квоту,
        // а для отлова крашей достаточно самих исключений.
        options.tracesSampleRate = 0.2;

        // Персональных данных у нас нет (регистрации в приложении нет),
        // и отправлять лишнее не нужно.
        options.sendDefaultPii = false;
      },
      appRunner: appRunner,
    );
  }

  /// Ручная отправка ошибки — для мест, где перехват не срабатывает сам
  /// (например, падение до построения интерфейса).
  ///
  /// Никогда не бросает: вызывается из обработчика ошибок, и собственная
  /// неудача телеметрии не должна превращаться во второе падение.
  static Future<void> report(Object error, StackTrace stack, {String? context}) async {
    if (!isEnabled) return;
    try {
      await Sentry.captureException(
        error,
        stackTrace: stack,
        withScope: (scope) {
          if (context != null) scope.setTag('failure_context', context);
        },
      );
    } catch (_) {
      // телеметрия недоступна — молчим, у приложения есть дела важнее
    }
  }
}