# status.ps1 — состояние наблюдателя: жив ли процесс, последние строки лога.
$ErrorActionPreference = 'Continue'
$dir     = Split-Path -Parent $MyInvocation.MyCommand.Path
$pidFile = Join-Path $dir 'watcher.pid'
$logFile = Join-Path $dir 'watcher.log'

$alive = $false
if (Test-Path $pidFile) {
    $wpid = [int](Get-Content $pidFile -Raw).Trim()
    $proc = Get-Process -Id $wpid -ErrorAction SilentlyContinue
    if ($proc) { $alive = $true }
}

if ($alive) {
    Write-Host "[ON]  Наблюдатель работает (PID $wpid)" -ForegroundColor Green
} else {
    Write-Host '[OFF] Наблюдатель не запущен' -ForegroundColor Yellow
}

if (Test-Path $logFile) {
    Write-Host ''
    Write-Host "Последние строки $logFile :" -ForegroundColor DarkCyan
    Get-Content $logFile -Tail 8 | ForEach-Object { Write-Host "  $_" }
}
