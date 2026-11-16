'use strict';
// LIVEVIEW : écran des joueurs connectés, en direct, pour les dispatchers.
//
// Voie principale — vidéo WebRTC par serveur relais (SFU LiveKit, TURN intégré), si LIVEKIT_* est configuré :
//   1. un dispatcher regarde des joueurs (Socket.IO « live:watch ») : le site vérifie sa session (rôle Discord),
//      enregistre la consultation (mdc_action_log : live.view) et lui signe un jeton LECTEUR par joueur
//      (salle « mdc-live-<id joueur> », abonnement seul, participant caché, valable 2 min pour entrer) ;
//   2. le site demande au serveur FiveM (API « live.start ») de dire au joueur de diffuser, avec un jeton ÉMETTEUR
//      (publication seule, dans SA salle) : le NUI du MDC dessine les captures screenshot-basic (image du JEU
//      uniquement) dans un canevas et publie ce canevas en vidéo (~2 images / s, résolution et débit plafonnés) ;
//   3. le relais ne transmet la vidéo qu'aux dispatchers abonnés ; plus personne ne regarde : « live.stop », la
//      salle est fermée par l'API du relais (tout le monde en est retiré) ; un dispatcher qui arrête de regarder
//      ou perd son rôle est retiré de la salle côté serveur (pas seulement dans son navigateur).
// Repli — captures JPEG relayées par le site (sans relais configuré, ou si le NUI ne peut pas publier) :
//   le jeu envoie chaque image au site (POST /live/frame + jeton aléatoire), relayée aux seuls dispatchers abonnés.
// Sans renouvellement (toutes les 8 s), le jeu s'arrête seul (25 s). LIVE_MAX_STREAMS joueurs à la fois.
const crypto = require('crypto');
const config = require('./config');
const fivem = require('./fivem');
const { logAction } = require('./db');
const log = require('./logger');

const rtc = config.live.rtc;
let sdk = null;
let roomService = null;
if (rtc.enabled) {
    sdk = require('livekit-server-sdk');
    roomService = new sdk.RoomServiceClient(rtc.apiUrl, rtc.apiKey, rtc.apiSecret);
}

const targets = new Map(); // serverId -> { token, viewers: Map(socketId -> { mode, identity }), mode, sentMode, lastStart, lastFrame }
const tokens = new Map();  // jeton (repli JPEG) -> serverId
let io = null;
let timer = null;

const room = (serverId) => `live:${serverId}`;
const rtcRoom = (serverId) => `${rtc.roomPrefix}${serverId}`;
// mode du joueur : débit et taille de l'image (agrandi = un dispatcher l'affiche en grand)
const RTC_MODES = {
    grid: { w: 640, h: 360, fps: 2, kbps: Math.round(rtc.maxKbps / 2) },
    focus: { w: 1280, h: 720, fps: 2, kbps: rtc.maxKbps },
};

async function signToken(identity, name, grant, ttl) {
    const at = new sdk.AccessToken(rtc.apiKey, rtc.apiSecret, { identity, name, ttl });
    at.addGrant({ roomJoin: true, canPublishData: false, ...grant });
    return at.toJwt();
}
const viewerToken = (serverId, identity) => signToken(identity, 'Dispatch', { room: rtcRoom(serverId), canSubscribe: true, canPublish: false, hidden: true }, '2m');
const publisherToken = (serverId) => signToken(`player-${serverId}`, `Joueur ${serverId}`, { room: rtcRoom(serverId), canSubscribe: false, canPublish: true }, '15m');

function kick(serverId, identity) { if (roomService) roomService.removeParticipant(rtcRoom(serverId), identity).catch(() => {}); }
function closeRoom(serverId) { if (roomService) roomService.deleteRoom(rtcRoom(serverId)).catch(() => {}); }

function wantedMode(t) {
    for (const v of t.viewers.values()) if (v.mode === 'focus') return 'focus';
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
            closeRoom(serverId);
            continue;
        }
        t.mode = wantedMode(t);
        if (force || t.sentMode !== t.mode || now - t.lastStart > 8000) {
            const item = { serverId, token: t.token, mode: t.mode };
            if (rtc.enabled) item.rtc = { url: rtc.url, token: await publisherToken(serverId), ...RTC_MODES[t.mode] };
            start.push(item);
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
 * Retourne { ok, refused: [serverId], rtc: { url, tokens: { serverId: jeton lecteur } } | null }.
 */
async function setWatch(socket, list, players) {
    const wanted = new Map();
    for (const item of Array.isArray(list) ? list.slice(0, 64) : []) {
        const id = Number(item && item.serverId);
        if (Number.isInteger(id) && id > 0 && id < 65536) wanted.set(id, item.mode === 'focus' ? 'focus' : 'grid');
    }
    const refused = [];
    const identity = `dispatch-${socket.data.userId}-${socket.id.slice(0, 8)}`;
    // arrêts : joueurs que ce dispatcher ne regarde plus (retiré de la salle côté relais)
    for (const [serverId, t] of targets) {
        if (t.viewers.has(socket.id) && !wanted.has(serverId)) {
            t.viewers.delete(socket.id);
            socket.leave(room(serverId));
            kick(serverId, identity);
        }
    }
    const granted = [];
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
                { serverId, name: p ? p.name : `Joueur ${serverId}`, via: rtc.enabled ? 'webrtc' : 'images' }).catch(() => {});
        }
        t.viewers.set(socket.id, { mode, identity });
        granted.push(serverId);
    }
    sync().catch((e) => log.warn('LiveView :', e.message));
    let rtcInfo = null;
    if (rtc.enabled && granted.length) {
        const signed = await Promise.all(granted.map((id) => viewerToken(id, identity)));
        rtcInfo = { url: rtc.url, tokens: Object.fromEntries(granted.map((id, i) => [id, signed[i]])) };
    }
    return { ok: true, refused, rtc: rtcInfo };
}

function dropSocket(socket) {
    let changed = false;
    for (const [serverId, t] of targets) {
        const v = t.viewers.get(socket.id);
        if (v) { t.viewers.delete(socket.id); kick(serverId, v.identity); changed = true; }
    }
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

// ---- Repli : réception des images (POST /live/frame), envoyées par le NUI du MDC (origine https://cfx-nui-rp_mdc) ----
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

module.exports = { setIo: (x) => { io = x; }, setWatch, dropSocket, dropPlayers, cors, receiveFrame, status, RTC_MODES };
