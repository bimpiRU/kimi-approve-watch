#Requires -Version 5.1
<#
.SYNOPSIS
  Установка Kimi Approve Watch: автозапуск + старт наблюдателя.

.DESCRIPTION
  Режимы автозапуска:
    gate    - задача планировщика: при входе в Windows появляется окно
              подтверждения, наблюдатель стартует только после "Да".
              Требуются права администратора (скрипт сам перезапросит).
    startup - ярлык в папке "Автозагрузка" (shell:startup). Прав админа
              не нужно, наблюдатель стартует сразу при входе, без вопросов.
    none    - без автозапуска, просто запустить наблюдателя сейчас.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install.ps1
  powershell -ExecutionPolicy Bypass -File .\install.ps1 -Mode startup
#>
param(
    [ValidateSet('gate','startup','none')]
    [string]$Mode = '',
    # Включить/выключить стабилизатор ПК (stabilize.ps1). Если не задано — спросит в меню.
    [switch]$WithStabilizer,
    [switch]$NoStabilizer,
    # Внутренний флаг: при элевации только создать задачу, не запускать наблюдателя.
    [switch]$SkipStart
)

$ErrorActionPreference = 'Stop'
$dir       = Split-Path -Parent $MyInvocation.MyCommand.Path
$watcher   = Join-Path $dir 'watch-approve.ps1'
$gate      = Join-Path $dir 'watcher-gate.ps1'
$startAll  = Join-Path $dir 'start-all.ps1'
$stabFlag  = Join-Path $dir 'stabilizer.enabled'
$taskName  = 'KimiApproveWatchGate'
$lnkPath   = Join-Path ([Environment]::GetFolderPath('Startup')) 'KimiApproveWatch.lnk'
$psExe     = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

if (-not (Test-Path $watcher)) { Write-Host "Не найден $watcher" -ForegroundColor Red; exit 1 }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-GateTask {
    $arg = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $gate)
    $act = New-ScheduledTaskAction -Execute $psExe -Argument $arg
    $trg = New-ScheduledTaskTrigger -AtLogOn
    $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
           -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)
    Register-ScheduledTask -TaskName $taskName -Action $act -Trigger $trg -Settings $set -Force | Out-Null
}

function Install-StartupLnk {
    $wsh = New-Object -ComObject WScript.Shell
    $lnk = $wsh.CreateShortcut($lnkPath)
    $lnk.TargetPath = $psExe
    $lnk.Arguments  = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $startAll)
    $lnk.WorkingDirectory = $dir
    $lnk.WindowStyle = 7
    $lnk.Description = 'Kimi Approve Watch'
    $lnk.Save()
}

# --- выбор режима ---
if (-not $Mode) {
    Write-Host ''
    Write-Host '  ┌───────────────────────────────┐' -ForegroundColor Cyan
    Write-Host '  │   Kimi Approve Watch v0.2.0   │' -ForegroundColor Cyan
    Write-Host '  └───────────────────────────────┘' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Режим автозапуска:'
    Write-Host '    1) gate    - при входе в Windows спрашивает подтверждение (рекомендуется)'
    Write-Host '    2) startup - автозапуск без вопросов (папка "Автозагрузка")'
    Write-Host '    3) none    - без автозапуска, просто запустить сейчас'
    Write-Host ''
    $c = (Read-Host '  Выбор [1/2/3]').Trim()
    switch ($c) {
        '1' { $Mode = 'gate' }
        '2' { $Mode = 'startup' }
        '3' { $Mode = 'none' }
        default { Write-Host 'Отменено.'; exit 1 }
    }
}

# --- стабилизатор ПК ---
if (-not $WithStabilizer -and -not $NoStabilizer) {
    $s = (Read-Host '  Включить стабилизатор ПК (RAM/диск/сеть/питание)? [Y/n]').Trim()
    if ($s -eq '' -or $s -match '^(y|Y|д|Д|да|Да)$') { $WithStabilizer = $true } else { $NoStabilizer = $true }
}
if ($WithStabilizer) {
    New-Item -Path $stabFlag -ItemType File -Force | Out-Null
    Write-Host '[OK] Стабилизатор включён (stabilizer.enabled).' -ForegroundColor Green
} else {
    Remove-Item $stabFlag -Force -ErrorAction SilentlyContinue
}

# --- автозапуск ---
if ($Mode -eq 'gate') {
    try {
        Install-GateTask
        Write-Host "[OK] Задача планировщика '$taskName' создана (подтверждение при входе)." -ForegroundColor Green
    } catch {
        if (-not (Test-Admin)) {
            Write-Host 'Создание задачи требует права администратора - перезапуск с запросом UAC...' -ForegroundColor Yellow
            Start-Process $psExe -Verb RunAs -Wait -ArgumentList (
                '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode gate -SkipStart' -f (Join-Path $dir 'install.ps1'))
            Write-Host 'Если UAC был подтверждён, задача создана. Продолжаю.' -ForegroundColor Yellow
        } else {
            Write-Host "[ОШИБКА] Не удалось создать задачу: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host 'Альтернатива: .\install.ps1 -Mode startup' -ForegroundColor Yellow
            exit 1
        }
    }
} elseif ($Mode -eq 'startup') {
    Install-StartupLnk
    Write-Host "[OK] Ярлык добавлен в автозагрузку: $lnkPath" -ForegroundColor Green
}

# --- запуск сейчас ---
if (-not $SkipStart) {
    Remove-Item (Join-Path $dir 'STOP') -Force -ErrorAction SilentlyContinue
    & $psExe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $startAll
    Start-Sleep -Milliseconds 700
    $log = Join-Path $dir 'watcher.log'
    if (Test-Path $log) {
        Write-Host "[OK] Наблюдатель запущен. Лог: $log" -ForegroundColor Green
        Get-Content $log -Tail 2 | ForEach-Object { Write-Host "     $_" }
    }
    if ($WithStabilizer) {
        Write-Host "[OK] Стабилизатор запускается. Лог: $(Join-Path $dir 'stabilizer.log')" -ForegroundColor Green
    }
    Write-Host ''
    Write-Host 'Управление:  .\status.ps1 - состояние,  .\stop-watcher.ps1 - стоп,  .\uninstall.ps1 - удаление' -ForegroundColor DarkCyan
}
