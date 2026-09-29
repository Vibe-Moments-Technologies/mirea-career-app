# env.ps1 — окружение разработки «Карьера РТУ МИРЭА».
# Всё живёт ВНУТРИ проекта на E:, системный диск не засоряется.
# Использование:  . .\env.ps1   (точка+пробел — выполнить в текущей сессии)
#
# Почему так: реестр/системный PATH мы не трогаем (не нужны права и сюрпризы
# для других проектов), а тяжёлые артефакты Flutter/Dart/pub уводим с C:.

$Root = $PSScriptRoot
$Sdk  = Join-Path $Root '.sdk'

# --- Пути ---
$env:FLUTTER_ROOT   = Join-Path $Sdk 'flutter'
$env:PUB_CACHE      = Join-Path $Sdk 'pub-cache'      # пакеты pub (~сотни МБ)
$env:DART_ANALYTICS_PATH = Join-Path $Sdk 'dart-tool' # Dart пишет сюда, не в %APPDATA%
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'

# --- Обход блокировок песочницы/прав ---
# Gradle/AGP по умолчанию лезут в ~/.gradle на C:, а Android SDK — куда скажут.
$env:GRADLE_USER_HOME = Join-Path $Sdk 'gradle'       # кэш Gradle (сотни МБ)

# Android SDK: своей копии в проекте может не быть — берём установленную в системе.
# Свой путь имеет приоритет, если каталог создан (тяжёлые компоненты не на C:).
$localAndroidSdk = Join-Path $Sdk 'android-sdk'
$env:ANDROID_SDK_ROOT = if (Test-Path $localAndroidSdk) { $localAndroidSdk } else { Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
$env:ANDROID_HOME     = $env:ANDROID_SDK_ROOT
$env:ANDROID_AVD_HOME = Join-Path $Sdk 'avd'          # образы эмулятора (гигабайты!)

# Для Flutter/Dart создаём каталоги заранее — иначе они уйдут на C:
foreach ($d in $env:PUB_CACHE, $env:DART_ANALYTICS_PATH, $env:GRADLE_USER_HOME) {
  if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}

# --- PATH только на время сессии ---
$env:Path = "$env:FLUTTER_ROOT\bin;$env:FLUTTER_ROOT\bin\cache\dart-sdk\bin;$env:ANDROID_SDK_ROOT\platform-tools;$env:Path"

Write-Host "Flutter : $((& flutter --version 2>$null | Select-Object -First 1))" -ForegroundColor Green
Write-Host "PUB_CACHE=$env:PUB_CACHE"
Write-Host "GRADLE_USER_HOME=$env:GRADLE_USER_HOME"
Write-Host "ANDROID_SDK_ROOT=$env:ANDROID_SDK_ROOT"
Write-Host "Root: $Root"