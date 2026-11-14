'use strict';
// Temps réel (Socket.IO) : seuls les dispatchers authentifiés (session + rôle Discord) reçoivent les événements.
// Le navigateur ne fait rien passer par le socket : toutes les actions passent par l'API REST (CSRF, contrôle du rôle).
const { Server } = require('socket.io');
const config = require('./config');
const queries = require('./queries');
const { verifyRole } = require('./auth');
const log = require('./logger');

let io = null;
const presence = new Map(); // id Discord -> { id, name, avatar, sockets }

function dispatchers() {
    return [...presence.values()].map((p) => ({ id: p.id, name: p.name }));
}

function init(httpServer, sessionMiddleware, onPresenceChange) {
    io = new Server(httpServer, { serveClient: true, cors: { origin: config.publicUrl, credentials: true } });
    io.engine.use(sessionMiddleware);

    io.use(async (socket, next) => {
        const session = socket.request.session;
        const check = await verifyRole(session, config.discord.roleRecheck);
        if (!check.ok) return next(new Error('unauthorized'));
        session.save(() => next());
    });

    io.on('connection', (socket) => {
        const u = socket.request.session.user;
        socket.data.userId = u.id;
        socket.join('dispatch');
        const p = presence.get(u.id) || { id: u.id, name: u.name, avatar: u.avatar, sockets: 0 };
        p.sockets += 1;
        p.name = u.name;
        presence.set(u.id, p);
        if (p.sockets === 1) {
            log.info(`dispatcher en ligne : ${u.name}`);
            onPresenceChange();
        }
        broadcast('presence', dispatchers());
        socket.on('disconnect', () => {
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
        if (topics.has('units')) broadcast('units', await queries.units());
        for (const e of events) {
            if (e.topic === 'dispatch' && e.data) broadcast('dispatch', e.data);
            if (ALERTS[e.topic] && e.data) broadcast('alert', { type: ALERTS[e.topic], ...e.data });
            if (e.topic === 'message' && e.data && e.data.id) {
                const m = await queries.messageById(Number(e.data.id));
                if (m) broadcast('message', m);
            }
        }
        if (topics.has('message') || topics.has('reads') || topics.has('units') || topics.has('calls')) broadcast('conversations', await queries.conversations());
    } catch (e) {
        log.error('relecture MySQL après un événement du jeu :', e.message);
    }
}

module.exports = { init, broadcast, dispatchers, handleGameEvents };
