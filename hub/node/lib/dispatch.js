// Диспетч агентов: .cmd-обёртка (защита от квотирования), лок на агента, exit-код.
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const KIMI = path.join(process.env.USERPROFILE, '.kimi-code', 'bin', 'kimi.exe');

function pad(n) { return String(n).padStart(2, '0'); }
function runId(agent) {
  const d = new Date();
  return `${agent}-${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
}

function dispatch(settings, RUNS_DIR, agent, task) {
  const a = settings.agents[agent];
  if (!a) return { ok: false, error: `нет агента ${agent}` };
  if (!task) return { ok: false, error: 'пустая задача' };
  if (!fs.existsSync(KIMI)) return { ok: false, error: `kimi не найден: ${KIMI}` };
  if (!fs.existsSync(a.workdir)) return { ok: false, error: `workdir не существует: ${a.workdir}` };

  const lockFile = path.join(RUNS_DIR, `${agent}.lock`);
  if (fs.existsSync(lockFile)) {
    const pid = parseInt(fs.readFileSync(lockFile, 'utf8'), 10);
    let busy = false;
    try { process.kill(pid, 0); busy = true; } catch {}
    if (busy) return { ok: false, error: `агент занят (PID ${pid})` };
    fs.rmSync(lockFile, { force: true });
  }

  const id = runId(agent) + '-' + String(Date.now() % 1000).padStart(3, '0');
  const log = path.join(RUNS_DIR, `${id}.log`);
  const errLog = path.join(RUNS_DIR, `${id}.err.log`);
  const exitF = path.join(RUNS_DIR, `${id}.exit`);
  const prompt = `${a.role}\n\nЗадача от главагента: ${task}\n\nКогда закончишь — дай краткий итог: что сделано, что нет и почему.`
    .replace(/\{AGENT_TOKEN\}/g, process.env.AGENT_TOKEN || '')
    .replace(/\{HUB_URL\}/g, `http://127.0.0.1:${process.env.PORT || 8787}`);
  const modelArg = a.model ? `-m "${String(a.model).replace(/"/g, '')}"` : '';
  // Промпт уходит через env-переменную (Unicode, без проблем кодировки cmd);
  // чистим символы, ломающие парсинг cmd после подстановки (включая %VAR%).
  const safe = prompt.replace(/\r?\n/g, ' ').replace(/"/g, "'").replace(/[&|<>^%]/g, ' ');
  const cmdFile = path.join(RUNS_DIR, `${id}.cmd`);
  fs.writeFileSync(cmdFile, [
    '@echo off',
    `"${KIMI}" -p "%JH_PROMPT%" --output-format text ${modelArg} > "${log}" 2> "${errLog}"`,
    `echo %ERRORLEVEL% > "${exitF}"`,
    `del "${lockFile}" >nul 2>&1`,
  ].join('\r\n'), 'ascii');

  // detached/windowsHide ломают вывод kimi (создаётся процесс без консоли) — не использовать!
  const child = spawn('cmd.exe', ['/c', cmdFile], {
    cwd: a.workdir, stdio: 'ignore',
    env: { ...process.env, JH_PROMPT: safe },
  });
  child.unref();
  if (!child.pid) return { ok: false, error: 'не удалось запустить процесс' };
  fs.writeFileSync(lockFile, String(child.pid));
  return { ok: true, runId: id };
}

function prune(RUNS_DIR, olderThanMin = 30) {
  const now = Date.now();
  const { execFileSync } = require('child_process');
  let killed = 0, cleaned = 0;
  for (const f of fs.readdirSync(RUNS_DIR)) {
    const full = path.join(RUNS_DIR, f);
    if (f.endsWith('.lock')) {
      const pid = parseInt(fs.readFileSync(full, 'utf8'), 10);
      let alive = false;
      if (Number.isFinite(pid)) { try { process.kill(pid, 0); alive = true; } catch {} }
      if (!alive) { fs.rmSync(full, { force: true }); cleaned++; }
      continue; // .lock не чистим по возрасту — агент может жить долго
    }
    if (f.endsWith('.cmd') && !fs.existsSync(full.replace(/\.cmd$/, '.exit'))) {
      const ageMin = (now - fs.statSync(full).birthtimeMs) / 60000;
      if (ageMin > olderThanMin) {
        const m = f.match(/^(.*)-\d{8}-\d{6}/);
        const agent = m ? m[1] : f.split('-')[0];
        const lock = path.join(RUNS_DIR, `${agent}.lock`);
        if (fs.existsSync(lock)) {
          const pid = parseInt(fs.readFileSync(lock, 'utf8'), 10);
          if (Number.isFinite(pid) && pid > 0) {
            try { execFileSync('taskkill', ['/PID', String(pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' }); killed++; } catch {}
          }
          fs.rmSync(lock, { force: true });
        }
        fs.writeFileSync(full.replace(/\.cmd$/, '.exit'), '-1');
      }
      continue;
    }
    if (now - fs.statSync(full).mtimeMs > 7 * 24 * 3600 * 1000) { fs.rmSync(full, { force: true }); cleaned++; }
  }
  return { killed, cleaned };
}

module.exports = { dispatch, prune };
