<#
.SYNOPSIS
  Собрать Basehub.cfe из исходников (src/) Конфигуратором установленной платформы 1С.

.DESCRIPTION
  1. Создаёт временную файловую базу и загружает в неё минимальную конфигурацию из build/base
     (язык «Русский» и пустой ПриНачалеРаботыСистемы). Конфигурация должна быть сохранена в базе:
     у пустой базы UUID языка при каждой выгрузке новый, и расширение из неё не применится в других базах.
  2. Загружает расширение из src/ (/LoadConfigFromFiles -Extension Basehub).
  3. Выгружает его в .cfe (/DumpCfg -Extension Basehub).

.EXAMPLE
  .\build.ps1
  .\build.ps1 -Platform "C:\Program Files\1cv8\8.3.24.1691" -Out D:\Basehub.cfe
#>
param(
  # каталог платформы (…\1cv8\8.3.xx.xxxx); по умолчанию — самая новая установленная
  [string]$Platform = "",
  [string]$Out = (Join-Path $PSScriptRoot "Basehub.cfe")
)
$ErrorActionPreference = "Stop"

if (-not $Platform) {
  $Platform = Get-ChildItem "C:\Program Files\1cv8", "C:\Program Files (x86)\1cv8" -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName "bin\1cv8.exe") } |
    Sort-Object { [version]($_.Name -replace '[^\d.]', '') } -Descending |
    Select-Object -First 1 -ExpandProperty FullName
}
$exe = Join-Path $Platform "bin\1cv8.exe"
if (-not (Test-Path $exe)) { throw "Не найден 1cv8.exe: укажите -Platform" }

$work = Join-Path ([IO.Path]::GetTempPath()) ("basehub-ext-" + [guid]::NewGuid().ToString("N"))
$db = Join-Path $work "db"
New-Item -ItemType Directory -Force $work | Out-Null

function Invoke-1C([string]$Arguments, [string]$Log) {
  $p = Start-Process $exe -ArgumentList "$Arguments /Out `"$Log`" /DisableStartupDialogs /DisableStartupMessages" -PassThru -Wait
  Start-Sleep -Milliseconds 500
  $text = if (Test-Path $Log) { Get-Content $Log -Raw -Encoding UTF8 } else { "" }
  if ($text -match "(?i)ошибк|error|не совпадает|не удалось|невозможно") { throw "1С: $text" }
  return $text
}

try {
  Write-Host "Платформа: $Platform"
  Invoke-1C "CREATEINFOBASE File=`"$db`"" (Join-Path $work "create.log") | Out-Null
  Invoke-1C "DESIGNER /F `"$db`" /LoadConfigFromFiles `"$(Join-Path $PSScriptRoot 'build\base')`" /UpdateDBCfg" (Join-Path $work "base.log") | Out-Null
  Invoke-1C "DESIGNER /F `"$db`" /LoadConfigFromFiles `"$(Join-Path $PSScriptRoot 'src')`" -Extension Basehub" (Join-Path $work "load.log") | Out-Null
  if (Test-Path $Out) { Remove-Item $Out }
  Invoke-1C "DESIGNER /F `"$db`" /DumpCfg `"$Out`" -Extension Basehub" (Join-Path $work "dump.log") | Out-Null
  if (-not (Test-Path $Out)) { throw "Конфигуратор не создал $Out" }
  Write-Host "Готово: $Out ($((Get-Item $Out).Length) байт)"
} finally {
  Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
