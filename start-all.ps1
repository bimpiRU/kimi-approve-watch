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
    if (-not $s.ContainsKey($v) -or $null -eq $s[$v]) { continue }
    if ($s[$v] -is [Array]) {
      foreach ($item in $s[$v]) {
        if ("$item" -ne '') { $parts += "-$v $item" }
      }
    } elseif ("$($s[$v])" -ne '') {
      $parts += "-$v $($s[$v])"
    }
  }
  return ($parts -join ' ')
}

function Start-Module([string]$target, [string]$mutex, [string]$argsLine) {
  $procArgs = @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
    '-File', $launcher,
    '-Target', $target,
    '-MutexName', $mutex,
    '-TargetArgs', $argsLine
  )
  Start-Process $psExe -WindowStyle Hidden -ArgumentList $procArgs
}

# 1. наблюдатель апрувов
$watcherArgs = ''
if ($cfg -and $cfg.Watcher) {
  $watcherArgs = Build-Args $cfg.Watcher @('NoKeepAwake','FocusRestore','NoSelfSkip') @('IntervalSeconds','Agents','ApproveKey','ExcludeHwnd')
}
Start-Module 'watch-approve.ps1' 'Local\KimiApproveWatch' $watcherArgs

# 2. стабилизатор ПК — только если включён файлом stabilizer.enabled
$stabFlag   = Join-Path $dir 'stabilizer.enabled'
$stabScript = Join-Path $dir 'stabilize.ps1'
if ((Test-Path $stabFlag) -and (Test-Path $stabScript)) {
  if ($cfg -and $cfg.Stabilizer) {
    $stabArgs = Build-Args $cfg.Stabilizer @('HighPerformance','BoostTerminalPriority','NoKeepAwake','NoNetCheck','ManageAgentPriority','PromptTips') @('IntervalSeconds','MinFreeRamGB','MinFreeDiskGB','WatchDrives','PromptTipIntervalMinutes')
  } else {
    $stabArgs = '-HighPerformance -BoostTerminalPriority'   # умолчания без конфига
  }
  Start-Module 'stabilize.ps1' 'Local\KimiPcStabilizer' $stabArgs
}
