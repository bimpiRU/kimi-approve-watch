#Requires -Version 5.1
<#
.SYNOPSIS
  Установка Kimi Approve Watch как фонового "сервиса" Windows с gate-подтверждением.

.DESCRIPTION
  Создаёт две задачи планировщика:
    1. KAWService — запускается при старте Windows (до входа пользователя),
       ждёт сигнала подтверждения и затем запускает watcher + stabilizer.
    2. KAWGate — запускается при входе пользователя, показывает окно
       подтверждения. При "Да" создаёт сигнальный файл, после чего сервис
       начинает работу.

  Требуются права администратора.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install-service.ps1
#>
$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$serviceTask = 'KAWService'
$gateTask = 'KAWGate'
$serviceRunner = Join-Path $dir 'service-runner.ps1'
$gate = Join-Path $dir 'watcher-gate.ps1'
$stabFlag = Join-Path $dir 'stabilizer.enabled'

function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
  Write-Host 'Требуются права администратора. Перезапуск с запросом UAC...' -ForegroundColor Yellow
  Start-Process $psExe -Verb RunAs -Wait -ArgumentList (
    '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $dir 'install-service.ps1'))
  exit
}

# стабилизатор
$s = (Read-Host 'Включить стабилизатор ПК (RAM/диск/сеть/питание/приоритеты)? [Y/n]').Trim()
if ($s -eq '' -or $s -match '^(y|Y|д|Д|да|Да)$') {
  New-Item -Path $stabFlag -ItemType File -Force | Out-Null
  Write-Host '[OK] Стабилизатор включён.' -ForegroundColor Green
} else {
  Remove-Item $stabFlag -Force -ErrorAction SilentlyContinue
}

# 1. Фоновый сервис (AtStartup, SYSTEM, hidden)
$svcAct = New-ScheduledTaskAction -Execute $psExe -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $serviceRunner)
$svcTrg = New-ScheduledTaskTrigger -AtStartup
$svcSet = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
           -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -Hidden
$svcPrin = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName $serviceTask -Action $svcAct -Trigger $svcTrg -Settings $svcSet -Principal $svcPrin -Force | Out-Null
Write-Host "[OK] Служба '$serviceTask' создана (старт при включении ПК)." -ForegroundColor Green

# 2. Gate при входе пользователя
$gateAct = New-ScheduledTaskAction -Execute $psExe -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $gate)
$gateTrg = New-ScheduledTaskTrigger -AtLogOn
$gateSet = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName $gateTask -Action $gateAct -Trigger $gateTrg -Settings $gateSet -Force | Out-Null
Write-Host "[OK] Gate '$gateTask' создан (подтверждение при входе пользователя)." -ForegroundColor Green

Write-Host ''
Write-Host 'Теперь при следующем включении ПК:' -ForegroundColor Cyan
Write-Host '  1. Фоновый сервис запустится и будет ждать подтверждения.' -ForegroundColor Cyan
Write-Host '  2. После входа в Windows появится окно подтверждения.' -ForegroundColor Cyan
Write-Host '  3. Только после "Да" начнут работу watcher и stabilizer.' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Управление:  .\kaw.ps1 start/stop/status  |  .\uninstall.ps1 — полное удаление' -ForegroundColor DarkCyan
