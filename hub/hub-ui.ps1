# hub-ui.ps1 — дашборд хаба. Тема: theme.psd1 (цвета, панели, ширина, автообновление).
#   hub-ui.ps1          — интерактив (q — выход, r — обновить)
#   hub-ui.ps1 -Once    — один кадр (для тестов/скриншотов)
param([switch]$Once)

$ErrorActionPreference = 'SilentlyContinue'
$HubDir = $PSScriptRoot
$Hub    = Join-Path $HubDir 'hub.ps1'
$Theme  = Import-PowerShellDataFile (Join-Path $HubDir 'theme.psd1')

function Get-Section($name) {
    # hub.ps1 пишет через Write-Host — перехватываем только во внешнем процессе
    switch ($name) {
        'kaw' {
            $lines = & powershell -NoProfile -ExecutionPolicy Bypass -File $Hub status 2>$null
            $i = 0..($lines.Count - 1) | Where-Object { $lines[$_] -match '== KAW' } | Select-Object -First 1
            if ($null -ne $i) { $out = $lines[($i + 1)..([Math]::Min($i + 2, $lines.Count - 1))] }
        }
        'system' {
            $lines = & powershell -NoProfile -ExecutionPolicy Bypass -File $Hub status 2>$null
            $i = 0..($lines.Count - 1) | Where-Object { $lines[$_] -match '== Система' } | Select-Object -First 1
            if ($null -ne $i) { $out = $lines[($i + 1)..([Math]::Min($i + 2, $lines.Count - 1))] }
        }
        'agents' { $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $Hub agents 2>$null }
        'runs'   { $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $Hub runs 2>$null }
        'repos'  { $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $Hub gh status 2>$null }
    }
    ($out | Out-String) -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 12
}

function Draw-Panel($title, [string[]]$lines) {
    $w = [int]$Theme.Width
    $line = '─' * ($w - 2)
    Write-Host ("┌" + $line + "┐") -ForegroundColor $Theme.Accent
    $t = " $title "
    Write-Host ("│" + $t.PadRight($w - 2) + "│") -ForegroundColor $Theme.Accent
    Write-Host ("├" + $line + "┤") -ForegroundColor $Theme.Accent
    foreach ($l in $lines) {
        $cut = if ($l.Length -gt $w - 4) { $l.Substring(0, $w - 5) + '…' } else { $l }
        Write-Host ("│ " + $cut.PadRight($w - 4) + " │") -ForegroundColor $Theme.Text
    }
    Write-Host ("└" + $line + "┘") -ForegroundColor $Theme.Accent
}

function Render {
    Clear-Host
    $banner = $Theme.Banner
    Write-Host ''
    Write-Host ("  " + $banner) -ForegroundColor $Theme.Accent
    Write-Host ("  " + (Get-Date -Format 'dd.MM.yyyy HH:mm:ss')) -ForegroundColor DarkGray
    Write-Host ''
    $titles = @{ kaw = 'KAW'; system = 'СИСТЕМА'; agents = 'АГЕНТЫ'; runs = 'ЗАПУСКИ'; repos = 'GITHUB-РЕПОЗИТОРИИ' }
    foreach ($p in $Theme.Panels) {
        Draw-Panel $titles[$p] (Get-Section $p)
        Write-Host ''
    }
    Write-Host '  q — выход · r — обновить · настройки: hub\theme.psd1, команды: hub.ps1 do' -ForegroundColor DarkGray
}

if ($Once) { Render; return }

while ($true) {
    Render
    $waited = 0
    while ($waited -lt [int]$Theme.RefreshSec * 10) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true).KeyChar
            if ($key -eq 'q') { Clear-Host; return }
            if ($key -eq 'r') { break }
        }
        Start-Sleep -Milliseconds 100
        $waited++
    }
}
