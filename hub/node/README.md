# Jarvis Hub (Node.js)

Веб-пульт главагента: агенты Kimi, KAW, GitHub, система. Ноль npm-зависимостей (node:http + fetch).

## Запуск

```bash
node server.js            # http://127.0.0.1:8787/ , помощь: /help
# или
npm start
```

## Конфигурация

- `public/` — SPA (пульт) и страница помощи
- `data/settings.json` — настройки (редактируются из веб-UI, кнопка ⚙)
- `.env` — порт/host и OAuth-ключи (см. `.env.example`; создаётся из веб-UI: Настройки → Авторизация)
- `../runs/` — логи запусков агентов

## OAuth (GitHub / Google)

Без ключей — открытый локальный режим. Как только задан хотя бы один провайдер,
пульт требует вход (cookie-сессия 7 дней, allowlist через `AUTH_ALLOW`).
Подробно: `/help`, раздел 4.

## Деплой на сервер

```bash
HOST=0.0.0.0 node server.js
# или Docker:
docker build -t jarvis-hub .
docker run -d -p 8787:8787 --env-file .env -v $(pwd)/data:/app/data jarvis-hub
```

Наружу — только с включённым OAuth и за reverse proxy с HTTPS.
Панели KAW/G-Helper/агенты работают только на Windows-хосте, где живут kimi-approve-watch и kimi CLI.

## API

См. `/help` раздел 6: `/api/state`, `/api/dispatch`, `/api/result`, `/api/cmd`, `/api/prune`, `/api/settings`, `/api/me`.
