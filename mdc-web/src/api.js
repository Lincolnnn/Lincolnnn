'use strict';
// API REST du panel (toutes les routes : dispatcher connecté avec le rôle ; actions : CSRF + revérification du rôle).
// Les actions sont exécutées par le serveur FiveM (seul à écrire les données du MDC) : le jeu est prévenu tout de
// suite et renvoie l'événement au site, qui met à jour tous les dispatchers.
const express = require('express');
const config = require('./config');
const queries = require('./queries');
const fivem = require('./fivem');
const realtime = require('./realtime');
const { requireDispatcher, requireCsrf } = require('./auth');
const log = require('./logger');

const router = express.Router();
const read = requireDispatcher(false);
const act = [requireDispatcher(true), requireCsrf];

const STATUSES = ['available', 'en_route', 'on_scene', 'unavailable'];
// Canaux où le dispatch écrit : groupe civil, conversation privée d'un civil (joueur), unité, intervention
const CHANNEL = /^d:(civ|u:\d{1,9}|c:\d{1,9}|p:[A-Za-z0-9]{1,28})$/;
// Lecture seule (observation) : conversations entre deux unités
const OBSERVE = /^u:\d{1,9}:\d{1,9}$/;

const id = (v) => {
    const n = Number(v);
    return Number.isInteger(n) && n > 0 && n < 1e9 ? n : null;
};
const text = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
// Le dispatcher apparaît toujours sous le nom « Dispatch » (jeu, messages, notes, journal) ; son identifiant Discord
// reste dans le journal (mdc_action_log.actor_id) pour les administrateurs.
const DISPATCH_NAME = 'Dispatch';
const actor = (req) => ({ id: req.session.user.id, name: DISPATCH_NAME });

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
    res.json({ ok: true, user: { name: DISPATCH_NAME }, csrf: req.session.csrf });
});

router.get('/state', read, wrap(async (req, res) => {
    const [calls, units, conversations, mode] = await Promise.all([queries.activeCalls(), queries.units(),
        queries.conversations(realtime.players()), queries.dispatchMode()]);
    const status = fivem.publicStatus();
    res.json({ ok: true, calls, units, conversations, fivem: status,
        dispatch: status.dispatch || { enabled: mode, online: false, effective: false, count: 0 },
        presence: realtime.dispatchers(), positions: realtime.positions(), players: realtime.players(), editing: realtime.editing() });
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

// ---------------------------------------------------------------- recherches (mêmes règles et fiches que le MDC en jeu)
const DOB = /^(\d{2})\/(\d{2})\/(\d{4})$/;
router.get('/search', read, wrap(async (req, res) => {
    const type = req.query.type === 'vehicle' ? 'vehicle' : 'identity';
    const body = type === 'vehicle'
        ? { type, query: text(req.query.query, 20) }
        : { type, lastname: text(req.query.lastname, 40), firstname: text(req.query.firstname, 40), dob: text(req.query.dob, 10), ssn: text(req.query.ssn, 11) };
    if (type === 'identity' && (!body.lastname || !DOB.test(body.dob))) {
        return res.status(400).json({ ok: false, error: 'Le nom de famille et la date de naissance (JJ/MM/AAAA) sont obligatoires.' });
    }
    const result = await fivem.call('search', body);
    if (!result || result.ok !== true) return res.status(result && /injoignable/.test(result.error || '') ? 503 : 400).json({ ok: false, error: (result && result.error) || 'Recherche impossible.' });
    res.json({ ok: true, results: Array.isArray(result.results) ? result.results : [] });
}));

router.get('/records/:kind/:id', read, wrap(async (req, res) => {
    const kind = req.params.kind === 'vehicle' ? 'vehicle' : 'identity';
    const rid = id(req.params.id);
    if (!rid) return res.status(400).json({ ok: false, error: 'Fiche invalide.' });
    const result = await fivem.call('record', { kind, id: rid });
    if (!result || result.ok !== true) return res.status(404).json({ ok: false, error: (result && result.error) || 'Fiche introuvable.' });
    res.json({ ok: true, record: result.record });
}));

router.get('/conversations', read, wrap(async (req, res) => {
    res.json({ ok: true, conversations: await queries.conversations(realtime.players()) });
}));

// Observation : conversations entre unités, en lecture seule (rien n'est marqué comme lu, aucun signe de présence)
router.get('/observe', read, wrap(async (req, res) => {
    res.json({ ok: true, conversations: await queries.observeConversations() });
}));

router.get('/players', read, wrap(async (req, res) => {
    res.json({ ok: true, players: realtime.players(), liveview: realtime.liveviewAvailable(), rtc: config.live.rtc.enabled });
}));

router.get('/messages', read, wrap(async (req, res) => {
    const channel = String(req.query.channel || '');
    if (!CHANNEL.test(channel) && !OBSERVE.test(channel)) return res.status(400).json({ ok: false, error: 'Conversation invalide.' });
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
callAction('delete', 'call.delete');   // corbeille (restaurable)
callAction('reopen', 'call.reopen');   // intervention / incident terminé(e) rouvert(e)

// ---- Création d'une intervention / d'un incident par le dispatch (formulaire rapide ou détaillé) ----
const PRIORITIES = ['px', 'k1', 'k2', 'k3', 'k4', 'k0', 'nonurgent', 'p1', 'p2', 'p3'];
function callFields(b, partial) {
    const out = {};
    const str = (k, max) => { if (b[k] !== undefined) out[k] = text(b[k], max); };
    str('title', 60); str('address', 80); str('crossStreet', 80); str('block', 40); str('sector', 40);
    str('caller', 60); str('phone', 20);
    if (b.description !== undefined) out.description = typeof b.description === 'string' ? b.description.trim().slice(0, 2000) : '';
    if (b.priority !== undefined) { if (b.priority !== '' && !PRIORITIES.includes(b.priority)) return null; out.priority = b.priority; }
    if (b.responseCode !== undefined && b.responseCode !== null && b.responseCode !== '') {
        const rc = Number(b.responseCode);
        if (![1, 2, 3].includes(rc)) return null;
        out.responseCode = rc;
    }
    if (b.idealUnits !== undefined && b.idealUnits !== '') {
        const n = Number(b.idealUnits);
        if (!Number.isInteger(n) || n < 1 || n > 20) return null;
        out.idealUnits = n;
    }
    const ag = b.agencies !== undefined ? b.agencies : b.agency;
    if (ag !== undefined) {
        const list = (Array.isArray(ag) ? ag : String(ag).split('+')).map(String).filter((a) => ['kcso', 'wsp'].includes(a));
        if (!list.length) return null;
        out[partial ? 'agency' : 'agencies'] = [...new Set(list)];
    }
    return out;
}

router.post('/calls', act, wrap(async (req, res) => {
    const b = req.body || {};
    const fields = callFields(b, false);
    if (!fields) return res.status(400).json({ ok: false, error: 'Données invalides.' });
    const call = { ...fields, kind: b.kind === 'incident' ? 'incident' : 'intervention',
        units: Array.isArray(b.units) ? b.units.map(id).filter(Boolean).slice(0, 10) : [] };
    return game(res, 'call.create', { call }, req);
}));

// ---- Modification (avant l'envoi, ou pendant l'intervention) : n° de version pour les modifications simultanées ----
router.post('/calls/:id/edit', act, wrap(async (req, res) => {
    const cid = id(req.params.id);
    const b = req.body || {};
    const fields = callFields(b.fields || {}, true);
    if (!cid || !fields || !Number.isInteger(Number(b.rev))) return res.status(400).json({ ok: false, error: 'Données invalides.' });
    const result = await fivem.call('call.edit', { id: cid, rev: Number(b.rev), force: b.force === true, fields, actor: actor(req) });
    if (result && result.conflict) return res.status(409).json({ ok: false, conflict: true, rev: result.rev, error: result.error });
    if (!result || result.ok !== true) return res.status(400).json({ ok: false, error: (result && result.error) || 'Modification refusée.' });
    return res.json(result);
}));

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

// ---------------------------------------------------------------- registres (mêmes données que le jeu)
const KINDS = ['identity', 'vehicle', 'report', 'bolo'];
const fromGame = async (res, action, body, notFound) => {
    const result = await fivem.call(action, body);
    if (!result || result.ok !== true) {
        return res.status(result && /injoignable/.test(result.error || '') ? 503 : (notFound ? 404 : 400))
            .json({ ok: false, error: (result && result.error) || 'Indisponible.' });
    }
    return res.json(result);
};
router.get('/registry/offenders', read, wrap(async (req, res) => fromGame(res, 'registry.offenders', { type: req.query.type === 'kidnap' ? 'kidnap' : 'sex' })));
router.get('/registry/bolos', read, wrap(async (req, res) => fromGame(res, 'registry.bolos', {})));
router.get('/registry/bolos/:id', read, wrap(async (req, res) => fromGame(res, 'registry.bolo', { id: id(req.params.id) }, true)));
router.get('/registry/reports', read, wrap(async (req, res) => fromGame(res, 'registry.reports',
    { type: text(req.query.type, 20), query: text(req.query.q, 60), page: Math.min(10000, Math.max(1, Number(req.query.page) || 1)) })));
router.get('/registry/reports/:id', read, wrap(async (req, res) => fromGame(res, 'registry.report', { id: id(req.params.id) }, true)));
let reportTypesCache = null;
router.get('/registry/report-types', read, wrap(async (req, res) => {
    if (reportTypesCache && Date.now() - reportTypesCache.at < 600000) return res.json(reportTypesCache.data);
    const result = await fivem.call('registry.reportTypes', {});
    if (!result || result.ok !== true) return res.status(503).json({ ok: false, error: 'Modèles indisponibles (serveur FiveM).' });
    reportTypesCache = { at: Date.now(), data: result };
    return res.json(result);
}));

// Modification / suppression de TOUTE fiche par le dispatch (mêmes contrôles qu'en jeu ; suppression = corbeille)
router.post('/records/:kind/:id', act, wrap(async (req, res) => {
    const kind = String(req.params.kind);
    const rid = id(req.params.id);
    if (!KINDS.includes(kind) || !rid || typeof req.body.data !== 'object' || !req.body.data) return res.status(400).json({ ok: false, error: 'Données invalides.' });
    return game(res, 'record.update', { kind, id: rid, data: req.body.data }, req);
}));
router.post('/records/:kind/:id/delete', act, wrap(async (req, res) => {
    const kind = String(req.params.kind);
    const rid = id(req.params.id);
    if (!KINDS.includes(kind) || !rid) return res.status(400).json({ ok: false, error: 'Fiche invalide.' });
    return game(res, 'record.delete', { kind, id: rid }, req);
}));

// Conversations : supprimer (ou vider) — messages à la corbeille, la conversation peut être recréée
router.post('/conversations/delete', act, wrap(async (req, res) => {
    const channel = String(req.body.channel || '');
    const mode = req.body.mode === 'empty' ? 'empty' : 'delete';
    if (!CHANNEL.test(channel) && !OBSERVE.test(channel)) return res.status(400).json({ ok: false, error: 'Conversation invalide.' });
    return game(res, 'conversation.delete', { channel, mode }, req);
}));

// Corbeille et journal d'audit (tous les dispatchers)
router.get('/trash', read, wrap(async (req, res) => res.json({ ok: true, items: await queries.trash() })));
router.post('/trash/:id/restore', act, wrap(async (req, res) => {
    const tid = id(req.params.id);
    if (!tid) return res.status(400).json({ ok: false, error: 'Élément invalide.' });
    return game(res, 'trash.restore', { id: tid }, req);
}));
router.post('/trash/:id/purge', act, wrap(async (req, res) => {
    const tid = id(req.params.id);
    if (!tid) return res.status(400).json({ ok: false, error: 'Élément invalide.' });
    return game(res, 'trash.purge', { id: tid }, req);
}));
router.get('/audit', read, wrap(async (req, res) => {
    const kind = ['identity', 'vehicle', 'report', 'bolo', 'call', 'conversation'].includes(req.query.kind) ? req.query.kind : '';
    const action = ['delete', 'restore', 'purge', 'update', 'reopen', 'empty'].includes(req.query.action) ? req.query.action : '';
    const page = Math.min(10000, Math.max(1, Number(req.query.page) || 1));
    res.json({ ok: true, ...(await queries.audit({ kind, action, q: text(req.query.q, 60), page })) });
}));

// Fenêtres et espaces de travail du dispatcher (gardés d'une session à l'autre)
router.get('/layout', read, wrap(async (req, res) => res.json({ ok: true, layout: await queries.layout(req.session.user.id) })));
router.post('/layout', act, wrap(async (req, res) => {
    const data = req.body && req.body.layout;
    if (!data || typeof data !== 'object' || JSON.stringify(data).length > 30000) return res.status(400).json({ ok: false, error: 'Disposition invalide.' });
    await queries.saveLayout(req.session.user.id, data);
    res.json({ ok: true });
}));

module.exports = router;
