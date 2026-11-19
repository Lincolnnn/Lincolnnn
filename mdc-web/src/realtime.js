'use strict';
// Temps réel (Socket.IO) : seuls les dispatchers authentifiés (session + rôle Discord) reçoivent les événements.
// Le navigateur ne fait rien passer par le socket : toutes les actions passent par l'API REST (CSRF, contrôle du rôle).
const { Server } = require('socket.io');
const config = require('./config');
const queries = require('./queries');
const { verifyRole } = require('./auth');
const fivem = require('./fivem');
const liveview = require('./liveview');
const log = require('./logger');

let io = null;
const presence = new Map(); // id Discord -> { id, name, avatar, sockets }
// Données du jeu gardées en mémoire (jamais écrites dans MySQL : envoyées par le serveur FiveM quand elles changent)
const cache = { positions: new Map(), coords: new Map(), players: [], liveview: false };
// Postes en train de modifier une intervention (verrou doux) : id de l'appel -> Map(socket -> n° de poste)
const editors = new Map();
let stationSeq = 0;

function editing() {
    const out = {};
    for (const [callId, m] of editors) if (m.size) out[callId] = [...m.values()];
    return out;
}

async function refreshPlayers() {
    const res = await fivem.call('players', {});
    if (res && res.ok && Array.isArray(res.players)) {
        cache.players = res.players.map((p) => ({ serverId: Number(p.serverId), name: String(p.name || ''), agency: p.agency || '',
            unitId: p.unitId ? Number(p.unitId) : null, unitName: p.unitName || null, civKey: p.civKey || null }));
        cache.liveview = res.liveview === true;
        broadcast('players', { players: cache.players, liveview: cache.liveview });
        liveview.dropPlayers(cache.players.map((p) => p.serverId));
    }
}

async function refreshPositions() {
    const res = await fivem.call('positions', {});
    if (res && res.ok && Array.isArray(res.positions)) {
        cache.positions.clear();
        cache.coords.clear();
        for (const p of res.positions) {
            if (p.location) cache.positions.set(Number(p.unitId), p.location);
            const c = cleanCoords(p.coords);
            if (c) cache.coords.set(c.unitId, c);
        }
        broadcast('positions', Object.fromEntries(cache.positions));
        broadcast('coords', [...cache.coords.values()]);
    }
}

/** LiveMAP : position exacte d'une unité (envoyée par le serveur FiveM), nombres vérifiés */
function cleanCoords(c) {
    if (!c || typeof c !== 'object') return null;
    const n = (v) => (Number.isFinite(Number(v)) ? Number(v) : null);
    const unitId = n(c.unitId); const x = n(c.x); const y = n(c.y);
    if (!unitId || x === null || y === null || Math.abs(x) > 20000 || Math.abs(y) > 20000) return null;
    return { unitId, x, y, h: n(c.h) || 0, s: n(c.s) || 0, v: c.v === true, at: n(c.at) || Math.floor(Date.now() / 1000) };
}

function dispatchers() {
    return [...presence.values()].map((p) => ({ id: p.id, name: 'Dispatch' }));
}

function init(httpServer, sessionMiddleware, onPresenceChange) {
    // origines : la console (même site) et le NUI du MDC en jeu (espace « /live » du LiveView, jeton de diffusion)
    io = new Server(httpServer, { serveClient: true, cors: { origin: [config.publicUrl, ...config.live.origins], credentials: true },
        maxHttpBufferSize: 64 * 1024 });
    io.engine.use(sessionMiddleware);
    liveview.attach(io);

    io.use(async (socket, next) => {
        const session = socket.request.session;
        const check = await verifyRole(session, config.discord.roleRecheck);
        if (!check.ok) return next(new Error('unauthorized'));
        session.save(() => next());
    });

    io.on('connection', (socket) => {
        const u = socket.request.session.user;
        socket.data.userId = u.id;
        stationSeq += 1;
        socket.data.station = `Poste ${stationSeq}`;
        socket.join('dispatch');
        socket.emit('station', socket.data.station);
        const p = presence.get(u.id) || { id: u.id, name: 'Dispatch', sockets: 0 };
        p.sockets += 1;
        presence.set(u.id, p);
        if (p.sockets === 1) {
            log.info(`dispatcher en ligne : ${u.name}`);
            onPresenceChange();
        }
        broadcast('presence', dispatchers());

        // Verrou doux : « Poste N modifie cette intervention » chez les autres postes (rien n'est bloqué)
        socket.on('edit:start', (callId) => {
            const cid = Number(callId);
            if (!Number.isInteger(cid) || cid <= 0) return;
            for (const m of editors.values()) m.delete(socket.id);
            if (!editors.has(cid)) editors.set(cid, new Map());
            editors.get(cid).set(socket.id, socket.data.station);
            broadcast('editing', editing());
        });
        socket.on('edit:stop', () => {
            for (const m of editors.values()) m.delete(socket.id);
            broadcast('editing', editing());
        });

        // LiveView : joueurs regardés par ce poste, puis signalisation WebRTC (réponse, candidats ICE) vers le joueur
        let liveBudget = { at: Date.now(), n: 0 };
        socket.on('live:signal', (msg) => {
            const now = Date.now();
            if (now - liveBudget.at > 1000) liveBudget = { at: now, n: 0 };
            if ((liveBudget.n += 1) > 200) return;
            liveview.fromViewer(socket, msg);
        });
        socket.on('live:watch', (list, ack) => {
            liveview.setWatch(socket, list, cache.players)
                .then((r) => { if (typeof ack === 'function') ack(r); })
                .catch((e) => { log.warn('LiveView :', e.message); if (typeof ack === 'function') ack({ ok: false, refused: [] }); });
        });

        socket.on('disconnect', () => {
            let wasEditing = false;
            for (const m of editors.values()) if (m.delete(socket.id)) wasEditing = true;
            if (wasEditing) broadcast('editing', editing());
            liveview.dropSocket(socket);
            const cur = presence.get(u.id);
            if (!cur) return;
            cur.sockets -= 1;
            if (cur.sockets <= 0) {
                presence.delete(u.id);
                log.info(`dispatcher hors ligne : ${u.name}`);
                onPresenceChange();
            }
            broadcast('presence', dispatchers());
        });
    });

    // Revérification périodique : session expirée ou rôle retiré -> déconnecté tout de suite
    setInterval(async () => {
        for (const socket of await io.in('dispatch').fetchSockets()) {
            const s = io.sockets.sockets.get(socket.id);
            if (!s) continue;
            const session = s.request.session;
            await new Promise((resolve) => session.reload(() => resolve()));
            const check = await verifyRole(session, config.discord.roleRecheck);
            if (!check.ok || !session.user || session.user.id !== s.data.userId) {
                s.emit('revoked', { reason: check.reason || 'session' });
                s.disconnect(true);
            } else {
                session.save(() => {});
            }
        }
    }, 60000).unref();
}

function broadcast(event, data) {
    if (io) io.to('dispatch').emit(event, data);
}

// ---- Événements du jeu (POST /bridge/events) -> relecture MySQL -> dispatchers ----
const ALERTS = {
    'call:awaiting': 'awaiting',
    'call:new': 'new',
    'call:validated': 'validated',
    'call:refused': 'refused',
    'call:closed': 'closed',
};

async function handleGameEvents(events) {
    const topics = new Set(events.map((e) => e.topic));
    try {
        if (topics.has('calls') || [...topics].some((t) => t.startsWith('call:'))) broadcast('calls', await queries.activeCalls());
        // une intervention qui change (clôture, affectation…) change aussi l'appel en cours des unités
        if (topics.has('units') || topics.has('calls') || [...topics].some((t) => t.startsWith('call:'))) broadcast('units', await queries.units());
        if (topics.has('players') || topics.has('units')) await refreshPlayers();
        for (const e of events) {
            if (e.topic === 'position' && e.data && e.data.unitId) {
                cache.positions.set(Number(e.data.unitId), e.data.location);
                broadcast('position', { unitId: Number(e.data.unitId), location: e.data.location });
            }
            if (e.topic === 'coords' && e.data && Array.isArray(e.data.list)) {
                const list = e.data.list.map(cleanCoords).filter(Boolean);
                for (const c of list) cache.coords.set(c.unitId, c);
                if (list.length) broadcast('coords', list);
            }
            if (e.topic === 'call:edited' && e.data) broadcast('call:edited', e.data);
            if (e.topic === 'records') broadcast('records', {});   // registres modifiés (jeu ou site)
            if (e.topic === 'serviceNote' && e.data) broadcast('serviceNote', e.data);
            if (e.topic === 'dispatch' && e.data) broadcast('dispatch', e.data);
            if (ALERTS[e.topic] && e.data) broadcast('alert', { type: ALERTS[e.topic], ...e.data });
            if (e.topic === 'message' && e.data && e.data.id) {
                const m = await queries.messageById(Number(e.data.id));
                if (m) broadcast('message', m);
            }
        }
        if (topics.has('message') || topics.has('reads') || topics.has('units') || topics.has('calls') || topics.has('players')) {
            broadcast('conversations', await queries.conversations(cache.players));
        }
    } catch (e) {
        log.error('relecture MySQL après un événement du jeu :', e.message);
    }
}

/** Serveur FiveM de nouveau joignable (ou démarrage) : joueurs et positions relus */
async function resync() {
    await refreshPlayers();
    await refreshPositions();
}

module.exports = { init, broadcast, dispatchers, handleGameEvents, resync, editing,
    positions: () => Object.fromEntries(cache.positions), coords: () => Object.fromEntries(cache.coords), players: () => cache.players, liveviewAvailable: () => cache.liveview };
