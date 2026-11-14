'use strict';
// API REST du panel (toutes les routes : dispatcher connecté avec le rôle ; actions : CSRF + revérification du rôle).
// Les actions sont exécutées par le serveur FiveM (seul à écrire les données du MDC) : le jeu est prévenu tout de
// suite et renvoie l'événement au site, qui met à jour tous les dispatchers.
const express = require('express');
const queries = require('./queries');
const fivem = require('./fivem');
const realtime = require('./realtime');
const { requireDispatcher, requireCsrf } = require('./auth');
const log = require('./logger');

const router = express.Router();
const read = requireDispatcher(false);
const act = [requireDispatcher(true), requireCsrf];

const STATUSES = ['available', 'en_route', 'on_scene', 'unavailable'];
const CHANNEL = /^d:(civ|u:\d{1,9}|c:\d{1,9})$/;

const id = (v) => {
    const n = Number(v);
    return Number.isInteger(n) && n > 0 && n < 1e9 ? n : null;
};
const text = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const actor = (req) => ({ id: req.session.user.id, name: req.session.user.name });

const wrap = (fn) => (req, res) => Promise.resolve(fn(req, res)).catch((e) => {
    log.error(`${req.method} ${req.originalUrl} :`, e.message);
    res.status(500).json({ ok: false, error: 'Erreur du serveur Web (base de données ?).' });
});

/** Action exécutée par le serveur FiveM */
async function game(res, action, body, req) {
    const result = await fivem.call(action, { ...body, actor: actor(req) });
    if (!result || result.ok !== true) {
        return res.status(result && /injoignable|refuse/.test(result.error || '') ? 503 : 400)
            .json({ ok: false, error: (result && result.error) || 'Action refusée par le serveur FiveM.' });
    }
    return res.json(result);
}

// ---------------------------------------------------------------- lecture
router.get('/me', read, (req, res) => {
    const u = req.session.user;
    res.json({ ok: true, user: { id: u.id, name: u.name, avatar: u.avatar }, csrf: req.session.csrf });
});

router.get('/state', read, wrap(async (req, res) => {
    const [calls, units, conversations, mode] = await Promise.all([queries.activeCalls(), queries.units(), queries.conversations(),
        queries.dispatchMode()]);
    const status = fivem.publicStatus();
    res.json({ ok: true, calls, units, conversations, fivem: status,
        dispatch: status.dispatch || { enabled: mode, online: false, effective: false, count: 0 },
        presence: realtime.dispatchers() });
}));

router.get('/calls/:id', read, wrap(async (req, res) => {
    const cid = id(req.params.id);
    const call = cid && await queries.callDetail(cid);
    if (!call) return res.status(404).json({ ok: false, error: 'Intervention introuvable.' });
    res.json({ ok: true, call });
}));

router.get('/history', read, wrap(async (req, res) => {
    const q = text(req.query.q, 60);
    const status = ['all', 'closed', 'refused', 'cancelled'].includes(req.query.status) ? req.query.status : 'all';
    const from = Math.max(0, Number(req.query.from) || 0);
    const to = Math.max(0, Number(req.query.to) || 0);
    const page = Math.min(10000, Math.max(1, Number(req.query.page) || 1));
    res.json({ ok: true, ...(await queries.history({ q, status, from, to, page })) });
}));

router.get('/log', read, wrap(async (req, res) => {
    const source = ['all', 'dispatch', 'game', 'web'].includes(req.query.source) ? req.query.source : 'all';
    const page = Math.min(10000, Math.max(1, Number(req.query.page) || 1));
    res.json({ ok: true, ...(await queries.actionLog({ source, page })) });
}));

router.get('/conversations', read, wrap(async (req, res) => {
    res.json({ ok: true, conversations: await queries.conversations() });
}));

router.get('/messages', read, wrap(async (req, res) => {
    const channel = String(req.query.channel || '');
    if (!CHANNEL.test(channel)) return res.status(400).json({ ok: false, error: 'Conversation invalide.' });
    const before = Math.max(0, Number(req.query.before) || 0);
    res.json({ ok: true, channel, messages: await queries.channelMessages(channel, before) });
}));

// ---------------------------------------------------------------- actions (exécutées par le serveur FiveM)
router.post('/dispatch/mode', act, wrap(async (req, res) => {
    if (typeof req.body.enabled !== 'boolean') return res.status(400).json({ ok: false, error: 'Valeur invalide.' });
    return game(res, 'dispatch.mode', { enabled: req.body.enabled }, req);
}));

const callAction = (path, action, build) => router.post(`/calls/:id/${path}`, act, wrap(async (req, res) => {
    const cid = id(req.params.id);
    if (!cid) return res.status(400).json({ ok: false, error: 'Intervention invalide.' });
    const extra = build ? build(req.body || {}) : {};
    if (extra === null) return res.status(400).json({ ok: false, error: 'Données invalides.' });
    return game(res, action, { id: cid, ...extra }, req);
}));

callAction('validate', 'call.validate', (b) => {
    const units = Array.isArray(b.units) ? b.units.map(id).filter(Boolean).slice(0, 10) : [];
    return { units };
});
callAction('refuse', 'call.refuse', (b) => ({ reason: text(b.reason, 200) }));
callAction('cancel', 'call.cancel', (b) => ({ reason: text(b.reason, 200) }));
callAction('close', 'call.close', (b) => {
    const clear = b.clear ? String(b.clear).toUpperCase() : '';
    return ['', 'A', 'B', 'C'].includes(clear) ? { clear } : null;
});
callAction('assign', 'call.assign', (b) => (id(b.unitId) ? { unitId: id(b.unitId) } : null));
callAction('unassign', 'call.unassign', (b) => (id(b.unitId) ? { unitId: id(b.unitId) } : null));
callAction('note', 'call.note', (b) => (text(b.text, 500) ? { text: text(b.text, 500) } : null));

router.post('/units/:id/status', act, wrap(async (req, res) => {
    const uid = id(req.params.id);
    const status = String(req.body.status || '');
    if (!uid || !STATUSES.includes(status)) return res.status(400).json({ ok: false, error: 'Statut invalide.' });
    return game(res, 'unit.status', { unitId: uid, status }, req);
}));

router.post('/messages', act, wrap(async (req, res) => {
    const channel = String(req.body.channel || '');
    const body = text(req.body.text, 300);
    if (!CHANNEL.test(channel) || !body) return res.status(400).json({ ok: false, error: 'Message vide ou conversation invalide.' });
    return game(res, 'message.send', { channel, text: body }, req);
}));

router.post('/messages/read', act, wrap(async (req, res) => {
    const channel = String(req.body.channel || '');
    if (!CHANNEL.test(channel)) return res.status(400).json({ ok: false, error: 'Conversation invalide.' });
    // le jeu enregistre la lecture puis prévient le site (événement « reads ») : non-lus à jour chez tous les dispatchers
    const result = await fivem.call('message.read', { channel, actor: actor(req) });
    res.json({ ok: !!(result && result.ok) });
}));

module.exports = router;
