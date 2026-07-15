# show-windows.ps1 — список окон Windows Terminal: hwnd, заголовок, свёрнуто ли,
# есть ли активный диалог Approve. Нужен, чтобы найти hwnd для -ExcludeHwnd.
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$sig = @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class SwApi {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);

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

$wt = Get-Process WindowsTerminal -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $wt) { Write-Host 'Windows Terminal не запущен.' -ForegroundColor Yellow; exit 0 }

Write-Host ''
Write-Host ('{0,-12} {1,-8} {2,-8} {3}' -f 'HWND','СВЁРНУТ','ДИАЛОГ','ЗАГОЛОВОК') -ForegroundColor Cyan
foreach ($h in [SwApi]::Cascadia($wt.Id)) {
    $title = ''; $text = ''
    try {
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
        if ($root) {
            $title = ('' + $root.Current.Name).Trim()
            $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
                [System.Windows.Automation.Condition]::TrueCondition)
            $sb = New-Object System.Text.StringBuilder
            foreach ($el in $all) {
                if ($el.Current.ClassName -match 'TermControl') {
                    try {
                        $tp = $el.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
                        [void]$sb.AppendLine($tp.DocumentRange.GetText(-1))
                    } catch {}
                }
            }
            $text = $sb.ToString()
        }
    } catch {}
    $lines = ($text -split "`r?`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    $tail = ($lines | Select-Object -Last 15) -join "`n"
    $dlg = ($tail -match 'Approve once' -and $tail -match '1/2/3/4 choose')
    Write-Host ('{0,-12} {1,-8} {2,-8} {3}' -f $h.ToInt64(), [SwApi]::IsIconic($h), $dlg, $title)
}
Write-Host ''
Write-Host 'Чтобы исключить окно (например, своё):' -ForegroundColor DarkCyan
Write-Host '  .\watch-approve.ps1 -ExcludeHwnd 12345678'
