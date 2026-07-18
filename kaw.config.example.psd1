@{
  # Скопируйте этот файл в kaw.config.psd1 и отредактируйте под себя.
  # Параметры командной строки всегда важнее значений из конфига.

  Watcher = @{
    IntervalSeconds = 5           # период сканирования окон, сек
    Agents          = 'kimi'      # профили агентов через запятую: kimi, claude, generic
    ApproveKey      = ''          # ''|'1'|'2'|'3' — свой вариант; 'auto' — автоопределение из текста
    ExcludeHwnd     = @()         # hwnd окон, которые не трогать: @(3344318)
    NoKeepAwake     = $false      # $true — не блокировать сон
    FocusRestore    = $false      # $true — вернуть фокус прежнему окну (экспериментально)
    NoSelfSkip      = $false      # $true — апрувить и в окнах, где обсуждается этот бот
    AutoApproveSelf = $true       # $true — апрувить и в собственном окне watcher-а (главный терминал)
    FastMode        = $true       # $true — меньше задержек, быстрее реакция
  }

  Stabilizer = @{
    IntervalSeconds       = 30
    MinFreeRamGB          = 1.5
    MinFreeDiskGB         = 5
    WatchDrives           = @('C:')
    HighPerformance       = $true
    BoostTerminalPriority = $true
    NoKeepAwake           = $false
    NoNetCheck            = $false
    ManageAgentPriority   = $false   # $true — понижать приоритет агентам Kimi, неактивным >2 ч
    PromptTips            = $false   # $true — всплывающие советы по промтам (кроссплатформенно)
    PromptTipIntervalMinutes = 30
    AutoCleanTemp         = $false   # $true — автоочистка %TEMP% при нехватке диска
    QuietHours            = ''       # "23-07" — не показывать уведомления в это время
  }
}
