@{
    # Тема дашборда hub-ui.ps1. Цвета — любые ConsoleColor (Cyan, Green, Gray, DarkGray, Yellow, Magenta, White, Red).
    Banner     = 'J A R V I S   H U B'
    Accent     = 'Cyan'       # заголовки панелей и рамки
    Text       = 'Gray'       # основной текст
    Warn       = 'Yellow'
    Ok         = 'Green'
    Width      = 96           # ширина панелей в символах
    RefreshSec = 5            # автообновление дашборда
    # Какие панели показывать и в каком порядке: kaw, system, agents, runs, repos
    Panels     = @('kaw', 'system', 'agents', 'runs', 'repos')
}
