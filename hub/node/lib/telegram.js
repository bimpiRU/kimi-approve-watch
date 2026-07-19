// Telegram-бот: управление и уведомления. Инлайн-кнопки, выбор агента, шаблоны.
// Конфиг: TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID (.env). Отвечает только разрешённому чату.
const fs = require('fs');
const path = require('path');

const token = () => process.env.TELEGRAM_BOT_TOKEN || '';
const chatId = () => process.env.TELEGRAM_CHAT_ID || '';
const api = () => `https://api.telegram.org/bot${token()}`;

function persistEnv(key, value) {
  const envFile = path.join(__dirname, '..', '.env');
  let lines = [];
  try { lines = fs.readFileSync(envFile, 'utf8').split('\n').filter(l => l.trim() && !l.startsWith('#')); } catch {}
  const map = new Map(lines.map(l => { const m = l.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)$/); return m ? [m[1], m[2]] : null; }).filter(Boolean));
  map.set(key, value);
  fs.writeFileSync(envFile, [...map].map(([k, v]) => `${k}=${v}`).join('\n') + '\n', 'utf8');
}

async function call(method, body) {
  try {
    const r = await fetch(`${api()}/${method}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
    });
    return await r.json();
  } catch { return null; }
}

const send = (text, to, keyboard) => {
  const chat = to || chatId();
  if (!token() || !chat) return Promise.resolve();
  return call('sendMessage', {
    chat_id: chat, text: String(text).slice(0, 3900),
    ...(keyboard ? { reply_markup: { inline_keyboard: keyboard } } : {}),
  });
};

const mainMenu = () => [
  [{ text: '📊 Статус', callback_data: 'status' }, { text: '📋 Запуски', callback_data: 'runs' }],
  [{ text: '🤖 Агенты (задача)', callback_data: 'agents' }, { text: '⭐ Шаблоны', callback_data: 'presets' }],
  [{ text: '🧹 Prune', callback_data: 'prune' }, { text: '↻ Перезапуск', callback_data: 'restart' }],
];

const pending = new Map(); // chatId -> agent (ждём текст задачи)

function statusText(ctx) {
  const s = ctx.state();
  const agents = s.agents.map(a => `${a.busy ? '🟡' : '🟢'}${a.name}`).join(' ');
  return `KAW: watcher ${s.kaw.watcher || 'OFF'}, stabilizer ${s.kaw.stabilizer || 'OFF'}\nCPU ${s.system.cpu}% RAM ${s.system.ramFree}/${s.system.ramTotal} GB, C: ${s.system.diskFree} GB\nGPU ${s.system.gpu}, режим ${s.system.perf}\nАгенты: ${agents}`;
}

function runsText(ctx) {
  const runs = ctx.state().runs.slice(0, 5);
  return runs.length ? runs.map(r => `${r.id} — exit ${r.exit} (${r.started})`).join('\n') : 'запусков нет';
}

function allowed(from) {
  return !chatId() || String(from) === chatId();
}

async function adopt(from) {
  process.env.TELEGRAM_CHAT_ID = String(from);
  persistEnv('TELEGRAM_CHAT_ID', String(from));
  await send(`⬢ Чат ${from} привязан как админский.`, from, mainMenu());
}

async function onCallback(ctx, cb) {
  const from = cb.message.chat.id;
  await call('answerCallbackQuery', { callback_query_id: cb.id });
  if (!allowed(from)) return;
  const d = cb.data;

  if (d === 'status') return send(statusText(ctx), from, mainMenu());
  if (d === 'runs') return send(runsText(ctx), from, mainMenu());
  if (d === 'agents') {
    const kb = ctx.state().agents.map(a => [{ text: `${a.busy ? '🟡' : '🟢'} ${a.name}`, callback_data: `d:${a.name}` }]);
    kb.push([{ text: '« меню', callback_data: 'menu' }]);
    return send('Кому поручить? Выбери агента, затем одним сообщением напиши задачу:', from, kb);
  }
  if (d.startsWith('d:')) {
    const agent = d.slice(2);
    pending.set(String(from), agent);
    return send(`✍️ Пиши задачу для «${agent}» одним сообщением (или /cancel):`, from);
  }
  if (d === 'presets') {
    const presets = ctx.settings().presets || [];
    if (!presets.length) return send('Шаблоны не настроены (Настройки → Шаблоны в веб-пульте).', from, mainMenu());
    const kb = presets.map((p, i) => [{ text: p.name, callback_data: `p:${i}` }]);
    kb.push([{ text: '« меню', callback_data: 'menu' }]);
    return send('Шаблоны задач:', from, kb);
  }
  if (d.startsWith('p:')) {
    const p = (ctx.settings().presets || [])[+d.slice(2)];
    if (!p) return send('шаблон не найден', from, mainMenu());
    const r = ctx.dispatch(p.agent, p.task);
    return send(r.ok ? `🚀 ${p.name}: запущен ${r.runId}` : `ошибка: ${r.error}`, from, mainMenu());
  }
  if (d === 'prune') {
    const r = ctx.prune();
    return send(`prune: убито ${r.killed}, очищено ${r.cleaned}`, from, mainMenu());
  }
  if (d === 'restart') {
    await send('↻ перезапуск сервера…', from);
    return ctx.restart();
  }
  if (d === 'menu') return send('⬢ Jarvis Hub', from, mainMenu());
}

async function onMessage(ctx, msg) {
  if (!msg.text) return;
  const from = String(msg.chat.id);
  if (!allowed(from)) return;
  if (!chatId()) return adopt(from); // авто-привязка первого чата

  const text = msg.text.trim();
  if (text === '/cancel') { pending.delete(String(from)); return send('отменено', from, mainMenu()); }

  if (pending.has(String(from)) && !text.startsWith('/')) {
    const agent = pending.get(String(from));
    pending.delete(String(from));
    const r = ctx.dispatch(agent, text);
    return send(r.ok ? `🚀 запущен: ${r.runId}` : `ошибка: ${r.error}`, from, mainMenu());
  }

  const [cmd, ...rest] = text.split(/\s+/);
  const arg = rest.join(' ').replace(/^["«]|["»]$/g, '');
  if (cmd === '/start' || cmd === '/help' || cmd === '/menu') {
    return send('⬢ Jarvis Hub — кнопки ниже. Команды: /status /runs /dispatch <агент> <задача> /prune /restart', from, mainMenu());
  }
  if (cmd === '/status') return send(statusText(ctx), from, mainMenu());
  if (cmd === '/runs') return send(runsText(ctx), from, mainMenu());
  if (cmd === '/dispatch') {
    const sp = arg.indexOf(' ');
    if (sp < 0) return send('формат: /dispatch <агент> <задача>', from);
    const r = ctx.dispatch(arg.slice(0, sp), arg.slice(sp + 1));
    return send(r.ok ? `🚀 запущен: ${r.runId}` : `ошибка: ${r.error}`, from, mainMenu());
  }
  if (cmd === '/prune') { const r = ctx.prune(); return send(`prune: убито ${r.killed}, очищено ${r.cleaned}`, from, mainMenu()); }
  if (cmd === '/restart') { await send('↻ перезапуск сервера…', from); return ctx.restart(); }
  send('непонятно. /menu — кнопки, /help — команды', from, mainMenu());
}

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
          if (u.callback_query) onCallback(ctx, u.callback_query).catch(() => {});
          else if (u.message) onMessage(ctx, u.message).catch(() => {});
        }
      } catch { await new Promise(r2 => setTimeout(r2, 5000)); }
    }
  })();
  watchRuns(ctx);
  send('⬢ Jarvis Hub поднят', null, mainMenu());
  console.log('[telegram] бот запущен');
}

module.exports = { start, send };
