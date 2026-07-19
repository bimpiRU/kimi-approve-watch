# hub.ps1 — управляющий терминал главагента (KAW + оркестрация агентов Kimi + GitHub)
#   status                    — KAW, система, агенты, активные запуски
#   agents                    — реестр агентов
#   dispatch <agent> "задача" — запустить агента (1 запуск на агента, лок, exit-код)
#   runs                      — последние запуски с exit-кодами
#   result <runId>            — вывод запуска
#   prune [минут=30]          — убить зависшие запуски, снять локи, почистить логи старше 7 дней
#   gh status|prs|issues      — обзор репозиториев из repos.psd1
#   gh clone <repo>           — клонировать bimpiRU/<repo> в github_publish
#   ui [here]                 — дашборд (тема: theme.psd1); here = в текущем окне
#   do [имя]                  — пользовательские команды из commands.psd1
#   kaw <команда>             — проброс в kaw.ps1
param(
    [Parameter(Position = 0)][string]$Command = 'help',
    [Parameter(Position = 1)][string]$Arg1 = '',
    [Parameter(Position = 2)][string]$Arg2 = ''
)

$ErrorActionPreference = 'SilentlyContinue'
$HubDir  = $PSScriptRoot
$KawDir  = Split-Path $HubDir -Parent
$RunsDir = Join-Path $HubDir 'runs'
$Kimi    = Join-Path $env:USERPROFILE '.kimi-code\bin\kimi.exe'
$Agents  = Import-PowerShellDataFile (Join-Path $HubDir 'agents.psd1')
$Repos   = Import-PowerShellDataFile (Join-Path $HubDir 'repos.psd1')
$PubDir  = Join-Path $env:USERPROFILE 'github_publish'
New-Item -ItemType Directory -Force $RunsDir | Out-Null

# ---------- общие ----------

function Get-ActiveRuns {
    # запуск = .cmd без .exit; PID берём из .lock
    $runs = @()
    foreach ($cmdFile in (Get-ChildItem $RunsDir -Filter '*.cmd')) {
        $runId = $cmdFile.BaseName
        $exitFile = Join-Path $RunsDir "$runId.exit"
        $agent = ($runId -split '-')[0]
        $lockFile = Join-Path $RunsDir "$agent.lock"
        $procId = 0
        if (Test-Path $lockFile) { $procId = [int](Get-Content $lockFile -TotalCount 1) }
        $runs += [pscustomobject]@{
            RunId   = $runId
            Agent   = $agent
            Pid     = $procId
            Done    = Test-Path $exitFile
            Exit    = if (Test-Path $exitFile) { (Get-Content $exitFile -Raw).Trim() } else { '' }
            Started = $cmdFile.CreationTime
            Alive   = ($procId -gt 0) -and [bool](Get-Process -Id $procId)
        }
    }
    $runs
}

# ---------- команды ----------

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
    Write-Host ("  CPU {0}%  RAM {1}/{2} GB свободно  C: {3} GB свободно" -f
        $cpu, $ramFree, $ramTotal, [math]::Round($disk.FreeSpace / 1GB, 1))

    $ghCfg = Join-Path $env:APPDATA 'GHelper\config.json'
    if (Test-Path $ghCfg) {
        $gh = Get-Content $ghCfg -Raw | ConvertFrom-Json
        $gpuModes = @{ 0 = 'Eco'; 1 = 'Standard'; 2 = 'Ultimate' }
        $perfModes = @{ 0 = 'Turbo'; 1 = 'Balanced'; 2 = 'Silent' }
        Write-Host ("  GPU: {0} (auto={1})  Режим: {2} (сеть: {3}, батарея: {4})" -f
            $gpuModes[[int]$gh.gpu_mode], $gh.gpu_auto, $perfModes[[int]$gh.performance_mode],
            $perfModes[[int]$gh.performance_1], $perfModes[[int]$gh.performance_0])
    }

    Write-Host '== Запуски агентов ==' -ForegroundColor Cyan
    $active = Get-ActiveRuns | Where-Object { -not $_.Done }
    if ($active) {
        $active | ForEach-Object { Write-Host ("  {0}  PID {1}  старт {2:HH:mm:ss}{3}" -f $_.RunId, $_.Pid, $_.Started, $(if (-not $_.Alive) { ' (процесс потерян — prune)' })) }
    } else { Write-Host '  нет активных' }
}

function Show-Agents {
    foreach ($name in $Agents.Keys) {
        $a = $Agents[$name]
        $model = if ($a.Model) { $a.Model } else { 'default' }
        $busy = Test-Path (Join-Path $RunsDir "$name.lock")
        Write-Host ("  {0,-12} {1}  [{2}]{3}" -f $name, $a.WorkDir, $model, $(if ($busy) { '  ЗАНЯТ' } else { '' })) -ForegroundColor Green
    }
}

function Invoke-Dispatch {
    param($Name, $Task)
    if (-not (Test-Path $Kimi)) { Write-Host "kimi не найден: $Kimi" -ForegroundColor Red; return }
    if (-not $Agents.Contains($Name)) { Write-Host "Нет агента '$Name'. Смотри: hub.ps1 agents" -ForegroundColor Red; return }
    if (-not $Task) { Write-Host 'Укажи задачу.' -ForegroundColor Red; return }
    $a = $Agents[$Name]
    if (-not (Test-Path $a.WorkDir)) { Write-Host "WorkDir не существует: $($a.WorkDir)" -ForegroundColor Red; return }

    $lockFile = Join-Path $RunsDir "$Name.lock"
    if (Test-Path $lockFile) {
        $lockPid = [int](Get-Content $lockFile -TotalCount 1)
        if (Get-Process -Id $lockPid) {
            Write-Host "Агент '$Name' занят (PID $lockPid). Дождись или: hub.ps1 prune" -ForegroundColor Yellow; return
        }
        Remove-Item $lockFile -Force
    }

    $runId  = '{0}-{1:yyyyMMdd-HHmmss}' -f $Name, (Get-Date)
    $log    = Join-Path $RunsDir "$runId.log"
    $errLog = Join-Path $RunsDir "$runId.err.log"
    $exitF  = Join-Path $RunsDir "$runId.exit"
    $prompt = "{0}`n`nЗадача от главагента: {1}`n`nКогда закончишь — дай краткий итог: что сделано, что нет и почему." -f $a.Role, $Task
    $modelArg = if ($a.Model) { "-m `"$($a.Model)`"" } else { '' }

    # PowerShell 5.1 ломает квотирование аргументов со спецсимволами — уходим через .cmd-файл
    $safe = ($prompt -replace '\r?\n', ' ' -replace '"', "'") -replace '[&|<>^]', ' ' -replace '%', '%%'
    $cmdFile = Join-Path $RunsDir "$runId.cmd"
    Set-Content -Path $cmdFile -Encoding OEM -Value (
        '@echo off',
        "`"$Kimi`" -p `"$safe`" --output-format text $modelArg > `"$log`" 2> `"$errLog`"",
        "echo %ERRORLEVEL% > `"$exitF`"",
        "del `"$lockFile`" >nul 2>&1"
    )
    $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', "`"$cmdFile`"" `
        -WorkingDirectory $a.WorkDir -WindowStyle Hidden -PassThru
    Set-Content -Path $lockFile -Value $proc.Id
    Write-Host "Запущен агент '$Name' (PID $($proc.Id)), run: $runId" -ForegroundColor Green
    Write-Host "  лог: $log"
}

function Show-Runs {
    Get-ActiveRuns | Sort-Object Started -Descending | Select-Object -First 15 |
        Format-Table RunId, Pid, @{n = 'exit'; e = { if ($_.Done) { $_.Exit } else { '...' } } },
                    @{n = 'старт'; e = { $_.Started.ToString('dd.MM HH:mm') } } -AutoSize |
        Out-String | Write-Host
}

function Invoke-Prune {
    param([int]$OlderThanMin = 30)
    $now = Get-Date
    foreach ($run in (Get-ActiveRuns | Where-Object { -not $_.Done })) {
        $ageMin = ($now - $run.Started).TotalMinutes
        if (-not $run.Alive -or $ageMin -gt $OlderThanMin) {
            Write-Host "завершаю $($run.RunId) (PID $($run.Pid), возраст $([int]$ageMin) мин)"
            if ($run.Pid -gt 0) { & taskkill /PID $run.Pid /T /F | Out-Null }
            Set-Content -Path (Join-Path $RunsDir "$($run.RunId).exit") -Value '-1'
            Remove-Item (Join-Path $RunsDir "$($run.Agent).lock") -Force
        }
    }
    $cutoff = $now.AddDays(-7)
    Get-ChildItem $RunsDir | Where-Object { $_.LastWriteTime -lt $cutoff } | ForEach-Object {
        Remove-Item $_.FullName -Force; Write-Host "удалён старый файл $($_.Name)"
    }
    Write-Host 'prune: ок' -ForegroundColor Green
}

# ---------- GitHub ----------

function Invoke-Gh {
    param($Sub, $Name)
    switch ($Sub) {
        'status' {
            foreach ($path in $Repos.Keys) {
                if (-not (Test-Path (Join-Path $path '.git'))) { continue }
                $branch = (& git -C $path branch --show-current)
                $dirty = (& git -C $path status --porcelain | Measure-Object).Count
                $sync = (& git -C $path status -sb | Select-Object -First 1)
                $ahead = ''; if ($sync -match '\[(.*)\]') { $ahead = " [$($Matches[1])]" }
                Write-Host ("  {0,-45} {1,-20} изменений: {2}{3}" -f $path, $branch, $dirty, $ahead)
            }
        }
        'prs' {
            foreach ($slug in $Repos.Values) {
                if (-not $slug) { continue }
                Write-Host "== $slug ==" -ForegroundColor Cyan
                & gh pr list -R $slug --limit 5 2>&1 | ForEach-Object { Write-Host "  $_" }
            }
        }
        'issues' {
            foreach ($slug in $Repos.Values) {
                if (-not $slug) { continue }
                Write-Host "== $slug ==" -ForegroundColor Cyan
                & gh issue list -R $slug --limit 5 2>&1 | ForEach-Object { Write-Host "  $_" }
            }
        }
        'clone' {
            if (-not $Name) { Write-Host 'Укажи репо: hub.ps1 gh clone <repo>' -ForegroundColor Red; return }
            & gh repo clone "bimpiRU/$Name" (Join-Path $PubDir $Name)
        }
        default { Write-Host 'gh: status | prs | issues | clone <repo>' }
    }
}

# ---------- роутер ----------

switch ($Command) {
    'status'   { Show-Status }
    'agents'   { Show-Agents }
    'dispatch' { Invoke-Dispatch -Name $Arg1 -Task $Arg2 }
    'runs'     { Show-Runs }
    'result'   {
        $f = Join-Path $RunsDir "$Arg1.log"
        if (Test-Path $f) { Get-Content $f -Raw } else { Write-Host "Нет запуска '$Arg1'" -ForegroundColor Red }
    }
    'prune'    { Invoke-Prune -OlderThanMin $(if ($Arg1) { [int]$Arg1 } else { 30 }) }
    'gh'       { Invoke-Gh -Sub $Arg1 -Name $Arg2 }
    'ui'       {
        $ui = Join-Path $HubDir 'hub-ui.ps1'
        if ($Arg1 -eq 'here') { & powershell -NoProfile -ExecutionPolicy Bypass -File $ui }
        else {
            $wt = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
            Start-Process $wt -ArgumentList '-w', 'new', '-d', $KawDir, 'powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ui
            Write-Host 'Дашборд открыт в новом окне терминала.' -ForegroundColor Green
        }
    }
    'do'       {
        $cmds = Import-PowerShellDataFile (Join-Path $HubDir 'commands.psd1')
        if (-not $Arg1) {
            Write-Host 'Пользовательские команды (hub\commands.psd1):' -ForegroundColor Cyan
            foreach ($k in $cmds.Keys) { Write-Host ("  {0,-16} {1}" -f $k, $cmds[$k].Desc) }
        }
        elseif ($cmds.Contains($Arg1)) {
            $line = $cmds[$Arg1].Run -replace '\{KAW\}', [regex]::Escape($KawDir).Replace('\\', '\')
            & cmd /c $line
        }
        else { Write-Host "Нет команды '$Arg1'. Список: hub.ps1 do" -ForegroundColor Red }
    }
    'kaw'      { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $KawDir 'kaw.ps1') $Arg1 $Arg2 }
    default    { Get-Content $PSCommandPath -TotalCount 11 | Write-Host }
}
