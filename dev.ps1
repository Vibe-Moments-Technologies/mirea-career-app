# dev.ps1 — локальная сборка и запуск приложения (Windows).
#
# Запуск:  .\dev.ps1              — список команд
#          .\dev.ps1 run          — собрать и запустить на подключённом устройстве
#          .\dev.ps1 apk          — собрать debug APK для установки вручную
#          .\dev.ps1 apk-rel      — release APK (подпись: debug-ключ, если нет key.properties)
#          .\dev.ps1 devices      — какие устройства видит adb
#          .\dev.ps1 connect      — подключить BlueStacks по adb
#          .\dev.ps1 logs         — логи приложения с устройства
#          .\dev.ps1 check        — статическая проверка кода (работает даже в песочнице)
#          .\dev.ps1 test         — unit-тесты
#          .\dev.ps1 clean        — очистить артефакты сборки
#
# Все тяжёлые пути — внутри проекта (.sdk/), системный диск не засоряется.

param(
  [Parameter(Position = 0)]
  [ValidateSet('run', 'apk', 'apk-rel', 'devices', 'connect', 'logs', 'check', 'test', 'clean', 'doctor', 'help')]
  [string]$Command = 'help',

  # куда ставить APK (по умолчанию — build/app/outputs/flutter-apk)
  [string]$OutDir,

  # доп. аргументы для flutter (например: -d emulator-5554)
  [string[]]$FlutterArgs = @()
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$App = Join-Path $Root 'app'
$Sdk = Join-Path $Root '.sdk'

# ---------- окружение ----------
$env:FLUTTER_ROOT = Join-Path $Sdk 'flutter'
$env:PUB_CACHE = Join-Path $Sdk 'pub-cache'
$env:GRADLE_USER_HOME = Join-Path $Sdk 'gradle'
$env:DART_ANALYTICS_PATH = Join-Path $Sdk 'dart-tool'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'

# Android SDK: берём уже установленный, если своего в проекте нет
$localAndroidSdk = Join-Path $Sdk 'android-sdk'
$systemAndroidSdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$env:ANDROID_SDK_ROOT = if (Test-Path $localAndroidSdk) { $localAndroidSdk } else { $systemAndroidSdk }
$env:ANDROID_HOME = $env:ANDROID_SDK_ROOT
$env:ANDROID_AVD_HOME = Join-Path $Sdk 'avd'

$env:Path = "$env:FLUTTER_ROOT\bin;$env:FLUTTER_ROOT\bin\cache\dart-sdk\bin;$env:ANDROID_SDK_ROOT\platform-tools;$env:Path"

foreach ($d in $env:PUB_CACHE, $env:GRADLE_USER_HOME, $env:DART_ANALYTICS_PATH) {
  if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}

$Adb = Join-Path $env:ANDROID_SDK_ROOT 'platform-tools\adb.exe'
$Dart = Join-Path $env:FLUTTER_ROOT 'bin\cache\dart-sdk\bin\dart.exe'

function Show-Header([string]$text) {
  Write-Host ''
  Write-Host "=== $text ===" -ForegroundColor Cyan
}

# Ключи Supabase читаем из .env в корне проекта, чтобы не набирать вручную.
$DartDefines = @()
$EnvFile = Join-Path $Root '.env'
if (Test-Path $EnvFile) {
  $supabaseUrl = (Select-String -Path $EnvFile -Pattern '^SUPABASE_URL=(.+)$').Matches.Groups[1].Value
  $anonKey = (Select-String -Path $EnvFile -Pattern '^ANON_KEY=(.+)$').Matches.Groups[1].Value
  if ($supabaseUrl) { $DartDefines += "--dart-define=SUPABASE_URL=$supabaseUrl" }
  if ($anonKey) { $DartDefines += "--dart-define=SUPABASE_ANON_KEY=$anonKey" }
  if ($DartDefines.Count -gt 0) {
    Write-Host "Ключи Supabase подставлены из .env" -ForegroundColor DarkGray
  }
} else {
  Write-Host "Файл .env не найден — сборка без ключей (приложение покажет экран настройки)" -ForegroundColor Yellow
}

function Show-Help {
  Write-Host @'
Локальная разработка «Карьера РТУ МИРЭА»

  .\dev.ps1 run        собрать и запустить на подключённом устройстве
  .\dev.ps1 apk        debug APK (быстро, для установки и теста)
  .\dev.ps1 apk-rel    release APK (R8, подпись из key.properties)
  .\dev.ps1 devices    список устройств, видимых adb
  .\dev.ps1 connect    подключить BlueStacks по adb (запусти его заранее)
  .\dev.ps1 logs       поток логов приложения
  .\dev.ps1 check      проверка кода без сборки (работает в любой среде)
  .\dev.ps1 test       unit-тесты
  .\dev.ps1 doctor     окружение: что установлено и чего не хватает
  .\dev.ps1 clean      удалить артефакты сборки

Передать аргументы Flutter можно так:
  .\dev.ps1 run -FlutterArgs @('-d','emulator-5554')
  .\dev.ps1 apk -OutDir 'D:\раздача'

BlueStacks: обычно это x86-эмулятор, поэтому ставь APK с поддержкой x86_64
  .\dev.ps1 apk -FlutterArgs @('--target-platform','android-x64')
'@ -ForegroundColor Gray
}

function Invoke-Check {
  # flutter analyze в песочнице не работает (спавнит analysis_server),
  # поэтому используем in-process анализатор — см. docs/DEVELOPMENT.md
  $tools = Join-Path $Sdk 'tools'
  if (-not (Test-Path (Join-Path $tools 'bin\check.dart'))) {
    Write-Host "Чекер не найден: $tools\bin\check.dart" -ForegroundColor Red
    exit 1
  }
  Push-Location $tools
  try {
    & $Dart run bin/check.dart $App
    $code = $LASTEXITCODE
  } finally {
    Pop-Location
  }
  if ($code -ne 0) { exit $code }
}

function Invoke-Flutter([string[]]$arguments) {
  Push-Location $App
  try {
    & flutter @arguments
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  } finally {
    Pop-Location
  }
}

switch ($Command) {
  'help' { Show-Help }

  'check' {
    Show-Header 'Проверка кода'
    Invoke-Check
  }

  'test' {
    Show-Header 'Unit-тесты'
    Invoke-Flutter @('test')
  }

  'doctor' {
    Show-Header 'Окружение'
    Invoke-Flutter @('doctor', '-v')
  }

  'devices' {
    Show-Header 'Устройства (adb)'
    if (-not (Test-Path $Adb)) { Write-Host "adb не найден: $Adb" -ForegroundColor Red; exit 1 }
    & $Adb devices -l
    Show-Header 'Устройства (flutter)'
    Invoke-Flutter @('devices')
  }

  'connect' {
    Show-Header 'Подключение BlueStacks'
    if (-not (Test-Path $Adb)) { Write-Host "adb не найден: $Adb" -ForegroundColor Red; exit 1 }

    # BlueStacks слушает то 5555 (обычно), то 21503 (Nougat64) — пробуем оба
    $ports = @(5555, 5565, 21503, 5556)
    $connected = $false
    foreach ($port in $ports) {
      Write-Host "Пробую 127.0.0.1:$port ..." -ForegroundColor DarkGray
      $out = & $Adb connect "127.0.0.1:$port" 2>&1
      Write-Host "  $out"
      if ($out -match 'connected') { $connected = $true }
    }
    Write-Host ''
    if (-not $connected) {
      Write-Host 'Ни один порт не ответил. Запусти BlueStacks и включи в нём' -ForegroundColor Yellow
      Write-Host 'Настройки → Дополнительно → ADB (Android Debug Bridge).' -ForegroundColor Yellow
    }
    & $Adb devices -l
  }

  'logs' {
    Show-Header 'Логи приложения'
    Invoke-Flutter (@('logs') + $FlutterArgs)
  }

  'run' {
    Show-Header 'Запуск на устройстве'
    Invoke-Flutter (@('run', '--debug') + $DartDefines + $FlutterArgs)
  }

  'apk' {
    Show-Header 'Debug APK'
    Invoke-Flutter (@('build', 'apk', '--debug',
      '--dart-define=FLUTTER_BUILD_MODE=debug') + $DartDefines + $FlutterArgs)
    $apk = Join-Path $App 'build\app\outputs\flutter-apk\app-debug.apk'
    if (Test-Path $apk) {
      Write-Host ''
      Write-Host "APK: $apk" -ForegroundColor Green
      Write-Host "Размер: $([math]::Round((Get-Item $apk).Length / 1MB, 1)) МБ"
      if ($OutDir) {
        New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
        Copy-Item $apk (Join-Path $OutDir 'kariera-mirea-debug.apk') -Force
        Write-Host "Скопирован в: $OutDir\kariera-mirea-debug.apk" -ForegroundColor Green
      }
    }
  }

  'apk-rel' {
    Show-Header 'Release APK'
    if (-not (Test-Path (Join-Path $App 'android\key.properties'))) {
      Write-Host 'key.properties не найден — подпишу debug-ключом.' -ForegroundColor Yellow
      Write-Host 'Для публикации создай ключ: app/android/key.properties (образец рядом).' -ForegroundColor Yellow
      Write-Host ''
    }
    Invoke-Flutter (@('build', 'apk', '--release') + $DartDefines + $FlutterArgs)
    $apk = Join-Path $App 'build\app\outputs\flutter-apk\app-release.apk'
    if (Test-Path $apk) {
      Write-Host ''
      Write-Host "APK: $apk" -ForegroundColor Green
      Write-Host "Размер: $([math]::Round((Get-Item $apk).Length / 1MB, 1)) МБ"
    }
  }

  'clean' {
    Show-Header 'Очистка'
    Invoke-Flutter @('clean')
    $build = Join-Path $App 'build'
    if (Test-Path $build) { Remove-Item $build -Recurse -Force -ErrorAction SilentlyContinue }
    Write-Host 'Готово' -ForegroundColor Green
  }
}