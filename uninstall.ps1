#Requires -Version 5.1
<#
.SYNOPSIS
  Полное удаление Kimi Approve Watch: остановка наблюдателя + снятие автозапуска.
#>
$ErrorActionPreference = 'Continue'
$dir      = Split-Path -Parent $MyInvocation.MyCommand.Path
$stopFile = Join-Path $dir 'STOP'
$taskName = 'KimiApproveWatchGate'
$lnkPath  = Join-Path ([Environment]::GetFolderPath('Startup')) 'KimiApproveWatch.lnk'

# 1. мягкая остановка через STOP (общий для наблюдателя и стабилизатора)
New-Item -Path $stopFile -ItemType File -Force | Out-Null
Write-Host 'STOP создан, жду завершения всех модулей...' -ForegroundColor Yellow

# ждём, пока процессы завершатся сами (до 40 сек), вместо фиксированной паузы
$deadline = (Get-Date).AddSeconds(40)
$mine = @()
do {
    Start-Sleep -Seconds 2
    $mine = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
              Where-Object { $_.CommandLine -and $_.CommandLine.Contains($dir) })
} while ($mine.Count -gt 0 -and (Get-Date) -lt $deadline)

# 2. добиваем оставшиеся процессы наших скриптов
foreach ($p in $mine) {
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    Write-Host "  остановлен PID $($p.ProcessId)"
}
Remove-Item $stopFile -Force -ErrorAction SilentlyContinue

# 3. снятие автозапуска
$removed = $false
try {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
    Write-Host "[OK] Задача '$taskName' удалена." -ForegroundColor Green
    $removed = $true
} catch {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Write-Host "[!] Не удалось удалить задачу '$taskName' (нужны права администратора)." -ForegroundColor Yellow
        Write-Host "    Выполните от администратора: Unregister-ScheduledTask -TaskName $taskName -Confirm:`$false"
    }
}
if (Test-Path $lnkPath) {
    Remove-Item $lnkPath -Force
    Write-Host "[OK] Ярлык автозагрузки удалён." -ForegroundColor Green
    $removed = $true
}
if (-not $removed) { Write-Host 'Автозапуск не был установлен — нечего снимать.' }

Write-Host ''
Write-Host 'Готово. Папку можно просто удалить.' -ForegroundColor Cyan
