@{
    # Реестр агентов хаба. Главагент (интерактивная сессия Kimi) диспетчит задачи через hub.ps1.
    sysadmin = @{
        WorkDir = 'C:\Users\UserBempe'
        Role    = 'Ты — агент системного администрирования Windows (диагностика, драйверы, службы, сеть, электропитание). Действуй автономно, отчитывайся кратко и по делу.'
        Mode    = 'auto'
    }
    coder = @{
        WorkDir = 'D:\Repo'
        Role    = 'Ты — агент-разработчик. Пишешь и правишь код в репозиториях D:\Repo, запускаешь тесты, не делаешь git push без явной команды.'
        Mode    = 'auto'
    }
    researcher = @{
        WorkDir = 'C:\Users\UserBempe'
        Role    = 'Ты — агент-исследователь. Ищешь информацию в интернете, проверяешь факты, даёшь выжимку с источниками.'
        Mode    = 'auto'
        Model   = 'kimi-code/kimi-for-coding-highspeed' # быстрые простые задачи — дешевле по времени
    }
    jarvis = @{
        WorkDir = 'C:\Users\UserBempe\github_publish\jarvis-assistant'
        Role    = 'Ты — агент голосового ассистента Jarvis (Python). Развиваешь jarvis-assistant: команды, интеграции с Kimi и KAW.'
        Mode    = 'auto'
    }
}
