// Сбор состояния: KAW, система, G-Helper, запуски, репозитории (кэш 30 с).
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const HUB_DIR = path.join(__dirname, '..', '..');
const KAW_DIR = path.join(HUB_DIR, '..');
const RUNS_DIR = path.join(HUB_DIR, 'runs');

const alive = pid => { try { process.kill(pid, 0); return true; } catch { return false; } };

function svcState(name) {
  try {
    const pid = parseInt(fs.readFileSync(path.join(KAW_DIR, `${name}.pid`), 'utf8'), 10);
    if (pid && alive(pid)) return `ON (PID ${pid})`;
  } catch {}
  return '';
}

// CPU: дельта между вызовами (loadavg на Windows бесполезен)
let prevCpus = null;
function cpuPercent() {
  const cpus = os.cpus();
  if (!prevCpus) { prevCpus = cpus; return null; }
  let idle = 0, total = 0;
  for (let i = 0; i < cpus.length; i++) {
    const a = prevCpus[i].times, b = cpus[i].times;
    idle += b.idle - a.idle;
    total += (b.user + b.nice + b.sys + b.irq + b.idle) - (a.user + a.nice + a.sys + a.irq + a.idle);
  }
  prevCpus = cpus;
  return total > 0 ? Math.round(100 * (1 - idle / total)) : null;
}

function diskFreeGB() {
  try {
    const st = fs.statfsSync('C:\\');
    return Math.round((st.bavail * st.bsize) / 2 ** 30 * 10) / 10;
  } catch { return null; }
}

function ghelperState() {
  const out = { gpu: 'n/a', gpuAuto: '', perf: '', perfAC: '', perfBatt: '' };
  try {
    const gh = JSON.parse(fs.readFileSync(path.join(process.env.APPDATA, 'GHelper', 'config.json'), 'utf8'));
    const gpuModes = { 0: 'Eco', 1: 'Standard', 2: 'Ultimate' };
    const perfModes = { 0: 'Turbo', 1: 'Balanced', 2: 'Silent' };
    out.gpu = gpuModes[gh.gpu_mode] || 'n/a';
    out.gpuAuto = gh.gpu_auto;
    out.perf = perfModes[gh.performance_mode] || '';
    out.perfAC = perfModes[gh.performance_1] || '';
    out.perfBatt = perfModes[gh.performance_0] || '';
  } catch {}
  return out;
}

function runStates() {
  const runs = [];
  try {
    const files = fs.readdirSync(RUNS_DIR).filter(f => f.endsWith('.cmd'))
      .map(f => ({ f, t: fs.statSync(path.join(RUNS_DIR, f)).birthtime }))
      .sort((a, b) => b.t - a.t).slice(0, 10);
    for (const { f, t } of files) {
      const id = f.replace(/\.cmd$/, '');
      let exit = '...';
      try { exit = fs.readFileSync(path.join(RUNS_DIR, `${id}.exit`), 'utf8').trim(); } catch {}
      const dd = String(t.getDate()).padStart(2, '0'), mm = String(t.getMonth() + 1).padStart(2, '0');
      const hh = String(t.getHours()).padStart(2, '0'), mi = String(t.getMinutes()).padStart(2, '0');
      runs.push({ id, exit, started: `${dd}.${mm} ${hh}:${mi}` });
    }
  } catch {}
  return runs;
}

let reposCache = null, reposCacheAt = 0;
function repoStates(repos) {
  if (reposCache && Date.now() - reposCacheAt < 30000) return reposCache;
  const git = (cwd, args) => { try { return execFileSync('git', ['-C', cwd, ...args], { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }).trim(); } catch { return ''; } };
  reposCache = repos.filter(r => { try { return fs.existsSync(path.join(r.path, '.git')); } catch { return false; } })
    .map(r => {
      const branch = git(r.path, ['branch', '--show-current']);
      const dirty = git(r.path, ['status', '--porcelain']).split('\n').filter(Boolean).length;
      const sb = git(r.path, ['status', '-sb']).split('\n')[0] || '';
      const m = sb.match(/\[(.*)\]/);
      return { repo: path.basename(r.path), slug: r.slug || '', branch, dirty, sync: m ? ` [${m[1]}]` : '' };
    });
  reposCacheAt = Date.now();
  return reposCache;
}

function agentStates(agents) {
  return Object.entries(agents).map(([name, a]) => ({
    name, model: a.model || 'default',
    busy: (() => { try { return fs.existsSync(path.join(RUNS_DIR, `${name}.lock`)); } catch { return false; } })(),
  }));
}

function fmtTime(d = new Date()) {
  const p = n => String(n).padStart(2, '0');
  return `${p(d.getDate())}.${p(d.getMonth() + 1)}.${d.getFullYear()} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}

function getState(settings) {
  const cpu = cpuPercent();
  return {
    time: fmtTime(),
    theme: settings.theme,
    kaw: { watcher: svcState('watcher'), stabilizer: svcState('stabilizer') },
    system: {
      cpu: cpu === null ? '…' : cpu,
      ramFree: Math.round(os.freemem() / 2 ** 30 * 10) / 10,
      ramTotal: Math.round(os.totalmem() / 2 ** 30 * 10) / 10,
      diskFree: diskFreeGB(),
      ...ghelperState(),
    },
    agents: agentStates(settings.agents),
    runs: runStates(),
    repos: repoStates(settings.repos),
    commands: Object.entries(settings.commands).map(([name, c]) => ({ name, desc: c.desc })),
  };
}

module.exports = { getState, HUB_DIR, KAW_DIR, RUNS_DIR };
