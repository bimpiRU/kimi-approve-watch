// Telegram-бот: управление и уведомления. Конфиг: TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID (.env).
// Длинный polling, без зависимостей. Отвечает только разрешённому chat_id.
const fs = require('fs');
const path = require('path');

const token = () => process.env.TELEGRAM_BOT_TOKEN || '';
const chatId = () => process.env.TELEGRAM_CHAT_ID || '';
const api = () => `https://api.telegram.org/bot${token()}`;

async function send(text, to) {
  const chat = to || chatId();
  if (!token() || !chat) return;
  try {
    await fetch(`${api()}/sendMessage`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: chat, text: String(text).slice(0, 3900) }),
    });
  } catch {}
}

async function handle(ctx, msg) {
  if (!msg || !msg.text) return;
  const from = String(msg.chat.id);
  if (chatId() && from !== chatId()) return; // чужой чат — молчим
  if (!chatId()) { console.log(`[telegram] сообщение из чата ${from} — добавь TELEGRAM_CHAT_ID=${from} в .env для доступа`); return; }

  const [cmd, ...rest] = msg.text.trim().split(/\s+/);
  const arg = rest.join(' ').replace(/^["«]|["»]$/g, '');

  if (cmd === '/start' || cmd === '/help') {
    return send('⬢ Jarvis Hub\n/status — состояние\n/runs — последние запуски\n/dispatch <агент> <задача>\n/prune — убить зависшие\n/restart — перезапуск сервера', from);
  }
  if (cmd === '/status') {
    const s = ctx.state();
    const agents = s.agents.map(a => `${a.busy ? '🟡' : '🟢'}${a.name}`).join(' ');
    return send(`KAW: watcher ${s.kaw.watcher || 'OFF'}, stabilizer ${s.kaw.stabilizer || 'OFF'}\nCPU ${s.system.cpu}% RAM ${s.system.ramFree}/${s.system.ramTotal} GB, C: ${s.system.diskFree} GB\nGPU ${s.system.gpu}, режим ${s.system.perf}\nАгенты: ${agents}`, from);
  }
  if (cmd === '/runs') {
    const runs = ctx.state().runs.slice(0, 5);
    return send(runs.length ? runs.map(r => `${r.id} — exit ${r.exit} (${r.started})`).join('\n') : 'запусков нет', from);
  }
  if (cmd === '/dispatch') {
    const sp = arg.indexOf(' ');
    if (sp < 0) return send('формат: /dispatch <агент> <задача>', from);
    const r = ctx.dispatch(arg.slice(0, sp), arg.slice(sp + 1));
    return send(r.ok ? `🚀 запущен: ${r.runId}` : `ошибка: ${r.error}`, from);
  }
  if (cmd === '/prune') {
    const r = ctx.prune();
    return send(`prune: убито ${r.killed}, очищено ${r.cleaned}`, from);
  }
  if (cmd === '/restart') {
    await send('↻ перезапуск сервера…', from);
    return ctx.restart();
  }
  send('непонятно. /help', from);
}

// уведомления о завершившихся запусках
function watchRuns(ctx) {
  const seen = new Set();
  try { for (const f of fs.readdirSync(ctx.RUNS_DIR)) if (f.endsWith('.exit')) seen.add(f); } catch {}
  setInterval(() => {
    try {
      for (const f of fs.readdirSync(ctx.RUNS_DIR)) {
        if (!f.endsWith('.exit') || seen.has(f)) continue;
        seen.add(f);
        const id = f.replace(/\.exit$/, '');
        const code = fs.readFileSync(path.join(ctx.RUNS_DIR, f), 'utf8').trim();
        let tail = '';
        try { tail = fs.readFileSync(path.join(ctx.RUNS_DIR, `${id}.log`), 'utf8').trim().slice(-400); } catch {}
        send(`${code === '0' ? '✅' : '❌'} ${id} (exit ${code})${tail ? '\n' + tail : ''}`);
      }
    } catch {}
  }, 10000).unref();
}

function start(ctx) {
  if (!token()) { console.log('[telegram] TELEGRAM_BOT_TOKEN не задан — бот выключен'); return; }
  let offset = 0;
  (async function poll() {
    for (;;) {
      try {
        const r = await fetch(`${api()}/getUpdates?offset=${offset}&timeout=25`);
        const d = await r.json();
        for (const u of d.result || []) {
          offset = u.update_id + 1;
          handle(ctx, u.message).catch(() => {});
        }
      } catch { await new Promise(r2 => setTimeout(r2, 5000)); }
    }
  })();
  watchRuns(ctx);
  send('⬢ Jarvis Hub поднят');
  console.log('[telegram] бот запущен');
}

module.exports = { start, send };
