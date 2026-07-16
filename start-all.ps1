# start-all.ps1 — единая точка запуска: наблюдатель апрувов + стабилизатор ПК.
# Вызывается установщиком, шлюзом (watcher-gate.ps1) и ярлыком автозагрузки.
# Аргументы модулей берутся из kaw.config.psd1 (если есть), иначе — по умолчанию.
$ErrorActionPreference = 'Continue'
$dir      = Split-Path -Parent $MyInvocation.MyCommand.Path
$psExe    = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$launcher = Join-Path $dir 'watch-approve-launcher.ps1'

# --- конфиг ---
$cfg = $null
$cfgFile = Join-Path $dir 'kaw.config.psd1'
if (Test-Path $cfgFile) {
  try { $cfg = Import-PowerShellDataFile $cfgFile } catch {}
}

function Build-Args([hashtable]$s, [string[]]$switches, [string[]]$values) {
  $parts = @()
  foreach ($sw in $switches) { if ($s[$sw]) { $parts += "-$sw" } }
  foreach ($v in $values) {
    if ($s.ContainsKey($v) -and $null -ne $s[$v] -and "$($s[$v])" -ne '') {
      $val = $(if ($s[$v] -is [Array]) { $s[$v] -join ',' } else { $s[$v] })
      $parts += "-$v $val"
    }
  }
  return ($parts -join ' ')
}

# 1. наблюдатель апрувов
$watcherArgs = ''
if ($cfg -and $cfg.Watcher) {
  $watcherArgs = Build-Args $cfg.Watcher @('NoKeepAwake','FocusRestore') @('IntervalSeconds','Agents','ApproveKey','ExcludeHwnd')
}
Start-Process $psExe -WindowStyle Hidden -ArgumentList (
  '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Target "{1}" -MutexName "{2}" -TargetArgs "{3}"' -f
    $launcher, 'watch-approve.ps1', 'Local\KimiApproveWatch', $watcherArgs)

# 2. стабилизатор ПК — только если включён файлом stabilizer.enabled
$stabFlag   = Join-Path $dir 'stabilizer.enabled'
$stabScript = Join-Path $dir 'stabilize.ps1'
if ((Test-Path $stabFlag) -and (Test-Path $stabScript)) {
  if ($cfg -and $cfg.Stabilizer) {
    $stabArgs = Build-Args $cfg.Stabilizer @('HighPerformance','BoostTerminalPriority','NoKeepAwake','NoNetCheck') @('IntervalSeconds','MinFreeRamGB','MinFreeDiskGB','WatchDrives')
  } else {
    $stabArgs = '-HighPerformance -BoostTerminalPriority'   # умолчания без конфига
  }
  Start-Process $psExe -WindowStyle Hidden -ArgumentList (
    '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Target "{1}" -MutexName "{2}" -TargetArgs "{3}"' -f
      $launcher, 'stabilize.ps1', 'Local\KimiPcStabilizer', $stabArgs)
}
