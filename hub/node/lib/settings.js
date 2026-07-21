// Хранилище настроек: data/settings.json поверх дефолтов. Всё редактируется из веб-UI.
const fs = require('fs');
const path = require('path');

const DATA_DIR = path.join(__dirname, '..', 'data');
const FILE = path.join(DATA_DIR, 'settings.json');

const DEFAULTS = {
  theme: {
    accent: '#00e5ff', text: '#b8c0cc', ok: '#39ff8e', warn: '#ffd75f',
    bg: '#050b12', panel: '#0a1420', banner: 'J A R V I S   H U B', refreshSec: 5, preset: 'jarvis',
  },
  // пресеты тем — редактируются на вкладке «Тема»
  themes: {
    jarvis:   { accent: '#00e5ff', text: '#b8c0cc', ok: '#39ff8e', warn: '#ffd75f', bg: '#050b12', panel: '#0a1420' },
    terminal: { accent: '#e0e0e0', text: '#c8c8c8', ok: '#7ee787', warn: '#e3b341', bg: '#000000', panel: '#0d0d0d' },
    green:    { accent: '#00ff41', text: '#9fdf9f', ok: '#00ff41', warn: '#e6ff5f', bg: '#020a02', panel: '#041204' },
    cloud:    { accent: '#4a90d9', text: '#33475b', ok: '#2e9e6b', warn: '#d9962e', bg: '#eef4fb', panel: '#ffffff' },
  },
  agents: {
    sysadmin:   { workdir: 'C:\\Users\\UserBempe', model: '', role: 'Ты — агент системного администрирования Windows (диагностика, драйверы, службы, сеть, электропитание). Действуй автономно, отчитывайся кратко и по делу.' },
    coder:      { workdir: 'D:\\Repo', model: '', role: 'Ты — агент-разработчик. Пишешь и правишь код в репозиториях D:\\Repo, запускаешь тесты, не делаешь git push без явной команды.' },
    researcher: { workdir: 'C:\\Users\\UserBempe', model: 'kimi-code/kimi-for-coding-highspeed', role: 'Ты — агент-исследователь. Ищешь информацию в интернете, проверяешь факты, даёшь выжимку с источниками.' },
    jarvis:     { workdir: 'C:\\Users\\UserBempe\\github_publish\\jarvis-assistant', model: '', role: 'Ты — агент голосового ассистента Jarvis (Python). Развиваешь jarvis-assistant: команды, интеграции с Kimi и KAW.' },
    master:     { workdir: 'C:\\Users\\UserBempe', model: '', role: 'Ты — мастерагент Jarvis Hub. Твоя работа: разбить задачу главагента на подзадачи, раздать их агентам (sysadmin, coder, researcher, jarvis) и собрать итог. Поручение: curl -s -X POST -H "Content-Type: application/json" -H "x-agent-token: {AGENT_TOKEN}" -d "{\\"agent\\":\\"ИМЯ\\",\\"task\\":\\"ЗАДАЧА\\"}" {HUB_URL}/api/dispatch — вернёт runId. Статус: curl -s -H "x-agent-token: {AGENT_TOKEN}" {HUB_URL}/api/state. Результат запуска: curl -s -H "x-agent-token: {AGENT_TOKEN}" "{HUB_URL}/api/result?id=RUNID". Не делай работу агентов сам — делегируй, жди завершения (exit в /api/state), суммируй.' },
  },
  commands: {
    'brightness-max': { desc: 'Яркость ноутбука на 100%', run: 'powershell -NoProfile -Command "(Get-WmiObject -Namespace root/wmi -Class WmiMonitorBrightnessMethods).WmiSetBrightness(1,100)"' },
    'kaw-restart':    { desc: 'Перезапуск KAW', run: 'powershell -NoProfile -ExecutionPolicy Bypass -File "{KAW}\\kaw.ps1" restart' },
    'ghelper':        { desc: 'Открыть окно G-Helper', run: 'start "" "C:\\Users\\UserBempe\\Desktop\\GHelper.exe"' },
    'temp-clean':     { desc: 'Очистка %TEMP% старше 7 дней', run: 'powershell -NoProfile -Command "Get-ChildItem $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue | Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-7)} | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue"' },
    'wt-all':         { desc: 'Окна терминалов (hwnd) через KAW', run: 'powershell -NoProfile -ExecutionPolicy Bypass -File "{KAW}\\kaw.ps1" windows' },
  },
  repos: [
    { path: 'C:\\Users\\UserBempe\\kimi-approve-watch', slug: 'bimpiRU/kimi-approve-watch' },
    { path: 'C:\\Users\\UserBempe\\github_publish\\jarvis-assistant', slug: 'bimpiRU/jarvis-assistant' },
    { path: 'C:\\Users\\UserBempe\\github_publish\\project-aegis', slug: '' },
    { path: 'C:\\Users\\UserBempe\\github_publish\\USB_AUDIT', slug: 'bimpiRU/USB_AUDIT' },
  ],
  presets: [
    { name: '🔍 Проверь систему', agent: 'sysadmin', task: 'Быстрая проверка здоровья системы: CPU, RAM, диск, проблемные устройства, перегрев. Краткий отчёт.' },
    { name: '🌐 GitHub обзор', agent: 'researcher', task: 'Проверь репозитории bimpiRU на GitHub: открытые PR, issues, что требует внимания. Кратко.' },
    { name: '🧹 Чистка ПК', agent: 'sysadmin', task: 'Очисти временные файлы (%TEMP% старше 7 дней), проверь свободное место, отчёт.' },
  ],
};

// атомарная запись (tmp + rename) — падение посреди write не убивает settings.json
function writeAtomic(file, data) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  const tmp = `${file}.tmp`;
  fs.writeFileSync(tmp, data, 'utf8');
  fs.renameSync(tmp, file);
}

function load() {
  let stored = {};
  try { stored = JSON.parse(fs.readFileSync(FILE, 'utf8')); } catch {}
  // агенты: stored имеет приоритет; master гарантирован, пока его не удалили осознанно
  const deleted = Array.isArray(stored.agentsDeleted) ? stored.agentsDeleted : [];
  let agents = stored.agents && typeof stored.agents === 'object' && !Array.isArray(stored.agents) ? stored.agents : DEFAULTS.agents;
  if (!agents.master && !deleted.includes('master')) agents = { ...agents, master: DEFAULTS.agents.master };
  return {
    theme: { ...DEFAULTS.theme, ...(stored.theme || {}) },
    themes: { ...DEFAULTS.themes, ...(stored.themes || {}) },
    agents,
    agentsDeleted: deleted,
    commands: stored.commands || DEFAULTS.commands,
    repos: stored.repos || DEFAULTS.repos,
    presets: stored.presets || DEFAULTS.presets,
  };
}

function save(settings) {
  writeAtomic(FILE, JSON.stringify(settings, null, 2));
}

module.exports = { load, save, DEFAULTS };
