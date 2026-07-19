// Jarvis Hub — Node.js сервер. Ноль зависимостей (node:http + fetch).
// Конфиг: .env (см. .env.example). Запуск: node server.js
const http = require('http');
const fs = require('fs');
const path = require('path');

// --- .env ---
try {
  for (const line of fs.readFileSync(path.join(__dirname, '.env'), 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2];
  }
} catch {}

const PORT = parseInt(process.env.PORT || '8787', 10);
const HOST = process.env.HOST || '127.0.0.1'; // 0.0.0.0 — для выноса на сервер

const settingsStore = require('./lib/settings');
const state = require('./lib/state');
const disp = require('./lib/dispatch');
const auth = require('./lib/auth');

const RUNS_DIR = state.RUNS_DIR;
fs.mkdirSync(RUNS_DIR, { recursive: true });
let settings = settingsStore.load();

const json = (res, code, obj) => {
  const body = JSON.stringify(obj);
  res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(body);
};
const text = (res, code, body, type = 'text/plain; charset=utf-8') => res.writeHead(code, { 'Content-Type': type }).end(body);
const readBody = req => new Promise(resolve => {
  let b = '';
  req.on('data', c => { b += c; if (b.length > 1e6) req.destroy(); });
  req.on('end', () => { try { resolve(JSON.parse(b || '{}')); } catch { resolve({}); } });
});
const baseUrl = req => `${req.headers['x-forwarded-proto'] || 'http'}://${req.headers.host}`;

function restartServer() {
  setTimeout(() => {
    // новый экземпляр поднимется рядом, старый уходит; дочерним агентам detached не вредит
    require('child_process').spawn(process.execPath, [path.join(__dirname, 'server.js')], {
      cwd: __dirname, detached: true, windowsHide: true, stdio: 'ignore',
    }).unref();
    process.exit(0);
  }, 400);
}

async function handler(req, res) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const p = url.pathname;
  try {
    // --- открытые маршруты ---
    if (p === '/api/health') return json(res, 200, { ok: true, ts: Date.now() });
    if (p === '/api/me') {
      const s = auth.getSession(req);
      return json(res, 200, {
        authRequired: auth.anyConfigured(),
        providers: auth.providers(),
        pin: auth.pinEnabled(),
        local: auth.localEnabled(),
        user: s ? s.user : null,
      });
    }
    if (p === '/auth/local' && req.method === 'POST') {
      const body = await readBody(req);
      if (auth.verifyUser(body.login, body.password)) {
        const token = auth.createSession(String(body.login).toLowerCase(), 'local');
        res.writeHead(302, {
          'Set-Cookie': `jh_session=${token}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${7 * 24 * 3600}`,
          Location: '/',
        });
        return res.end();
      }
      return text(res, 403, 'неверный логин или пароль');
    }
    if (p === '/auth/pin' && req.method === 'POST') {
      const body = await readBody(req);
      if (auth.pinEnabled() && body.pin === process.env.AUTH_PIN) {
        const token = auth.createSession('admin (pin)', 'pin');
        res.writeHead(302, {
          'Set-Cookie': `jh_session=${token}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${7 * 24 * 3600}`,
          Location: '/',
        });
        return res.end();
      }
      return text(res, 403, 'неверный PIN');
    }
    if (p === '/logout') {
      auth.destroySession(req);
      res.writeHead(302, { 'Set-Cookie': 'jh_session=; Path=/; Max-Age=0', Location: '/' });
      return res.end();
    }
    const authMatch = p.match(/^\/auth\/(github|google)(\/callback)?$/);
    if (authMatch) {
      const [, provider, cb] = authMatch;
      if (!auth.configured(provider)) return text(res, 400, `Провайдер ${provider} не настроен (см. Настройки → Авторизация)`);
      if (!cb) {
        res.writeHead(302, { Location: auth.startAuth(provider, baseUrl(req)) });
        return res.end();
      }
      try {
        const login = await auth.finishAuth(provider, Object.fromEntries(url.searchParams), baseUrl(req));
        const token = auth.createSession(login, provider);
        res.writeHead(302, {
          'Set-Cookie': `jh_session=${token}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${7 * 24 * 3600}`,
          Location: '/',
        });
        return res.end();
      } catch (e) {
        return text(res, 403, `Вход не удался: ${e.message}`);
      }
    }

    // --- защищённые маршруты ---
    if (auth.anyConfigured() && !auth.getSession(req)) {
      if (p.startsWith('/api/')) return json(res, 401, { error: 'unauthorized' });
    }

    if (p === '/' || p === '/index.html') {
      return text(res, 200, fs.readFileSync(path.join(__dirname, 'public', 'index.html'), 'utf8'), 'text/html; charset=utf-8');
    }
    if (p === '/help') {
      return text(res, 200, fs.readFileSync(path.join(__dirname, 'public', 'help.html'), 'utf8'), 'text/html; charset=utf-8');
    }
    if (p === '/api/state') return json(res, 200, state.getState(settings));
    if (p === '/api/result') {
      const id = (url.searchParams.get('id') || '').replace(/[^\w-]/g, '');
      const f = path.join(RUNS_DIR, `${id}.log`);
      if (!fs.existsSync(f)) return text(res, 200, '(нет такого запуска)');
      let out = fs.readFileSync(f, 'utf8');
      if (!out.trim()) { // kimi иногда завершается с пустым stdout — показываем диагностику вместо пустоты
        const ex = path.join(RUNS_DIR, `${id}.exit`);
        const er = path.join(RUNS_DIR, `${id}.err.log`);
        const code = fs.existsSync(ex) ? fs.readFileSync(ex, 'utf8').trim() : '(ещё выполняется)';
        out = `(stdout пуст, exit: ${code})`;
        if (fs.existsSync(er)) {
          const tail = fs.readFileSync(er, 'utf8').trim().split('\n').slice(-15).join('\n');
          if (tail) out += `\n--- stderr (последние строки) ---\n${tail}`;
        }
      }
      return text(res, 200, out);
    }
    if (p === '/api/dispatch' && req.method === 'POST') {
      const body = await readBody(req);
      return json(res, 200, disp.dispatch(settings, RUNS_DIR, body.agent, body.task));
    }
    if (p === '/api/cmd' && req.method === 'POST') {
      const body = await readBody(req);
      const cmd = settings.commands[body.name];
      if (!cmd) return json(res, 404, { ok: false, error: 'нет такой команды' });
      const line = cmd.run.replace(/\{KAW\}/g, state.KAW_DIR);
      const f = path.join(RUNS_DIR, `cmd-${Date.now()}.cmd`);
      fs.writeFileSync(f, '@echo off\r\nchcp 65001 >nul\r\n' + line + '\r\n', 'utf8');
      require('child_process').spawn('cmd.exe', ['/c', f], { stdio: 'ignore' }).unref();
      return json(res, 200, { ok: true });
    }
    if (p === '/api/prune' && req.method === 'POST') {
      const body = await readBody(req);
      return json(res, 200, disp.prune(RUNS_DIR, body.minutes || 30));
    }
    if (p === '/api/restart' && req.method === 'POST') {
      json(res, 200, { ok: true });
      return restartServer();
    }
    if (p === '/api/users' && req.method === 'POST') {
      const body = await readBody(req);
      if (body.action === 'add') return json(res, 200, auth.addUser(body.login, body.password));
      if (body.action === 'remove') return json(res, 200, auth.removeUser(body.login));
      return json(res, 200, { ok: true, users: auth.listUsers() });
    }
    if (p === '/api/sessions') {
      // старые сессии kimi из session_index.jsonl, свежие сверху
      const idx = path.join(process.env.USERPROFILE, '.kimi-code', 'session_index.jsonl');
      const out = [];
      try {
        for (const line of fs.readFileSync(idx, 'utf8').split('\n')) {
          if (!line.trim()) continue;
          try {
            const s = JSON.parse(line);
            let mtime = 0;
            try { mtime = fs.statSync(s.sessionDir).mtimeMs; } catch {}
            out.push({ id: s.sessionId, workDir: s.workDir, mtime });
          } catch {}
        }
      } catch {}
      out.sort((a, b) => b.mtime - a.mtime);
      const p2 = n => String(n).padStart(2, '0');
      return json(res, 200, out.slice(0, 30).map(s => {
        const d = new Date(s.mtime);
        return { id: s.id, workDir: s.workDir, when: `${p2(d.getDate())}.${p2(d.getMonth() + 1)} ${p2(d.getHours())}:${p2(d.getMinutes())}` };
      }));
    }
    if (p === '/api/sessions/open' && req.method === 'POST') {
      const body = await readBody(req);
      const id = String(body.id || '').replace(/[^\w-]/g, '');
      const workDir = String(body.workDir || process.env.USERPROFILE);
      if (!id) return json(res, 400, { ok: false, error: 'нет id' });
      const kimi = path.join(process.env.USERPROFILE, '.kimi-code', 'bin', 'kimi.exe');
      const f = path.join(RUNS_DIR, `open-${Date.now()}.cmd`);
      fs.writeFileSync(f, `@echo off\r\nstart "" wt -w new -d "${workDir}" cmd /k ""${kimi}" -S ${id}"\r\n`, 'ascii');
      require('child_process').spawn('cmd.exe', ['/c', f], { stdio: 'ignore' }).unref();
      return json(res, 200, { ok: true });
    }
    if (p === '/api/stop' && req.method === 'POST') {
      const body = await readBody(req);
      const agent = String(body.agent || '').replace(/[^\w-]/g, '');
      const lock = path.join(RUNS_DIR, `${agent}.lock`);
      if (!fs.existsSync(lock)) return json(res, 404, { ok: false, error: 'агент не запущен' });
      const pid = parseInt(fs.readFileSync(lock, 'utf8'), 10);
      require('child_process').execFile('taskkill', ['/PID', String(pid), '/T', '/F'], () => {});
      fs.rmSync(lock, { force: true });
      return json(res, 200, { ok: true });
    }
    if (p === '/api/settings') {
      if (req.method === 'GET') return json(res, 200, settings);
      if (req.method === 'POST') {
        const body = await readBody(req);
        if (body.authEnv) { // ключи OAuth — в .env и сразу в process.env (без рестарта)
          const envFile = path.join(__dirname, '.env');
          let lines = [];
          try { lines = fs.readFileSync(envFile, 'utf8').split('\n').filter(l => l.trim() && !l.startsWith('#')); } catch {}
          const map = new Map(lines.map(l => { const m = l.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)$/); return m ? [m[1], m[2]] : null; }).filter(Boolean));
          for (const [k, v] of Object.entries(body.authEnv)) {
            if (/^[A-Z0-9_]+$/.test(k) && typeof v === 'string') { map.set(k, v); process.env[k] = v; }
          }
          fs.writeFileSync(envFile, [...map].map(([k, v]) => `${k}=${v}`).join('\n') + '\n', 'utf8');
          return json(res, 200, { ok: true });
        }
        settings = { ...settings, ...body };
        settingsStore.save(settings);
        return json(res, 200, { ok: true });
      }
    }

    res.writeHead(404); res.end();
  } catch (e) {
    json(res, 500, { error: e.message });
  }
}

const server = http.createServer(handler);
server.listen(PORT, HOST, () => {
  console.log(`Jarvis Hub: http://${HOST}:${PORT}/  (help: /help, auth: ${auth.anyConfigured() ? auth.providers().join('+') : 'off, local mode'})`);
  require('./lib/telegram').start({
    RUNS_DIR,
    settings: () => settings,
    state: () => state.getState(settings),
    dispatch: (agent, task) => disp.dispatch(settings, RUNS_DIR, agent, task),
    prune: () => disp.prune(RUNS_DIR, 30),
    restart: restartServer,
  });
});

// HTTPS: если есть data/cert.pfx (см. make-cert.ps1) — дополнительно слушаем HTTPS_PORT
const PFX = path.join(__dirname, 'data', 'cert.pfx');
const HTTPS_PORT = parseInt(process.env.HTTPS_PORT || '8443', 10);
if (fs.existsSync(PFX)) {
  require('https').createServer(
    { pfx: fs.readFileSync(PFX), passphrase: process.env.CERT_PASS || 'jarvis-hub' },
    handler
  ).listen(HTTPS_PORT, HOST, () => console.log(`Jarvis Hub HTTPS: https://${HOST}:${HTTPS_PORT}/`));
}
