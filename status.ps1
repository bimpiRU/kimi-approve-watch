# status.ps1 — состояние наблюдателя и стабилизатора: живы ли процессы, хвосты логов.
$ErrorActionPreference = 'Continue'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Show-Unit([string]$Name, [string]$PidFileName, [string]$LogFileName) {
    $pidFile = Join-Path $dir $PidFileName
    $logFile = Join-Path $dir $LogFileName
    $alive = $false
    $wpid = ''
    if (Test-Path $pidFile) {
        $wpid = (Get-Content $pidFile -Raw).Trim()
        if ($wpid -and (Get-Process -Id ([int]$wpid) -ErrorAction SilentlyContinue)) { $alive = $true }
    }
    if ($alive) {
        Write-Host "[ON]  $Name (PID $wpid)" -ForegroundColor Green
    } else {
        Write-Host "[OFF] $Name" -ForegroundColor Yellow
    }
    if (Test-Path $logFile) {
        Get-Content $logFile -Tail 4 | ForEach-Object { Write-Host "      $_" }
    }
    Write-Host ''
}

Show-Unit 'Наблюдатель апрувов' 'watcher.pid'    'watcher.log'
Show-Unit 'Стабилизатор ПК'     'stabilizer.pid' 'stabilizer.log'

if (Test-Path (Join-Path $dir 'stabilizer.enabled')) {
    Write-Host 'Стабилизатор: включён в автозапуске (stabilizer.enabled)' -ForegroundColor DarkCyan
}
