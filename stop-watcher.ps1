# stop-watcher.ps1 — остановить наблюдатель и лаунчер.
# Создаёт файл STOP: наблюдатель завершится на следующем тике, лаунчер не перезапустит его.
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$stopFile = Join-Path $dir 'STOP'
New-Item -Path $stopFile -ItemType File -Force | Out-Null
Write-Host "[OK] Создан файл STOP. Наблюдатель остановится в течение ~10 секунд." -ForegroundColor Green
Write-Host "Чтобы снова запустить: .\install.ps1 -Mode none  (STOP удаляется автоматически)"
