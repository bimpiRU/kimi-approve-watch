#Requires -Version 5.1
<#
.SYNOPSIS
  quickstart.ps1 — установка Kimi Approve Watch одной командой.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/bimpiRU/kimi-approve-watch/main/quickstart.ps1 | iex"

  При запуске через irm|iex параметры передаются переменными окружения:
  $env:KAW_MODE='startup'; $env:KAW_DIR='D:\tools\kaw'
#>
param(
  [string]$Dir  = "$env:USERPROFILE\kimi-approve-watch",
  [string]$Mode = '',
  [switch]$NoStabilizer
)
$ErrorActionPreference = 'Stop'
$repo = 'https://github.com/bimpiRU/kimi-approve-watch'

# переопределения для стиля irm|iex
if ($env:KAW_DIR)  { $Dir  = $env:KAW_DIR }
if ($env:KAW_MODE) { $Mode = $env:KAW_MODE }

Write-Host ''
Write-Host '  Kimi Approve Watch — quickstart' -ForegroundColor Cyan
Write-Host "  Каталог: $Dir"
Write-Host ''

if (Test-Path (Join-Path $Dir '.git')) {
    Write-Host 'Уже установлено — обновляю (git pull)...' -ForegroundColor Yellow
    git -C $Dir pull --ff-only
} elseif (Get-Command git -ErrorAction SilentlyContinue) {
    git clone $repo $Dir
} else {
    Write-Host 'git не найден — скачиваю ZIP...' -ForegroundColor Yellow
    $zip = Join-Path $env:TEMP 'kimi-approve-watch.zip'
    Invoke-WebRequest "$repo/archive/refs/heads/main.zip" -OutFile $zip
    $tmp = Join-Path $env:TEMP ('kaw-' + [guid]::NewGuid().ToString('N'))
    Expand-Archive $zip -DestinationPath $tmp
    $inner = Join-Path $tmp 'kimi-approve-watch-main'
    if (Test-Path $Dir) { Remove-Item $Dir -Recurse -Force }
    Move-Item $inner $Dir
    Remove-Item $zip, $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$instArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $Dir 'install.ps1'))
if ($Mode) { $instArgs += @('-Mode', $Mode) }
$instArgs += $(if ($NoStabilizer) { '-NoStabilizer' } else { '-WithStabilizer' })
& powershell.exe @instArgs
