'use strict';
// =====================================================================================================================
// LIVEVIEW — vidéo WebRTC de l'écran des joueurs, pour les dispatchers (écrit de zéro, sans relais externe).
//
//   Navigateur du dispatcher  ◄──── vidéo WebRTC (pair à pair, ou par un serveur TURN) ────  NUI du joueur (jeu)
//            │  Socket.IO « / »                                                         Socket.IO « /live »  │
//            └──────────────────────────► ce site : signalisation seulement ◄──────────────────────────────┘
//
// 1. Un dispatcher regarde des joueurs (« live:watch ») : session et rôle vérifiés (comme toute la console), consultation
//    journalisée (mdc_action_log : live.view), une « liaison » (peerId aléatoire) par dispatcher et par joueur.
// 2. Le site demande au serveur FiveM (API « live.start ») de dire au joueur de diffuser, avec un JETON DE DIFFUSION
//    aléatoire (24 octets) : le NUI du MDC se connecte à l'espace « /live » avec ce jeton, rien d'autre ne l'ouvre.
// 3. Le NUI dessine le RENDU DU JEU (texture du jeu en WebGL, sans l'interface) dans un canevas, en fait une piste
//    vidéo (30 images / s par défaut) et ouvre une connexion WebRTC par liaison : offre, réponse et candidats ICE
//    passent par ce site, la vidéo jamais (directe, chiffrée DTLS-SRTP ; TURN si les deux côtés sont filtrés).
// 4. Mosaïque / agrandi : seule la liaison concernée change de débit, de taille et de cadence (setParameters, sans
//    renégociation). Plus personne ne regarde : liaisons fermées, « live.stop », la diffusion s'arrête.
// Contrôles : chaque message de signalisation est vérifié (liaison appartenant à CE dispatcher / à CE joueur), tailles
// et cadences plafonnées. Le jeu s'arrête seul sans renouvellement (client/liveview.lua : 45 s).
// =====================================================================================================================
const crypto = require('crypto');
const config = require('./config');
const fivem = require('./fivem');
const { logAction } = require('./db');
const log = require('./logger');

const L = config.live;
const targets = new Map(); // serverId -> { token, publisher (socket | null), viewers: Map(socketId -> peerId), lastStart, createdAt }
const tokens = new Map();  // jeton de diffusion -> serverId
const peers = new Map();   // peerId -> { serverId, viewer (socketId), mode }
let io = null;
let timer = null;

const MAX_SDP = 32 * 1024;
const MAX_CANDIDATE = 1024;

// ---------------------------------------------------------------------------------------------------------- ICE
/**
 * Serveurs ICE donnés au navigateur et au jeu : STUN (adresse publique) + TURN (relais si la liaison directe est
 * impossible). TURN : identifiants TEMPORAIRES (coturn « use-auth-secret », RFC « TURN REST API ») : nom = expiration
 * + identité, mot de passe = HMAC-SHA1(secret partagé, nom), valables LIVE_TURN_TTL secondes.
 */
function iceServers(identity) {
    const list = [];
    if (L.stun.length) list.push({ urls: L.stun });
    if (L.turn.urls.length) {
        if (L.turn.secret) {
            const username = `${Math.floor(Date.now() / 1000) + L.turn.ttl}:${identity}`;
            const credential = crypto.createHmac('sha1', L.turn.secret).update(username).digest('base64');
            list.push({ urls: L.turn.urls, username, credential });
        } else if (L.turn.username) {
            list.push({ urls: L.turn.urls, username: L.turn.username, credential: L.turn.password });
        }
    }
    return list;
}

/** Réglages envoyés au jeu : taille maximale de capture, cadence, codec préféré, profils mosaïque / agrandi */
function publisherConfig(serverId) {
    return {
        iceServers: iceServers(`player-${serverId}`),
        relayOnly: L.relayOnly,
        maxWidth: L.maxWidth,
        maxHeight: L.maxHeight,
        fps: L.fps,
        codec: L.codec,
        modes: L.modes,
    };
}

// ---------------------------------------------------------------------------------------------------------- outils
const viewerSocket = (socketId) => (io ? io.of('/').sockets.get(socketId) : null);
const toViewer = (socketId, event, data) => { const s = viewerSocket(socketId); if (s) s.emit(event, data); };
const toPublisher = (serverId, event, data) => { const t = targets.get(serverId); if (t && t.publisher) t.publisher.emit(event, data); };

function newPeer(serverId, socketId, mode) {
    const peerId = crypto.randomBytes(12).toString('hex');
    peers.set(peerId, { serverId, viewer: socketId, mode });
    return peerId;
}
function closePeer(peerId, notifyPublisher = true) {
    const p = peers.get(peerId);
    if (!p) return;
    peers.delete(peerId);
    const t = targets.get(p.serverId);
    if (t && t.viewers.get(p.viewer) === peerId) t.viewers.delete(p.viewer);
    if (notifyPublisher) toPublisher(p.serverId, 'peer:close', { peerId });
}
function dropTarget(serverId, reason) {
    const t = targets.get(serverId);
    if (!t) return;
    for (const peerId of t.viewers.values()) {
        const p = peers.get(peerId);
        if (p) toViewer(p.viewer, 'live:gone', { serverId, reason });
        peers.delete(peerId);
    }
    targets.delete(serverId);
    tokens.delete(t.token);
    if (t.publisher) { t.publisher.emit('stop', { reason }); t.publisher.disconnect(true); }
}

// ---------------------------------------------------------------------------------------------------------- jeu
/** Ordres au serveur FiveM : diffuser (nouveaux joueurs, renouvellement) / arrêter (plus personne ne regarde) */
async function sync() {
    const start = [];
    const stop = [];
    const now = Date.now();
    for (const [serverId, t] of targets) {
        if (t.viewers.size === 0) { stop.push(serverId); dropTarget(serverId, 'plus personne ne regarde'); continue; }
        // renouvellement (le jeu s'arrête seul sans nouvel ordre), ou relance si la diffusion ne s'est pas connectée
        if (now - t.lastStart > L.renewMs || (!t.publisher && now - t.lastStart > 10000)) {
            start.push({ serverId, token: t.token });
            t.lastStart = now;
        }
    }
    if (stop.length) await fivem.call('live.stop', { serverIds: stop });
    if (start.length) {
        const res = await fivem.call('live.start', { targets: start, url: L.publicUrl });
        if (!res || res.ok !== true) {
            for (const s of start) { const t = targets.get(s.serverId); if (t) t.lastStart = 0; }
            if (io) io.to('dispatch').emit('live:error', { error: (res && res.error) || 'LiveView indisponible : serveur FiveM injoignable.' });
        }
    }
    if (targets.size === 0 && timer) { clearInterval(timer); timer = null; }
    if (targets.size > 0 && !timer) timer = setInterval(() => sync().catch(() => {}), 5000);
}

// ---------------------------------------------------------------------------------------------------------- dispatchers
/**
 * Joueurs regardés par un dispatcher (remplace sa liste) : [{ serverId, mode: 'grid' | 'focus' }].
 * Retourne { ok, refused: [serverId], iceServers, peers: { serverId: peerId } } : le navigateur attend l'offre du joueur.
 */
async function setWatch(socket, list, players) {
    const wanted = new Map();
    for (const item of Array.isArray(list) ? list.slice(0, 64) : []) {
        const id = Number(item && item.serverId);
        if (Number.isInteger(id) && id > 0 && id < 65536) wanted.set(id, item.mode === 'focus' ? 'focus' : 'grid');
    }
    // joueurs que ce dispatcher ne regarde plus : liaison fermée des deux côtés
    for (const [serverId, t] of targets) {
        const peerId = t.viewers.get(socket.id);
        if (peerId && !wanted.has(serverId)) closePeer(peerId);
    }
    const refused = [];
    const out = {};
    for (const [serverId, mode] of wanted) {
        let t = targets.get(serverId);
        if (!t) {
            if (targets.size >= L.maxStreams) { refused.push(serverId); continue; }
            const token = crypto.randomBytes(24).toString('hex');
            t = { token, publisher: null, viewers: new Map(), lastStart: 0, createdAt: Date.now() };
            targets.set(serverId, t);
            tokens.set(token, serverId);
        }
        let peerId = t.viewers.get(socket.id);
        if (peerId && peers.get(peerId)) {
            const p = peers.get(peerId);
            if (p.mode !== mode) { p.mode = mode; toPublisher(serverId, 'peer:mode', { peerId, mode }); }
        } else {
            if (t.viewers.size >= L.maxViewers) { refused.push(serverId); continue; }
            peerId = newPeer(serverId, socket.id, mode);
            t.viewers.set(socket.id, peerId);
            const p = (players || []).find((x) => x.serverId === serverId);
            logAction('web', `discord:${socket.data.userId}`, 'Dispatch', 'live.view', { serverId, name: p ? p.name : `Joueur ${serverId}`, via: 'webrtc' }).catch(() => {});
            if (t.publisher) toPublisher(serverId, 'peer', { peerId, mode });
        }
        out[serverId] = peerId;
    }
    await sync().catch((e) => log.warn('LiveView :', e.message));
    return { ok: true, refused, iceServers: iceServers(`dispatch-${socket.data.userId}`), relayOnly: L.relayOnly, peers: out };
}

/** Signalisation navigateur -> joueur (réponse SDP, candidats ICE, demande de nouvelle offre) */
function fromViewer(socket, msg) {
    if (!msg || typeof msg !== 'object') return;
    const p = peers.get(String(msg.peerId || ''));
    if (!p || p.viewer !== socket.id) return; // liaison d'un autre dispatcher : ignorée
    const out = { peerId: msg.peerId };
    if (msg.description) {
        const d = msg.description;
        if (!d || d.type !== 'answer' || typeof d.sdp !== 'string' || d.sdp.length > MAX_SDP) return;
        out.description = { type: 'answer', sdp: d.sdp };
    } else if (msg.candidate !== undefined) {
        const c = msg.candidate;
        if (c !== null && (typeof c !== 'object' || typeof c.candidate !== 'string' || c.candidate.length > MAX_CANDIDATE)) return;
        out.candidate = c === null ? null : { candidate: c.candidate, sdpMid: c.sdpMid ?? null, sdpMLineIndex: c.sdpMLineIndex ?? null };
    } else if (msg.restart === true) {
        out.restart = true; // image figée / liaison perdue : le joueur refait une offre (redémarrage ICE)
    } else return;
    toPublisher(p.serverId, 'signal', out);
}

function dropSocket(socket) {
    let changed = false;
    for (const t of targets.values()) {
        const peerId = t.viewers.get(socket.id);
        if (peerId) { closePeer(peerId); changed = true; }
    }
    if (changed) sync().catch(() => {});
}

/** Joueurs partis : leurs diffusions s'arrêtent */
function dropPlayers(onlineIds) {
    const online = new Set(onlineIds);
    let changed = false;
    for (const serverId of [...targets.keys()]) {
        if (!online.has(serverId)) { dropTarget(serverId, 'joueur déconnecté'); changed = true; }
    }
    if (changed) sync().catch(() => {});
}

// ---------------------------------------------------------------------------------------------------------- jeu (NUI)
function originAllowed(origin) {
    if (!origin) return true; // le NUI de FiveM n'envoie pas toujours d'origine en WebSocket ; le jeton suffit
    return L.origins.some((o) => origin === o || (o.endsWith('*') && origin.startsWith(o.slice(0, -1))));
}

/** Espace Socket.IO « /live » : réservé au NUI du MDC qui présente un jeton de diffusion valide */
function attach(server) {
    io = server;
    const nsp = io.of('/live');
    nsp.use((socket, next) => {
        const token = String((socket.handshake.auth && socket.handshake.auth.token) || '');
        const serverId = tokens.get(token);
        if (!serverId || !originAllowed(socket.handshake.headers.origin)) return next(new Error('refused'));
        socket.data.serverId = serverId;
        return next();
    });
    nsp.on('connection', (socket) => {
        const serverId = socket.data.serverId;
        const t = targets.get(serverId);
        if (!t) { socket.disconnect(true); return; }
        if (t.publisher && t.publisher.id !== socket.id) t.publisher.disconnect(true); // ancienne connexion du même joueur
        t.publisher = socket;
        socket.emit('config', publisherConfig(serverId));
        for (const peerId of t.viewers.values()) {
            const p = peers.get(peerId);
            if (p) socket.emit('peer', { peerId, mode: p.mode });
        }
        let budget = { at: Date.now(), n: 0 }; // 120 messages / s au plus (candidats ICE en rafale)
        socket.on('signal', (msg) => {
            const now = Date.now();
            if (now - budget.at > 1000) budget = { at: now, n: 0 };
            if ((budget.n += 1) > 120 || !msg || typeof msg !== 'object') return;
            const p = peers.get(String(msg.peerId || ''));
            if (!p || p.serverId !== serverId) return; // liaison d'un autre joueur : ignorée
            // n° de session de la connexion WebRTC du joueur : nouvelle session = le navigateur repart de zéro
            const out = { serverId, peerId: msg.peerId, session: String(msg.session || '').replace(/[^\w-]/g, '').slice(0, 32) };
            if (msg.description) {
                const d = msg.description;
                if (!d || d.type !== 'offer' || typeof d.sdp !== 'string' || d.sdp.length > MAX_SDP) return;
                out.description = { type: 'offer', sdp: d.sdp };
            } else if (msg.candidate !== undefined) {
                const c = msg.candidate;
                if (c !== null && (typeof c !== 'object' || typeof c.candidate !== 'string' || c.candidate.length > MAX_CANDIDATE)) return;
                out.candidate = c === null ? null : { candidate: c.candidate, sdpMid: c.sdpMid ?? null, sdpMLineIndex: c.sdpMLineIndex ?? null };
            } else if (msg.stats && typeof msg.stats === 'object') {
                // cadence réellement capturée par le jeu (affichée dans la tuile du dispatcher)
                out.stats = { fps: Number(msg.stats.fps) || 0, width: Number(msg.stats.width) || 0, height: Number(msg.stats.height) || 0 };
            } else return;
            toViewer(p.viewer, 'live:signal', out);
        });
        socket.on('disconnect', () => {
            const cur = targets.get(serverId);
            if (!cur || cur.publisher !== socket) return;
            cur.publisher = null;
            for (const peerId of cur.viewers.values()) {
                const p = peers.get(peerId);
                if (p) toViewer(p.viewer, 'live:offline', { serverId, peerId });
            }
        });
    });
}

function status() {
    return [...targets.entries()].map(([serverId, t]) => ({ serverId, viewers: t.viewers.size, connected: !!t.publisher }));
}

module.exports = { attach, setWatch, fromViewer, dropSocket, dropPlayers, status, iceServers };
