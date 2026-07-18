#Requires -Version 5.1
<#
.SYNOPSIS
  kaw.ps1 — единая точка управления Kimi Approve Watch.

.EXAMPLE
  .\kaw.ps1 start            запустить всё
  .\kaw.ps1 stop             мягко остановить всё
  .\kaw.ps1 restart          перезапуск
  .\kaw.ps1 status           состояние модулей и хвосты логов
  .\kaw.ps1 log watcher      последние 20 строк лога (watcher|stabilizer)
  .\kaw.ps1 enable stabilizer    включить стабилизатор в автозапуске
  .\kaw.ps1 disable stabilizer   выключить
  .\kaw.ps1 config           показать действующий конфиг
  .\kaw.ps1 windows          окна терминала (hwnd для ExcludeHwnd)
  .\kaw.ps1 install          установка автозапуска
  .\kaw.ps1 uninstall        полное удаление
  .\kaw.ps1 version          версия
#>
param(
    [Parameter(Position = 0)][string]$Command = 'help',
    [Parameter(Position = 1)][string]$Arg1 = ''
)
$ErrorActionPreference = 'Continue'
$script:KawVersion = '0.3.0'
$dir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

function Show-Banner {
    Write-Host ''
    Write-Host '  ┌───────────────────────────────┐' -ForegroundColor Cyan
    Write-Host "  │   Kimi Approve Watch v$($script:KawVersion)   │" -ForegroundColor Cyan
    Write-Host '  └───────────────────────────────┘' -ForegroundColor Cyan
}

function Show-Help {
    Show-Banner
    Write-Host @'

  Управление:
    start | stop | restart | status
    log <watcher|stabilizer>   хвост лога (20 строк)
    enable|disable stabilizer  стабилизатор в автозапуске
    config                     действующий конфиг
    windows                    hwnd окон терминала
    install | uninstall
    version

'@
}

switch ($Command.ToLower()) {
    'start' {
        Remove-Item (Join-Path $dir 'STOP') -Force -ErrorAction SilentlyContinue
        Start-Process $psExe -WindowStyle Hidden -ArgumentList (
            '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f (Join-Path $dir 'start-all.ps1'))
        Start-Sleep -Milliseconds 700
        & (Join-Path $dir 'status.ps1')
    }
    'stop'    { & (Join-Path $dir 'stop-watcher.ps1') }
    'restart' {
        & (Join-Path $dir 'stop-watcher.ps1')
        Start-Sleep -Seconds 35
        Remove-Item (Join-Path $dir 'STOP') -Force -ErrorAction SilentlyContinue
        Start-Process $psExe -WindowStyle Hidden -ArgumentList (
            '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f (Join-Path $dir 'start-all.ps1'))
        Start-Sleep -Milliseconds 700
        & (Join-Path $dir 'status.ps1')
    }
    'status'  { & (Join-Path $dir 'status.ps1') }
    'log' {
        $name = $(if ($Arg1 -match '^stab') { 'stabilizer.log' } else { 'watcher.log' })
        $f = Join-Path $dir $name
        if (Test-Path $f) { Get-Content $f -Tail 20 } else { Write-Host "Лог $name ещё не создан." -ForegroundColor Yellow }
    }
    'enable'  {
        if ($Arg1 -match '^stab') {
            New-Item -Path (Join-Path $dir 'stabilizer.enabled') -ItemType File -Force | Out-Null
            Write-Host '[OK] Стабилизатор включён. Перезапустите: .\kaw.ps1 restart' -ForegroundColor Green
        } else { Write-Host 'Пока можно включать только: stabilizer' -ForegroundColor Yellow }
    }
    'disable' {
        if ($Arg1 -match '^stab') {
            Remove-Item (Join-Path $dir 'stabilizer.enabled') -Force -ErrorAction SilentlyContinue
            Write-Host '[OK] Стабилизатор выключен из автозапуска. Перезапустите: .\kaw.ps1 restart' -ForegroundColor Green
        } else { Write-Host 'Пока можно выключать только: stabilizer' -ForegroundColor Yellow }
    }
    'config' {
        $cfg = Join-Path $dir 'kaw.config.psd1'
        if (Test-Path $cfg) {
            Write-Host "Действующий конфиг: $cfg" -ForegroundColor Cyan
            Get-Content $cfg
        } else {
            Write-Host 'Свой конфиг не создан — действуют значения по умолчанию.' -ForegroundColor Yellow
            Write-Host 'Скопируйте kaw.config.example.psd1 в kaw.config.psd1 и отредактируйте.'
        }
    }
    'windows'   { & (Join-Path $dir 'show-windows.ps1') }
    'install'   { & (Join-Path $dir 'install.ps1') }
    'uninstall' { & (Join-Path $dir 'uninstall.ps1') }
    'version'   { Write-Host "Kimi Approve Watch v$($script:KawVersion)" }
    default     { Show-Help }
}
