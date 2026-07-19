// Аутентификация: OAuth GitHub + Google, сессии по cookie, allowlist.
// Если клиентские ключи не заданы — «открытый локальный режим» (без входа).
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const DATA_DIR = path.join(__dirname, '..', 'data');
const SESSIONS_FILE = path.join(DATA_DIR, 'sessions.json');
const SESSION_TTL = 7 * 24 * 3600 * 1000;

const PROVIDERS = {
  github: {
    authUrl: 'https://github.com/login/oauth/authorize',
    tokenUrl: 'https://github.com/login/oauth/access_token',
    userUrl: 'https://api.github.com/user',
    scope: 'read:user',
    id: () => process.env.GITHUB_CLIENT_ID || '',
    secret: () => process.env.GITHUB_CLIENT_SECRET || '',
    login: u => u.login,
  },
  google: {
    authUrl: 'https://accounts.google.com/o/oauth2/v2/auth',
    tokenUrl: 'https://oauth2.googleapis.com/token',
    userUrl: 'https://www.googleapis.com/oauth2/v3/userinfo',
    scope: 'openid email profile',
    id: () => process.env.GOOGLE_CLIENT_ID || '',
    secret: () => process.env.GOOGLE_CLIENT_SECRET || '',
    login: u => u.email,
  },
};

const allowlist = () =>
  (process.env.AUTH_ALLOW || 'bimpiRU').split(',').map(s => s.trim().toLowerCase()).filter(Boolean);

const configured = p => !!(PROVIDERS[p].id() && PROVIDERS[p].secret());
const pinEnabled = () => !!process.env.AUTH_PIN;
const anyConfigured = () => Object.keys(PROVIDERS).some(configured) || pinEnabled();

// --- сессии ---
let sessions = new Map();
try { sessions = new Map(JSON.parse(fs.readFileSync(SESSIONS_FILE, 'utf8'))); } catch {}
const pendingStates = new Map(); // oauth state -> provider

function persist() {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  fs.writeFileSync(SESSIONS_FILE, JSON.stringify([...sessions]), 'utf8');
}

function createSession(user, provider) {
  const token = crypto.randomBytes(32).toString('hex');
  sessions.set(token, { user, provider, created: Date.now() });
  persist();
  return token;
}

function getSession(req) {
  const cookie = req.headers.cookie || '';
  const m = cookie.match(/(?:^|;\s*)jh_session=([0-9a-f]+)/);
  if (!m) return null;
  const s = sessions.get(m[1]);
  if (!s) return null;
  if (Date.now() - s.created > SESSION_TTL) { sessions.delete(m[1]); persist(); return null; }
  return s;
}

function destroySession(req) {
  const m = (req.headers.cookie || '').match(/(?:^|;\s*)jh_session=([0-9a-f]+)/);
  if (m) { sessions.delete(m[1]); persist(); }
}

// --- OAuth flow ---
function startAuth(provider, baseUrl) {
  const p = PROVIDERS[provider];
  const state = crypto.randomBytes(16).toString('hex');
  pendingStates.set(state, provider);
  setTimeout(() => pendingStates.delete(state), 10 * 60 * 1000).unref?.();
  const url = new URL(p.authUrl);
  url.searchParams.set('client_id', p.id());
  url.searchParams.set('redirect_uri', `${baseUrl}/auth/${provider}/callback`);
  url.searchParams.set('scope', p.scope);
  url.searchParams.set('state', state);
  if (provider === 'google') url.searchParams.set('response_type', 'code');
  return url.toString();
}

async function finishAuth(provider, query, baseUrl) {
  const p = PROVIDERS[provider];
  if (!query.state || pendingStates.get(query.state) !== provider) throw new Error('bad state');
  pendingStates.delete(query.state);
  if (!query.code) throw new Error('no code');

  const redirect_uri = `${baseUrl}/auth/${provider}/callback`;
  const tokenResp = await fetch(p.tokenUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify({
      client_id: p.id(), client_secret: p.secret(), code: query.code,
      redirect_uri, ...(provider === 'google' ? { grant_type: 'authorization_code' } : {}),
    }),
  });
  const tokenData = await tokenResp.json();
  if (!tokenData.access_token) throw new Error('no access_token');

  const userResp = await fetch(p.userUrl, { headers: { Authorization: `Bearer ${tokenData.access_token}`, 'User-Agent': 'jarvis-hub' } });
  const user = await userResp.json();
  const login = (p.login(user) || '').toLowerCase();
  if (!login) throw new Error('no login');
  if (!allowlist().includes(login)) throw new Error(`user not allowed: ${login}`);
  return login;
}

module.exports = { configured, anyConfigured, pinEnabled, providers: () => Object.keys(PROVIDERS).filter(configured), startAuth, finishAuth, createSession, getSession, destroySession };
