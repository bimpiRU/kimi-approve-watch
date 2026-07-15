#Requires -Version 5.1
<#
.SYNOPSIS
  stabilize.ps1 — стабилизатор ПК на время долгой работы агентов в терминалах.

.DESCRIPTION
  Работает фоном рядом с watch-approve.ps1 и держит машину в рабочем состоянии,
  пока Kimi CLI / другие нейросети собирают проекты, гоняют тесты и билдят APK:

    - keep-awake: не даёт ПК заснуть и погасить дисплей
    - HighPerformance: на время работы включает схему "Максимальная производительность",
      при выходе возвращает прежнюю (троттлинг убивает долгие сборки)
    - BoostTerminalPriority: держит WindowsTerminal на AboveNormal,
      чтобы терминалы не лагали под нагрузкой
    - следит за RAM: при нехватке пишет в лог топ-5 процессов по памяти
    - следит за местом на дисках (сборки едят гигабайты)
    - следит за сетью: фиксирует окна отказа (в это время API нейросетей недоступен)
    - предупреждает об ожидающей перезагрузке Windows (Update)
    - детектит падение Windows Terminal (потеря сессий агентов)

  Мониторинг не ломает: скрипт только наблюдает и пишет лог. Активные действия —
  схема питания (возвращается при выходе) и приоритет терминала (per-process,
  сбрасывается при перезапуске процесса).

  Стоп: файл STOP рядом со скриптом (общий с watch-approve — stop-watcher.ps1 гасит оба).
  Лог:  stabilizer.log.

  Необязательный конфиг: kaw.config.psd1 рядом со скриптом (секция Stabilizer).
  Параметры командной строки важнее значений из конфига.

.PARAMETER IntervalSeconds   период проверки ресурсов, сек (по умолчанию 30)
.PARAMETER MinFreeRamGB      тревога, если свободной RAM меньше, ГБ (по умолчанию 1.5)
.PARAMETER MinFreeDiskGB     тревога, если на диске меньше, ГБ (по умолчанию 5)
.PARAMETER WatchDrives       диски для контроля (по умолчанию системный)
.PARAMETER HighPerformance   включить "Макс. производительность", вернуть при выходе
.PARAMETER BoostTerminalPriority  держать WindowsTerminal на AboveNormal
.PARAMETER NoKeepAwake       не блокировать сон/дисплей
.PARAMETER NoNetCheck        не проверять сеть
.PARAMETER Once              один цикл и выход (для теста)
#>
param(
  [int]$IntervalSeconds = 30,
  [double]$MinFreeRamGB = 1.5,
  [double]$MinFreeDiskGB = 5,
  [string[]]$WatchDrives = @($env:SystemDrive),
  [switch]$HighPerformance,
  [switch]$BoostTerminalPriority,
  [switch]$NoKeepAwake,
  [switch]$NoNetCheck,
  [switch]$Once
)

$ErrorActionPreference = 'Continue'
$dir      = Split-Path -Parent $MyInvocation.MyCommand.Path
$stopFile = Join-Path $dir 'STOP'
$logFile  = Join-Path $dir 'stabilizer.log'
$pidFile  = Join-Path $dir 'stabilizer.pid'

$PID | Out-File -FilePath $pidFile -Encoding ascii

# мягкость: собственный процесс — с пониженным приоритетом
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch {}

$sig = @'
using System;
using System.Runtime.InteropServices;
public class StApi {
  [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);
}
'@
Add-Type -TypeDefinition $sig

function SLog([string]$msg) {
  $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $msg
  Add-Content -Path $logFile -Value $line -Encoding UTF8
}

function Get-TopHogs {
  return (Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 |
    ForEach-Object { '{0}={1:N1}GB' -f $_.ProcessName, ($_.WorkingSet64 / 1GB) }) -join ', '
}

function Test-PendingReboot {
  return (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
         (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
}

# --- необязательный конфиг kaw.config.psd1 (параметры CLI важнее) ---
function Apply-Config([hashtable]$Cfg, [string]$Section, [hashtable]$Bound) {
  if (-not $Cfg -or -not $Cfg.ContainsKey($Section)) { return 0 }
  $applied = 0
  foreach ($k in $Cfg[$Section].Keys) {
    if (-not $Bound.ContainsKey($k)) { Set-Variable -Name $k -Value $Cfg[$Section][$k] -Scope 1; $applied++ }
  }
  return $applied
}
$cfgFile = Join-Path $dir 'kaw.config.psd1'
if (Test-Path $cfgFile) {
  try {
    $n = Apply-Config (Import-PowerShellDataFile $cfgFile) 'Stabilizer' $PSBoundParameters
    if ($n -gt 0) { SLog "config loaded: kaw.config.psd1 ($n values)" }
  } catch { SLog ("config error: " + $_.Exception.Message) }
}

# WatchDrives может прийти одной строкой "C:,D:" (из конфига/через лаунчер) — нормализуем
$WatchDrives = @($WatchDrives | ForEach-Object { "$_" -split ',' } | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })

# только один экземпляр
$script:mutex = New-Object System.Threading.Mutex($false, 'Local\KimiPcStabilizer')
if (-not $script:mutex.WaitOne(0)) { SLog 'another instance is running, exit'; exit 0 }

# keep-awake
if (-not $NoKeepAwake) {
  [StApi]::SetThreadExecutionState([Convert]::ToUInt32(0x80000003L)) | Out-Null  # ES_CONTINUOUS|ES_SYSTEM_REQUIRED|ES_DISPLAY_REQUIRED
}

# схема питания: High performance на время работы
$hpGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$prevScheme = $null
if ($HighPerformance) {
  try {
    $cur = (powercfg /getactivescheme) -join ' '
    if ($cur -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { $prevScheme = $Matches[1] }
    powercfg /setactive $hpGuid | Out-Null
    SLog "power plan -> High performance (previous: $prevScheme)"
  } catch {
    SLog ("power plan switch failed (admin?): " + $_.Exception.Message)
  }
}

SLog "stabilizer started (PID $PID)$(if ($Once) {' [ONCE mode]'}), interval ${IntervalSeconds}s, ram<${MinFreeRamGB}GB, disk<${MinFreeDiskGB}GB, drives=[$($WatchDrives -join ',')], hp=$HighPerformance, boost=$BoostTerminalPriority, keep-awake=$(-not $NoKeepAwake)"

# состояния (логируем переходы, а не каждый тик — лог остаётся чистым)
$ramBad = $false
$diskBad = @{}
$netDown = $false
$netDownSince = $null
$cpuStreak = 0
$rebootWarned = $false
$wtWasRunning = [bool](Get-Process WindowsTerminal -ErrorAction SilentlyContinue)
$cycle = 0

while ($true) {
  if (Test-Path $stopFile) { SLog 'STOP file found, exit'; break }
  $cycle++
  try {
    # --- RAM ---
    $os = Get-CimInstance Win32_OperatingSystem
    $freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    if ($freeGB -lt $MinFreeRamGB) {
      if (-not $ramBad) {
        $ramBad = $true
        SLog "LOW RAM: ${freeGB}GB free. Top hogs: $(Get-TopHogs)"
      }
    } elseif ($ramBad) {
      $ramBad = $false
      SLog "RAM recovered: ${freeGB}GB free"
    }

    # --- диски ---
    foreach ($d in $WatchDrives) {
      $letter = ($d.TrimEnd(':','\'))
      $ld = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='${letter}:'" -ErrorAction SilentlyContinue
      if (-not $ld) { continue }
      $freeD = [math]::Round($ld.FreeSpace / 1GB, 1)
      if ($freeD -lt $MinFreeDiskGB) {
        if (-not $diskBad[$letter]) {
          $diskBad[$letter] = $true
          SLog "LOW DISK ${letter}: ${freeD}GB free — сборки могут упасть"
        }
      } elseif ($diskBad[$letter]) {
        $diskBad[$letter] = $false
        SLog "disk ${letter}: OK again (${freeD}GB free)"
      }
    }

    # --- CPU (инфо: длительный 100% — норма для билдов, но фиксируем) ---
    $cpu = [int]((Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average)
    if ($cpu -ge 97) {
      $cpuStreak++
      if ($cpuStreak -eq 6) { SLog "CPU pinned at ~${cpu}% for $($IntervalSeconds * 6 / 60)+ min (info)" }
    } else { $cpuStreak = 0 }

    # --- сеть ---
    if (-not $NoNetCheck) {
      $netOk = Test-Connection 1.1.1.1 -Count 1 -Quiet -ErrorAction SilentlyContinue
      if (-not $netOk) { $netOk = Test-Connection 8.8.8.8 -Count 1 -Quiet -ErrorAction SilentlyContinue }
      if ($netOk) {
        if ($netDown) {
          $mins = [math]::Round(((Get-Date) - $netDownSince).TotalMinutes, 1)
          SLog "network recovered after ${mins} min outage"
          $netDown = $false
        }
      } elseif (-not $netDown) {
        $netDown = $true
        $netDownSince = Get-Date
        SLog 'NETWORK OUTAGE — API нейросетей в это время недоступен'
      }
    }

    # --- ожидающая перезагрузка Windows (раз в ~10 мин) ---
    if (($cycle % 20) -eq 1) {
      $pending = Test-PendingReboot
      if ($pending -and -not $rebootWarned) {
        $rebootWarned = $true
        SLog 'PENDING REBOOT: Windows ждёт перезагрузки (Update) — не забудьте между задачами'
      } elseif (-not $pending -and $rebootWarned) {
        $rebootWarned = $false
        SLog 'pending reboot cleared'
      }
    }

    # --- падение Windows Terminal ---
    $wtNow = [bool](Get-Process WindowsTerminal -ErrorAction SilentlyContinue)
    if ($wtWasRunning -and -not $wtNow) {
      SLog 'ALERT: WindowsTerminal исчез (падение?) — сессии агентов могли быть потеряны'
    }
    $wtWasRunning = $wtNow

    # --- приоритет терминала ---
    if ($BoostTerminalPriority) {
      Get-Process WindowsTerminal -ErrorAction SilentlyContinue |
        Where-Object { $_.PriorityClass -ne 'AboveNormal' } |
        ForEach-Object {
          try { $_.PriorityClass = 'AboveNormal'; SLog "boosted WindowsTerminal PID $($_.Id) -> AboveNormal" } catch {}
        }
    }
  } catch {
    SLog ("cycle error: " + $_.Exception.Message)
  }
  if ($Once) { break }
  Start-Sleep -Seconds $IntervalSeconds
}

# восстановление
if ($HighPerformance -and $prevScheme) {
  try { powercfg /setactive $prevScheme | Out-Null; SLog "power plan restored ($prevScheme)" } catch {}
}
if (-not $NoKeepAwake) {
  [StApi]::SetThreadExecutionState([Convert]::ToUInt32(0x80000000L)) | Out-Null
}
try { $script:mutex.ReleaseMutex() } catch {}
SLog 'stabilizer stopped'
