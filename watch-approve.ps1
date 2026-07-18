# =============================================================================
# watch-approve.ps1 — автономный наблюдатель за диалогами подтверждения Kimi CLI.
#
# Каждые N секунд сканирует видимые окна Windows Terminal, находит активный
# диалог (по профилю агента) и нажимает выбранный вариант (по умолчанию "1" —
# одноразовый апрув). После апрува чистит мусорный символ в строке ввода.
# Держит ПК бодрствующим. Работает мягко: пониженный приоритет собственного
# процесса, чтение только TermControl-элементов, возврат фокуса прежнему окну.
#
# Стоп: создать файл STOP рядом со скриптом (или stop-watcher.ps1).
# Лог:  watcher.log рядом со скриптом.
#
# Параметры:
#   -IntervalSeconds <int>   период сканирования, сек (по умолчанию 10)
#   -ExcludeHwnd <long[]>    hwnd окон, которые НЕ трогать (напр. своё окно)
#   -Agents <строка>         профили агентов через запятую: kimi, claude
#                            (по умолчанию kimi; claude — экспериментально)
#   -ApproveKey <1|2|3>      какой вариант диалога нажимать (по умолчанию 1 —
#                            одноразовый апрув; 2 = "approve always", осторожно!)
#   -NoKeepAwake             не блокировать сон/отключение дисплея
#   -FocusRestore            вернуть фокус прежнему окну после нажатия (по умолчанию выключено — безопаснее для надёжности)
#   -NoSelfSkip              не пропускать окна, в которых обсуждается этот бот
#   -Once                    один цикл сканирования и выход (для тестов)
#
# Необязательный конфиг: kaw.config.psd1 рядом со скриптом (секция Watcher).
# Параметры командной строки важнее значений из конфига.
# =============================================================================
param(
  [int]$IntervalSeconds = 5,
  [long[]]$ExcludeHwnd = @(),
  [string]$Agents = 'kimi',
  [ValidateSet('','1','2','3','auto')][string]$ApproveKey = '',
  [switch]$NoKeepAwake,
  [switch]$FocusRestore,
  [switch]$NoSelfSkip,
  [switch]$AutoApproveSelf,
  [switch]$FastMode,
  [switch]$Once
)

$ErrorActionPreference = 'Continue'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$stopFile = Join-Path $dir 'STOP'
$logFile = Join-Path $dir 'watcher.log'
$pidFile = Join-Path $dir 'watcher.pid'

$PID | Out-File -FilePath $pidFile -Encoding ascii

# мягкость: собственный процесс — с пониженным приоритетом
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch {}

# скорость: уменьшим задержки в FastMode
$delayFocus = if ($FastMode) { 40 } else { 80 }
$delayAfterKey = if ($FastMode) { 200 } else { 400 }
$delayCleanup = if ($FastMode) { 40 } else { 80 }

# автоапрув себя: определяем hwnd собственного консольного окна, если возможно
$script:selfHwnd = [IntPtr]::Zero
try {
  Add-Type -Name ConsoleWin -Namespace Wa -MemberDefinition @'
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
'@ -ErrorAction Stop
  $script:selfHwnd = [Wa.ConsoleWin]::GetConsoleWindow()
  while ($script:selfHwnd -ne [IntPtr]::Zero) {
    $parent = (Get-Process -Id $PID -ErrorAction SilentlyContinue).Parent
    if (-not $parent -or $parent.Name -notlike '*powershell*') { break }
    # в launcher ищем реальное окно терминала
    $wt = Get-Process WindowsTerminal -ErrorAction SilentlyContinue | Where-Object { $_.Id -eq $parent.Id }
    if ($wt) { $script:selfHwnd = [IntPtr]::Zero; break }
    break
  }
} catch {}

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
    $n = Apply-Config (Import-PowerShellDataFile $cfgFile) 'Watcher' $PSBoundParameters
    if ($n -gt 0) { Log "config loaded: kaw.config.psd1 ($n values)" }
  } catch { Log ("config error: " + $_.Exception.Message) }
}

# из конфига/CLI ExcludeHwnd может прийти одной строкой "111,222" — нормализуем
$ExcludeHwnd = @($ExcludeHwnd | ForEach-Object { "$_" -split ',' } |
  Where-Object { $_.Trim() } | ForEach-Object { [long]$_.Trim() })

function Get-WinInfo([IntPtr]$h) {
  $info = [PSCustomObject]@{ Title = ''; Text = $null }
  try {
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
    if (-not $root) { return $info }
    $info.Title = ('' + $root.Current.Name)
    # лёгкость: только TermControl-элементы, а не всё дерево окна
    $cond = New-Object System.Windows.Automation.PropertyCondition(
      [System.Windows.Automation.AutomationElement]::ClassNameProperty, 'TermControl')
    $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
    $sb = New-Object System.Text.StringBuilder
    foreach ($el in $all) {
      try {
        $tp = $el.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
        # -1 = весь буфер, без обрезки: диалог всегда в самом низу
        [void]$sb.AppendLine($tp.DocumentRange.GetText(-1))
      } catch {}
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
  Start-Sleep -Milliseconds $delayFocus
  [System.Windows.Forms.SendKeys]::SendWait($keys)
  # мягкость: вернуть фокус окну, которое было активно до нажатия
  if ($FocusRestore -and $fg -ne [IntPtr]::Zero -and $fg -ne $h) {
    Start-Sleep -Milliseconds $delayCleanup
    [WaApi]::AttachThreadInput($myThread, $fgThread, $true) | Out-Null
    [WaApi]::SetForegroundWindow($fg) | Out-Null
    [WaApi]::AttachThreadInput($myThread, $fgThread, $false) | Out-Null
  }
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

function Input-Is-StrayKey([string]$text, [string]$key) {
  $lines = ($text -split "`r?`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
  for ($i = $lines.Count - 1; $i -ge [math]::Max(0, $lines.Count - 8); $i--) {
    $norm = ($lines[$i] -replace '[^0-9A-Za-zА-Яа-я>]', '')   # срезаем рамку ╭│╯, пробелы, курсор █
    if ($norm -eq ('>' + $key)) { return $true }
    if ($norm.StartsWith('>')) { return $false }  # чужой ввод — не трогаем
  }
  return $false
}

function Find-DialogKey([string]$text, [string]$defaultKey) {
  if ($defaultKey -ne 'auto') { return $defaultKey }
  # пытаемся найти строку с вариантами "1. Approve once" и выбрать "1"
  $tail = (($text -split "`r?`n") | Select-Object -Last 20) -join "`n"
  # ищем любую строку вида "N. Approve once" или "N/... choose" и берём N
  if ($tail -match '(?m)^[^\d]*([1-9])[^\n]*Approve once') { return $Matches[1] }
  if ($tail -match '(?m)^[^\d]*([1-9])[^\n]*Yes') { return $Matches[1] }
  if ($tail -match '([1-9])/\d+\s+choose') { return $Matches[1] }
  return '1'
}

# Профили агентов: Marker — признак окна агента в буфере (regex, $null = любое окно),
# Dialog — все строки, которые должны быть в хвосте буфера у активного диалога,
# Key — какой вариант нажимать (в профилях по умолчанию "1" = одноразовый апрув).
$profileTable = @{
  kimi   = @{ Marker = 'kimi'; Dialog = @('Approve', 'choose'); Key = '1' }
  claude = @{ Marker = $null;             Dialog = @('proceed', 'Yes'); Key = '1' }
  generic = @{ Marker = $null;             Dialog = @('Approve', 'choose'); Key = '1' }
}
$activeProfiles = @()
foreach ($a in ($Agents -split ',')) {
  $a = $a.Trim()
  if ($a -and $profileTable.Contains($a)) { $activeProfiles += $profileTable[$a] }
}
if (-not $activeProfiles) { Log "no known agent profiles in -Agents '$Agents', exit"; exit 1 }
if ($ApproveKey -and $ApproveKey -ne 'auto') { foreach ($p in $activeProfiles) { $p.Key = $ApproveKey } }
if ($ApproveKey -eq 'auto') { foreach ($p in $activeProfiles) { $p.Key = 'auto' } }

# только один экземпляр наблюдателя
$script:mutex = New-Object System.Threading.Mutex($false, 'Local\KimiApproveWatch')
if (-not $script:mutex.WaitOne(0)) { Log "another instance is running, exit"; exit 0 }

# не давать ПК заснуть/погасить экран, пока работает наблюдатель
if (-not $NoKeepAwake) {
  [WaApi]::SetThreadExecutionState([Convert]::ToUInt32(0x80000003L)) | Out-Null  # ES_CONTINUOUS|ES_SYSTEM_REQUIRED|ES_DISPLAY_REQUIRED
}

Log "watcher started (PID $PID)$(if ($Once) {' [ONCE mode]'}), interval ${IntervalSeconds}s, keep-awake $(-not $NoKeepAwake), agents=[$Agents], key=$($activeProfiles[0].Key), fast=$FastMode, self=$AutoApproveSelf"

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
        # автоапрув себя: если включён AutoApproveSelf, не пропускаем собственное окно
        $isSelf = ($script:selfHwnd -ne [IntPtr]::Zero -and $h -eq $script:selfHwnd)
        if ($text -match 'approve-watch' -and -not $NoSelfSkip -and -not $isSelf) { continue }
        foreach ($prof in $activeProfiles) {
          if ($prof.Marker -and $text -notmatch $prof.Marker) { continue }   # не окно этого агента
          $attempt = 0
          $key = Find-DialogKey $text $prof.Key
          while ((Has-Dialog $text $prof.Dialog) -and $attempt -lt 3) {
            $attempt++
            Log ("dialog in hwnd " + $h.ToInt64() + " ('" + $info.Title.Trim() + "') — sending '$key' (attempt $attempt)")
            Send-Key $h $key
            Start-Sleep -Milliseconds $delayAfterKey
            $text2 = Get-TermText $h
            if (Has-Dialog $text2 $prof.Dialog) { $text = $text2; continue }
            if (Input-Is-StrayKey $text2 $key) {
              Send-Key $h '{BACKSPACE}'
              Log ("cleaned stray '$key' in hwnd " + $h.ToInt64())
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
