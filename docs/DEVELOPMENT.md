# Разработка приложения — окружение и проверка кода

## Где что лежит

Всё тяжёлое — **внутри проекта на E:**, системный диск не засоряется:

```
.sdk/
├── flutter/      # Flutter SDK 3.47.5 (stable), Dart 3.13.4
├── pub-cache/    # пакеты pub
├── gradle/       # кэш Gradle (создастся при Android-сборке)
├── dart-tool/    # аналитика Dart (иначе ушла бы в %APPDATA%)
└── tools/        # вспомогательный пакет: check.dart — статическая проверка
app/              # Flutter-приложение
admin/            # веб-админка (этап 4, ещё не создана)
supabase/         # миграции и скрипты БД
```

`.sdk/` и `.env` — в `.gitignore`: SDK не коммитится, ключи не утекают.

## Окружение

```powershell
. .\env.ps1        # точка + пробел: выполнить в текущей сессии
```

Скрипт задаёт `FLUTTER_ROOT`, `PUB_CACHE`, `GRADLE_USER_HOME`, `ANDROID_SDK_ROOT`,
`DART_ANALYTICS_PATH` и добавляет Flutter в PATH **только на время сессии** —
реестр и системный PATH не трогаются.

> `env.ps1` требует обычного (FullLanguage) PowerShell. В ограниченном режиме
> песочницы dot-source запрещён — тогда задавайте переменные той же командой,
> что запускает сборку (см. ниже).

## Проверка кода без сборочных процессов

`flutter analyze` и `dart analyze` в ограниченной песочнице не работают: они
поднимают `analysis_server` дочерним процессом с piped stdio, а такой спавн
отклоняется (`EPERM`, `process_win.cc:744`). Тот же барьер у `flutter build`
и `dart test` — они зовут git и прекомпилируют раннер.

Для проверки кода используйте in-process анализатор:

```powershell
$root = "E:\Projects Directory\MIREA-Career"
$dart = "$root\.sdk\flutter\bin\cache\dart-sdk\bin\dart.exe"
Set-Location "$root\.sdk\tools"
& $dart run bin/check.dart "$root\app"
```

Он грузит `package:analyzer` как библиотеку в текущий процесс, разбирает все
`.dart` файлы пакета и печатает ошибки и предупреждения с номерами строк.
Ненулевой код возврата — есть ошибки.

## Запуск и сборка приложения

Всё делается через один скрипт — он сам подставляет окружение, ключи из `.env`
и пути Android SDK:

```powershell
.\dev.ps1 run        # собрать и запустить на устройстве (в т.ч. BlueStacks)
.\dev.ps1 apk        # debug APK — для установки руками
.\dev.ps1 apk-rel    # release APK (R8, подпись из key.properties)
.\dev.ps1 devices    # что видит adb и flutter
.\dev.ps1 connect    # подключить BlueStacks по adb
.\dev.ps1 logs       # логи приложения
.\dev.ps1 check      # проверка кода (работает даже в песочнице)
.\dev.ps1 test       # unit-тесты
.\dev.ps1 doctor     # состояние окружения
.\dev.ps1 clean      # очистить сборку
.\dev.ps1            # без аргументов — справка
```

Дополнительные аргументы Flutter передаются массивом:

```powershell
.\dev.ps1 run  -FlutterArgs @('-d','emulator-5554')
.\dev.ps1 apk  -OutDir 'D:\раздача'
```

> Скрипт требует **обычного** PowerShell: в ограниченной песочнице Flutter
> не может запустить дочерние процессы (см. раздел про `check.dart`).
> В обычном терминале работает без ограничений.

### BlueStacks

BlueStacks подключается тем же `adb`, что и обычное устройство, но с двумя
особенностями:

1. **ADB надо включить в самом BlueStacks**: Настройки → Дополнительно → ADB.
   После включения — `.\dev.ps1 connect` (скрипт пробует порты 5555 и 21503).
2. **BlueStacks — x86-эмулятор.** Обычный APK содержит ARM-библиотеки и на нём
   либо не запустится, либо пойдёт через медленную трансляцию. Для него собирай
   под x86_64:

   ```powershell
   .\dev.ps1 apk -FlutterArgs @('--target-platform','android-x64')
   ```

   Для реального телефона (ARM) такой флаг не нужен — обычный `.\dev.ps1 apk`.

### Android SDK

SDK уже установлен в системе (`%LOCALAPPDATA%\Android\Sdk`, platform 37,
build-tools 36) — скрипт использует его. Если понадобится своя копия,
положи её в `.sdk/android-sdk/` — этот путь имеет приоритет, и тяжёлые
компоненты не попадут на системный диск.

### iOS

На Windows сборка невозможна: нужен macOS с Xcode. Отсюда iOS собирается
в GitHub Actions (см. ниже). Платформенная папка `app/ios/` готова.

## Сборки в GitHub Actions

Репозиторий: `Vibe-Moments-Technologies/mirea-career-app` (приватный).

Три workflow, схема взята из `krasava-app` и адаптирована под Flutter:

| Workflow | Когда запускается | Что даёт |
|---|---|---|
| `preview-main.yml` | каждый push в `main` | rolling-релиз `preview` с APK и IPA, версия `X.Y.Z-dev.N` |
| `test-build.yml` | вручную, для любой ветки | артефакты на 14 дней, ничего не публикует |
| `release-mobile.yml` | тег `v*` или вручную | релиз с APK + AAB + IPA |

**Обе платформы собираются всегда.** Тестировщик с iPhone и тестировщик
с Android качают свои файлы из одного и того же релиза, с одинаковым
номером сборки — обновление встаёт поверх предыдущего.

### Как тестировать сборки

Самый простой путь — rolling-preview из main:

1. Пуш в `main` (или Actions → Main Preview Build → Run workflow).
2. Через ~10–20 минут: **Releases** → `preview`.
3. Android-тестировщик ставит `kariera-mirea-preview.apk`.
4. iOS-тестировщик скачивает `kariera-mirea-preview.ipa`.

Для проверки отдельной ветки до мержа — `test-build.yml`: запускаешь вручную,
указываешь ветку, забираешь артефакты со страницы запуска.

### Версионирование

Единый источник — `tools/versioning.py`. Версия в репозитории живёт только
в `app/pubspec.yaml` (чистая линия, например `0.1.0+1`); CI подставляет полную
версию с суффиксом и номером сборки.

| Канал | Источник | Пример версии |
|---|---|---|
| stable | тег `v26.10` | `26.10` |
| beta / rc | тег `v26.10-beta.1` | `26.10-beta.1` |
| dev | push в `main` | `0.1.0-dev.5` |
| contrib | ручная сборка ветки | `0.1.0-contrib.42` |

**BUILD_NUMBER** (versionCode / CFBundleVersion) — epoch-секунды, вычисляются
один раз в resolve-джобе и передаются во все остальные. Так APK и IPA получают
одинаковый номер, и свежая сборка гарантированно встаёт поверх старой.

Почему epoch, а не `github.run_id`: run_id (~34e9) не влезает в Int32, а это
жёсткий потолок Android versionCode (2147483647). Epoch-секунды влезают
с запасом до 2038 года.

Выпуск версии:

```bash
git tag v26.10 && git push origin v26.10
```

### Секреты репозитория

Уже настроены: `SUPABASE_URL`, `SUPABASE_ANON_KEY`.

Осталось добавить для подписи Android (нужно для публикации в Play,
для тестовых сборок не требуется):

| Секрет | Значение |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | keystore в base64 (см. ниже) |
| `ANDROID_KEYSTORE_PASSWORD` | пароль хранилища |
| `ANDROID_KEY_ALIAS` | алиас ключа |
| `ANDROID_KEY_PASSWORD` | пароль ключа |

**Важно:** релизный workflow (по тегу) падает без ключа подписи — намеренно.
APK, подписанный debug-ключом, Google Play отвергнет, а обновление не встанет
поверх предыдущей версии. Тестовые сборки (`preview`, `test-build`)
debug-ключом подписываются нормально.

Как получить base64 от ключа:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("mirea-career.jks")) | Set-Clipboard
```

Хранилище создаётся один раз:

```powershell
keytool -genkey -v -keystore mirea-career.jks -keyalg RSA -keysize 2048 `
        -validity 10000 -alias mirea-career
```

Затем скопируй `app/android/key.properties.example` в `app/android/key.properties`
и впиши пароли — для локальных release-сборок. Оба файла в `.gitignore`.

### iOS: важное ограничение

Workflow собирает IPA **без подписи**. Это значит:

* ✅ сборка компилируется — можно убедиться, что проект живой;
* ✅ файл можно поставить на **симулятор**;
* ❌ **на реальный iPhone его поставить нельзя**.

Для установки на устройство и TestFlight нужен Apple Developer ($99/год):
сертификат распространения и provisioning profile добавляются секретами,
шаг сборки меняется на `flutter build ipa`. Пока этого нет — iOS-тестировщик
сможет смотреть приложение только в симуляторе через Xcode на Mac.

Это ограничение Apple, обойти его без аккаунта разработчика невозможно.

## Тесты

```powershell
.\dev.ps1 test        # 30 тестов: фильтры, скоринг, LocalStore, модели
```

В ограниченной песочнице не запускаются (раннер прекомпилируется дочерним
процессом). Проверить, что тесты хотя бы компилируются, можно через
`.\dev.ps1 check` — он сканирует `test/` вместе с `lib/`.