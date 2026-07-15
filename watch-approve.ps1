# =============================================================================
# watch-approve.ps1 — автономный наблюдатель за диалогами подтверждения Kimi CLI.
#
# Каждые N секунд сканирует видимые окна Windows Terminal, находит активный
# диалог "Run this command? / 1. Approve once / ... / 1/2/3/4 choose" в окнах
# Kimi CLI и нажимает "1" (Approve once). После апрува чистит мусорный символ
# "1", который TUI оставляет в строке ввода. Держит ПК бодрствующим.
#
# Стоп: создать файл STOP рядом со скриптом (или stop-watcher.ps1).
# Лог:  watcher.log рядом со скриптом.
#
# Параметры:
#   -IntervalSeconds <int>   период сканирования, сек (по умолчанию 10)
#   -ExcludeHwnd <long[]>    hwnd окон, которые НЕ трогать (напр. своё окно)
#   -Agents <строка>         профили агентов через запятую: kimi, claude
#                            (по умолчанию kimi; claude — экспериментально)
#   -NoKeepAwake             не блокировать сон/отключение дисплея
#   -Once                    один цикл сканирования и выход (для тестов)
# =============================================================================
param(
  [int]$IntervalSeconds = 10,
  [long[]]$ExcludeHwnd = @(),
  [string]$Agents = 'kimi',
  [switch]$NoKeepAwake,
  [switch]$Once
)

$ErrorActionPreference = 'Continue'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$stopFile = Join-Path $dir 'STOP'
$logFile = Join-Path $dir 'watcher.log'
$pidFile = Join-Path $dir 'watcher.pid'

$PID | Out-File -FilePath $pidFile -Encoding ascii

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms

$sig = @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class WaApi {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);

  public static List<IntPtr> Cascadia(uint targetPid) {
    var res = new List<IntPtr>();
    EnumWindows((h, l) => {
      uint pid; GetWindowThreadProcessId(h, out pid);
      var c = new StringBuilder(256); GetClassName(h, c, 256);
      if (pid == targetPid && IsWindowVisible(h) && c.ToString() == "CASCADIA_HOSTING_WINDOW_CLASS") res.Add(h);
      return true;
    }, IntPtr.Zero);
    return res;
  }
}
'@
Add-Type -TypeDefinition $sig

function Log([string]$msg) {
  $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $msg
  Add-Content -Path $logFile -Value $line -Encoding UTF8
}

function Get-WinInfo([IntPtr]$h) {
  $info = [PSCustomObject]@{ Title = ''; Text = $null }
  try {
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
    if (-not $root) { return $info }
    $info.Title = ('' + $root.Current.Name)
    $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
      [System.Windows.Automation.Condition]::TrueCondition)
    $sb = New-Object System.Text.StringBuilder
    foreach ($el in $all) {
      if ($el.Current.ClassName -match 'TermControl') {
        try {
          $tp = $el.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
          # -1 = весь буфер, без обрезки: диалог всегда в самом низу
          [void]$sb.AppendLine($tp.DocumentRange.GetText(-1))
        } catch {}
      }
    }
    $info.Text = $sb.ToString()
  } catch {}
  return $info
}

function Get-TermText([IntPtr]$h) { return (Get-WinInfo $h).Text }

function Send-Key([IntPtr]$h, [string]$keys) {
  if ([WaApi]::IsIconic($h)) { [WaApi]::ShowWindow($h, 9) | Out-Null }  # SW_RESTORE
  $fg = [WaApi]::GetForegroundWindow()
  $fgPid = 0
  $fgThread = [WaApi]::GetWindowThreadProcessId($fg, [ref]$fgPid)
  $myThread = [WaApi]::GetCurrentThreadId()
  [WaApi]::AttachThreadInput($myThread, $fgThread, $true) | Out-Null
  [WaApi]::SetForegroundWindow($h) | Out-Null
  [WaApi]::BringWindowToTop($h) | Out-Null
  [WaApi]::AttachThreadInput($myThread, $fgThread, $false) | Out-Null
  Start-Sleep -Milliseconds 400
  [System.Windows.Forms.SendKeys]::SendWait($keys)
}

function Has-Dialog([string]$text, [string[]]$needles) {
  # активный диалог всегда внизу буфера; смотрим только хвост,
  # чтобы не срабатывать на упоминания диалога в скроллбэке
  $lines = ($text -split "`r?`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
  $tail = ($lines | Select-Object -Last 15) -join "`n"
  foreach ($n in $needles) {
    if ($tail -notmatch [regex]::Escape($n)) { return $false }
  }
  return $true
}

function Input-Is-Stray1([string]$text) {
  $lines = ($text -split "`r?`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    $norm = ($lines[$i] -replace '[^0-9A-Za-zА-Яа-я>]', '')   # срезаем рамку ╭│╯, пробелы, курсор █
    if ($norm -eq '>1') { return $true }
    if ($norm.StartsWith('>')) { return $false }  # чужой ввод — не трогаем
  }
  return $false
}

# Профили агентов: Marker — признак окна агента в буфере (regex, $null = любое окно),
# Dialog — все строки, которые должны быть в хвосте буфера у активного диалога.
# Во всех профилях "1" = одноразовое подтверждение (никогда не "always").
$profileTable = @{
  kimi   = @{ Marker = 'kimi-for-coding'; Dialog = @('Approve once', '1/2/3/4 choose') }
  claude = @{ Marker = $null;             Dialog = @('Do you want to proceed', '1. Yes') }
}
$activeProfiles = @()
foreach ($a in ($Agents -split ',')) {
  $a = $a.Trim()
  if ($a -and $profileTable.Contains($a)) { $activeProfiles += $profileTable[$a] }
}
if (-not $activeProfiles) { Log "no known agent profiles in -Agents '$Agents', exit"; exit 1 }

# только один экземпляр наблюдателя
$script:mutex = New-Object System.Threading.Mutex($false, 'Local\KimiApproveWatch')
if (-not $script:mutex.WaitOne(0)) { Log "another instance is running, exit"; exit 0 }

# не давать ПК заснуть/погасить экран, пока работает наблюдатель
if (-not $NoKeepAwake) {
  [WaApi]::SetThreadExecutionState([Convert]::ToUInt32(0x80000003L)) | Out-Null  # ES_CONTINUOUS|ES_SYSTEM_REQUIRED|ES_DISPLAY_REQUIRED
}

Log "watcher started (PID $PID)$(if ($Once) {' [ONCE mode]'}), interval ${IntervalSeconds}s, keep-awake $(-not $NoKeepAwake), agents=[$Agents]"

while ($true) {
  if (Test-Path $stopFile) { Log "STOP file found, exit"; break }
  try {
    $wt = Get-Process WindowsTerminal -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $wt) { Log "WindowsTerminal not found" }
    else {
      foreach ($h in [WaApi]::Cascadia($wt.Id)) {
        if ($ExcludeHwnd -contains $h.ToInt64()) { continue }
        if ([WaApi]::IsIconic($h)) { continue }                 # свёрнутое не трогаем
        $info = Get-WinInfo $h
        $text = $info.Text
        if ([string]::IsNullOrEmpty($text)) { continue }
        if ($text -match 'approve-watch') { continue }          # сессия, обсуждающая этого бота
        foreach ($prof in $activeProfiles) {
          if ($prof.Marker -and $text -notmatch $prof.Marker) { continue }   # не окно этого агента
          $attempt = 0
          while ((Has-Dialog $text $prof.Dialog) -and $attempt -lt 3) {
            $attempt++
            Log ("dialog in hwnd " + $h.ToInt64() + " ('" + $info.Title.Trim() + "') — sending '1' (attempt $attempt)")
            Send-Key $h '1'
            Start-Sleep -Milliseconds 1200
            $text2 = Get-TermText $h
            if (Has-Dialog $text2 $prof.Dialog) { $text = $text2; continue }
            if (Input-Is-Stray1 $text2) {
              Send-Key $h '{BACKSPACE}'
              Log ("cleaned stray '1' in hwnd " + $h.ToInt64())
            }
            Log ("approved in hwnd " + $h.ToInt64())
            break
          }
        }
      }
    }
  } catch {
    Log ("cycle error: " + $_.Exception.Message)
  }
  if ($Once) { break }
  Start-Sleep -Seconds $IntervalSeconds
}

if (-not $NoKeepAwake) {
  [WaApi]::SetThreadExecutionState([Convert]::ToUInt32(0x80000000L)) | Out-Null  # сброс keep-awake
}
try { $script:mutex.ReleaseMutex() } catch {}
Log "watcher stopped"
