# Kimi Approve Watch

![Version](https://img.shields.io/badge/version-0.3.0-blue)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE?logo=powershell&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-10%2F11-0078D6?logo=windows&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)

**[English version → README.en.md](README.en.md)**

> Лёгкий и мягкий автоапрувер диалогов [Kimi CLI](https://github.com/MoonshotAI/kimi-cli) + стабилизатор ПК на время долгой работы агентов в терминалах. Одна команда — и машина под контролем, пока нейросети кодят и собирают проекты.

---

## Установка одной командой — из любого терминала

**PowerShell / Windows Terminal / pwsh 7:**

```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/bimpiRU/kimi-approve-watch/main/quickstart.ps1 | iex"
```

**CMD:**

```cmd
curl -L -o "%TEMP%\kaw-quickstart.ps1" https://raw.githubusercontent.com/bimpiRU/kimi-approve-watch/main/quickstart.ps1 && powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\kaw-quickstart.ps1"
```

**Git Bash / MSYS2 / WSL:**

```bash
curl -sL https://raw.githubusercontent.com/bimpiRU/kimi-approve-watch/main/quickstart.sh | bash
```

Всё ставится в `%USERPROFILE%\kimi-approve-watch` (через `git clone`, без git — ZIP). Повторный запуск обновляет до последней версии. Переопределения: `KAW_MODE=gate|startup|none`, `KAW_DIR=<путь>`.

## Что делает

### Наблюдатель апрувов — быстрый и мягкий

Kimi CLI при опасных действиях показывает диалог (`Run this command? 1. Approve once ...`). Наблюдатель сканирует окна Windows Terminal каждые 5 секунд и нажимает выбранный вариант за вас.

- **быстро**: `FastMode` уменьшает задержки; `-ApproveKey auto` сам находит номер варианта «Approve once» в тексте диалога
- **мягко**: после нажатия возвращает фокус окну, в котором вы работали; собственный процесс — с пониженным приоритетом
- **легко**: читает только `TermControl`-элементы через UI Automation (не всё дерево окна), смотрит только хвост буфера
- **выбор варианта**: `-ApproveKey 1|2|3|auto` — какой пункт диалога нажимать (по умолчанию `1` — одноразовый апрув)
- **автоапрув себя**: `-AutoApproveSelf` — апрувить и в собственном окне watcher-а (главный терминал); `-NoSelfSkip` — не пропускать окна, где обсуждается этот бот
- чистит мусорный символ, который TUI иногда оставляет в строке ввода
- свёрнутые окна и окна из `-ExcludeHwnd` не трогает
- профили агентов: `kimi` (по умолчанию), `claude` (экспериментально), `generic` (любой похожий диалог)

### Стабилизатор ПК

- **keep-awake** — ПК не заснёт и экран не погаснет
- **High performance** — максимальная схема питания на время работы, прежняя возвращается при выходе
- **приоритет терминала** — WindowsTerminal держится на AboveNormal
- **приоритет неактивных агентов** — процессы `kimi`, которые молчат более 2 часов, автоматически понижаются до `BelowNormal` и возвращаются в `Normal` при появлении активности (`ManageAgentPriority`)
- **советы по промтам** — каждые N минут кроссплатформенное уведомление с подсказкой, как сформулировать запрос агенту (`PromptTips`, `PromptTipIntervalMinutes`)
- **тихие часы** — `QuietHours = "23-07"` отключает уведомления ночью
- **автоочистка temp** — при нехватке места на диске очищает `%TEMP%` (`AutoCleanTemp`)
- **RAM** — при нехватке пишет в лог топ-5 процессов по памяти
- **диск** — тревога при нехватке места (сборки едят гигабайты)
- **сеть** — фиксирует окна отказа (в это время API нейросетей недоступен)
- **pending reboot** — предупредит об ожидающей перезагрузке Windows
- **падение Windows Terminal** — алерт в лог

### Надёжность

- **шлюз при входе в Windows** — работа начинается только после вашего «Да»
- **фоновый сервис** — `install-service.ps1` запускает runner при старте ПК, но watcher/stabilizer стартуют только после подтверждения при входе
- **антидубль** — мьютексы против двойного запуска
- **самовосстановление** — лаунчер перезапускает упавший модуль
- логи только о событиях, без спама

## Требования

- Windows 10/11, Windows Terminal, PowerShell 5.1 (всё встроено)

## Режимы автозапуска

| Режим | Что делает | Права админа |
|---|---|---|
| `gate` | При входе в Windows окно подтверждения — старт только после «Да» | Да (UAC при установке) |
| `startup` | Ярлык в «Автозагрузке», стартует сразу и молча | Нет |
| `none` | Без автозапуска, просто запустить сейчас | Нет |
| `service` | `install-service.ps1` — фоновый сервис до входа + подтверждение при входе | Да |

## Управление — `kaw.ps1`

```powershell
.\kaw.ps1 start               # запустить всё
.\kaw.ps1 stop                # мягко остановить всё
.\kaw.ps1 restart             # перезапуск
.\kaw.ps1 status              # состояние модулей + хвосты логов
.\kaw.ps1 log stabilizer      # хвост лога (watcher|stabilizer)
.\kaw.ps1 enable stabilizer   # включить стабилизатор в автозапуске
.\kaw.ps1 disable stabilizer  # выключить
.\kaw.ps1 config              # показать действующий конфиг
.\kaw.ps1 windows             # hwnd окон терминала
.\kaw.ps1 uninstall           # полное удаление
```

Отдельные скрипты (`status.ps1`, `stop-watcher.ps1`, `show-windows.ps1`...) тоже работают — `kaw.ps1` просто удобная обёртка над ними.

## Настройка — `kaw.config.psd1`

Скопируйте `kaw.config.example.psd1` → `kaw.config.psd1` и отредактируйте. Конфиг подхватывается и при автозапуске, и при ручном старте; параметры командной строки важнее конфига.

```powershell
@{
  Watcher = @{
    IntervalSeconds = 5           # период сканирования
    Agents          = 'kimi'      # 'kimi' или 'kimi,claude,generic'
    ApproveKey      = ''          # '' = 1 (одноразовый); '1'|'2'|'3' — свой вариант; 'auto'
    ExcludeHwnd     = @()         # @(3344318) — не трогать эти окна
    FocusRestore    = $false      # $true — вернуть фокус прежнему окну (экспериментально)
    NoSelfSkip      = $true       # $true — апрувить и в окне, где обсуждается этот бот
    AutoApproveSelf = $true       # $true — апрувить и в собственном окне watcher-а
    FastMode        = $true       # $true — быстрее, но чуть больше нагрузка
  }
  Stabilizer = @{
    MinFreeRamGB = 1.5; MinFreeDiskGB = 5; WatchDrives = @('C:')
    HighPerformance = $true; BoostTerminalPriority = $true
    ManageAgentPriority = $false   # $true — управлять приоритетом неактивных агентов
    PromptTips = $false            # $true — всплывающие советы по промтам
    PromptTipIntervalMinutes = 30
    AutoCleanTemp = $false         # $true — автоочистка %TEMP% при нехватке диска
    QuietHours = ''                # "23-07" — тихие часы
  }
}
```

Запуск напрямую с параметрами тоже работает:

```powershell
.\watch-approve.ps1 -IntervalSeconds 5 -ApproveKey auto -ExcludeHwnd 3344318 -FastMode -Once
.\stabilize.ps1 -MinFreeRamGB 2 -WatchDrives 'C:','D:' -AutoCleanTemp -Once
```

hwnd своего окна подскажет `.\kaw.ps1 windows` — исключите его, если не хотите автоапрува в личной сессии.

### Личные вкладки и автоапрув себя

Названия вкладок у каждого свои, поэтому исключения задаются не по имени, а по **hwnd** окна:

1. Откройте нужные вкладки и запустите `.\kaw.ps1 windows`.
2. Скопируйте hwnd личных вкладок в `kaw.config.psd1` → `Watcher.ExcludeHwnd`.
3. Если вы управляете watcher из той же сессии, включите `NoSelfSkip = $true` и `AutoApproveSelf = $true`.

```powershell
@{
  Watcher = @{
    ExcludeHwnd   = @(328372, 1377268)   # личные вкладки
    NoSelfSkip    = $true                # апрувить и в окнах, где обсуждается бот
    AutoApproveSelf = $true              # апрувить и в собственном окне watcher-а
  }
}
```

## Как это работает

1. Раз в `IntervalSeconds` перечисляются окна `CASCADIA_HOSTING_WINDOW_CLASS` (Windows Terminal).
2. UI Automation читает только `TermControl`-элементы — легко даже на больших буферах.
3. Все строки диалога из профиля есть в хвосте (15 строк) → окно на передний план, `SendKeys` с выбранным вариантом, **фокус возвращается** прежнему окну.
4. Мусорный символ в строке ввода после нажатия убирается Backspace.
5. Стабилизатор параллельно опрашивает CIM (RAM/диск/CPU), пингует сеть, проверяет реестр на pending reboot — и пишет в лог только переходы состояний.

## Почему не классическая служба Windows?

Классические службы работают в сессии 0 и **не видят окна пользователя** — UI Automation и SendKeys там бесполезны. Поэтому основной режим — задача планировщика «при входе» (`gate`) или «Автозагрузка» (`startup`).

Для тех, кто хочет именно фоновый сервис до входа, есть `install-service.ps1`: он создаёт задачу `KAWService` (старт при включении ПК) и задачу `KAWGate` (окно подтверждения при входе). Фоновый сервис ждёт сигнала, и только после вашего «Да» запускает watcher и stabilizer в интерактивной сессии.

## Файлы

| Файл | Назначение |
|---|---|
| `kaw.ps1` | Единая команда управления (start/stop/status/log/config/...) |
| `watch-approve.ps1` | Ядро автоапрува: профили агентов, выбор варианта, возврат фокуса |
| `stabilize.ps1` | Стабилизатор: питание, RAM/диск/сеть/CPU, алерты, уведомления |
| `watch-approve-launcher.ps1` | Перезапуск упавших модулей, антидубль |
| `start-all.ps1` | Точка запуска обоих модулей (аргументы из конфига) |
| `watcher-gate.ps1` | Окно подтверждения при входе в Windows |
| `service-runner.ps1` | Фоновый раннер для режима `service` |
| `install.ps1` / `install-service.ps1` / `uninstall.ps1` | Установка / удаление автозапуска |
| `quickstart.ps1` / `quickstart.sh` | Bootstrap одной командой (PowerShell / bash) |
| `kaw.config.example.psd1` | Пример конфига |
| `stop-watcher.ps1`, `status.ps1`, `show-windows.ps1` | Служебные скрипты |

Runtime-файлы (`*.log`, `*.pid`, `STOP`, `stabilizer.enabled`, `kaw.config.psd1`, `.service-go`) в git не попадают.

## Безопасность

- По умолчанию нажимается только одноразовый апрув (`1`); вариант `2` («approve always») доступен, но включайте осознанно.
- Диалог определяется по хвосту буфера — срабатывание на историю исключено.
- Стабилизатор только наблюдает; активные действия (схема питания, приоритет) откатываются.
- Профиль `claude` экспериментальный — проверьте на своей версии Claude Code.
- Никаких сетевых запросов (кроме quickstart) и внешних зависимостей.

## Лицензия

[MIT](LICENSE) · [Changelog](CHANGELOG.md)
