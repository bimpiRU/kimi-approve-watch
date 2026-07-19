// Хранилище настроек: data/settings.json поверх дефолтов. Всё редактируется из веб-UI.
const fs = require('fs');
const path = require('path');

const DATA_DIR = path.join(__dirname, '..', 'data');
const FILE = path.join(DATA_DIR, 'settings.json');

const DEFAULTS = {
  theme: {
    accent: '#00e5ff', text: '#b8c0cc', ok: '#39ff8e', warn: '#ffd75f',
    bg: '#050b12', panel: '#0a1420', banner: 'J A R V I S   H U B', refreshSec: 5,
  },
  agents: {
    sysadmin:   { workdir: 'C:\\Users\\UserBempe', model: '', role: 'Ты — агент системного администрирования Windows (диагностика, драйверы, службы, сеть, электропитание). Действуй автономно, отчитывайся кратко и по делу.' },
    coder:      { workdir: 'D:\\Repo', model: '', role: 'Ты — агент-разработчик. Пишешь и правишь код в репозиториях D:\\Repo, запускаешь тесты, не делаешь git push без явной команды.' },
    researcher: { workdir: 'C:\\Users\\UserBempe', model: 'kimi-code/kimi-for-coding-highspeed', role: 'Ты — агент-исследователь. Ищешь информацию в интернете, проверяешь факты, даёшь выжимку с источниками.' },
    jarvis:     { workdir: 'C:\\Users\\UserBempe\\github_publish\\jarvis-assistant', model: '', role: 'Ты — агент голосового ассистента Jarvis (Python). Развиваешь jarvis-assistant: команды, интеграции с Kimi и KAW.' },
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

function load() {
  let stored = {};
  try { stored = JSON.parse(fs.readFileSync(FILE, 'utf8')); } catch {}
  return {
    theme: { ...DEFAULTS.theme, ...(stored.theme || {}) },
    agents: stored.agents || DEFAULTS.agents,
    commands: stored.commands || DEFAULTS.commands,
    repos: stored.repos || DEFAULTS.repos,
    presets: stored.presets || DEFAULTS.presets,
  };
}

function save(settings) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  fs.writeFileSync(FILE, JSON.stringify(settings, null, 2), 'utf8');
}

module.exports = { load, save, DEFAULTS };
