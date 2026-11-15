'use strict';
// LIVEVIEW : écran des joueurs connectés, en direct, pour les dispatchers.
// Technique : captures compressées (JPEG) plutôt que WebRTC — pas de serveur TURN/STUN, pas de négociation, débit
// prévisible et plafonné, aucune charge sur le serveur FiveM :
//   1. un dispatcher regarde des joueurs (Socket.IO « live:watch ») ;
//   2. le site crée un jeton aléatoire par joueur regardé et demande au serveur FiveM (API « live.start ») de dire au
//      joueur de capturer son écran : image du JEU uniquement (screenshot-basic), réduite dans le NUI à 480 x 270
//      (mosaïque, 1 image / 2 s) ou 960 x 540 (agrandie, 2 images / s), JPEG ;
//   3. le jeu envoie chaque image DIRECTEMENT au site (POST /live/frame + jeton), le site la relaie aux seuls
//      dispatchers qui regardent ce joueur ;
//   4. plus personne ne regarde : « live.stop » ; sans renouvellement (toutes les 8 s), le jeu s'arrête seul (25 s).
// Limites : LIVE_MAX_STREAMS joueurs à la fois, 700 Ko par image, 1 image / 150 ms au plus par joueur.
// Chaque consultation est enregistrée dans le journal (mdc_action_log : live.view).
const crypto = require('crypto');
const config = require('./config');
const fivem = require('./fivem');
const { logAction } = require('./db');
const log = require('./logger');

const targets = new Map(); // serverId -> { token, viewers: Map(socketId -> mode), mode, sentMode, lastStart, lastFrame }
const tokens = new Map();  // jeton -> serverId
let io = null;
let timer = null;

const room = (serverId) => `live:${serverId}`;

function wantedMode(t) {
    for (const mode of t.viewers.values()) if (mode === 'focus') return 'focus';
    return 'grid';
}

/** Envoie au jeu les ordres en attente (nouveaux joueurs, changement de mode, renouvellement) et les arrêts */
async function sync(force = false) {
    const start = [];
    const stop = [];
    const now = Date.now();
    for (const [serverId, t] of targets) {
        if (t.viewers.size === 0) {
            targets.delete(serverId);
            tokens.delete(t.token);
            stop.push(serverId);
            continue;
        }
        t.mode = wantedMode(t);
        if (force || t.sentMode !== t.mode || now - t.lastStart > 8000) {
            start.push({ serverId, token: t.token, mode: t.mode });
            t.sentMode = t.mode;
            t.lastStart = now;
        }
    }
    if (stop.length) await fivem.call('live.stop', { serverIds: stop });
    if (start.length) {
        const res = await fivem.call('live.start', { targets: start, url: config.live.uploadUrl });
        if (!res || res.ok !== true) {
            for (const s of start) {
                const t = targets.get(s.serverId);
                if (t) { t.sentMode = null; t.error = (res && res.error) || 'Serveur FiveM injoignable.'; }
            }
            if (io) io.to('dispatch').emit('live:error', { error: (res && res.error) || 'LiveView indisponible.' });
        } else {
            for (const s of start) { const t = targets.get(s.serverId); if (t) t.error = null; }
        }
    }
    if (targets.size === 0 && timer) { clearInterval(timer); timer = null; }
    if (targets.size > 0 && !timer) timer = setInterval(() => sync().catch(() => {}), 8000);
}

/**
 * Joueurs regardés par un dispatcher (remplace sa liste) : [{ serverId, mode: 'grid' | 'focus' }].
 * Retourne { ok, refused: [serverId] } (limite de flux atteinte).
 */
function setWatch(socket, list, players) {
    const wanted = new Map();
    for (const item of Array.isArray(list) ? list.slice(0, 64) : []) {
        const id = Number(item && item.serverId);
        if (Number.isInteger(id) && id > 0 && id < 65536) wanted.set(id, item.mode === 'focus' ? 'focus' : 'grid');
    }
    const refused = [];
    // arrêts : joueurs que ce dispatcher ne regarde plus
    for (const [serverId, t] of targets) {
        if (t.viewers.has(socket.id) && !wanted.has(serverId)) {
            t.viewers.delete(socket.id);
            socket.leave(room(serverId));
        }
    }
    for (const [serverId, mode] of wanted) {
        let t = targets.get(serverId);
        if (!t) {
            if (targets.size >= config.live.maxStreams) { refused.push(serverId); continue; }
            const token = crypto.randomBytes(24).toString('hex');
            t = { token, viewers: new Map(), mode, sentMode: null, lastStart: 0, lastFrame: 0, error: null };
            targets.set(serverId, t);
            tokens.set(token, serverId);
        }
        if (!t.viewers.has(socket.id)) {
            socket.join(room(serverId));
            const p = (players || []).find((x) => x.serverId === serverId);
            logAction('web', `discord:${socket.data.userId}`, 'Dispatch', 'live.view',
                { serverId, name: p ? p.name : `Joueur ${serverId}` }).catch(() => {});
        }
        t.viewers.set(socket.id, mode);
    }
    sync().catch((e) => log.warn('LiveView :', e.message));
    return { ok: true, refused };
}

function dropSocket(socket) {
    let changed = false;
    for (const t of targets.values()) if (t.viewers.delete(socket.id)) changed = true;
    if (changed) sync().catch(() => {});
}

/** Joueur parti : ses flux s'arrêtent */
function dropPlayers(onlineIds) {
    const online = new Set(onlineIds);
    let changed = false;
    for (const [serverId, t] of targets) {
        if (!online.has(serverId)) {
            t.viewers.clear();
            changed = true;
            if (io) io.to(room(serverId)).emit('live:gone', { serverId });
        }
    }
    if (changed) sync().catch(() => {});
}

// ---- Réception des images (POST /live/frame), envoyées par le NUI du MDC en jeu (origine https://cfx-nui-rp_mdc) ----
function cors(req, res, next) {
    const origin = String(req.get('Origin') || '');
    if (config.live.origins.some((o) => origin === o || (o.endsWith('*') && origin.startsWith(o.slice(0, -1))))) {
        res.set('Access-Control-Allow-Origin', origin);
        res.set('Vary', 'Origin');
        res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
        res.set('Access-Control-Allow-Headers', 'Content-Type, X-Live-Token, X-Live-Ms, X-Live-Size');
        res.set('Access-Control-Max-Age', '600');
    }
    if (req.method === 'OPTIONS') return res.status(204).end();
    return next();
}

function receiveFrame(req, res) {
    const serverId = tokens.get(String(req.get('X-Live-Token') || ''));
    const t = serverId && targets.get(serverId);
    if (!t) return res.status(410).json({ ok: false }); // jeton inconnu ou expiré : le jeu s'arrêtera seul
    const body = req.body;
    if (!Buffer.isBuffer(body) || body.length < 100 || body[0] !== 0xff || body[1] !== 0xd8) return res.status(400).json({ ok: false });
    const now = Date.now();
    if (now - t.lastFrame < 150) return res.status(429).json({ ok: false });
    t.lastFrame = now;
    const size = /^\d{2,4}x\d{2,4}$/.test(String(req.get('X-Live-Size') || '')) ? req.get('X-Live-Size') : '';
    const uploadMs = Math.max(0, Math.min(60000, Number(req.get('X-Live-Ms')) || 0));
    if (io) io.to(room(serverId)).emit('live:frame', { serverId, at: now, bytes: body.length, size, uploadMs, mode: t.mode, data: body });
    return res.json({ ok: true });
}

function status() {
    return [...targets.entries()].map(([serverId, t]) => ({ serverId, viewers: t.viewers.size, mode: t.mode, error: t.error }));
}

module.exports = { setIo: (x) => { io = x; }, setWatch, dropSocket, dropPlayers, cors, receiveFrame, status };
