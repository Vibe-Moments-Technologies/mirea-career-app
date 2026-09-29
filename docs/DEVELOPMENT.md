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

## Релизные сборки в GitHub Actions

`.github/workflows/build.yml` собирает обе платформы:

| Когда | Что происходит |
|---|---|
| PR в `main` | только проверка кода и тесты (быстро, минуты не тратятся) |
| Тег `vX.Y.Z` | полная сборка Android + iOS |
| Вручную | чекбоксами выбираешь, что собирать |

Локальный запуск сборки в CI не нужен — поэтому workflow не висит на каждом
коммите: полная сборка двух платформ занимает 10–20 минут.

```bash
git tag v0.1.0 && git push origin v0.1.0
```

Артефакты (30 дней хранения): `app-release.apk`, `app-release.aab`,
`kariera-mirea-ios.zip`. Скачиваются со страницы запуска в Actions.

### Секреты репозитория

Settings → Secrets and variables → Actions:

| Секрет | Значение |
|---|---|
| `SUPABASE_URL` | `https://<project>.supabase.co` |
| `SUPABASE_ANON_KEY` | public anon-ключ |
| `ANDROID_KEYSTORE_BASE64` | keystore в base64 (см. ниже) |
| `ANDROID_KEYSTORE_PASSWORD` | пароль хранилища |
| `ANDROID_KEY_ALIAS` | алиас ключа |
| `ANDROID_KEY_PASSWORD` | пароль ключа |

Без секретов подписи Android-сборка всё равно пройдёт — подпишется debug-ключом
(годится для теста, **не** для Google Play), а в логе будет предупреждение.

Как получить base64 от ключа:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("mirea-career.jks")) | Set-Clipboard
```

Само хранилище создаётся один раз:

```powershell
keytool -genkey -v -keystore mirea-career.jks -keyalg RSA -keysize 2048 `
        -validity 10000 -alias mirea-career
```

Затем скопируй `app/android/key.properties.example` в `app/android/key.properties`
и впиши пароли — для локальных release-сборок. Оба файла в `.gitignore`.

### iOS и TestFlight

Workflow собирает `.app` **без подписи** — этого достаточно, чтобы убедиться,
что проект собирается, и запустить на симуляторе. Для установки на реальный
iPhone и TestFlight понадобится Apple Developer ($99/год): сертификат
распространения и provisioning profile добавляются отдельными секретами,
а шаг сборки меняется на `flutter build ipa`.

## Тесты

```powershell
.\dev.ps1 test        # 30 тестов: фильтры, скоринг, LocalStore, модели
```

В ограниченной песочнице не запускаются (раннер прекомпилируется дочерним
процессом). Проверить, что тесты хотя бы компилируются, можно через
`.\dev.ps1 check` — он сканирует `test/` вместе с `lib/`.