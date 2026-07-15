# watch-approve-launcher.ps1 — обёртка автозапуска для watch-approve.ps1.
# Перезапускает наблюдатель, если тот упал (фатальная ошибка). Выход — по файлу STOP.
# Если другой экземпляр уже держит наблюдение (мьютекс) — ждёт, не плодит дубли.
$ErrorActionPreference = 'Continue'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$stopFile = Join-Path $dir 'STOP'
$logFile = Join-Path $dir 'watcher.log'
$target = Join-Path $dir 'watch-approve.ps1'

function LLog([string]$msg) {
  Add-Content -Path $logFile -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' launcher: ' + $msg) -Encoding UTF8
}

$mutex = New-Object System.Threading.Mutex($false, 'Local\KimiApproveWatch')

while ($true) {
  if (Test-Path $stopFile) { LLog "STOP found, exit"; break }
  if ($mutex.WaitOne(0)) {
    $mutex.ReleaseMutex()
    try {
      & $target
    } catch {
      LLog ("watcher crashed: " + $_.Exception.Message)
    }
    Start-Sleep -Seconds 5   # наблюдатель завершился — пауза и перезапуск (если не STOP)
  } else {
    Start-Sleep -Seconds 15  # другой экземпляр уже работает — ждём
  }
}
