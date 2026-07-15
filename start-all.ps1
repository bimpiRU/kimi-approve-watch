# start-all.ps1 — единая точка запуска: наблюдатель апрувов + стабилизатор ПК.
# Вызывается установщиком, шлюзом (watcher-gate.ps1) и ярлыком автозагрузки.
$ErrorActionPreference = 'Continue'
$dir      = Split-Path -Parent $MyInvocation.MyCommand.Path
$psExe    = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$launcher = Join-Path $dir 'watch-approve-launcher.ps1'

# 1. наблюдатель апрувов Kimi CLI
Start-Process $psExe -WindowStyle Hidden -ArgumentList (
  '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $launcher)

# 2. стабилизатор ПК — только если включён файлом stabilizer.enabled
#    (файл создаёт/удаляет install.ps1; флаги стабилизатора настраиваются ниже)
$stabFlag   = Join-Path $dir 'stabilizer.enabled'
$stabScript = Join-Path $dir 'stabilize.ps1'
if ((Test-Path $stabFlag) -and (Test-Path $stabScript)) {
  $stabFlags = '-HighPerformance -BoostTerminalPriority'   # <-- настройте под себя
  Start-Process $psExe -WindowStyle Hidden -ArgumentList (
    '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Target "{1}" -MutexName "{2}" -TargetArgs "{3}"' -f
      $launcher, 'stabilize.ps1', 'Local\KimiPcStabilizer', $stabFlags)
}
