'use strict';
// Lectures pour le panel du dispatch (MySQL : même base que le jeu). Formats identiques à ceux du MDC en jeu
// (statuts d'appel, n° RD, canaux de messagerie).
const { query, queryRaw } = require('./db');

const now = () => Math.floor(Date.now() / 1000);
const RECENT_CLOSED_SECONDS = 6 * 3600; // terminées récentes affichées avec les appels actifs

const agencies = (v) => String(v || '').split(/[+,\s]+/).filter(Boolean);

/** Statut d'un appel : même règle que server.lua (interventionStatus) */
function callStatus(row, unitCount) {
    if (row.dispatch_state === 'refused') return 'refused';
    if (row.dispatch_state === 'cancelled') return 'cancelled';
    if (Number(row.closed) === 1) return 'closed';
    if (row.dispatch_state === 'awaiting') return 'awaiting';
    return unitCount > 0 ? 'ongoing' : 'pending';
}

function callView(r, units = [], extra = {}) {
    return {
        id: Number(r.id), number: r.number, kind: r.kind, title: r.title, caller: r.caller || '', phone: r.phone || '',
        priority: r.priority || '', responseCode: r.response_code === null ? null : Number(r.response_code),
        agency: agencies(r.agency), idealUnits: r.ideal_units === null ? null : Number(r.ideal_units),
        address: r.address, crossStreet: r.cross_street || '', block: r.block || '', sector: r.sector || '',
        description: r.description || '', unitName: r.unit_name || '', backup: Number(r.backup) === 1,
        requestedBy: r.requested_by || '', closed: Number(r.closed) === 1, clear: r.clear_code || null,
        dispatch: r.dispatch_state || null, dispatchReason: r.dispatch_reason || '', dispatchBy: r.dispatch_by || '',
        dispatchAt: r.dispatch_at ? Number(r.dispatch_at) : null, createdByName: r.created_by_name || '',
        createdAt: Number(r.created_at), closedAt: r.closed_at ? Number(r.closed_at) : null, closedByName: r.closed_by_name || '',
        updatedAt: r.updated_at ? Number(r.updated_at) : null,
        status: callStatus(r, units.length), units, ...extra,
    };
}

async function unitsOfCalls(ids) {
    if (!ids.length) return {};
    const rows = await queryRaw(`SELECT cu.call_id, cu.assigned_at, u.id, u.name, u.tag, u.color, u.agency, u.status
        FROM mdc_call_units cu JOIN mdc_units u ON u.id = cu.unit_id WHERE cu.call_id IN (?) ORDER BY cu.assigned_at`, [ids]);
    const map = {};
    for (const r of rows) {
        (map[r.call_id] = map[r.call_id] || []).push({ id: Number(r.id), name: r.name, tag: r.tag, color: r.color,
            agency: r.agency, status: r.status, assignedAt: Number(r.assigned_at) });
    }
    return map;
}

/** Appels actifs (en attente du dispatch, en attente d'unité, en cours) et terminés depuis moins de 6 h */
async function activeCalls() {
    const rows = await query('SELECT * FROM mdc_calls WHERE closed = 0 OR closed_at >= ? ORDER BY id DESC LIMIT 300',
        [now() - RECENT_CLOSED_SECONDS]);
    const ids = rows.map((r) => Number(r.id));
    const units = await unitsOfCalls(ids);
    const notes = ids.length ? await queryRaw('SELECT call_id, COUNT(*) n FROM mdc_call_notes WHERE call_id IN (?) GROUP BY call_id', [ids]) : [];
    const noteCount = Object.fromEntries(notes.map((n) => [n.call_id, Number(n.n)]));
    return rows.map((r) => callView(r, units[r.id] || [], { notesCount: noteCount[r.id] || 0 }));
}

/** Fiche complète d'un appel : unités, notes, fiches liées, messages du canal de l'appel, actions du dispatch */
async function callDetail(id) {
    const rows = await query('SELECT * FROM mdc_calls WHERE id = ?', [id]);
    if (!rows.length) return null;
    const units = (await unitsOfCalls([Number(id)]))[id] || [];
    const notes = await query('SELECT * FROM mdc_call_notes WHERE call_id = ? ORDER BY note_id', [id]);
    const links = await query(`SELECT l.kind, l.record_id, l.added_by, l.added_at,
            i.lastname, i.firstname, i.dob, v.plate
        FROM mdc_call_links l
        LEFT JOIN mdc_identities i ON l.kind = 'identity' AND i.id = l.record_id
        LEFT JOIN mdc_vehicles v ON l.kind = 'vehicle' AND v.id = l.record_id
        WHERE l.call_id = ? ORDER BY l.added_at`, [id]);
    const log = await query('SELECT * FROM mdc_action_log WHERE call_id = ? ORDER BY id', [id]);
    return callView(rows[0], units, {
        notes: notes.map((n) => ({ id: Number(n.note_id), unitName: n.unit_name, unitTag: n.unit_tag, authorName: n.author_name,
            text: n.text, dispatch: Number(n.dispatch) === 1, backup: n.backup, createdAt: Number(n.created_at),
            updatedAt: n.updated_at ? Number(n.updated_at) : null })),
        links: links.map((l) => ({ kind: l.kind, recordId: Number(l.record_id), addedBy: l.added_by, addedAt: Number(l.added_at),
            label: l.kind === 'vehicle' ? (l.plate || `Véhicule n°${l.record_id}`)
                : (l.lastname ? `${String(l.lastname).toUpperCase()} ${l.firstname} (${l.dob})` : `Identité n°${l.record_id}`) })),
        log: log.map(logView),
        messages: await channelMessages(`d:c:${Number(id)}`),
    });
}

/** Unités (indicatif, tag, police, statut, membres connectés avec grade, interventions en cours) */
async function units() {
    const rows = await query('SELECT * FROM mdc_units ORDER BY agency, name');
    const members = await query(`SELECT m.unit_id, m.server_id, m.joined_at, a.rp_name, a.grade
        FROM mdc_unit_members m LEFT JOIN mdc_agents a ON a.identifier = m.identifier ORDER BY a.rp_name`);
    const calls = await query(`SELECT cu.unit_id, c.id, c.number, c.title FROM mdc_call_units cu
        JOIN mdc_calls c ON c.id = cu.call_id WHERE c.closed = 0 ORDER BY c.id DESC`);
    const lastStatus = await query('SELECT unit_id, MAX(created_at) at FROM mdc_unit_status_log GROUP BY unit_id');
    const statusAt = Object.fromEntries(lastStatus.map((s) => [s.unit_id, Number(s.at)]));
    return rows.map((u) => {
        const m = members.filter((x) => Number(x.unit_id) === Number(u.id)).map((x) => ({
            serverId: Number(x.server_id), name: x.rp_name || 'Agent sans nom RP', grade: x.grade || '' }));
        return {
            id: Number(u.id), agency: u.agency, name: u.name, tag: u.tag, color: u.color, status: u.status,
            updatedAt: Number(u.updated_at), statusAt: statusAt[u.id] || Number(u.updated_at), members: m, connected: m.length > 0,
            calls: calls.filter((c) => Number(c.unit_id) === Number(u.id)).map((c) => ({ id: Number(c.id), number: c.number, title: c.title })),
        };
    });
}

function messageView(m) {
    return { id: Number(m.id), channel: m.channel, callId: m.call_id ? Number(m.call_id) : null, senderType: m.sender_type,
        unitId: m.sender_unit_id ? Number(m.sender_unit_id) : null, author: m.sender_name, text: m.text, at: Number(m.created_at) };
}

/** Messages d'un canal (les plus récents, `before` : pagination vers le passé) */
async function channelMessages(channel, before = 0, limit = 60) {
    const rows = before > 0
        ? await queryRaw('SELECT * FROM mdc_messages WHERE channel = ? AND id < ? ORDER BY id DESC LIMIT ?', [channel, before, limit])
        : await queryRaw('SELECT * FROM mdc_messages WHERE channel = ? ORDER BY id DESC LIMIT ?', [channel, limit]);
    return rows.reverse().map(messageView);
}

async function messageById(id) {
    const rows = await query('SELECT * FROM mdc_messages WHERE id = ?', [id]);
    return rows.length ? messageView(rows[0]) : null;
}

/** Conversations du dispatch : groupe civil, chaque unité, chaque intervention ouverte (dernier message, non-lus) */
async function conversations() {
    const unitRows = await units();
    const openCalls = await query('SELECT id, number, title, dispatch_state FROM mdc_calls WHERE closed = 0 ORDER BY id DESC');
    const last = await query(`SELECT m.* FROM mdc_messages m JOIN (SELECT channel, MAX(id) id FROM mdc_messages
        WHERE channel LIKE 'd:%' GROUP BY channel) t ON t.id = m.id`);
    const unread = await query(`SELECT m.channel, COUNT(*) n FROM mdc_messages m
        LEFT JOIN mdc_message_reads r ON r.channel = m.channel AND r.reader = 'dispatch'
        WHERE m.channel LIKE 'd:%' AND m.sender_type <> 'dispatch' AND m.id > COALESCE(r.last_id, 0) GROUP BY m.channel`);
    const lastBy = Object.fromEntries(last.map((m) => [m.channel, messageView(m)]));
    const unreadBy = Object.fromEntries(unread.map((u) => [u.channel, Number(u.n)]));
    const item = (channel, kind, label, extra = {}) => ({ channel, kind, label, last: lastBy[channel] || null,
        unread: unreadBy[channel] || 0, ...extra });
    const list = [item('d:civ', 'civil', 'Groupe civil')];
    for (const u of unitRows) {
        if (u.connected || lastBy[`d:u:${u.id}`]) {
            list.push(item(`d:u:${u.id}`, 'unit', u.name, { unitId: u.id, agency: u.agency, tag: u.tag, connected: u.connected, status: u.status }));
        }
    }
    for (const c of openCalls) {
        if (c.dispatch_state !== 'awaiting') {
            list.push(item(`d:c:${c.id}`, 'call', `${c.number} — ${c.title}`, { callId: Number(c.id), number: c.number }));
        }
    }
    return list;
}

/** Historique : appels terminés / refusés / annulés, recherche et pagination */
async function history({ q = '', status = 'all', from = 0, to = 0, page = 1, size = 25 }) {
    const where = ['closed = 1'];
    const params = [];
    if (q) {
        where.push('(number LIKE ? OR title LIKE ? OR address LIKE ? OR caller LIKE ?)');
        const like = `%${q.replace(/[%_\\]/g, '\\$&')}%`;
        params.push(like, like, like, like);
    }
    if (status === 'refused') where.push("dispatch_state = 'refused'");
    else if (status === 'cancelled') where.push("dispatch_state = 'cancelled'");
    else if (status === 'closed') where.push("(dispatch_state IS NULL OR dispatch_state = 'validated')");
    if (from > 0) { where.push('created_at >= ?'); params.push(from); }
    if (to > 0) { where.push('created_at <= ?'); params.push(to); }
    const w = where.join(' AND ');
    const total = (await queryRaw(`SELECT COUNT(*) n FROM mdc_calls WHERE ${w}`, params))[0].n;
    const rows = await queryRaw(`SELECT * FROM mdc_calls WHERE ${w} ORDER BY id DESC LIMIT ? OFFSET ?`,
        [...params, size, (Math.max(1, page) - 1) * size]);
    const unitMap = await unitsOfCalls(rows.map((r) => Number(r.id)));
    return { total: Number(total), page, size, calls: rows.map((r) => callView(r, unitMap[r.id] || [])) };
}

function logView(l) {
    let details = null;
    try { details = l.details ? JSON.parse(l.details) : null; } catch (e) { details = l.details; }
    return { id: Number(l.id), source: l.source, actorName: l.actor_name, action: l.action,
        callId: l.call_id ? Number(l.call_id) : null, unitId: l.unit_id ? Number(l.unit_id) : null, details, at: Number(l.created_at) };
}

/** Journal des actions (dispatch Web, jeu, connexions) */
async function actionLog({ source = 'all', page = 1, size = 50 }) {
    const where = source === 'all' ? '1 = 1' : 'source = ?';
    const params = source === 'all' ? [] : [source];
    const total = (await queryRaw(`SELECT COUNT(*) n FROM mdc_action_log WHERE ${where}`, params))[0].n;
    const rows = await queryRaw(`SELECT * FROM mdc_action_log WHERE ${where} ORDER BY id DESC LIMIT ? OFFSET ?`,
        [...params, size, (Math.max(1, page) - 1) * size]);
    return { total: Number(total), page, size, entries: rows.map(logView) };
}

async function dispatchMode() {
    const rows = await query("SELECT value FROM mdc_settings WHERE name = 'dispatch_mode'");
    return rows.length ? rows[0].value === '1' : false;
}

module.exports = { activeCalls, callDetail, units, channelMessages, messageById, conversations, history, actionLog, dispatchMode, callStatus };
