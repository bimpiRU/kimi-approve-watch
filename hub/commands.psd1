@{
    # Пользовательские команды хаба: hub.ps1 do <имя>.
    # Run — любая командная строка; плейсхолдер {KAW} заменяется на папку kimi-approve-watch.
    'brightness-max' = @{
        Desc = 'Яркость ноутбука на 100%'
        Run  = 'powershell -NoProfile -Command "(Get-WmiObject -Namespace root/wmi -Class WmiMonitorBrightnessMethods).WmiSetBrightness(1,100)"'
    }
    'kaw-restart' = @{
        Desc = 'Перезапуск наблюдателя и стабилизатора KAW'
        Run  = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{KAW}\kaw.ps1" restart'
    }
    'ghelper' = @{
        Desc = 'Открыть окно G-Helper'
        Run  = 'start "" "C:\Users\UserBempe\Desktop\GHelper.exe"'
    }
    'temp-clean' = @{
        Desc = 'Очистка %TEMP% от файлов старше 7 дней'
        Run  = 'powershell -NoProfile -Command "Get-ChildItem $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue | Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-7)} | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue"'
    }
    'wt-all' = @{
        Desc = 'Список окон терминалов (hwnd) через KAW'
        Run  = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{KAW}\kaw.ps1" windows'
    }
}
