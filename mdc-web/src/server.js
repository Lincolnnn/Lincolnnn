'use strict';
// MDC WEB DU DISPATCH - point d'entrée : site (Express), sessions MySQL, Discord OAuth2, API, temps réel, pont FiveM.
const http = require('http');
const path = require('path');
const crypto = require('crypto');
const express = require('express');
const session = require('express-session');
const MySQLStore = require('express-mysql-session')(session);
const helmet = require('helmet');
const config = require('./config');
const log = require('./logger');

if (config.missing.length) {
    log.error(`configuration incomplète (.env) : ${config.missing.join(', ')}. Voir .env.example et le README.`);
    process.exit(1);
}

const { pool } = require('./db');
const auth = require('./auth');
const api = require('./api');
const fivem = require('./fivem');
const realtime = require('./realtime');

const app = express();
app.disable('x-powered-by');
if (config.trustProxy) app.set('trust proxy', 1);

app.use(helmet({
    contentSecurityPolicy: {
        useDefaults: true,
        directives: {
            'default-src': ["'self'"],
            'script-src': ["'self'"],
            'style-src': ["'self'"],
            'img-src': ["'self'", 'data:', 'https://cdn.discordapp.com'],
            'connect-src': ["'self'"],
            'font-src': ["'self'"],
            'object-src': ["'none'"],
            'frame-ancestors': ["'none'"],
            'form-action': ["'self'", 'https://discord.com'],
            'upgrade-insecure-requests': config.cookieSecure ? [] : null,
        },
    },
    crossOriginEmbedderPolicy: false,
    referrerPolicy: { policy: 'same-origin' },
}));

// Sessions enregistrées dans MySQL (table mdc_web_sessions, créée automatiquement)
const store = new MySQLStore({
    createDatabaseTable: true,
    schema: { tableName: 'mdc_web_sessions' },
    clearExpired: true,
    checkExpirationInterval: 15 * 60 * 1000,
    expiration: config.sessionHours * 3600 * 1000,
}, pool);

const sessionMiddleware = session({
    name: 'mdc.sid',
    secret: config.sessionSecret,
    store,
    resave: false,
    saveUninitialized: false,
    rolling: true,
    cookie: { httpOnly: true, sameSite: 'lax', secure: config.cookieSecure, maxAge: config.sessionHours * 3600 * 1000 },
});

// ---- Pont : événements envoyés par le serveur FiveM (avant les sessions : pas de cookie, clé + IP) ----
const safeEqual = (a, b) => {
    const x = Buffer.from(String(a || ''));
    const y = Buffer.from(String(b || ''));
    return x.length === y.length && crypto.timingSafeEqual(x, y);
};
const clientIp = (req) => String(req.ip || req.socket.remoteAddress || '').replace(/^::ffff:/, '');

app.post('/bridge/events', express.json({ limit: '256kb' }), (req, res) => {
    const ip = clientIp(req);
    if (config.fivem.bridgeIps.length && !config.fivem.bridgeIps.includes(ip)) {
        log.warn(`/bridge/events refusé pour ${ip} (BRIDGE_ALLOWED_IPS)`);
        return res.status(403).json({ ok: false });
    }
    if (!safeEqual(req.get('X-MDC-Key'), config.fivem.apiKey)) return res.status(401).json({ ok: false });
    const events = Array.isArray(req.body && req.body.events) ? req.body.events.slice(0, 300) : [];
    res.json({ ok: true });
    realtime.handleGameEvents(events.filter((e) => e && typeof e.topic === 'string'));
});

app.use(sessionMiddleware);
app.use(express.json({ limit: '32kb' }));

// Limite de requêtes par session (protège l'API et le serveur FiveM)
const hits = new Map();
app.use('/api', (req, res, next) => {
    const key = (req.session && req.session.user && req.session.user.id) || clientIp(req);
    const nowS = Math.floor(Date.now() / 1000);
    const h = hits.get(key) || { s: nowS, n: 0 };
    if (h.s !== nowS) { h.s = nowS; h.n = 0; }
    h.n += 1;
    hits.set(key, h);
    if (h.n > 25) return res.status(429).json({ ok: false, error: 'Trop de requêtes : patientez un instant.' });
    return next();
});
setInterval(() => hits.clear(), 60000).unref();

app.use(auth.router);
app.use('/api', api);

const page = (file) => path.join(__dirname, '..', 'public', file);
app.get('/login', (req, res) => (req.session.user ? res.redirect('/') : res.sendFile(page('login.html'))));
app.get('/denied', (req, res) => res.sendFile(page('denied.html')));
app.get('/', auth.requireDispatcher(false), (req, res) => res.sendFile(page('app.html')));
app.use('/assets', express.static(path.join(__dirname, '..', 'public', 'assets'), { maxAge: '1h', index: false }));
app.get('/healthz', (req, res) => res.json({ ok: true, fivem: fivem.publicStatus().online }));

app.use((req, res) => res.status(404).json({ ok: false, error: 'Introuvable.' }));
app.use((err, req, res, next) => { // eslint-disable-line no-unused-vars
    log.error(`${req.method} ${req.originalUrl} :`, err.message);
    res.status(500).json({ ok: false, error: 'Erreur du serveur Web.' });
});

const server = http.createServer(app);
let heartbeat = null;
realtime.init(server, sessionMiddleware, () => heartbeat && heartbeat.beat());
fivem.setStatusListener((status) => realtime.broadcast('fivem', status));

pool.query('SELECT 1 FROM mdc_calls LIMIT 1').then(() => {
    server.listen(config.port, () => {
        log.info(`MDC Web en ligne : ${config.publicUrl} (port ${config.port})`);
        heartbeat = fivem.startHeartbeat(realtime.dispatchers);
    });
}).catch((e) => {
    log.error(`MySQL injoignable ou tables du MDC absentes (${e.message}). Démarrez d'abord la ressource rp_mdc (elle crée les tables), puis vérifiez MYSQL_* dans .env.`);
    process.exit(1);
});

const stop = () => {
    log.info('arrêt du MDC Web…');
    if (heartbeat) heartbeat.stop();
    server.close(() => pool.end().finally(() => process.exit(0)));
    setTimeout(() => process.exit(0), 5000).unref();
};
process.on('SIGINT', stop);
process.on('SIGTERM', stop);
