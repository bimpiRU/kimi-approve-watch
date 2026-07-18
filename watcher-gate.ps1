# watcher-gate.ps1 — шлюз подтверждения запуска наблюдателя.
# Запускается задачей планировщика при входе пользователя в систему.
# Показывает запрос: запустить наблюдатель или нет. Работа начинается только после "Да".
$ErrorActionPreference = 'Continue'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$logFile = Join-Path $dir 'watcher.log'
$goFile = Join-Path $dir '.service-go'
$startAll = Join-Path $dir 'start-all.ps1'

function GateLog([string]$msg) {
  Add-Content -Path $logFile -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' gate: ' + $msg) -Encoding UTF8
}

$wshell = New-Object -ComObject WScript.Shell
$res = $wshell.Popup("Запустить Kimi Approve Watch?`n`nНаблюдатель: жмёт 'Approve once' в окнах Kimi каждые 5 сек.`nСтабилизатор: keep-awake, мониторинг RAM/диска/сети, приоритеты агентов.`nБез подтверждения работа не начнётся. (ожидание 120 сек)", 120, 'Kimi Approve Watch v0.3', 4 + 64 + 4096)

if ($res -eq 6) {
  GateLog "user confirmed start"
  # сигнализируем фоновому сервису-раннеру, что можно стартовать
  New-Item -Path $goFile -ItemType File -Force | Out-Null
} elseif ($res -eq 7) {
  GateLog "user declined start"
} else {
  GateLog ("no answer (timeout/code " + $res + "), watcher not started")
}
