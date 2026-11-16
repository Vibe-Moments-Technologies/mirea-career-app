# Применение миграций к живой БД через VDS (прямой Postgres из рабочей среды недостижим).
#
# Зачем параметр Encoding: PowerShell 5.1 (и часть SSH-клиентов) отдают файл в
# системной кодировке, и кириллица доезжает как «РљР°СЂСЊРµСЂР°». Именно так
# испортился contact_name в 0005_org_contacts.sql — данные осели в БД битыми,
# а файл в репозитории был правильный.
#
# Использование:
#   .\tools\apply-migration.ps1 supabase\migrations\0012_something.sql

param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$SshHost = 'myvds',
    [string]$DbHost = 'db.rpmsjribjsrmnithqvap.supabase.co',
    [string]$DbUser = 'postgres',
    [string]$DbName = 'postgres'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Path)) { throw "Файл миграции не найден: $Path" }

# 1. Файл обязан быть корректным UTF-8. Ищем признак mojibake: «Р»/«С» + кириллица подряд.
$text = [IO.File]::ReadAllText((Resolve-Path $Path), [Text.Encoding]::UTF8)
$moji = [regex]::Matches($text, '(?:[\u0420\u0421][\u0401-\u045f]){3,}')
if ($moji.Count -gt 0) {
    throw "В файле $Path найдена битая кодировка (например «$($moji[0].Value)»). Пересохраните файл в UTF-8 без BOM."
}

# 2. Пароль берём из .env, наружу не печатаем.
$envLine = Select-String -Path (Join-Path $PSScriptRoot '..\.env') -Pattern '^DATABASE_URL=' | Select-Object -First 1
if (-not $envLine) { throw 'В .env нет DATABASE_URL' }
$dbPassword = [regex]::Match($envLine.Line, '://postgres:([^@]+)@').Groups[1].Value
if (-not $dbPassword) { throw 'Не удалось разобрать пароль из DATABASE_URL' }
$dbPassword = [uri]::UnescapeDataString($dbPassword)

# 3. Копируем файл на VDS и применяем с принудительным UTF-8 на обоих концах.
$remote = "/tmp/$(Split-Path $Path -Leaf)"
Write-Host "→ Копирую $Path на ${SshHost}:$remote"
& scp $Path "${SshHost}:$remote"
if ($LASTEXITCODE -ne 0) { throw 'scp не удался' }

$cmd = "PGCLIENTENCODING=UTF8 PGPASSWORD='$dbPassword' psql -h $DbHost -p 5432 -U $DbUser -d $DbName -v ON_ERROR_STOP=1 -f $remote; rc=`$?; rm -f $remote; exit `$rc"
Write-Host '→ Применяю миграцию'
& ssh $SshHost $cmd
if ($LASTEXITCODE -ne 0) { throw "psql вернул ошибку (код $LASTEXITCODE)" }

Write-Host '✓ Готово'
