# watch-approve-launcher.ps1 — обёртка автозапуска для наблюдателя/стабилизатора.
# Перезапускает целевой скрипт, если тот упал (фатальная ошибка). Выход — по файлу STOP.
# Если другой экземпляр уже держит наблюдение (мьютекс) — ждёт, не плодит дубли.
#
# Параметры:
#   -Target <имя.ps1>    целевой скрипт из этого каталога (по умолчанию watch-approve.ps1)
#   -MutexName <имя>     мьютекс цели (по умолчанию Local\KimiApproveWatch)
#   -TargetArgs "<флаги>"  аргументы для цели, напр. "-HighPerformance -BoostTerminalPriority"
param(
  [string]$Target = 'watch-approve.ps1',
  [string]$MutexName = 'Local\KimiApproveWatch',
  [string]$TargetArgs = ''
)
$ErrorActionPreference = 'Continue'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$stopFile = Join-Path $dir 'STOP'
$logName = $(if ($Target -eq 'watch-approve.ps1') { 'watcher.log' } else { [IO.Path]::GetFileNameWithoutExtension($Target) + '.log' })
$logFile = Join-Path $dir $logName
$targetPath = Join-Path $dir $Target

$argList = @()
if ($TargetArgs.Trim()) { $argList = $TargetArgs -split '\s+' | Where-Object { $_ } }

function LLog([string]$msg) {
  Add-Content -Path $logFile -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' launcher: ' + $msg) -Encoding UTF8
}

if (-not (Test-Path $targetPath)) { LLog "target $Target not found, exit"; exit 1 }

$mutex = New-Object System.Threading.Mutex($false, $MutexName)

while ($true) {
  if (Test-Path $stopFile) { LLog "STOP found, exit"; break }
  if ($mutex.WaitOne(0)) {
    $mutex.ReleaseMutex()
    try {
      & $targetPath @argList
    } catch {
      LLog ("$Target crashed: " + $_.Exception.Message)
    }
    Start-Sleep -Seconds 5   # цель завершилась — пауза и перезапуск (если не STOP)
  } else {
    Start-Sleep -Seconds 15  # другой экземпляр уже работает — ждём
  }
}
