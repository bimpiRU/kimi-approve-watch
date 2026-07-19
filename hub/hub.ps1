# hub.ps1 — управляющий терминал главагента (прототип объединения KAW + оркестрации агентов Kimi)
# Использование:
#   .\hub.ps1 status                    — KAW, система, живые агенты
#   .\hub.ps1 agents                    — реестр агентов
#   .\hub.ps1 dispatch <agent> "задача" — запустить агента с задачей (фон, лог в hub\runs\)
#   .\hub.ps1 runs                      — список запусков
#   .\hub.ps1 result <runId>            — вывод запуска (runId = имя файла без расширения)
#   .\hub.ps1 kaw <команда>             — проброс в kaw.ps1
param(
    [Parameter(Position = 0)][string]$Command = 'help',
    [Parameter(Position = 1)][string]$Arg1 = '',
    [Parameter(Position = 2)][string]$Arg2 = ''
)

$ErrorActionPreference = 'SilentlyContinue'
$HubDir   = $PSScriptRoot
$KawDir   = Split-Path $HubDir -Parent
$RunsDir  = Join-Path $HubDir 'runs'
$Kimi     = Join-Path $env:USERPROFILE '.kimi-code\bin\kimi.exe'
$Agents   = Import-PowerShellDataFile (Join-Path $HubDir 'agents.psd1')
New-Item -ItemType Directory -Force $RunsDir | Out-Null

function Show-Status {
    Write-Host '== KAW ==' -ForegroundColor Cyan
    foreach ($svc in 'watcher', 'stabilizer') {
        $pidFile = Join-Path $KawDir "$svc.pid"
        $state = 'OFF'
        if (Test-Path $pidFile) {
            $svcPid = [int](Get-Content $pidFile)
            if (Get-Process -Id $svcPid) { $state = "ON (PID $svcPid)" }
        }
        Write-Host ("  {0,-12} {1}" -f $svc, $state)
    }

    Write-Host '== Система ==' -ForegroundColor Cyan
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = (Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average
    $ramFree = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $ramTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $disk = Get-CimInstance Win32_LogicalDisk -Filter 'DeviceID="C:"'
    $diskFree = [math]::Round($disk.FreeSpace / 1GB, 1)
    Write-Host ("  CPU {0}%  RAM свободно {1}/{2} GB  C: свободно {3} GB" -f $cpu, $ramFree, $ramTotal, $diskFree)

    $ghCfg = Join-Path $env:APPDATA 'GHelper\config.json'
    if (Test-Path $ghCfg) {
        $gh = Get-Content $ghCfg -Raw | ConvertFrom-Json
        $gpuModes = @{ 0 = 'Eco'; 1 = 'Standard'; 2 = 'Ultimate' }
        $perfModes = @{ 0 = 'Turbo'; 1 = 'Balanced'; 2 = 'Silent' }
        Write-Host ("  GPU: {0} (auto={1})  Режим: {2}  (сеть: {3}, батарея: {4})" -f
            $gpuModes[[int]$gh.gpu_mode], $gh.gpu_auto, $perfModes[[int]$gh.performance_mode],
            $perfModes[[int]$gh.performance_1], $perfModes[[int]$gh.performance_0])
    }

    Write-Host '== Агенты (живые kimi-процессы) ==' -ForegroundColor Cyan
    $kimiProcs = Get-Process kimi
    if ($kimiProcs) {
        $kimiProcs | Select-Object Id, StartTime | Format-Table -AutoSize | Out-String | Write-Host
    } else { Write-Host '  нет' }
}

function Show-Agents {
    foreach ($name in $Agents.Keys) {
        $a = $Agents[$name]
        Write-Host ("  {0,-12} {1}  [{2}]" -f $name, $a.WorkDir, $a.Mode) -ForegroundColor Green
        Write-Host ("               {0}" -f $a.Role)
    }
}

function Invoke-Dispatch {
    param($Name, $Task)
    if (-not $Agents.Contains($Name)) { Write-Host "Нет агента '$Name'. Смотри: .\hub.ps1 agents" -ForegroundColor Red; return }
    if (-not $Task) { Write-Host 'Укажи задачу: .\hub.ps1 dispatch <agent> "задача"' -ForegroundColor Red; return }
    $a = $Agents[$Name]
    $runId = '{0}-{1:yyyyMMdd-HHmmss}' -f $Name, (Get-Date)
    $log   = Join-Path $RunsDir "$runId.log"
    $errLog = Join-Path $RunsDir "$runId.err.log"
    $prompt = "{0}`n`nЗадача от главагента: {1}`n`nКогда закончишь — дай краткий итог: что сделано, что нет и почему." -f $a.Role, $Task
    $modeArg = if ($a.Mode -eq 'yolo') { '--yolo' } else { '--auto' }
    $proc = Start-Process -FilePath $Kimi -ArgumentList @('-p', $prompt, '--output-format', 'text', $modeArg) `
        -WorkingDirectory $a.WorkDir -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $log -RedirectStandardError $errLog
    Write-Host "Запущен агент '$Name' (PID $($proc.Id)), run: $runId" -ForegroundColor Green
    Write-Host "  лог: $log"
}

function Show-Runs {
    Get-ChildItem $RunsDir -Filter '*.log' | Sort-Object LastWriteTime -Descending |
        Select-Object -First 15 @{n = 'run'; e = { $_.BaseName } }, Length, LastWriteTime,
        @{n = 'работает'; e = { if ($_.BaseName -match '^(\w+)-') { $true } else { $false } } } |
        Format-Table -AutoSize | Out-String | Write-Host
}

switch ($Command) {
    'status'   { Show-Status }
    'agents'   { Show-Agents }
    'dispatch' { Invoke-Dispatch -Name $Arg1 -Task $Arg2 }
    'runs'     { Show-Runs }
    'result'   {
        $f = Join-Path $RunsDir "$Arg1.log"
        if (Test-Path $f) { Get-Content $f -Raw } else { Write-Host "Нет запуска '$Arg1'" -ForegroundColor Red }
    }
    'kaw'      { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $KawDir 'kaw.ps1') $Arg1 $Arg2 }
    default    { Get-Content $PSCommandPath -TotalCount 9 | Write-Host }
}
