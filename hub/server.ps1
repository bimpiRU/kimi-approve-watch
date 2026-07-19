# server.ps1 — веб-фронт Jarvis Hub (локальный, без зависимостей)
#   powershell -File server.ps1 [-Port 8787]
# Оптимизация: одна точка /api/state на всё состояние, сбор данных в процессе
# (без внешних вызовов hub.ps1), кэш git-статуса репозиториев на 30 с.
param([int]$Port = 8787)

$ErrorActionPreference = 'SilentlyContinue'
$HubDir  = $PSScriptRoot
$KawDir  = Split-Path $HubDir -Parent
$RunsDir = Join-Path $HubDir 'runs'
$Kimi    = Join-Path $env:USERPROFILE '.kimi-code\bin\kimi.exe'
$Agents  = Import-PowerShellDataFile (Join-Path $HubDir 'agents.psd1')
$Repos   = Import-PowerShellDataFile (Join-Path $HubDir 'repos.psd1')
$Cmds    = Import-PowerShellDataFile (Join-Path $HubDir 'commands.psd1')
$Theme   = Import-PowerShellDataFile (Join-Path $HubDir 'theme.psd1')
New-Item -ItemType Directory -Force $RunsDir | Out-Null

$cssColors = @{
    Cyan = '#00e5ff'; Green = '#39ff8e'; Gray = '#b8c0cc'; DarkGray = '#6b7280'
    Yellow = '#ffd75f'; Magenta = '#ff5fd2'; White = '#ffffff'; Red = '#ff5f5f'
}

function Get-SvcState($name) {
    $pidFile = Join-Path $KawDir "$name.pid"
    if (Test-Path $pidFile) {
        $svcPid = [int](Get-Content $pidFile)
        if (Get-Process -Id $svcPid) { return "ON (PID $svcPid)" }
    }
    ''
}

$script:reposCache = $null
$script:reposCacheAt = [datetime]::MinValue
function Get-RepoStates {
    if ($script:reposCache -and ((Get-Date) - $script:reposCacheAt).TotalSeconds -lt 30) { return $script:reposCache }
    $list = @()
    foreach ($path in $Repos.Keys) {
        if (-not (Test-Path (Join-Path $path '.git'))) { continue }
        $branch = (& git -C $path branch --show-current)
        $dirty = (& git -C $path status --porcelain | Measure-Object).Count
        $sb = (& git -C $path status -sb | Select-Object -First 1)
        $sync = ''; if ($sb -match '\[(.*)\]') { $sync = " [$($Matches[1])]" }
        $list += @{ repo = Split-Path $path -Leaf; branch = $branch; dirty = $dirty; sync = $sync }
    }
    $script:reposCache = $list
    $script:reposCacheAt = Get-Date
    $list
}

function Get-RunStates {
    $runs = @()
    foreach ($cmdFile in (Get-ChildItem $RunsDir -Filter '*.cmd' | Sort-Object CreationTime -Descending | Select-Object -First 10)) {
        $runId = $cmdFile.BaseName
        $exitFile = Join-Path $RunsDir "$runId.exit"
        $exitVal = $null
        if (Test-Path $exitFile) { $exitVal = Get-Content $exitFile -Raw }
        $runs += @{
            id      = $runId
            exit    = if ($null -ne $exitVal) { "$exitVal".Trim() } else { '...' }
            started = $cmdFile.CreationTime.ToString('dd.MM HH:mm')
        }
    }
    $runs
}

function Get-State {
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = (Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average
    $disk = Get-CimInstance Win32_LogicalDisk -Filter 'DeviceID="C:"'
    $gpu = 'n/a'; $gpuAuto = ''; $perf = ''; $perfAC = ''; $perfBatt = ''
    $ghCfg = Join-Path $env:APPDATA 'GHelper\config.json'
    if (Test-Path $ghCfg) {
        $gh = Get-Content $ghCfg -Raw | ConvertFrom-Json
        $gpuModes = @{ 0 = 'Eco'; 1 = 'Standard'; 2 = 'Ultimate' }
        $perfModes = @{ 0 = 'Turbo'; 1 = 'Balanced'; 2 = 'Silent' }
        $gpu = $gpuModes[[int]$gh.gpu_mode]; $gpuAuto = $gh.gpu_auto
        $perf = $perfModes[[int]$gh.performance_mode]
        $perfAC = $perfModes[[int]$gh.performance_1]; $perfBatt = $perfModes[[int]$gh.performance_0]
    }
    @{
        time     = Get-Date -Format 'dd.MM.yyyy HH:mm:ss'
        theme    = @{ '--accent' = $cssColors[$Theme.Accent]; '--text' = $cssColors[$Theme.Text]; '--ok' = $cssColors[$Theme.Ok]; '--warn' = $cssColors[$Theme.Warn] }
        kaw      = @{ watcher = Get-SvcState 'watcher'; stabilizer = Get-SvcState 'stabilizer' }
        system   = @{
            cpu = $cpu; ramFree = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
            ramTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
            diskFree = [math]::Round($disk.FreeSpace / 1GB, 1)
            gpu = $gpu; gpuAuto = $gpuAuto; perf = $perf; perfAC = $perfAC; perfBatt = $perfBatt
        }
        agents   = @($Agents.GetEnumerator() | ForEach-Object {
            @{ name = $_.Key; model = $(if ($_.Value.Model) { $_.Value.Model } else { 'default' })
               busy = [bool](Test-Path (Join-Path $RunsDir "$($_.Key).lock")) }
        })
        runs     = @(Get-RunStates)
        repos    = @(Get-RepoStates)
        commands = @($Cmds.GetEnumerator() | ForEach-Object { @{ name = $_.Key; desc = $_.Value.Desc } })
    }
}

function Invoke-Dispatch($agent, $task) {
    if (-not $Agents.Contains($agent)) { return @{ ok = $false; error = "нет агента $agent" } }
    if (-not $task) { return @{ ok = $false; error = 'пустая задача' } }
    $a = $Agents[$agent]
    $lockFile = Join-Path $RunsDir "$agent.lock"
    if (Test-Path $lockFile) {
        $lockPid = [int](Get-Content $lockFile -TotalCount 1)
        if (Get-Process -Id $lockPid) { return @{ ok = $false; error = "агент занят (PID $lockPid)" } }
        Remove-Item $lockFile -Force
    }
    $runId  = '{0}-{1:yyyyMMdd-HHmmss}' -f $agent, (Get-Date)
    $log    = Join-Path $RunsDir "$runId.log"
    $errLog = Join-Path $RunsDir "$runId.err.log"
    $exitF  = Join-Path $RunsDir "$runId.exit"
    $prompt = "{0}`n`nЗадача от главагента: {1}`n`nКогда закончишь — дай краткий итог: что сделано, что нет и почему." -f $a.Role, $task
    $modelArg = if ($a.Model) { "-m `"$($a.Model)`"" } else { '' }
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
    @{ ok = $true; runId = $runId }
}

function Send-Response($ctx, [string]$body, [string]$type) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($body)
    $ctx.Response.ContentType = $type
    $ctx.Response.ContentLength64 = $bytes.Length
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $ctx.Response.Close()
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()
Write-Host "Jarvis Hub: http://127.0.0.1:$Port/" -ForegroundColor Cyan

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $path = $ctx.Request.Url.AbsolutePath
    $method = $ctx.Request.HttpMethod
    try {
        switch ($path) {
            '/' {
                Send-Response $ctx ([IO.File]::ReadAllText((Join-Path $HubDir 'web\index.html'))) 'text/html; charset=utf-8'
            }
            '/api/state' {
                Send-Response $ctx (Get-State | ConvertTo-Json -Depth 6 -Compress) 'application/json; charset=utf-8'
            }
            '/api/result' {
                $id = [uri]::UnescapeDataString($ctx.Request.QueryString['id']) -replace '[^\w\-]', ''
                $f = Join-Path $RunsDir "$id.log"
                Send-Response $ctx $(if (Test-Path $f) { [IO.File]::ReadAllText($f) } else { '(нет такого запуска)' }) 'text/plain; charset=utf-8'
            }
            '/api/dispatch' {
                $reader = [IO.StreamReader]::new($ctx.Request.InputStream)
                $body = $reader.ReadToEnd() | ConvertFrom-Json
                Send-Response $ctx (Invoke-Dispatch $body.agent $body.task | ConvertTo-Json -Compress) 'application/json; charset=utf-8'
            }
            '/api/cmd' {
                $reader = [IO.StreamReader]::new($ctx.Request.InputStream)
                $body = $reader.ReadToEnd() | ConvertFrom-Json
                if ($Cmds.Contains($body.name)) {
                    $line = $Cmds[$body.name].Run -replace '\{KAW\}', $KawDir
                    Start-Process cmd.exe -ArgumentList '/c', $line -WindowStyle Hidden
                    Send-Response $ctx '{"ok":true}' 'application/json'
                } else { Send-Response $ctx '{"ok":false}' 'application/json' }
            }
            '/api/prune' {
                & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $HubDir 'hub.ps1') prune | Out-Null
                Send-Response $ctx '{"ok":true}' 'application/json'
            }
            default { $ctx.Response.StatusCode = 404; $ctx.Response.Close() }
        }
    } catch {
        "$([datetime]::Now) $method $path :: $($_.Exception.Message)`n$($_.ScriptStackTrace)" | Out-File (Join-Path $RunsDir 'server-error.log') -Append -Encoding utf8
        try { $ctx.Response.StatusCode = 500; $ctx.Response.Close() } catch {}
    }
}
