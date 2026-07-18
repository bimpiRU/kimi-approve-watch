#Requires -Version 5.1
# service-runner.ps1 — фоновый "сервис" Kimi Approve Watch.
# Запускается задачей планировщика при старте Windows (до входа пользователя).
# Ничего не делает, пока пользователь не войдёт и не подтвердит запуск через gate.
# После появления файла GO запускает start-all.ps1 и следит за его работой.
$ErrorActionPreference = 'Continue'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$goFile = Join-Path $dir '.service-go'
$stopFile = Join-Path $dir 'STOP'
$startAll = Join-Path $dir 'start-all.ps1'
$logFile = Join-Path $dir 'service.log'

function SvcLog([string]$msg) {
  Add-Content -Path $logFile -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' service: ' + $msg) -Encoding UTF8
}

SvcLog 'service runner started, waiting for user confirmation (GO file)'

# ждём GO до 24 часов
$waited = 0
while (-not (Test-Path $goFile)) {
  if (Test-Path $stopFile) { SvcLog 'STOP before GO, exit'; exit 0 }
  Start-Sleep -Seconds 10
  $waited += 10
  if ($waited -ge 86400) { SvcLog 'timeout waiting for GO, exit'; exit 0 }
}

SvcLog 'GO received, launching start-all.ps1'
Remove-Item $goFile -Force -ErrorAction SilentlyContinue

$psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$proc = Start-Process $psExe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $startAll + '"') -WindowStyle Hidden -PassThru

SvcLog ("start-all PID " + $proc.Id)

try {
  while (-not $proc.HasExited) {
    if (Test-Path $stopFile) {
      SvcLog 'STOP detected, terminating start-all subtree'
      try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
      break
    }
    Start-Sleep -Seconds 10
  }
} catch {
  SvcLog ("monitor error: " + $_.Exception.Message)
}

SvcLog 'service runner stopped'
