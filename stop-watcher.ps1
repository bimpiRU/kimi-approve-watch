# stop-watcher.ps1 — остановить наблюдатель, стабилизатор и лаунчеры.
# Создаёт файл STOP (общий для всех модулей): они завершатся на следующем тике,
# лаунчеры не перезапустят их.
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$stopFile = Join-Path $dir 'STOP'
New-Item -Path $stopFile -ItemType File -Force | Out-Null
Write-Host "[OK] Создан файл STOP. Наблюдатель и стабилизатор остановятся в течение ~30 секунд." -ForegroundColor Green
Write-Host "Чтобы снова запустить: .\install.ps1 -Mode none  (STOP удаляется автоматически)"
