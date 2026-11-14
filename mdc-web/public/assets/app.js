// =====================================================================================================================
// WASHINGTON DISPATCH - console du dispatcher (MDC Web). Données : API REST du site (lecture MySQL) + temps réel
// (Socket.IO). Actions : API REST (jeton CSRF), exécutées par le serveur FiveM, qui prévient le jeu tout de suite.
// =====================================================================================================================
(() => {
    'use strict';
    const $ = (s, root = document) => root.querySelector(s);
    const $$ = (s, root = document) => [...root.querySelectorAll(s)];
    const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

    // ---------------- libellés (identiques au MDC en jeu) ----------------
    const PRIORITY = {
        px: 'Priorité X', k1: 'Priorité 1', k2: 'Priorité 2', k3: 'Priorité 3', k4: 'Priorité 4', k0: 'Priorité 0',
        nonurgent: 'Non-Urgent', p1: 'Priorité 1', p2: 'Priorité 2', p3: 'Priorité 3',
    };
    const PRIORITY_MEANING = { px: 'Critique (danger de mort)', k1: 'Immédiat', k2: 'Rapide', k3: 'Routine', k4: 'Quand disponible', k0: '911 coupé sans info' };
    const RESPONSE = { 1: 'Code 1 (normal)', 2: 'Code 2 (urgent, moyen)', 3: 'Code 3 (urgent, rapide)' };
    const CALL_STATUS = { awaiting: 'À valider', pending: 'En attente d\'unité', ongoing: 'En cours', closed: 'Terminée', refused: 'Refusée', cancelled: 'Annulée' };
    const UNIT_STATUS = { available: 'Disponible', en_route: 'En route', on_scene: 'Sur place', unavailable: 'Indisponible' };
    const CLEAR = { A: 'Clear A — Notice of Infraction (ticket)', B: 'Clear B — Arrestation, retenue ou criminal citation et libération', C: 'Clear C — Warning' };
    const AGENCY = { kcso: 'KCSO', wsp: 'WSP' };
    const ACTIONS = {
        'dispatch.enable': 'Mode Dispatch activé', 'dispatch.disable': 'Mode Dispatch désactivé', 'dispatch.release': 'Appels transmis automatiquement',
        'call.validate': 'Intervention validée', 'call.refuse': 'Intervention refusée', 'call.cancel': 'Intervention annulée',
        'call.close': 'Intervention clôturée', 'call.assign': 'Unité affectée', 'call.unassign': 'Unité retirée', 'call.note': 'Note du dispatch',
        'call.create': 'Intervention créée (jeu)', 'incident.create': 'Incident déclaré (jeu)', 'call.delete': 'Intervention supprimée (jeu)',
        'unit.status': 'Statut d\'unité changé', 'unit.create': 'Unité créée (jeu)', 'unit.delete': 'Unité supprimée (jeu)',
        'web.login': 'Connexion au panel', 'web.logout': 'Déconnexion', 'web.denied': 'Connexion refusée (rôle)', 'web.revoked': 'Accès retiré (rôle)',
    };

    const state = {
        me: null, csrf: '', calls: [], units: [], conversations: [], dispatch: null, fivem: { online: false }, presence: [],
        view: 'dashboard', callFilter: 'awaiting', drawerId: null, drawerCall: null, chat: null, chatMessages: [],
        historyPage: 1, logPage: 1, soundOn: true,
    };

    // ---------------- outils ----------------
    const nowS = () => Math.floor(Date.now() / 1000);
    const pad = (n) => String(n).padStart(2, '0');
    const fmtTime = (t) => { const d = new Date(t * 1000); return `${pad(d.getHours())}:${pad(d.getMinutes())}`; };
    const fmtDate = (t) => { if (!t) return '-'; const d = new Date(t * 1000); return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}`; };
    const age = (t) => {
        const s = Math.max(0, nowS() - t);
        if (s < 60) return `${s} s`;
        if (s < 3600) return `${Math.floor(s / 60)} min`;
        return `${Math.floor(s / 3600)} h ${pad(Math.floor((s % 3600) / 60))}`;
    };
    const prioChip = (p) => (PRIORITY[p] ? `<span class="chip ${esc(p)}">${esc(PRIORITY[p])}</span>` : '<span class="muted">-</span>');
    const statusChip = (s) => `<span class="chip ${esc(s)}">${esc(CALL_STATUS[s] || s)}</span>`;
    const unitChip = (s) => `<span class="chip st-${esc(s)}">${esc(UNIT_STATUS[s] || s)}</span>`;
    const agencyChips = (list) => (list || []).map((a) => `<span class="chip agency ${esc(a)}">${esc(AGENCY[a] || a.toUpperCase())}</span>`).join(' ');
    const unitLabel = (u) => `${u.tag ? `<span class="tag">${esc(u.tag)}</span> ` : ''}${esc(u.name)}`;

    async function api(path, body) {
        const opts = body === undefined ? { headers: { Accept: 'application/json' } }
            : { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': state.csrf }, body: JSON.stringify(body) };
        let res;
        try {
            res = await fetch(`/api${path}`, { credentials: 'same-origin', ...opts });
        } catch (e) {
            toast('error', 'Réseau', 'Le site ne répond pas.');
            return null;
        }
        if (res.status === 401) { location.href = '/login'; return null; }
        const data = await res.json().catch(() => null);
        if (!data || data.ok !== true) {
            if (body !== undefined) toast('error', 'Action refusée', (data && data.error) || `Erreur ${res.status}`);
            return null;
        }
        return data;
    }

    // ---------------- sons (générés : aucun fichier) ----------------
    let audio = null;
    function tone(freqs, dur = 0.16, gap = 0.05, type = 'sine', vol = 0.18) {
        if (!state.soundOn) return;
        try {
            audio = audio || new (window.AudioContext || window.webkitAudioContext)();
            if (audio.state === 'suspended') audio.resume();
            let t = audio.currentTime;
            for (const f of freqs) {
                const o = audio.createOscillator();
                const g = audio.createGain();
                o.type = type; o.frequency.value = f;
                g.gain.setValueAtTime(0, t);
                g.gain.linearRampToValueAtTime(vol, t + 0.01);
                g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
                o.connect(g); g.connect(audio.destination);
                o.start(t); o.stop(t + dur + 0.02);
                t += dur + gap;
            }
        } catch (e) { /* audio indisponible */ }
    }
    const SOUND = {
        awaiting: () => tone([880, 660, 880, 660], 0.18, 0.04, 'square', 0.12),
        message: () => tone([740, 988], 0.12, 0.03),
        info: () => tone([523], 0.12),
        error: () => tone([220, 180], 0.18, 0.03, 'sawtooth', 0.08),
    };
    document.addEventListener('click', () => { if (audio && audio.state === 'suspended') audio.resume(); });
    $('#soundBtn').addEventListener('click', () => {
        state.soundOn = !state.soundOn;
        try { localStorage.setItem('mdc.sound', state.soundOn ? '1' : '0'); } catch (e) { /* stockage indisponible */ }
        renderSound();
        if (state.soundOn) SOUND.info();
    });
    function renderSound() {
        $('#soundBtn').textContent = state.soundOn ? 'Son : activé' : 'Son : coupé';
        $('#soundBtn').classList.toggle('off', !state.soundOn);
    }
    try { state.soundOn = localStorage.getItem('mdc.sound') !== '0'; } catch (e) { state.soundOn = true; }

    // ---------------- notifications ----------------
    function toast(kind, title, text, onClick, duration = 7000) {
        const el = document.createElement('div');
        el.className = `toast ${kind}`;
        el.innerHTML = `<b>${esc(title)}</b><div>${esc(text || '')}</div>`;
        el.addEventListener('click', () => { el.remove(); if (onClick) onClick(); });
        $('#toasts').prepend(el);
        while ($('#toasts').children.length > 6) $('#toasts').lastChild.remove();
        if (duration) setTimeout(() => el.remove(), duration);
    }

    function updateTitle() {
        const awaiting = state.calls.filter((c) => c.status === 'awaiting').length;
        const unread = state.conversations.reduce((n, c) => n + (c.unread || 0), 0);
        const total = awaiting + unread;
        document.title = total ? `(${total}) Washington Dispatch` : 'Washington Dispatch';
    }

    // Rappel sonore tant qu'une intervention attend la validation
    setInterval(() => {
        if (state.dispatch && state.dispatch.effective && state.calls.some((c) => c.status === 'awaiting' && nowS() - c.createdAt > 20)) SOUND.awaiting();
    }, 20000);

    // ---------------- en-tête ----------------
    setInterval(() => {
        const d = new Date();
        $('#clock').textContent = `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
        $$('[data-age]').forEach((el) => { el.textContent = age(Number(el.dataset.age)); });
    }, 1000);

    function renderHeader() {
        const d = state.dispatch || {};
        const sw = $('#modeSwitch');
        sw.setAttribute('aria-checked', d.enabled ? 'true' : 'false');
        $('#modeLabel').textContent = `MODE DISPATCH : ${d.enabled ? 'ACTIF' : 'INACTIF'}`;
        $('#modeHint').textContent = d.enabled
            ? (d.effective ? 'Les appels des civils attendent votre validation' : 'Activé, mais le jeu ne voit pas le dispatch en ligne')
            : 'Les appels partent directement aux unités';
        $('#indFivem').classList.toggle('on', !!state.fivem.online);
        $('#fivemBanner').classList.toggle('hidden', !!state.fivem.online);
        $('#indPlayers').textContent = typeof state.fivem.players === 'number' ? `${state.fivem.players} joueur(s)` : '';
        $('#indDispatchers').textContent = `${state.presence.length} dispatcher(s)`;
        $('#presenceList').innerHTML = `<b>DISPATCHERS EN LIGNE</b>${state.presence.map((p) => esc(p.name)).join('<br>') || '-'}`;
    }

    $('#modeSwitch').addEventListener('click', async () => {
        const enable = !(state.dispatch && state.dispatch.enabled);
        if (!enable && state.calls.some((c) => c.status === 'awaiting')
            && !confirm('Des interventions attendent votre validation : en désactivant le mode Dispatch, elles seront envoyées directement aux unités. Continuer ?')) return;
        const res = await api('/dispatch/mode', { enabled: enable });
        if (res && res.dispatch) { state.dispatch = res.dispatch; renderHeader(); renderDashboard(); }
    });

    $('#logoutBtn').addEventListener('click', async () => {
        await fetch('/auth/logout', { method: 'POST', headers: { 'X-CSRF-Token': state.csrf }, credentials: 'same-origin' });
        location.href = '/login';
    });

    // ---------------- navigation ----------------
    function showView(view) {
        state.view = view;
        $$('.nav').forEach((b) => b.classList.toggle('active', b.dataset.view === view));
        $$('.view').forEach((v) => v.classList.toggle('hidden', v.id !== `view-${view}`));
        if (view === 'history') loadHistory();
        if (view === 'log') loadLog();
        if (view === 'messages') renderChatList();
        renderAll();
    }
    $$('.nav').forEach((b) => b.addEventListener('click', () => showView(b.dataset.view)));

    // ---------------- tableau de bord ----------------
    const counts = () => {
        const c = { awaiting: 0, pending: 0, ongoing: 0 };
        for (const x of state.calls) if (c[x.status] !== undefined) c[x.status] += 1;
        return c;
    };

    function callRow(c, cols) {
        return `<tr data-call="${c.id}" class="prio-${esc(c.priority)} ${c.id === state.drawerId ? 'sel' : ''}">
            <td class="num">${esc(c.number)}</td>
            <td>${prioChip(c.priority)}${c.responseCode ? ` <span class="muted">C${esc(c.responseCode)}</span>` : ''}</td>
            <td><b>${esc(c.title)}</b>${c.kind === 'incident' ? ' <span class="muted">(incident)</span>' : ''}</td>
            <td>${esc(c.address)}${c.crossStreet ? ` <span class="muted">× ${esc(c.crossStreet)}</span>` : ''}</td>
            ${cols.includes('block') ? `<td>${esc(c.block)}</td>` : ''}
            <td>${agencyChips(c.agency)}</td>
            <td>${c.units.map((u) => esc(u.name)).join(', ') || '<span class="muted">-</span>'}</td>
            <td>${statusChip(c.status)}</td>
            <td>${cols.includes('created') ? fmtTime(c.createdAt) : `<span data-age="${c.createdAt}">${age(c.createdAt)}</span>`}</td>
        </tr>`;
    }

    function renderDashboard() {
        const c = counts();
        $('#kpiAwaiting').textContent = c.awaiting;
        $('#kpiPending').textContent = c.pending;
        $('#kpiOngoing').textContent = c.ongoing;
        const connected = state.units.filter((u) => u.connected);
        $('#kpiUnits').textContent = connected.length;
        $('#kpiAvailable').textContent = connected.filter((u) => u.status === 'available').length;
        const d = state.dispatch || {};
        $('#queueHint').textContent = d.effective ? 'les appels des civils attendent ici' : 'mode Dispatch inactif : appels transmis directement';
        const queue = state.calls.filter((x) => x.status === 'awaiting').sort((a, b) => a.createdAt - b.createdAt);
        $('#dashQueue').innerHTML = queue.length ? queue.map((x) => `
            <div class="qcard" data-call="${x.id}">
                <div class="q-top"><span class="num">${esc(x.number)}</span>${prioChip(x.priority)}${x.responseCode ? `<span class="chip">C${esc(x.responseCode)}</span>` : ''}
                    <span class="q-title">${esc(x.title)}</span><span class="age" data-age="${x.createdAt}">${age(x.createdAt)}</span></div>
                <div class="q-meta">${esc(x.address)}${x.block ? ` — bloc ${esc(x.block)}` : ''} · ${agencyChips(x.agency)} · requérant ${esc(x.caller || '-')}</div>
                <div class="q-actions">
                    <button type="button" class="btn ok small" data-quick="validate" data-id="${x.id}">Valider et transmettre</button>
                    <button type="button" class="btn small" data-open="${x.id}">Ouvrir / affecter</button>
                    <button type="button" class="btn danger small" data-quick="refuse" data-id="${x.id}">Refuser</button>
                </div>
            </div>`).join('') : '<div class="empty">Aucune intervention en attente de validation.</div>';
        const active = state.calls.filter((x) => ['awaiting', 'pending', 'ongoing'].includes(x.status));
        $('#dashCalls').innerHTML = active.map((x) => callRow(x, [])).join('') || '<tr><td colspan="8" class="empty">Aucune intervention active.</td></tr>';
        $('#dashUnits').innerHTML = connected.length ? connected.map((u) => `
            <div class="ucard">
                <div class="u-top">${unitLabel(u)} ${agencyChips([u.agency])}</div>
                <div class="u-members">${u.members.map((m) => `${esc(m.name)}${m.grade ? ` (${esc(m.grade)})` : ''}`).join(', ')}</div>
                ${statusSelect(u)}
                ${u.calls.length ? `<div class="u-call">${u.calls.map((c) => `${esc(c.number)} ${esc(c.title)}`).join(' · ')}</div>` : ''}
            </div>`).join('') : '<div class="empty">Aucune unité connectée.</div>';
    }

    function statusSelect(u) {
        return `<select class="status st-${esc(u.status)}" data-unit-status="${u.id}" title="Changer le statut de ${esc(u.name)}">
            ${Object.entries(UNIT_STATUS).map(([k, v]) => `<option value="${k}" ${k === u.status ? 'selected' : ''}>${esc(v)}</option>`).join('')}</select>`;
    }

    // ---------------- interventions ----------------
    function renderCalls() {
        const c = counts();
        $$('[data-count]').forEach((b) => {
            const n = c[b.dataset.count] || 0;
            b.textContent = n;
            b.classList.toggle('hidden', !n);
        });
        const f = state.callFilter;
        const list = state.calls.filter((x) => (f === 'all' ? true : f === 'recent' ? ['closed', 'refused', 'cancelled'].includes(x.status) : x.status === f));
        $('#callsBody').innerHTML = list.map((x) => callRow(x, ['block', 'created'])).join('');
        $('#callsEmpty').classList.toggle('hidden', list.length > 0);
    }
    $$('#callTabs .tab').forEach((t) => t.addEventListener('click', () => {
        state.callFilter = t.dataset.filter;
        $$('#callTabs .tab').forEach((x) => x.classList.toggle('active', x === t));
        renderCalls();
    }));

    // ---------------- unités ----------------
    function renderUnits() {
        const onlyConnected = $('#unitsConnected').checked;
        const agency = $('#unitsAgency').value;
        const list = state.units.filter((u) => (!onlyConnected || u.connected) && (!agency || u.agency === agency));
        const active = state.calls.filter((x) => ['pending', 'ongoing'].includes(x.status));
        $('#unitsBody').innerHTML = list.map((u) => `
            <tr>
                <td><b>${unitLabel(u)}</b>${u.connected ? '' : ' <span class="muted">(hors ligne)</span>'}</td>
                <td>${agencyChips([u.agency])}</td>
                <td>${u.members.map((m) => `${esc(m.name)}${m.grade ? ` <span class="muted">(${esc(m.grade)})</span>` : ''}`).join('<br>') || '<span class="muted">-</span>'}</td>
                <td>${statusSelect(u)}</td>
                <td>${u.calls.map((c) => `<a href="#" data-open="${c.id}" class="num">${esc(c.number)}</a>`).join(' ') || '<span class="muted">-</span>'}</td>
                <td><span data-age="${u.statusAt}">${age(u.statusAt)}</span></td>
                <td class="row-actions">
                    <button type="button" class="btn small" data-chat="d:u:${u.id}">Message</button>
                    ${active.length ? `<select data-assign-unit="${u.id}"><option value="">Affecter à…</option>${active.filter((c) => !c.units.some((x) => x.id === u.id))
                        .map((c) => `<option value="${c.id}">${esc(c.number)} — ${esc(c.title)}</option>`).join('')}</select>` : ''}
                </td>
            </tr>`).join('');
        $('#unitsEmpty').classList.toggle('hidden', list.length > 0);
        const connected = state.units.filter((u) => u.connected).length;
        $('#navUnits').textContent = connected;
        $('#navUnits').classList.toggle('hidden', !connected);
    }
    $('#unitsConnected').addEventListener('change', renderUnits);
    $('#unitsAgency').addEventListener('change', renderUnits);

    // ---------------- fiche d'intervention ----------------
    async function openCall(id) {
        state.drawerId = id;
        $('#drawer').classList.remove('hidden');
        const res = await api(`/calls/${id}`);
        if (!res || state.drawerId !== id) return;
        state.drawerCall = res.call;
        renderDrawer();
        renderAll();
        markRead(`d:c:${id}`);
    }
    function closeDrawer() {
        state.drawerId = null;
        state.drawerCall = null;
        $('#drawer').classList.add('hidden');
        renderAll();
    }
    $('#drawerClose').addEventListener('click', closeDrawer);

    function renderDrawer() {
        const c = state.drawerCall;
        if (!c) return;
        const open = !c.closed;
        $('#drawerTitle').innerHTML = `<div class="d-num">${esc(c.number)}</div><div class="d-title">${esc(c.title)} ${statusChip(c.status)}</div>`;
        const candidates = state.units.filter((u) => u.connected && ['kcso', 'wsp'].includes(u.agency) && !c.units.some((x) => x.id === u.id));
        let actions = '';
        if (c.status === 'awaiting') {
            actions = `
                <div class="d-actions awaiting">
                    <div class="d-section pick-section"><h4>Unités à affecter en validant (facultatif)</h4>
                        <div class="unit-pick">${candidates.map((u) => `<label><input type="checkbox" value="${u.id}" data-pick> ${esc(u.name)} ${unitChip(u.status)}</label>`).join('') || '<span class="muted">Aucune unité connectée.</span>'}</div>
                    </div>
                    <button type="button" class="btn ok" data-act="validate">Valider et transmettre</button>
                    <button type="button" class="btn danger" data-act="refuse">Refuser…</button>
                    <button type="button" class="btn ghost" data-act="cancel">Annuler…</button>
                </div>`;
        } else if (open) {
            actions = `
                <div class="d-actions">
                    <select id="clearSelect"><option value="">Clôturer sans code</option>${Object.entries(CLEAR).map(([k, v]) => `<option value="${k}">${esc(v)}</option>`).join('')}</select>
                    <button type="button" class="btn" data-act="close">Clôturer</button>
                    <button type="button" class="btn danger" data-act="cancel">Annuler l'intervention…</button>
                </div>`;
        }
        const info = [
            ['Priorité', `${prioChip(c.priority)} ${esc(PRIORITY_MEANING[c.priority] || '')}`],
            ['Code de réponse', c.responseCode ? esc(RESPONSE[c.responseCode]) : '-'],
            ['Police', agencyChips(c.agency)],
            ['Requérant', esc(c.caller || '-')], ['Téléphone', esc(c.phone || '-')],
            ['Adresse', `${esc(c.address)}${c.crossStreet ? ` × ${esc(c.crossStreet)}` : ''}`], ['Bloc', esc(c.block || '-')],
            ...(c.sector ? [['Secteur', esc(c.sector)]] : []),
            ['Unités idéales', c.idealUnits ? esc(c.idealUnits) : '-'],
            ['Créée', `${fmtDate(c.createdAt)} par ${esc(c.createdByName || '-')}`],
            ...(c.dispatch ? [['Dispatch', `${esc({ awaiting: 'En attente', validated: 'Validée', refused: 'Refusée', cancelled: 'Annulée' }[c.dispatch] || c.dispatch)}${c.dispatchBy ? ` par ${esc(c.dispatchBy)}` : ''}${c.dispatchReason ? ` — ${esc(c.dispatchReason)}` : ''}`]] : []),
            ...(c.closed ? [['Clôture', `${fmtDate(c.closedAt)} par ${esc(c.closedByName || '-')}${c.clear ? ` — ${esc(CLEAR[c.clear])}` : ''}`]] : []),
        ];
        $('#drawerBody').innerHTML = `
            ${actions}
            <div class="d-section"><h4>Informations</h4><dl class="info-grid">${info.map(([k, v]) => `<dt>${esc(k)}</dt><dd>${v}</dd>`).join('')}</dl></div>
            <div class="d-section"><h4>Description</h4><div class="desc">${esc(c.description || '-')}</div></div>
            <div class="d-section"><h4>Unités affectées (${c.units.length})</h4>
                <div class="assigned">${c.units.map((u) => `<span>${unitLabel(u)} ${unitChip(u.status)}${open ? `<button type="button" title="Retirer de l'intervention" data-unassign="${u.id}">✕</button>` : ''}</span>`).join('') || '<span class="muted">Aucune unité.</span>'}</div>
                ${open && c.status !== 'awaiting' ? `<div class="inline-form"><select id="assignSelect"><option value="">Choisir une unité connectée…</option>${candidates.map((u) => `<option value="${u.id}">${esc(u.name)} (${esc(AGENCY[u.agency] || u.agency)}) — ${esc(UNIT_STATUS[u.status])}</option>`).join('')}</select>
                    <button type="button" class="btn primary" data-act="assign">Affecter</button></div>` : ''}
            </div>
            ${c.links.length ? `<div class="d-section"><h4>Personnes et véhicules liés</h4>${c.links.map((l) => `<div>${l.kind === 'vehicle' ? 'Véhicule' : 'Identité'} : <b>${esc(l.label)}</b> <span class="muted">(${esc(l.addedBy)})</span></div>`).join('')}</div>` : ''}
            <div class="d-section"><h4>Déroulé et notes (${c.notes.length})</h4>
                <div class="timeline">${c.notes.map((n) => `<div class="note ${n.dispatch ? 'dispatch' : ''}"><div class="note-head"><span>${esc(n.dispatch ? `DISPATCH — ${n.authorName}` : `${n.unitName} — ${n.authorName}`)}</span><span>${fmtDate(n.createdAt)}</span></div><div class="note-text">${esc(n.text)}</div></div>`).join('') || '<span class="muted">Aucune note.</span>'}</div>
                ${open ? `<div class="inline-form"><input id="noteInput" maxlength="500" placeholder="Note du dispatch (affichée en jeu dans l'intervention)"><button type="button" class="btn" data-act="note">Ajouter</button></div>` : ''}
            </div>
            ${c.status !== 'awaiting' ? `<div class="d-section thread-small"><h4>Messages avec les unités de ${esc(c.number)}</h4>
                <div class="chat-body" id="drawerChat">${c.messages.map(bubble).join('') || '<span class="muted">Aucun message.</span>'}</div>
                ${open ? `<div class="inline-form"><input id="drawerMsg" maxlength="300" placeholder="Message aux unités de l'intervention"><button type="button" class="btn dispatch" data-act="msg">Envoyer</button></div>` : ''}
            </div>` : ''}
            ${c.log.length ? `<div class="d-section"><h4>Actions enregistrées</h4>${c.log.map((l) => `<div class="muted">${fmtDate(l.at)} — ${esc(ACTIONS[l.action] || l.action)} — ${esc(l.actorName)}</div>`).join('')}</div>` : ''}`;
        const chat = $('#drawerChat');
        if (chat) chat.scrollTop = chat.scrollHeight;
    }

    $('#drawerBody').addEventListener('click', async (e) => {
        const c = state.drawerCall;
        if (!c) return;
        const un = e.target.closest('[data-unassign]');
        if (un) { await api(`/calls/${c.id}/unassign`, { unitId: Number(un.dataset.unassign) }); return; }
        const b = e.target.closest('[data-act]');
        if (!b) return;
        const act = b.dataset.act;
        b.disabled = true;
        try {
            if (act === 'validate') {
                const units = $$('[data-pick]:checked', $('#drawerBody')).map((x) => Number(x.value));
                if (await api(`/calls/${c.id}/validate`, { units })) toast('ok', c.number, 'Intervention validée et transmise aux unités.');
            } else if (act === 'refuse' || act === 'cancel') {
                const reason = await askReason(act === 'refuse' ? `Refuser ${c.number}` : `Annuler ${c.number}`,
                    act === 'refuse' ? 'Motif du refus (communiqué au civil qui a appelé, facultatif) :' : 'Motif de l\'annulation (communiqué aux unités, facultatif) :');
                if (reason !== null && await api(`/calls/${c.id}/${act}`, { reason })) toast('ok', c.number, act === 'refuse' ? 'Intervention refusée.' : 'Intervention annulée.');
            } else if (act === 'close') {
                if (await api(`/calls/${c.id}/close`, { clear: $('#clearSelect').value })) toast('ok', c.number, 'Intervention clôturée.');
            } else if (act === 'assign') {
                const unitId = Number($('#assignSelect').value);
                if (!unitId) return toast('error', 'Affectation', 'Choisissez une unité.');
                if (await api(`/calls/${c.id}/assign`, { unitId })) toast('ok', c.number, 'Unité affectée.');
            } else if (act === 'note') {
                const text = $('#noteInput').value.trim();
                if (text && await api(`/calls/${c.id}/note`, { text })) $('#noteInput').value = '';
            } else if (act === 'msg') {
                const text = $('#drawerMsg').value.trim();
                if (text && await api('/messages', { channel: `d:c:${c.id}`, text })) $('#drawerMsg').value = '';
            }
        } finally {
            b.disabled = false;
        }
    });
    $('#drawerBody').addEventListener('keydown', (e) => {
        if (e.key !== 'Enter') return;
        if (e.target.id === 'noteInput') $('[data-act="note"]').click();
        if (e.target.id === 'drawerMsg') $('[data-act="msg"]').click();
    });

    // Motif (fenêtre)
    function askReason(title, text) {
        return new Promise((resolve) => {
            $('#modalTitle').textContent = title;
            $('#modalText').textContent = text;
            $('#modalInput').value = '';
            $('#modal').classList.remove('hidden');
            $('#modalInput').focus();
            const done = (value) => {
                $('#modal').classList.add('hidden');
                $('#modalForm').onsubmit = null;
                $('#modalCancel').onclick = null;
                resolve(value);
            };
            $('#modalForm').onsubmit = (e) => { e.preventDefault(); done($('#modalInput').value.trim()); };
            $('#modalCancel').onclick = () => done(null);
        });
    }

    // Délégation : ouvrir une intervention, actions rapides, statuts, affectations, messages
    document.addEventListener('click', async (e) => {
        const quick = e.target.closest('[data-quick]');
        if (quick) {
            const id = Number(quick.dataset.id);
            const c = state.calls.find((x) => x.id === id);
            if (quick.dataset.quick === 'validate') {
                if (await api(`/calls/${id}/validate`, { units: [] })) toast('ok', c ? c.number : '', 'Intervention transmise aux unités.');
            } else {
                const reason = await askReason(`Refuser ${c ? c.number : ''}`, 'Motif du refus (communiqué au civil, facultatif) :');
                if (reason !== null && await api(`/calls/${id}/refuse`, { reason })) toast('ok', c ? c.number : '', 'Intervention refusée.');
            }
            return;
        }
        const openBtn = e.target.closest('[data-open]');
        if (openBtn) { e.preventDefault(); openCall(Number(openBtn.dataset.open)); return; }
        const row = e.target.closest('tr[data-call]');
        if (row && !e.target.closest('select, button, a')) { openCall(Number(row.dataset.call)); return; }
        const chatBtn = e.target.closest('[data-chat]');
        if (chatBtn) { showView('messages'); openChat(chatBtn.dataset.chat); }
    });
    document.addEventListener('change', async (e) => {
        const st = e.target.closest('[data-unit-status]');
        if (st) {
            const unit = state.units.find((u) => u.id === Number(st.dataset.unitStatus));
            if (!await api(`/units/${st.dataset.unitStatus}/status`, { status: st.value }) && unit) st.value = unit.status;
            return;
        }
        const as = e.target.closest('[data-assign-unit]');
        if (as && as.value) {
            if (await api(`/calls/${as.value}/assign`, { unitId: Number(as.dataset.assignUnit) })) toast('ok', 'Affectation', 'Unité affectée.');
            as.value = '';
        }
    });

    // ---------------- messagerie ----------------
    const bubble = (m) => {
        const mine = m.senderType === 'dispatch';
        const who = mine ? `DISPATCH — ${m.author}` : m.senderType === 'civil' ? `${m.author} (civil)` : m.author;
        return `<div class="bubble ${mine ? 'mine' : ''}"><div class="b-meta"><b>${esc(who)}</b><span>${fmtTime(m.at)}</span></div><div class="b-text">${esc(m.text)}</div></div>`;
    };

    function renderChatList() {
        const groups = [['civil', 'Groupe civil'], ['unit', 'Unités'], ['call', 'Interventions']];
        $('#chatList').innerHTML = groups.map(([kind, label]) => {
            const items = state.conversations.filter((c) => c.kind === kind);
            if (!items.length && kind !== 'civil') return '';
            return `<div class="chat-group">${esc(label)}</div>${items.map((c) => `
                <button type="button" class="conv ${c.unread ? 'unread' : ''} ${state.chat === c.channel ? 'active' : ''}" data-conv="${esc(c.channel)}">
                    <span class="conv-top">${c.kind === 'unit' ? `${unitLabel({ name: c.label, tag: c.tag })} ${agencyChips([c.agency])}${c.connected ? '' : ' <span class="muted">(hors ligne)</span>'}` : esc(c.label)}
                        ${c.unread ? `<span class="badge hot">${c.unread}</span>` : ''}</span>
                    <span class="conv-last">${c.last ? `${c.last.senderType === 'dispatch' ? 'Vous : ' : `${esc(c.last.author)} : `}${esc(c.last.text)}` : 'Aucun message'}</span>
                </button>`).join('')}`;
        }).join('');
        const unread = state.conversations.reduce((n, c) => n + (c.unread || 0), 0);
        $('#navUnread').textContent = unread;
        $('#navUnread').classList.toggle('hidden', !unread);
        updateTitle();
    }
    $('#chatList').addEventListener('click', (e) => {
        const b = e.target.closest('[data-conv]');
        if (b) openChat(b.dataset.conv);
    });

    async function openChat(channel) {
        state.chat = channel;
        const conv = state.conversations.find((c) => c.channel === channel);
        $('#chatHead').textContent = conv ? (conv.kind === 'unit' ? `Unité ${conv.label}` : conv.label) : channel;
        $('#chatForm').classList.remove('hidden');
        const res = await api(`/messages?channel=${encodeURIComponent(channel)}`);
        if (!res || state.chat !== channel) return;
        state.chatMessages = res.messages;
        renderChat();
        renderChatList();
        markRead(channel);
        $('#chatInput').focus();
    }
    function renderChat() {
        $('#chatBody').innerHTML = state.chatMessages.map(bubble).join('') || '<div class="empty">Aucun message : écrivez le premier.</div>';
        $('#chatBody').scrollTop = $('#chatBody').scrollHeight;
    }
    function markRead(channel) {
        const conv = state.conversations.find((c) => c.channel === channel);
        if (conv && conv.unread) api('/messages/read', { channel });
    }
    $('#chatForm').addEventListener('submit', async (e) => {
        e.preventDefault();
        const text = $('#chatInput').value.trim();
        if (!text || !state.chat) return;
        $('#chatInput').disabled = true;
        const ok = await api('/messages', { channel: state.chat, text });
        $('#chatInput').disabled = false;
        if (ok) $('#chatInput').value = '';
        $('#chatInput').focus();
    });
    $('#chatInput').addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); $('#chatForm').requestSubmit(); }
    });

    // ---------------- historique ----------------
    const dateToS = (v, end) => (v ? Math.floor(new Date(`${v}T${end ? '23:59:59' : '00:00:00'}`).getTime() / 1000) : 0);
    async function loadHistory() {
        const p = new URLSearchParams({ q: $('#historyQ').value.trim(), status: $('#historyStatus').value,
            from: dateToS($('#historyFrom').value), to: dateToS($('#historyTo').value, true), page: state.historyPage });
        const res = await api(`/history?${p}`);
        if (!res) return;
        $('#historyBody').innerHTML = res.calls.map((c) => `
            <tr data-call="${c.id}" class="prio-${esc(c.priority)}">
                <td class="num">${esc(c.number)}</td><td>${prioChip(c.priority)}</td><td><b>${esc(c.title)}</b></td>
                <td>${esc(c.address)}</td><td>${agencyChips(c.agency)}</td><td>${statusChip(c.status)}</td>
                <td>${fmtDate(c.createdAt)}</td><td>${fmtDate(c.closedAt)}${c.clear ? ` <span class="muted">Clear ${esc(c.clear)}</span>` : ''}</td>
            </tr>`).join('') || '<tr><td colspan="8" class="empty">Aucun résultat.</td></tr>';
        pager('#historyPager', res, (page) => { state.historyPage = page; loadHistory(); });
    }
    $('#historyForm').addEventListener('submit', (e) => { e.preventDefault(); state.historyPage = 1; loadHistory(); });

    function pager(sel, res, go) {
        const pages = Math.max(1, Math.ceil(res.total / res.size));
        $(sel).innerHTML = `<span>${res.total} résultat(s) — page ${res.page} / ${pages}</span>
            <button type="button" class="btn small" ${res.page <= 1 ? 'disabled' : ''} data-page="${res.page - 1}">Précédente</button>
            <button type="button" class="btn small" ${res.page >= pages ? 'disabled' : ''} data-page="${res.page + 1}">Suivante</button>`;
        $$('[data-page]', $(sel)).forEach((b) => b.addEventListener('click', () => go(Number(b.dataset.page))));
    }

    // ---------------- journal ----------------
    async function loadLog() {
        const res = await api(`/log?source=${$('#logSource').value}&page=${state.logPage}`);
        if (!res) return;
        const detail = (l) => {
            const d = l.details || {};
            const parts = [d.number, d.unit, d.title, d.reason && `motif : ${d.reason}`, d.from && d.to && `${UNIT_STATUS[d.from] || d.from} → ${UNIT_STATUS[d.to] || d.to}`,
                d.clear && `Clear ${d.clear}`, Array.isArray(d.units) && d.units.length && `unités : ${d.units.join(', ')}`, d.count && `${d.count} appel(s)`].filter(Boolean);
            return parts.map(esc).join(' — ');
        };
        $('#logBody').innerHTML = res.entries.map((l) => `
            <tr><td>${fmtDate(l.at)}</td><td><span class="chip">${esc({ dispatch: 'Dispatch', game: 'Jeu', web: 'Connexion' }[l.source] || l.source)}</span></td>
                <td>${esc(l.actorName || '-')}</td><td>${esc(ACTIONS[l.action] || l.action)}</td><td>${detail(l)}</td></tr>`).join('')
            || '<tr><td colspan="5" class="empty">Journal vide.</td></tr>';
        pager('#logPager', res, (page) => { state.logPage = page; loadLog(); });
    }
    $('#logSource').addEventListener('change', () => { state.logPage = 1; loadLog(); });

    // ---------------- rendu général ----------------
    function renderAll() {
        renderHeader();
        if (state.view === 'dashboard') renderDashboard();
        if (state.view === 'calls') renderCalls();
        if (state.view === 'units') renderUnits();
        const awaiting = counts().awaiting;
        $('#navAwaiting').textContent = awaiting;
        $('#navAwaiting').classList.toggle('hidden', !awaiting);
        $$('tr[data-call]').forEach((tr) => tr.classList.toggle('sel', Number(tr.dataset.call) === state.drawerId));
        updateTitle();
    }

    // ---------------- temps réel ----------------
    function connect() {
        const socket = io({ withCredentials: true });
        socket.on('connect', () => { $('#indRealtime').classList.add('on'); refreshState(); });
        socket.on('disconnect', () => $('#indRealtime').classList.remove('on'));
        socket.on('connect_error', (err) => {
            $('#indRealtime').classList.remove('on');
            if (err && err.message === 'unauthorized') location.href = '/login';
        });
        socket.on('revoked', () => { location.href = '/denied?reason=role'; });
        socket.on('calls', (calls) => {
            state.calls = calls;
            renderAll();
            if (state.drawerId) {
                const still = calls.some((c) => c.id === state.drawerId);
                if (still || state.drawerCall) refreshDrawer();
            }
        });
        socket.on('units', (units) => { state.units = units; renderAll(); if (state.drawerCall) renderDrawer(); });
        socket.on('dispatch', (d) => { state.dispatch = d; renderAll(); });
        socket.on('fivem', (f) => { state.fivem = f; if (f.dispatch) state.dispatch = f.dispatch; renderAll(); });
        socket.on('presence', (p) => { state.presence = p; renderHeader(); });
        socket.on('conversations', (list) => { state.conversations = list; renderChatList(); });
        socket.on('message', (m) => {
            if (state.chat === m.channel && !state.chatMessages.some((x) => x.id === m.id)) {
                state.chatMessages.push(m);
                renderChat();
                if (m.senderType !== 'dispatch' && state.view === 'messages') markRead(m.channel);
            }
            if (state.drawerCall && m.channel === `d:c:${state.drawerCall.id}`) refreshDrawer();
            if (m.senderType !== 'dispatch' && !(state.chat === m.channel && state.view === 'messages')) {
                SOUND.message();
                toast('message', m.senderType === 'civil' ? `Groupe civil — ${m.author}` : `Message — ${m.author}`, m.text,
                    () => { showView('messages'); openChat(m.channel); }, 9000);
            }
        });
        socket.on('alert', (a) => {
            if (a.type === 'awaiting') {
                SOUND.awaiting();
                toast('awaiting', `NOUVELLE INTERVENTION À VALIDER — ${a.number}`, a.title || '', () => openCall(a.id), 0);
            } else if (a.type === 'new') {
                SOUND.info();
                toast('info', `Nouvelle intervention — ${a.number}`, a.title || '', () => openCall(a.id));
            }
        });
    }

    let drawerTimer = null;
    function refreshDrawer() {
        clearTimeout(drawerTimer);
        drawerTimer = setTimeout(async () => {
            if (!state.drawerId) return;
            const res = await api(`/calls/${state.drawerId}`);
            if (res && state.drawerId === res.call.id) { state.drawerCall = res.call; renderDrawer(); }
        }, 150);
    }

    async function refreshState() {
        const res = await api('/state');
        if (!res) return;
        Object.assign(state, { calls: res.calls, units: res.units, conversations: res.conversations, fivem: res.fivem,
            dispatch: res.dispatch, presence: res.presence });
        renderAll();
        renderChatList();
    }

    // ---------------- démarrage ----------------
    (async () => {
        renderSound();
        const me = await api('/me');
        if (!me) return;
        state.me = me.user;
        state.csrf = me.csrf;
        $('#userName').textContent = me.user.name;
        if (me.user.avatar) { $('#userAvatar').src = me.user.avatar; $('#userAvatar').classList.remove('hidden'); }
        await refreshState();
        connect();
    })();
})();
