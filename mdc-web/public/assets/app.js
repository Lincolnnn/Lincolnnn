// =====================================================================================================================
// KING COUNTY DISPATCH — console du dispatcher (MDC Web).
// Lecture : API REST du site (MySQL) + temps réel (Socket.IO). Actions : API REST (jeton CSRF), exécutées par le serveur
// FiveM, qui prévient le jeu tout de suite. Notifications visuelles : nouvelles interventions / incidents seulement ;
// les messages ne font qu'un son (le même pour tous).
// =====================================================================================================================
(() => {
    'use strict';
    const $ = (s, root = document) => root.querySelector(s);
    const $$ = (s, root = document) => [...root.querySelectorAll(s)];
    const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
    const icon = (name, cls = '') => `<svg class="i ${cls}" aria-hidden="true"><use href="#i-${name}"/></svg>`;
    const store = {
        get(key, def) { try { const v = localStorage.getItem(key); return v === null ? def : JSON.parse(v); } catch (e) { return def; } },
        set(key, v) { try { localStorage.setItem(key, JSON.stringify(v)); } catch (e) { /* stockage indisponible */ } },
    };

    // ---------------- libellés (identiques au MDC en jeu) ----------------
    const PRIORITY = {
        px: 'Priorité X', k1: 'Priorité 1', k2: 'Priorité 2', k3: 'Priorité 3', k4: 'Priorité 4', k0: 'Priorité 0',
        nonurgent: 'Non urgent', p1: 'Priorité 1', p2: 'Priorité 2', p3: 'Priorité 3',
    };
    const PRIORITY_MEANING = { px: 'Critique (danger de mort)', k1: 'Immédiat', k2: 'Rapide', k3: 'Routine', k4: 'Quand disponible', k0: '911 coupé sans info' };
    const PRIO_TONE = { px: 'solid-stop', k1: 'stop', p1: 'stop', k2: 'accent', p2: 'accent', k3: 'caution', p3: 'caution', k4: 'steel', k0: 'steel', nonurgent: 'steel' };
    const KCSO_PRIORITIES = ['px', 'k1', 'k2', 'k3', 'k4', 'k0'];
    const WSP_PRIORITIES = ['p1', 'p2', 'p3', 'nonurgent'];
    const RESPONSE = { 1: 'Code 1 — normal', 2: 'Code 2 — urgent, sans sirène', 3: 'Code 3 — urgent, gyrophares et sirène' };
    const CALL_STATUS = { awaiting: 'À valider', pending: 'Sans unité', ongoing: 'En cours', closed: 'Terminée', refused: 'Refusée', cancelled: 'Annulée' };
    const STATUS_TONE = { awaiting: 'accent', pending: 'caution', ongoing: 'go', closed: 'steel', refused: 'stop', cancelled: 'steel' };
    const UNIT_STATUS = { available: 'Disponible', en_route: 'En route', on_scene: 'Sur place', unavailable: 'Indisponible' };
    const UNIT_ORDER = { available: 0, en_route: 1, on_scene: 2, unavailable: 3 };
    const CLEAR = { A: 'Clear A — Notice of Infraction (ticket)', B: 'Clear B — Arrestation, retenue ou criminal citation', C: 'Clear C — Warning' };
    const AGENCY = { kcso: 'KCSO', wsp: 'WSP', generic: 'Civil' };
    const FIELD_LABEL = { title: 'Intitulé', address: 'Adresse', crossStreet: 'Croisement', block: 'Bloc', sector: 'Secteur', description: 'Description',
        caller: 'Requérant', phone: 'Téléphone', priority: 'Priorité', responseCode: 'Code de réponse', idealUnits: 'Unités idéales', agency: 'Police' };
    const ACTIONS = {
        'dispatch.enable': 'Mode Dispatch activé', 'dispatch.disable': 'Mode Dispatch désactivé', 'dispatch.release': 'Appels transmis automatiquement',
        'call.validate': 'Intervention validée', 'call.refuse': 'Intervention refusée', 'call.cancel': 'Intervention annulée',
        'call.close': 'Intervention clôturée', 'call.assign': 'Unité affectée', 'call.unassign': 'Unité retirée', 'call.note': 'Note du dispatch',
        'call.edit': 'Intervention modifiée', 'call.dispatch': 'Intervention créée (dispatch)', 'incident.dispatch': 'Incident créé (dispatch)',
        'call.create': 'Intervention créée (jeu)', 'incident.create': 'Incident déclaré (jeu)', 'call.delete': 'Intervention supprimée (jeu)',
        'unit.status': 'Statut d\'unité changé', 'unit.create': 'Unité créée (jeu)', 'unit.delete': 'Unité supprimée (jeu)',
        'web.login': 'Connexion au panel', 'web.logout': 'Déconnexion', 'web.denied': 'Connexion refusée (rôle)', 'web.revoked': 'Accès retiré (rôle)',
        'live.view': 'LiveView : écran consulté',
    };

    const state = {
        me: null, csrf: '', station: '', calls: [], units: [], conversations: [], observe: [], dispatch: null, fivem: { online: false },
        presence: [], positions: {}, players: [], liveAvailable: false, editing: {},
        view: 'dashboard', callFilter: 'active', kbIndex: -1, drawerId: null, drawerCall: null, editMode: false, editBase: null,
        chat: null, chatMessages: [], chatCat: 'civil', observeOn: false, historyPage: 1, logPage: 1,
        soundOn: store.get('mdc.sound', true), unitSort: store.get('mdc.unitSort', { key: 'status', dir: 1 }),
        searchType: 'identity', searchResults: [],
    };

    // ---------------- outils ----------------
    const nowS = () => Math.floor(Date.now() / 1000);
    const pad = (n) => String(n).padStart(2, '0');
    const fmtTime = (t) => { const d = new Date(t * 1000); return `${pad(d.getHours())}:${pad(d.getMinutes())}`; };
    const fmtDate = (t) => { if (!t) return '—'; const d = new Date(t * 1000); return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}`; };
    const fmtShort = (t) => { if (!t) return ''; const d = new Date(t * 1000); const today = new Date(); return d.toDateString() === today.toDateString() ? fmtTime(t) : `${pad(d.getDate())}/${pad(d.getMonth() + 1)}`; };
    const age = (t) => {
        const s = Math.max(0, nowS() - t);
        if (s < 60) return `${s} s`;
        if (s < 3600) return `${Math.floor(s / 60)} min`;
        return `${Math.floor(s / 3600)} h ${pad(Math.floor((s % 3600) / 60))}`;
    };
    const norm = (v) => String(v ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
    const prioChip = (p) => (PRIORITY[p] ? `<span class="chip ${PRIO_TONE[p] || ''}" title="${esc(PRIORITY_MEANING[p] || '')}">${esc(PRIORITY[p])}</span>` : '<span class="muted">—</span>');
    const statusChip = (s) => `<span class="chip ${STATUS_TONE[s] || ''}">${esc(CALL_STATUS[s] || s)}</span>`;
    const unitTone = { available: 'go', en_route: 'caution', on_scene: 'accent', unavailable: 'steel' };
    const unitChip = (s) => `<span class="chip ${unitTone[s] || ''}">${esc(UNIT_STATUS[s] || s)}</span>`;
    const agencyChips = (list) => (list || []).map((a) => `<span class="chip agency ${esc(a)}">${esc(AGENCY[a] || String(a).toUpperCase())}</span>`).join(' ');
    const unitLabel = (u) => `${u.tag ? `<span class="tag">${esc(u.tag)}</span> ` : ''}${esc(u.name)}`;
    const emptyState = (title, text, ic = 'inbox') => `<div class="empty">${icon(ic)}<b>${esc(title)}</b>${text ? `<span>${esc(text)}</span>` : ''}</div>`;
    const emptyRow = (cols, title, text) => `<tr><td colspan="${cols}" class="empty-cell">${emptyState(title, text)}</td></tr>`;
    const arr = (v) => (Array.isArray(v) ? v : v && typeof v === 'object' ? Object.values(v) : []);

    async function api(path, body, opts = {}) {
        const init = body === undefined ? { headers: { Accept: 'application/json' } }
            : { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': state.csrf }, body: JSON.stringify(body) };
        let res;
        try {
            res = await fetch(`/api${path}`, { credentials: 'same-origin', ...init });
        } catch (e) {
            if (!opts.quiet) toast('error', 'Réseau', 'Le site ne répond pas.');
            return null;
        }
        if (res.status === 401) { location.href = '/login'; return null; }
        const data = await res.json().catch(() => null);
        if (res.status === 409 && data && data.conflict) return data; // modification simultanée : géré par l'appelant
        if (!data || data.ok !== true) {
            if (body !== undefined && !opts.quiet) toast('error', 'Action refusée', (data && data.error) || `Erreur ${res.status}`);
            return null;
        }
        return data;
    }

    // ---------------- sons (générés : aucun fichier). UN seul son pour tous les messages ----------------
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
        call: () => tone([660, 880], 0.14, 0.04, 'triangle', 0.16),
        message: () => tone([740, 988], 0.12, 0.03),
        error: () => tone([220, 180], 0.18, 0.03, 'sawtooth', 0.08),
    };
    document.addEventListener('pointerdown', () => { if (audio && audio.state === 'suspended') audio.resume(); });
    function renderSound() {
        const b = $('#soundBtn');
        b.innerHTML = icon(state.soundOn ? 'sound' : 'mute');
        b.setAttribute('aria-pressed', state.soundOn ? 'true' : 'false');
        b.title = state.soundOn ? 'Sons : activés (cliquer pour couper)' : 'Sons : coupés (cliquer pour activer)';
    }
    $('#soundBtn').addEventListener('click', () => {
        state.soundOn = !state.soundOn;
        store.set('mdc.sound', state.soundOn);
        renderSound();
        if (state.soundOn) SOUND.message();
    });

    // ---------------- thème ----------------
    function renderTheme() {
        const day = document.documentElement.dataset.theme === 'day';
        $('#themeBtn').innerHTML = icon(day ? 'moon' : 'sun');
        $('#themeBtn').title = day ? 'Passer au thème nuit' : 'Passer au thème jour (plein soleil)';
    }
    $('#themeBtn').addEventListener('click', () => {
        const day = document.documentElement.dataset.theme !== 'day';
        document.documentElement.dataset.theme = day ? 'day' : 'night';
        try { localStorage.setItem('mdc.theme', day ? 'day' : 'night'); } catch (e) { /* stockage indisponible */ }
        renderTheme();
    });

    // ---------------- notifications visuelles : interventions / incidents seulement (et retours d'actions) ----------------
    function toast(kind, title, text, onClick, duration = 6000) {
        const el = document.createElement('div');
        el.className = `toast ${kind}`;
        el.setAttribute('role', kind === 'error' ? 'alert' : 'status');
        el.innerHTML = `<b>${esc(title)}</b><div>${esc(text || '')}</div>`;
        el.addEventListener('click', () => { el.remove(); if (onClick) onClick(); });
        $('#toasts').prepend(el);
        while ($('#toasts').children.length > 5) $('#toasts').lastChild.remove();
        if (duration) setTimeout(() => el.remove(), kind === 'ok' ? Math.min(duration, 3500) : duration);
        if (kind === 'error') SOUND.error();
    }

    function updateTitle() {
        const awaiting = state.calls.filter((c) => c.status === 'awaiting').length;
        const unread = state.conversations.reduce((n, c) => n + (c.unread || 0), 0);
        const total = awaiting + unread;
        document.title = total ? `(${total}) King County Dispatch` : 'King County Dispatch';
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
        $('#modeLabel').textContent = `Mode dispatch : ${d.enabled ? 'actif' : 'inactif'}`;
        $('#modeHint').textContent = d.enabled
            ? (d.effective ? 'Les appels des civils attendent votre validation' : 'Activé, mais le jeu ne voit aucun dispatch en ligne')
            : 'Les appels partent directement aux unités';
        $('#indFivem').classList.toggle('on', !!state.fivem.online);
        $('#fivemBanner').classList.toggle('hidden', !!state.fivem.online);
        $('#indPlayers').textContent = typeof state.fivem.players === 'number' ? `${state.fivem.players} joueur(s)` : '';
        $('#indDispatchers').textContent = `${state.presence.length} poste(s)`;
        $('#station').textContent = state.station;
        $('#presenceList').innerHTML = `<b>Dispatch</b>${state.presence.length} poste(s) connecté(s)`;
    }

    $('#modeSwitch').addEventListener('click', async () => {
        const enable = !(state.dispatch && state.dispatch.enabled);
        if (!enable && state.calls.some((c) => c.status === 'awaiting')
            && !confirm('Des interventions attendent votre validation : en désactivant le mode Dispatch, elles partent directement aux unités. Continuer ?')) return;
        const res = await api('/dispatch/mode', { enabled: enable });
        if (res && res.dispatch) { state.dispatch = res.dispatch; renderHeader(); renderDashboard(); }
    });

    $('#logoutBtn').addEventListener('click', async () => {
        await fetch('/auth/logout', { method: 'POST', headers: { 'X-CSRF-Token': state.csrf }, credentials: 'same-origin' });
        location.href = '/login';
    });

    // ---------------- fenêtres ----------------
    function openModal(id) {
        $(id).classList.remove('hidden');
        const first = $(`${id} input, ${id} select, ${id} textarea, ${id} button`);
        if (first) first.focus();
    }
    function closeModal(el) {
        el.classList.add('hidden');
        if (el.id === 'newModal') state.newOpen = false;
    }
    $$('[data-close-modal]').forEach((b) => b.addEventListener('click', () => closeModal(b.closest('.modal'))));
    $$('.modal').forEach((m) => m.addEventListener('mousedown', (e) => { if (e.target === m) closeModal(m); }));
    $('#helpBtn').addEventListener('click', () => openModal('#helpModal'));

    // ---------------- navigation ----------------
    const VIEWS = ['dashboard', 'calls', 'units', 'messages', 'search', 'live', 'history', 'log'];
    function showView(view, push = true) {
        if (!VIEWS.includes(view)) view = 'dashboard';
        if (state.view === 'live' && view !== 'live') liveSync(); // flux en arrière-plan conservés (même liste)
        state.view = view;
        $$('.nav').forEach((b) => (b.dataset.view === view ? b.setAttribute('aria-current', 'page') : b.removeAttribute('aria-current')));
        $$('.view').forEach((v) => v.classList.toggle('hidden', v.id !== `view-${view}`));
        if (push && location.hash !== `#${view}`) history.replaceState(null, '', `#${view}`);
        if (view === 'history') loadHistory();
        if (view === 'log') loadLog();
        if (view === 'messages') { renderChatList(); if (state.observeOn) loadObserve(); }
        if (view === 'live') renderLive();
        if (view === 'search') $(state.searchType === 'vehicle' ? '#sQuery' : '#sLast').focus();
        renderAll();
        $('#main').scrollTop = 0;
    }
    $$('.nav').forEach((b) => b.addEventListener('click', () => showView(b.dataset.view)));
    document.addEventListener('click', (e) => { const g = e.target.closest('[data-goto]'); if (g) showView(g.dataset.goto); });

    // ---------------- raccourcis clavier ----------------
    document.addEventListener('keydown', (e) => {
        const field = e.target.closest('input, textarea, select, [contenteditable]');
        const typing = field && !(field.tagName === 'INPUT' && ['checkbox', 'radio', 'button', 'submit', 'range'].includes(field.type));
        if (e.key === 'Escape') {
            const modal = $$('.modal').find((m) => !m.classList.contains('hidden'));
            if (modal) { closeModal(modal); return; }
            if (state.liveFocus) { setLiveFocus(null); return; }
            if (state.editMode) { leaveEdit(); return; }
            if (state.drawerId) { closeDrawer(); return; }
            if (typing) e.target.blur();
            return;
        }
        if (typing || e.ctrlKey || e.metaKey || e.altKey) return;
        if ($$('.modal').some((m) => !m.classList.contains('hidden'))) return;
        const k = e.key;
        if (/^[1-8]$/.test(k)) { e.preventDefault(); showView(VIEWS[Number(k) - 1]); return; }
        if (k === 'n' || k === 'N') { e.preventDefault(); openNew('intervention'); return; }
        if (k === 'i' || k === 'I') { e.preventDefault(); openNew('incident'); return; }
        if (k === '?') { e.preventDefault(); openModal('#helpModal'); return; }
        if (k === '/') {
            e.preventDefault();
            const target = { calls: '#callsQ', units: '#unitsQ', messages: '#chatQ', search: '#sLast', live: '#liveQ', history: '#historyQ' }[state.view];
            if (target) $(target).focus(); else { showView('calls'); $('#callsQ').focus(); }
            return;
        }
        if ((k === 'e' || k === 'E') && state.drawerCall && !state.drawerCall.closed) { e.preventDefault(); enterEdit(); return; }
        if ((k === 'v' || k === 'V') && state.drawerCall && state.drawerCall.status === 'awaiting') { e.preventDefault(); drawerAction('validate'); return; }
        if (state.view === 'calls' && (k === 'j' || k === 'k' || k === 'Enter')) {
            const rows = $$('#callsBody tr[data-call]');
            if (!rows.length) return;
            e.preventDefault();
            if (k === 'Enter') { const r = rows[Math.max(0, state.kbIndex)]; if (r) openCall(Number(r.dataset.call)); return; }
            state.kbIndex = Math.max(0, Math.min(rows.length - 1, state.kbIndex + (k === 'j' ? 1 : -1)));
            rows.forEach((r, i) => r.classList.toggle('kb', i === state.kbIndex));
            rows[state.kbIndex].scrollIntoView({ block: 'nearest' });
        }
    });

    // ---------------- tableau de bord ----------------
    const counts = () => {
        const c = { awaiting: 0, pending: 0, ongoing: 0 };
        for (const x of state.calls) if (c[x.status] !== undefined) c[x.status] += 1;
        return c;
    };
    const ACTIVE = ['awaiting', 'pending', 'ongoing'];

    function callRow(c, cols) {
        return `<tr data-call="${c.id}" class="prio-${esc(c.priority)} status-${esc(c.status)} ${c.id === state.drawerId ? 'sel' : ''}">
            <td class="num">${esc(c.number)}</td>
            <td>${prioChip(c.priority)}${c.responseCode ? ` <span class="muted mono">C${esc(c.responseCode)}</span>` : ''}</td>
            <td><b>${esc(c.title)}</b>${c.kind === 'incident' ? ' <span class="tag">Incident</span>' : ''}${state.editing[c.id] ? ` <span class="chip caution plain" title="${esc(state.editing[c.id].join(', '))} modifie cette fiche">${icon('edit')}</span>` : ''}</td>
            <td>${esc(c.address)}${c.crossStreet ? `<span class="sub">× ${esc(c.crossStreet)}</span>` : ''}</td>
            ${cols.includes('block') ? `<td class="mono">${esc(c.block)}</td>` : ''}
            <td>${agencyChips(c.agency)}</td>
            <td>${c.units.map((u) => esc(u.name)).join(', ') || '<span class="muted">—</span>'}</td>
            <td>${statusChip(c.status)}</td>
            <td class="mono">${cols.includes('created') ? fmtTime(c.createdAt) : `<span data-age="${c.createdAt}">${age(c.createdAt)}</span>`}</td>
        </tr>`;
    }

    function positionHtml(unitId, compact) {
        const p = state.positions[unitId];
        if (!p || !p.street) return '<span class="muted">Position inconnue</span>';
        const stale = nowS() - (p.at || 0) > 120;
        return `<span class="pos ${stale ? 'stale' : ''}" title="${stale ? 'Position non mise à jour depuis plus de 2 min' : ''}"><b>${esc(p.street)}${p.block ? ` · bloc ${esc(p.block)}` : ''}</b>${compact ? '' : `<small>${p.crossing ? `× ${esc(p.crossing)} · ` : ''}${p.at ? `il y a <span data-age="${p.at}">${age(p.at)}</span>` : ''}</small>`}</span>`;
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
        $('#queueHint').textContent = d.effective ? 'appels des civils à valider' : 'mode Dispatch inactif';
        const queue = state.calls.filter((x) => x.status === 'awaiting').sort((a, b) => a.createdAt - b.createdAt);
        $('#dashQueue').innerHTML = queue.length ? queue.map((x) => `
            <div class="qcard" data-open="${x.id}">
                <div class="q-top"><span class="num">${esc(x.number)}</span>${prioChip(x.priority)}${x.responseCode ? `<span class="muted mono">C${esc(x.responseCode)}</span>` : ''}
                    <span class="q-title">${esc(x.title)}</span><span class="q-age" data-age="${x.createdAt}">${age(x.createdAt)}</span></div>
                <div class="q-meta">${esc(x.address)}${x.block ? ` · bloc ${esc(x.block)}` : ''} · ${agencyChips(x.agency)} · requérant ${esc(x.caller || '—')}</div>
                <div class="q-actions">
                    <button type="button" class="btn go small" data-quick="validate" data-id="${x.id}">${icon('check')}Valider</button>
                    <button type="button" class="btn small" data-open="${x.id}">Ouvrir</button>
                    <button type="button" class="btn stop small" data-quick="refuse" data-id="${x.id}">Refuser</button>
                </div>
            </div>`).join('') : emptyState('Aucun appel à valider', d.effective ? 'Les appels des civils apparaîtront ici.' : 'Activez le mode Dispatch pour valider les appels des civils.');
        const active = state.calls.filter((x) => ACTIVE.includes(x.status));
        $('#dashCalls').innerHTML = active.map((x) => callRow(x, [])).join('') || emptyRow(8, 'Aucune intervention active', 'Créez-en une avec N.');
        $('#dashUnits').innerHTML = connected.length ? connected.map((u) => `
            <div class="ucard">
                <div class="u-top">${unitLabel(u)} ${agencyChips([u.agency])}</div>
                <div class="u-pos">${positionHtml(u.id, true)}</div>
                <div class="u-meta">${u.members.map((m) => esc(m.name)).join(', ')}</div>
                ${statusSelect(u)}
            </div>`).join('') : emptyState('Aucune unité en service', 'Les unités apparaissent dès qu\'un agent rejoint une unité en jeu.', 'units');
    }

    function statusSelect(u) {
        return `<select class="status st-${esc(u.status)}" data-unit-status="${u.id}" aria-label="Statut de ${esc(u.name)}">
            ${Object.entries(UNIT_STATUS).map(([k, v]) => `<option value="${k}" ${k === u.status ? 'selected' : ''}>${esc(v)}</option>`).join('')}</select>`;
    }

    // ---------------- interventions ----------------
    function filteredCalls() {
        const f = state.callFilter;
        const q = norm($('#callsQ').value);
        const agency = $('#callsAgency').value;
        return state.calls.filter((x) => (f === 'active' ? ACTIVE.includes(x.status)
            : f === 'recent' ? ['closed', 'refused', 'cancelled'].includes(x.status) : x.status === f)
            && (!agency || (x.agency || []).includes(agency))
            && (!q || norm([x.number, x.title, x.address, x.crossStreet, x.block, x.caller].join(' ')).includes(q)));
    }
    function renderCalls() {
        const c = counts();
        $$('[data-count]').forEach((b) => { const n = c[b.dataset.count] || 0; b.textContent = n ? `(${n})` : ''; });
        const list = filteredCalls();
        $('#callsBody').innerHTML = list.map((x) => callRow(x, ['block', 'created'])).join('')
            || emptyRow(9, 'Aucune intervention', $('#callsQ').value ? 'Aucun résultat pour ce filtre.' : 'Rien dans cette liste pour le moment.');
        const rows = $$('#callsBody tr[data-call]');
        if (state.kbIndex >= rows.length) state.kbIndex = rows.length - 1;
        rows.forEach((r, i) => r.classList.toggle('kb', i === state.kbIndex));
    }
    $$('#callTabs button').forEach((t) => t.addEventListener('click', () => {
        state.callFilter = t.dataset.filter;
        state.kbIndex = -1;
        $$('#callTabs button').forEach((x) => x.setAttribute('aria-pressed', x === t ? 'true' : 'false'));
        renderCalls();
    }));
    $('#callsQ').addEventListener('input', () => { state.kbIndex = -1; renderCalls(); });
    $('#callsAgency').addEventListener('change', renderCalls);

    // ---------------- unités ----------------
    function unitSortValue(u, key) {
        const p = state.positions[u.id] || {};
        if (key === 'status') return UNIT_ORDER[u.status] ?? 9;
        if (key === 'street') return norm(p.street || '~');
        if (key === 'zone') return norm(p.zone || '~');
        if (key === 'since') return u.statusAt || 0;
        if (key === 'agency') return u.agency;
        return norm(u.name);
    }
    function renderUnits() {
        const onlyConnected = $('#unitsConnected').checked;
        const agency = $('#unitsAgency').value;
        const status = $('#unitsStatus').value;
        const sector = $('#unitsSector').value;
        const q = norm($('#unitsQ').value);
        // secteurs connus (zone géographique du PLD)
        const zones = [...new Set(state.units.map((u) => (state.positions[u.id] || {}).zone).filter(Boolean))].sort();
        const sel = $('#unitsSector');
        const current = sel.value;
        sel.innerHTML = `<option value="">Tous les secteurs</option>${zones.map((z) => `<option ${z === current ? 'selected' : ''}>${esc(z)}</option>`).join('')}`;
        const list = state.units.filter((u) => {
            const p = state.positions[u.id] || {};
            return (!onlyConnected || u.connected) && (!agency || u.agency === agency) && (!status || u.status === status)
                && (!sector || p.zone === sector)
                && (!q || norm([u.name, u.tag, p.street, p.crossing, p.block, p.zone, ...u.members.map((m) => m.name)].join(' ')).includes(q));
        });
        const { key, dir } = state.unitSort;
        list.sort((a, b) => {
            const x = unitSortValue(a, key);
            const y = unitSortValue(b, key);
            return (x < y ? -1 : x > y ? 1 : 0) * dir || norm(a.name).localeCompare(norm(b.name));
        });
        $$('#unitsTable th[data-sort]').forEach((th) => th.setAttribute('aria-sort', th.dataset.sort === key ? (dir > 0 ? 'ascending' : 'descending') : 'none'));
        const active = state.calls.filter((x) => ['pending', 'ongoing'].includes(x.status));
        $('#unitsBody').innerHTML = list.map((u) => {
            const p = state.positions[u.id] || {};
            return `<tr>
                <td><b>${unitLabel(u)}</b>${u.connected ? '' : '<span class="sub">hors service</span>'}</td>
                <td>${agencyChips([u.agency])}</td>
                <td>${u.members.map((m) => esc(m.name)).join('<br>') || '<span class="muted">—</span>'}</td>
                <td>${statusSelect(u)}</td>
                <td data-pos="${u.id}">${u.connected ? positionHtml(u.id) : '<span class="muted">—</span>'}</td>
                <td>${esc(p.zone || '') || '<span class="muted">—</span>'}</td>
                <td>${u.calls.map((c) => `<button type="button" class="linkish" data-open="${c.id}">${esc(c.number)}</button> <span class="sub">${esc(c.title)}</span>`).join('') || '<span class="muted">—</span>'}</td>
                <td class="mono"><span data-age="${u.statusAt}">${age(u.statusAt)}</span></td>
                <td><div class="toolbar tight">
                    <button type="button" class="btn small icon" data-chat="d:u:${u.id}" title="Écrire à ${esc(u.name)}">${icon('msg')}</button>
                    ${active.length ? `<select data-assign-unit="${u.id}" aria-label="Affecter ${esc(u.name)}"><option value="">Affecter à…</option>${active.filter((c) => !c.units.some((x) => x.id === u.id))
                        .map((c) => `<option value="${c.id}">${esc(c.number)} — ${esc(c.title)}</option>`).join('')}</select>` : ''}
                </div></td>
            </tr>`;
        }).join('') || emptyRow(9, 'Aucune unité', 'Aucune unité ne correspond à ces filtres.');
        const connected = state.units.filter((u) => u.connected).length;
        $('#navUnits').textContent = connected;
        $('#navUnits').classList.toggle('hidden', !connected);
    }
    ['#unitsConnected', '#unitsAgency', '#unitsStatus', '#unitsSector'].forEach((s) => $(s).addEventListener('change', renderUnits));
    $('#unitsQ').addEventListener('input', renderUnits);
    $$('#unitsTable th[data-sort]').forEach((th) => th.addEventListener('click', () => {
        const key = th.dataset.sort;
        state.unitSort = { key, dir: state.unitSort.key === key ? -state.unitSort.dir : 1 };
        store.set('mdc.unitSort', state.unitSort);
        renderUnits();
    }));
    function updatePosition(unitId) { // mise à jour ciblée (pas de rendu complet à chaque position)
        const cell = $(`#unitsBody [data-pos="${unitId}"]`);
        if (cell) cell.innerHTML = positionHtml(unitId);
        if (state.view === 'dashboard') renderDashboard();
    }

    // ---------------- fiche d'intervention ----------------
    async function openCall(id) {
        if (state.editMode && state.drawerId !== id && !confirm('Quitter la modification en cours sans l\'enregistrer ?')) return;
        if (state.drawerId !== id) leaveEdit(true);
        state.drawerId = id;
        $('#drawer').classList.remove('hidden');
        if (!state.drawerCall || state.drawerCall.id !== id) $('#drawerBody').innerHTML = '<div class="loading-bar"></div>';
        const res = await api(`/calls/${id}`);
        if (!res || state.drawerId !== id) return;
        state.drawerCall = res.call;
        renderDrawer();
        renderAll();
        markRead(`d:c:${id}`);
    }
    function closeDrawer() {
        if (state.editMode && !confirm('Quitter la modification en cours sans l\'enregistrer ?')) return;
        leaveEdit(true);
        state.drawerId = null;
        state.drawerCall = null;
        $('#drawer').classList.add('hidden');
        renderAll();
    }
    $('#drawerClose').addEventListener('click', closeDrawer);

    function othersEditing(id) {
        return (state.editing[id] || []).filter((s) => s !== state.station);
    }
    function editLockHtml() {
        const c = state.drawerCall;
        const others = c ? othersEditing(c.id) : [];
        if (!others.length) return '';
        return `<div class="warn-line edit-lock">${esc(others.join(', '))} modifie ${state.editMode ? 'aussi ' : ''}cette intervention en ce moment${state.editMode ? ' : la dernière modification enregistrée l\'emporte, vous serez prévenu' : ''}.</div>`;
    }
    function conflictHtml() {
        if (!state.editConflict) return '';
        return `<div class="error-line" role="alert"><b>Modifiée entre-temps</b> (autre poste ou unité en jeu) : vos valeurs ne sont pas encore enregistrées.
            <div class="toolbar tight"><button type="button" class="btn small stop" data-act="force">Enregistrer quand même mes valeurs</button><button type="button" class="btn small" data-act="reload">Reprendre les valeurs actuelles</button></div></div>`;
    }
    function updateEditBanners() {
        const lock = $('#editLock');
        if (lock) lock.innerHTML = editLockHtml();
        const conflict = $('#editConflict');
        if (conflict) conflict.innerHTML = conflictHtml();
    }

    function changesHtml(details) {
        return arr(details && details.changes).map((ch) => `<span class="change">${esc(ch.label || FIELD_LABEL[ch.field] || ch.field)} : `
            + `${ch.field === 'description' ? '<ins>modifiée</ins>' : `<del>${esc(fieldText(ch.field, ch.from) || '—')}</del> → <ins>${esc(fieldText(ch.field, ch.to) || '—')}</ins>`}</span>`).join('');
    }
    function fieldText(field, v) {
        if (field === 'priority') return PRIORITY[v] || v;
        if (field === 'agency') return String(v || '').split('+').map((a) => AGENCY[a] || a).join(' + ');
        if (field === 'responseCode') return v ? `Code ${v}` : '';
        return v;
    }

    function renderDrawer() {
        const c = state.drawerCall;
        if (!c) return;
        const open = !c.closed;
        $('#drawerTitle').innerHTML = `<div class="d-num">${esc(c.number)} · ${c.kind === 'incident' ? 'Incident' : 'Intervention'}</div>
            <div class="d-title">${esc(c.title)}</div>
            <div class="d-chips">${statusChip(c.status)} ${prioChip(c.priority)} ${agencyChips(c.agency)}${c.responseCode ? ` <span class="chip plain mono">Code ${esc(c.responseCode)}</span>` : ''}</div>`;
        if (state.editMode) { renderEditForm(); return; }
        // champs en cours de saisie gardés lors d'un nouveau rendu (mise à jour en temps réel)
        const keep = { note: $('#noteInput') && $('#noteInput').value, msg: $('#drawerMsg') && $('#drawerMsg').value,
            assign: $('#assignSelect') && $('#assignSelect').value, focus: document.activeElement && document.activeElement.id,
            picks: $$('[data-pick]:checked').map((x) => x.value) };
        const candidates = state.units.filter((u) => u.connected && ['kcso', 'wsp'].includes(u.agency) && !c.units.some((x) => x.id === u.id));
        const info = [
            ['Priorité', `${prioChip(c.priority)} <span class="muted">${esc(PRIORITY_MEANING[c.priority] || '')}</span>`],
            ['Code de réponse', c.responseCode ? esc(RESPONSE[c.responseCode]) : '—'],
            ['Requérant', `${esc(c.caller || '—')}${c.phone ? ` <span class="mono muted">${esc(c.phone)}</span>` : ''}`],
            ['Adresse', `${esc(c.address)}${c.crossStreet ? ` × ${esc(c.crossStreet)}` : ''}`], ['Bloc', `<span class="mono">${esc(c.block || '—')}</span>`],
            ...(c.sector ? [['Secteur', esc(c.sector)]] : []),
            ...(c.kind === 'intervention' ? [['Unités idéales', c.idealUnits ? esc(c.idealUnits) : '—']] : [['Déclaré par', esc(c.unitName || '—')]]),
            ['Créée', `${fmtDate(c.createdAt)} par ${esc(c.createdByName || '—')}`],
            ...(c.updatedAt ? [['Modifiée', `${fmtDate(c.updatedAt)} · version ${esc(c.rev)}`]] : []),
            ...(c.dispatch ? [['Dispatch', `${esc({ awaiting: 'En attente', validated: 'Validée', refused: 'Refusée', cancelled: 'Annulée' }[c.dispatch] || c.dispatch)}${c.dispatchBy ? ` par ${esc(c.dispatchBy)}` : ''}${c.dispatchReason ? ` — ${esc(c.dispatchReason)}` : ''}`]] : []),
            ...(c.closed ? [['Clôture', `${fmtDate(c.closedAt)} par ${esc(c.closedByName || '—')}${c.clear ? ` — ${esc(CLEAR[c.clear])}` : ''}`]] : []),
        ];
        const edits = c.log.filter((l) => l.action === 'call.edit');
        $('#drawerBody').innerHTML = `
            <div id="editLock">${editLockHtml()}</div>
            ${c.status === 'awaiting' ? `<div class="d-section"><h3>Unités à affecter en validant <span class="grow"></span><span class="muted">facultatif</span></h3>
                <div class="unit-pick">${candidates.map((u) => `<label class="check"><input type="checkbox" value="${u.id}" data-pick> ${esc(u.name)} ${unitChip(u.status)}</label>`).join('') || '<span class="muted">Aucune unité en service.</span>'}</div></div>` : ''}
            <div class="d-section"><h3>Informations</h3><dl class="info-grid">${info.map(([k, v]) => `<dt>${esc(k)}</dt><dd>${v}</dd>`).join('')}</dl></div>
            <div class="d-section"><h3>Description</h3><div class="desc">${esc(c.description || '—')}</div></div>
            <div class="d-section"><h3>Unités affectées <span class="muted">(${c.units.length})</span></h3>
                <div class="assigned">${c.units.map((u) => `<span>${unitLabel(u)} ${unitChip(u.status)}${open ? `<button type="button" title="Retirer de l'intervention" data-unassign="${u.id}">${icon('x')}</button>` : ''}</span>`).join('') || '<span class="muted">Aucune unité.</span>'}</div>
                ${open && c.status !== 'awaiting' ? `<div class="inline-form"><select id="assignSelect" aria-label="Unité à affecter"><option value="">Choisir une unité en service…</option>${candidates.map((u) => `<option value="${u.id}">${esc(u.name)} (${esc(AGENCY[u.agency] || u.agency)}) — ${esc(UNIT_STATUS[u.status])}${state.positions[u.id] && state.positions[u.id].street ? ` — ${esc(state.positions[u.id].street)}` : ''}</option>`).join('')}</select>
                    <button type="button" class="btn primary" data-act="assign">Affecter</button></div>` : ''}
            </div>
            ${c.links.length ? `<div class="d-section"><h3>Personnes et véhicules liés</h3>${c.links.map((l) => `<div>${l.kind === 'vehicle' ? 'Véhicule' : 'Identité'} : <b>${esc(l.label)}</b> <span class="muted">(${esc(l.addedBy)})</span></div>`).join('')}</div>` : ''}
            <div class="d-section"><h3>Déroulé et notes <span class="muted">(${c.notes.length})</span></h3>
                <div class="timeline">${c.notes.map((n) => `<div class="note ${n.dispatch ? 'dispatch' : ''}"><div class="note-head"><span>${esc(n.dispatch ? 'Dispatch' : `${n.unitName} — ${n.authorName}`)}</span><span class="mono">${fmtDate(n.createdAt)}</span></div><div class="note-text">${esc(n.text)}</div></div>`).join('') || '<span class="muted">Aucune note.</span>'}</div>
                ${open ? `<div class="inline-form"><input id="noteInput" maxlength="500" placeholder="Note du dispatch (visible en jeu dans l'intervention)" aria-label="Note"><button type="button" class="btn" data-act="note">Ajouter</button></div>` : ''}
            </div>
            ${c.status !== 'awaiting' ? `<div class="d-section"><h3>Messages avec les unités de ${esc(c.number)}</h3>
                <div class="chat-body" id="drawerChat">${c.messages.map(bubble).join('') || '<span class="muted">Aucun message.</span>'}</div>
                ${open ? `<div class="inline-form"><input id="drawerMsg" maxlength="300" placeholder="Message aux unités de l'intervention" aria-label="Message"><button type="button" class="btn primary" data-act="msg">Envoyer</button></div>` : ''}
            </div>` : ''}
            <div class="d-section"><h3>Historique des modifications <span class="muted">(${edits.length})</span></h3>
                ${edits.length ? edits.slice().reverse().map((l) => `<div class="history-item"><time>${fmtDate(l.at)}</time><div><b>${esc(l.actorName || 'Dispatch')}</b>${l.details && l.details.forced ? ' <span class="chip caution plain">écrasée après avertissement</span>' : ''}${changesHtml(l.details)}</div></div>`).join('') : '<span class="muted">Aucune modification depuis la création.</span>'}
            </div>
            ${c.log.length ? `<div class="d-section"><h3>Actions enregistrées</h3>${c.log.map((l) => `<div class="muted"><span class="mono">${fmtDate(l.at)}</span> — ${esc(ACTIONS[l.action] || l.action)} — ${esc(l.actorName)}</div>`).join('')}</div>` : ''}`;
        // pied : actions principales (1 clic)
        let foot = '';
        if (c.status === 'awaiting') {
            foot = `<button type="button" class="btn go" data-act="validate">${icon('check')}Valider et transmettre<span class="kbd">V</span></button>
                <button type="button" class="btn" data-act="edit">${icon('edit')}Modifier<span class="kbd">E</span></button>
                <span class="grow push"></span>
                <button type="button" class="btn stop" data-act="refuse">Refuser…</button>
                <button type="button" class="btn ghost" data-act="cancel">Annuler…</button>`;
        } else if (open) {
            const sheriff = (c.agency || []).includes('kcso'); // pas de Clear pour les interventions du shérif (KCSO)
            foot = `<button type="button" class="btn" data-act="edit">${icon('edit')}Modifier<span class="kbd">E</span></button>
                <span class="grow push"></span>
                ${sheriff ? '' : `<select id="clearSelect" aria-label="Code de clôture"><option value="">Clôturer sans code</option>${Object.entries(CLEAR).map(([k, v]) => `<option value="${k}">${esc(v)}</option>`).join('')}</select>`}
                <button type="button" class="btn" data-act="close">Clôturer</button>
                <button type="button" class="btn stop" data-act="cancel">Annuler…</button>`;
        }
        $('#drawerFoot').innerHTML = foot;
        $('#drawerFoot').classList.toggle('hidden', !foot);
        const chat = $('#drawerChat');
        if (chat) chat.scrollTop = chat.scrollHeight;
        if (keep.note && $('#noteInput')) $('#noteInput').value = keep.note;
        if (keep.msg && $('#drawerMsg')) $('#drawerMsg').value = keep.msg;
        if (keep.assign && $('#assignSelect')) $('#assignSelect').value = keep.assign;
        keep.picks.forEach((v) => { const el = $(`[data-pick][value="${v}"]`); if (el) el.checked = true; });
        if (keep.focus && $(`#${keep.focus}`)) $(`#${keep.focus}`).focus();
    }

    // ---- Modification d'une intervention (avant son envoi ou pendant son déroulement) ----
    function enterEdit() {
        const c = state.drawerCall;
        if (!c || c.closed) return;
        state.editMode = true;
        state.editBase = { rev: c.rev, values: editValues(c) };
        state.editConflict = null;
        socket && socket.emit('edit:start', c.id);
        renderDrawer();
        const first = $('#drawerBody input, #drawerBody select');
        if (first) first.focus();
    }
    function leaveEdit(silent) {
        if (!state.editMode) return;
        state.editMode = false;
        state.editBase = null;
        state.editConflict = null;
        socket && socket.emit('edit:stop');
        if (!silent) renderDrawer();
    }
    function editValues(c) {
        return { title: c.title, priority: c.priority, responseCode: c.responseCode ? String(c.responseCode) : '', agency: [...(c.agency || [])],
            address: c.address, crossStreet: c.crossStreet, block: c.block, sector: c.sector, caller: c.caller, phone: c.phone,
            idealUnits: c.idealUnits ? String(c.idealUnits) : '', description: c.description };
    }

    // Champs communs (création et modification) : kind = intervention / incident ; full = formulaire détaillé
    function callFormHtml(v, kind, full, prefix) {
        const kcso = (v.agency || []).includes('kcso');
        const prios = kcso ? KCSO_PRIORITIES : WSP_PRIORITIES;
        const f = (name) => `${prefix}-${name}`;
        const agencyBoxes = ['kcso', 'wsp'].map((a) => `<label class="check"><input type="checkbox" name="agency" value="${a}" ${(v.agency || []).includes(a) ? 'checked' : ''}> ${AGENCY[a]}</label>`).join(' ');
        return `<div class="form-grid ${full ? '' : 'quick'}">
            <label class="field span-2"><span>${kind === 'incident' ? 'Type d\'incident' : 'Type d\'intervention'} <b>*</b></span><input id="${f('title')}" name="title" maxlength="60" value="${esc(v.title || '')}" required placeholder="ex : Accident matériel, Cambriolage…"></label>
            <div class="field span-2"><span>Police <b>*</b></span><div class="toolbar tight" data-agency-box>${agencyBoxes}</div></div>
            ${kind === 'intervention' ? `
            <label class="field ${kcso ? '' : 'span-2'}"><span>Priorité <b>*</b></span><select name="priority" required><option value="">Choisir…</option>${prios.map((p) => `<option value="${p}" ${p === v.priority ? 'selected' : ''}>${esc(PRIORITY[p])}${PRIORITY_MEANING[p] ? ` — ${esc(PRIORITY_MEANING[p])}` : ''}</option>`).join('')}</select></label>
            ${kcso ? `<label class="field"><span>Code de réponse <b>*</b></span><select name="responseCode" required><option value="">Choisir…</option>${[1, 2, 3].map((n) => `<option value="${n}" ${String(n) === String(v.responseCode) ? 'selected' : ''}>${esc(RESPONSE[n])}</option>`).join('')}</select></label>` : ''}` : ''}
            <label class="field span-2"><span>Adresse <b>*</b></span><input name="address" maxlength="80" value="${esc(v.address || '')}" required></label>
            <label class="field"><span>Bloc <b>*</b></span><input name="block" maxlength="40" value="${esc(v.block || '')}" required></label>
            <div class="detail-only">
                <label class="field"><span>Croisement</span><input name="crossStreet" maxlength="80" value="${esc(v.crossStreet || '')}"></label>
                <label class="field"><span>Secteur</span><input name="sector" maxlength="40" value="${esc(v.sector || '')}"></label>
                ${kind === 'intervention' ? `
                <label class="field"><span>Requérant</span><input name="caller" maxlength="60" value="${esc(v.caller || '')}" placeholder="Dispatch (911)"></label>
                <label class="field"><span>Téléphone</span><input name="phone" maxlength="20" value="${esc(v.phone || '')}" placeholder="généré si vide"></label>
                <label class="field"><span>Unités idéales</span><input name="idealUnits" type="number" min="1" max="20" value="${esc(v.idealUnits || '')}" placeholder="1"></label>` : ''}
                <label class="field span-4"><span>Description</span><textarea name="description" rows="4" maxlength="2000">${esc(v.description || '')}</textarea></label>
            </div>
        </div>`;
    }
    function readForm(root, kind) {
        const val = (n) => { const el = root.querySelector(`[name="${n}"]`); return el ? el.value.trim() : undefined; };
        const out = { title: val('title'), address: val('address'), block: val('block'), crossStreet: val('crossStreet'), sector: val('sector'),
            description: val('description'), agency: $$('[name="agency"]:checked', root).map((x) => x.value) };
        if (kind === 'intervention') {
            out.priority = val('priority');
            out.responseCode = val('responseCode') || null;
            out.caller = val('caller');
            out.phone = val('phone');
            out.idealUnits = val('idealUnits');
        }
        Object.keys(out).forEach((k) => out[k] === undefined && delete out[k]);
        return out;
    }
    function bindAgencyRefresh(root, rerender) {
        root.addEventListener('change', (e) => { if (e.target.name === 'agency') rerender(); });
    }

    function renderEditForm() {
        const c = state.drawerCall;
        const v = state.editDraft || state.editBase.values;
        $('#drawerBody').innerHTML = `
            <div id="editLock">${editLockHtml()}</div>
            <div id="editConflict">${conflictHtml()}</div>
            <form class="d-section" id="editForm" novalidate>
                <h3>Modifier ${esc(c.number)} <span class="grow"></span><span class="muted">${c.status === 'awaiting' ? 'avant son envoi aux unités' : 'pendant l\'intervention'}</span></h3>
                ${callFormHtml(v, c.kind, true, 'edit')}
                <p class="form-note">Les unités de l'intervention sont prévenues par un son, et la modification apparaît dans son déroulé en jeu.</p>
            </form>`;
        $('#drawerFoot').innerHTML = `<button type="button" class="btn primary" data-act="save">${icon('check')}Enregistrer</button><button type="button" class="btn ghost" data-act="cancelEdit">Annuler</button>
            <span class="form-note push">Échap : annuler</span>`;
        $('#drawerFoot').classList.remove('hidden');
        const form = $('#editForm');
        bindAgencyRefresh(form, () => { state.editDraft = readForm(form, c.kind); renderEditForm(); });
        form.addEventListener('input', () => { state.editDraft = readForm(form, c.kind); });
        form.addEventListener('submit', (e) => { e.preventDefault(); saveEdit(false); });
    }

    async function saveEdit(force) {
        const c = state.drawerCall;
        const form = $('#editForm');
        if (!c || !form) return;
        const values = readForm(form, c.kind);
        // seuls les champs changés sont envoyés
        const base = state.editBase.values;
        const fields = {};
        for (const [k, v] of Object.entries(values)) {
            const before = k === 'agency' ? [...(base.agency || [])].sort().join('+') : String(base[k] ?? '');
            const after = k === 'agency' ? [...v].sort().join('+') : String(v ?? '');
            if (before !== after) fields[k] = v;
        }
        if (fields.priority !== undefined || fields.agency !== undefined) { // priorité / code liés à la police
            fields.priority = values.priority; fields.agency = values.agency;
            if (values.responseCode !== undefined) fields.responseCode = values.responseCode;
        }
        if (!Object.keys(fields).length) { leaveEdit(); return; }
        const res = await api(`/calls/${c.id}/edit`, { rev: state.editBase.rev, force, fields });
        if (!res) return;
        if (res.conflict) {
            state.editConflict = { rev: res.rev };
            state.editDraft = values;
            SOUND.error();
            const fresh = await api(`/calls/${c.id}`);
            if (fresh) state.drawerCall = fresh.call;
            renderDrawer();
            return;
        }
        toast('ok', c.number, res.unchanged ? 'Aucun changement.' : 'Intervention modifiée : unités prévenues.');
        state.editDraft = null;
        leaveEdit(true);
        state.editMode = false;
        const fresh = await api(`/calls/${c.id}`);
        if (fresh) state.drawerCall = fresh.call;
        renderDrawer();
    }

    async function drawerAction(act, btn) {
        const c = state.drawerCall;
        if (!c) return;
        if (btn) btn.disabled = true;
        try {
            if (act === 'validate') {
                const units = $$('[data-pick]:checked', $('#drawerBody')).map((x) => Number(x.value));
                if (await api(`/calls/${c.id}/validate`, { units })) toast('ok', c.number, 'Intervention validée et transmise.');
            } else if (act === 'refuse' || act === 'cancel') {
                const reason = await askReason(act === 'refuse' ? `Refuser ${c.number}` : `Annuler ${c.number}`,
                    act === 'refuse' ? 'Motif du refus (communiqué au civil qui a appelé, facultatif) :' : 'Motif de l\'annulation (communiqué aux unités, facultatif) :');
                if (reason !== null && await api(`/calls/${c.id}/${act}`, { reason })) toast('ok', c.number, act === 'refuse' ? 'Intervention refusée.' : 'Intervention annulée.');
            } else if (act === 'close') {
                const clear = $('#clearSelect') ? $('#clearSelect').value : '';
                if (await api(`/calls/${c.id}/close`, { clear })) toast('ok', c.number, 'Intervention clôturée.');
            } else if (act === 'assign') {
                const unitId = Number($('#assignSelect').value);
                if (!unitId) { toast('error', 'Affectation', 'Choisissez une unité.'); return; }
                if (await api(`/calls/${c.id}/assign`, { unitId })) toast('ok', c.number, 'Unité affectée.');
            } else if (act === 'note') {
                const text = $('#noteInput').value.trim();
                if (text && await api(`/calls/${c.id}/note`, { text })) $('#noteInput').value = '';
            } else if (act === 'msg') {
                const text = $('#drawerMsg').value.trim();
                if (text && await api('/messages', { channel: `d:c:${c.id}`, text })) $('#drawerMsg').value = '';
            } else if (act === 'edit') enterEdit();
            else if (act === 'save') await saveEdit(false);
            else if (act === 'force') await saveEdit(true);
            else if (act === 'reload') {
                const fresh = await api(`/calls/${c.id}`);
                if (fresh) state.drawerCall = fresh.call;
                state.editDraft = null;
                state.editConflict = null;
                state.editBase = { rev: state.drawerCall.rev, values: editValues(state.drawerCall) };
                renderDrawer();
            }
            else if (act === 'cancelEdit') { state.editDraft = null; leaveEdit(); }
        } finally {
            if (btn) btn.disabled = false;
        }
    }
    for (const id of ['#drawerBody', '#drawerFoot']) {
        $(id).addEventListener('click', async (e) => {
            const c = state.drawerCall;
            if (!c) return;
            const un = e.target.closest('[data-unassign]');
            if (un) { await api(`/calls/${c.id}/unassign`, { unitId: Number(un.dataset.unassign) }); return; }
            const b = e.target.closest('[data-act]');
            if (b) drawerAction(b.dataset.act, b);
        });
    }
    $('#drawerBody').addEventListener('keydown', (e) => {
        if (e.key !== 'Enter' || e.shiftKey) return;
        if (e.target.id === 'noteInput') { e.preventDefault(); drawerAction('note'); }
        if (e.target.id === 'drawerMsg') { e.preventDefault(); drawerAction('msg'); }
        if (e.ctrlKey && $('#editForm')) { e.preventDefault(); saveEdit(false); }
    });

    // Motif (fenêtre)
    function askReason(title, text) {
        return new Promise((resolve) => {
            $('#modalTitle').textContent = title;
            $('#modalText').textContent = text;
            $('#modalInput').value = '';
            openModal('#modal');
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

    // ---- Nouvelle intervention / nouvel incident (formulaire rapide ou détaillé) ----
    const draft = { kind: 'intervention', mode: store.get('mdc.newMode', 'quick'), values: { agency: ['kcso'] }, units: [] };
    function openNew(kind) {
        draft.kind = kind;
        draft.values = { agency: draft.values.agency || ['kcso'] };
        draft.units = [];
        state.newOpen = true;
        renderNew();
        openModal('#newModal');
        $('#newBody [name="title"]').focus();
    }
    function renderNew() {
        $('#newTitle').textContent = draft.kind === 'incident' ? 'Nouvel incident' : 'Nouvelle intervention';
        $$('[data-nkind]').forEach((b) => b.setAttribute('aria-pressed', b.dataset.nkind === draft.kind ? 'true' : 'false'));
        $$('[data-nmode]').forEach((b) => b.setAttribute('aria-pressed', b.dataset.nmode === draft.mode ? 'true' : 'false'));
        const candidates = state.units.filter((u) => u.connected && ['kcso', 'wsp'].includes(u.agency));
        $('#newBody').innerHTML = `${callFormHtml(draft.values, draft.kind, draft.mode === 'full', 'new')}
            <div class="d-section flush-section"><h3>Affecter tout de suite <span class="grow"></span><span class="muted">facultatif</span></h3>
                <div class="unit-pick" id="newUnits">${newUnitsHtml(candidates)}</div></div>
            ${draft.mode === 'quick' ? '<p class="form-note">Rapide : requérant « Dispatch (911) », 1 unité idéale, description = intitulé. Détaillé pour tout renseigner.</p>' : ''}`;
        $('#newSubmit').textContent = draft.kind === 'incident' ? 'Créer l\'incident' : 'Créer et transmettre';
    }
    function newUnitsHtml(candidates) {
        return candidates.map((u) => `<label class="check"><input type="checkbox" value="${u.id}" data-newunit ${draft.units.includes(u.id) ? 'checked' : ''}> ${esc(u.name)} ${unitChip(u.status)}</label>`).join('') || '<span class="muted">Aucune unité en service.</span>';
    }
    function renderNewUnits() {
        draft.units = $$('[data-newunit]:checked').map((x) => Number(x.value));
        const box = $('#newUnits');
        if (box) box.innerHTML = newUnitsHtml(state.units.filter((u) => u.connected && ['kcso', 'wsp'].includes(u.agency)));
    }
    function keepNewValues() {
        draft.values = { ...draft.values, ...readForm($('#newBody'), draft.kind) };
        draft.units = $$('[data-newunit]:checked').map((x) => Number(x.value));
    }
    $$('[data-nkind]').forEach((b) => b.addEventListener('click', () => { keepNewValues(); draft.kind = b.dataset.nkind; renderNew(); }));
    $$('[data-nmode]').forEach((b) => b.addEventListener('click', () => { keepNewValues(); draft.mode = b.dataset.nmode; store.set('mdc.newMode', draft.mode); renderNew(); }));
    $('#newBody').addEventListener('change', (e) => { if (e.target.name === 'agency') { keepNewValues(); renderNew(); } });
    $('#newForm').addEventListener('keydown', (e) => { if (e.key === 'Enter' && e.ctrlKey) { e.preventDefault(); $('#newForm').requestSubmit(); } });
    $('#newForm').addEventListener('submit', async (e) => {
        e.preventDefault();
        keepNewValues();
        const v = draft.values;
        const missing = [!v.title && 'intitulé', !(v.agency || []).length && 'police', !v.address && 'adresse', !v.block && 'bloc',
            draft.kind === 'intervention' && !v.priority && 'priorité', draft.kind === 'intervention' && (v.agency || []).includes('kcso') && !v.responseCode && 'code de réponse'].filter(Boolean);
        if (missing.length) { toast('error', 'Champs obligatoires', `À remplir : ${missing.join(', ')}.`); return; }
        $('#newSubmit').disabled = true;
        const body = { kind: draft.kind, title: v.title, address: v.address, block: v.block, crossStreet: v.crossStreet, sector: v.sector,
            description: v.description, agencies: v.agency, units: draft.units };
        if (draft.kind === 'intervention') Object.assign(body, { priority: v.priority, responseCode: v.responseCode || null, caller: v.caller, phone: v.phone, idealUnits: v.idealUnits });
        const res = await api('/calls', body);
        $('#newSubmit').disabled = false;
        if (!res) return;
        closeModal($('#newModal'));
        draft.values = { agency: v.agency };
        toast('ok', res.number, draft.kind === 'incident' ? 'Incident créé.' : 'Intervention créée et transmise aux unités.');
        openCall(res.id);
    });
    document.addEventListener('click', (e) => { const n = e.target.closest('[data-new]'); if (n) openNew(n.dataset.new); });

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
        if (openBtn && !e.target.closest('select')) { e.preventDefault(); openCall(Number(openBtn.dataset.open)); return; }
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

    // ---------------- messagerie : groupe civil, civils (privé, le joueur), unités ; observation ----------------
    const bubble = (m) => {
        const mine = m.senderType === 'dispatch';
        const who = mine ? 'Dispatch' : m.senderType === 'civil' ? `${m.author} · civil` : m.author;
        const today = new Date(m.at * 1000).toDateString() === new Date().toDateString();
        return `<div class="bubble ${mine ? 'mine' : ''}"><div class="b-meta"><b>${esc(who)}</b><time>${today ? fmtTime(m.at) : fmtDate(m.at)}</time></div><div class="b-text">${esc(m.text)}</div></div>`;
    };
    const catOf = (c) => (c.kind === 'civil' ? 'civil' : c.kind === 'private' ? 'private' : c.kind === 'unit' ? 'unit' : 'call');

    function renderChatList() {
        const q = norm($('#chatQ').value);
        // compteurs de non-lus par catégorie
        for (const cat of ['civil', 'private', 'unit']) {
            const n = state.conversations.filter((c) => catOf(c) === cat).reduce((s, c) => s + (c.unread || 0), 0);
            const el = $(`[data-catcount="${cat}"]`);
            el.textContent = n;
            el.classList.toggle('hidden', !n);
        }
        $$('#chatTabs [data-cat]').forEach((b) => b.setAttribute('aria-selected', !state.observeOn && b.dataset.cat === state.chatCat ? 'true' : 'false'));
        $('#observeToggle').classList.toggle('on', state.observeOn);
        $('#observeChk').checked = state.observeOn;
        let items;
        if (state.observeOn) {
            items = state.observe.filter((c) => !q || norm(c.label).includes(q) || norm(c.last && c.last.text).includes(q));
        } else {
            items = state.conversations.filter((c) => catOf(c) === state.chatCat && (!q || norm(c.label).includes(q) || norm(c.last && c.last.text).includes(q)));
            // tri par activité récente (non-lus d'abord à égalité)
            items.sort((a, b) => ((b.last ? b.last.at : 0) - (a.last ? a.last.at : 0)) || ((b.unread || 0) - (a.unread || 0)));
        }
        $('#chatList').innerHTML = items.map((c) => `
            <button type="button" class="conv ${c.unread ? 'unread' : ''}" data-conv="${esc(c.channel)}" role="option" ${state.chat === c.channel ? 'aria-current="true"' : ''}>
                <span class="conv-name">${c.kind === 'unit' ? `${unitLabel({ name: c.label, tag: c.tag })} ${agencyChips([c.agency])}` : esc(c.label)}
                    ${c.kind === 'private' ? `<span class="dot ${c.online ? 'go' : ''}" title="${c.online ? 'Connecté' : 'Hors ligne'}"></span>` : ''}
                    ${c.kind === 'unit' && !c.connected ? '<span class="muted">hors service</span>' : ''}</span>
                <span class="conv-time">${c.last ? fmtShort(c.last.at) : ''}</span>
                <span class="conv-last">${c.last ? `${c.last.senderType === 'dispatch' ? 'Vous : ' : `${esc(c.last.author)} : `}${esc(c.last.text)}` : (c.kind === 'private' ? 'Aucun message — écrivez-lui' : 'Aucun message')}</span>
                ${c.unread ? `<span class="count">${c.unread}</span>` : (c.count ? `<span class="count dim">${c.count}</span>` : '')}
            </button>`).join('') || emptyState(state.observeOn ? 'Aucune conversation entre unités' : 'Aucune conversation',
            state.observeOn ? '' : state.chatCat === 'private' ? 'Les civils connectés apparaissent ici, même sans message.' : '', 'msg');
        const unread = state.conversations.reduce((n, c) => n + (c.unread || 0), 0);
        $('#navUnread').textContent = unread;
        $('#navUnread').classList.toggle('hidden', !unread);
        updateTitle();
    }
    $('#chatList').addEventListener('click', (e) => { const b = e.target.closest('[data-conv]'); if (b) openChat(b.dataset.conv); });
    $('#chatQ').addEventListener('input', renderChatList);
    $$('#chatTabs [data-cat]').forEach((b) => b.addEventListener('click', () => {
        state.chatCat = b.dataset.cat;
        state.observeOn = false;
        renderChatList();
    }));
    $('#observeChk').addEventListener('change', () => {
        state.observeOn = $('#observeChk').checked;
        if (state.observeOn) loadObserve(); else renderChatList();
    });
    async function loadObserve() {
        const res = await api('/observe');
        if (res) state.observe = res.conversations;
        renderChatList();
    }

    async function openChat(channel) {
        const observing = /^u:\d+:\d+$/.test(channel);
        state.chat = channel;
        const conv = (observing ? state.observe : state.conversations).find((c) => c.channel === channel);
        if (!observing && conv && conv.kind !== 'call') state.chatCat = catOf(conv);
        $('#chatHead').innerHTML = observing
            ? `<b>${esc(conv ? conv.label : channel)}</b><span class="chip caution">Observation</span>`
            : `<b>${esc(conv ? (conv.kind === 'unit' ? `Unité ${conv.label}` : conv.label) : channel)}</b>${conv && conv.kind === 'private' ? `<span class="chip plain">conversation privée${conv.online ? ' · connecté' : ' · hors ligne'}</span>` : ''}${conv && conv.kind === 'civil' ? '<span class="chip plain">tous les civils</span>' : ''}`;
        $('#chatForm').classList.toggle('hidden', observing);
        $('#readonlyNote').classList.toggle('hidden', !observing);
        $('#chatBody').innerHTML = '<div class="loading-bar"></div>';
        const res = await api(`/messages?channel=${encodeURIComponent(channel)}`);
        if (!res || state.chat !== channel) return;
        state.chatMessages = res.messages;
        renderChat();
        renderChatList();
        if (!observing) { markRead(channel); $('#chatInput').focus(); } // observation : jamais marqué comme lu
    }
    function renderChat() {
        $('#chatBody').innerHTML = state.chatMessages.map(bubble).join('') || emptyState('Aucun message', 'Écrivez le premier.', 'msg');
        $('#chatBody').scrollTop = $('#chatBody').scrollHeight;
    }
    function markRead(channel) {
        const conv = state.conversations.find((c) => c.channel === channel);
        if (conv && conv.unread) api('/messages/read', { channel }, { quiet: true });
    }
    $('#chatForm').addEventListener('submit', async (e) => {
        e.preventDefault();
        const text = $('#chatInput').value.trim();
        if (!text || !state.chat || /^u:/.test(state.chat)) return;
        $('#chatInput').disabled = true;
        const ok = await api('/messages', { channel: state.chat, text });
        $('#chatInput').disabled = false;
        if (ok) $('#chatInput').value = '';
        $('#chatInput').focus();
    });
    $('#chatInput').addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); $('#chatForm').requestSubmit(); }
    });

    // ---------------- recherches (mêmes règles et fiches que le MDC en jeu) ----------------
    const CONDITION = { none: 'Aucune', wanted: 'Recherché', missing: 'Personne disparue', deceased: 'Personne décédée' };
    const LICENSE_STATUS = { valid: 'Valide', suspended: 'Suspension', revoked: 'Révocation', cancelled: 'Annulation', disqualified: 'Disqualification' };
    const REG_STATUS = { valid: 'Valide', invalid: 'Invalide', suspended: 'Suspendue' };
    const INSURANCE = { valid: 'Valide', invalid: 'Invalide', cancelled: 'Résiliée', none: 'Non assuré' };
    const RESTRICTION = { weapon: 'Port d\'arme', daylight: 'Conduite de jour uniquement', nointerstate: 'Interdiction de rouler sur Interstate' };
    const REGISTRY = { sex: 'Sex Offender', kidnap: 'Kidnapping Offender' };
    const REG_FOLLOW = { compliant: 'Conforme', noncompliant: 'Non conforme', absconded: 'En fuite' };
    const NATIONALITY = { US: 'Américaine', CA: 'Canadienne', USCA: 'Américaine et canadienne' };
    const CLASS = { M: 'Misdemeanor', GM: 'Gross misdemeanor', FC: 'Felony C', FB: 'Felony B', FA: 'Felony A' };

    $('#recordSheet').innerHTML = emptyState('Aucune fiche', 'Lancez une recherche puis choisissez un résultat.', 'search');
    $('#searchResults').innerHTML = emptyState('Pas encore de recherche', 'Nom + date de naissance, ou plaque / VIN.', 'search');
    $$('#searchTabs [data-stype]').forEach((t) => t.addEventListener('click', () => {
        state.searchType = t.dataset.stype;
        $$('#searchTabs [data-stype]').forEach((x) => x.setAttribute('aria-pressed', x === t ? 'true' : 'false'));
        $('#searchIdentity').classList.toggle('hidden', state.searchType !== 'identity');
        $('#searchVehicle').classList.toggle('hidden', state.searchType !== 'vehicle');
        $(state.searchType === 'vehicle' ? '#sQuery' : '#sLast').focus();
    }));
    $('#sDob').addEventListener('input', (e) => { // JJ/MM/AAAA tapé au clavier
        const d = e.target.value.replace(/\D/g, '').slice(0, 8);
        e.target.value = [d.slice(0, 2), d.slice(2, 4), d.slice(4)].filter(Boolean).join('/');
    });
    async function runSearch(params) {
        $('#searchResults').innerHTML = '<div class="loading-bar"></div>';
        const res = await api(`/search?${new URLSearchParams(params)}`);
        state.searchResults = res ? res.results : [];
        $('#searchCount').textContent = res ? `${state.searchResults.length} résultat(s)` : '';
        $('#searchResults').innerHTML = state.searchResults.map((r, i) => `
            <button type="button" class="result" data-result="${i}">
                ${r.kind === 'vehicle'
                    ? `<b class="mono">${esc(r.plate)}</b> — ${esc([r.make, r.model].filter(Boolean).join(' '))}${r.stolen ? ' <span class="chip stop">Volé</span>' : ''}<small>VIN ${esc(r.vin || '—')} · ${esc(REG_STATUS[r.regStatus] || r.regStatus || '')}</small>`
                    : `<b>${esc(String(r.lastname || '').toUpperCase())}</b> ${esc([r.firstname, r.middlename].filter(Boolean).join(' '))}${r.condition === 'wanted' ? ' <span class="chip stop">Recherché</span>' : ''}${arr(r.registrations).length ? ' <span class="chip accent">Registre</span>' : ''}<small>${esc(r.dob || '')} · ${esc(r.address || '')}</small>`}
            </button>`).join('') || (res ? emptyState('Aucun résultat', 'Vérifiez l\'orthographe et la date de naissance.', 'search') : '<div class="error-line">Recherche impossible (serveur FiveM ?).</div>');
        if (state.searchResults.length === 1) showRecord(state.searchResults[0]);
    }
    $('#searchIdentity').addEventListener('submit', (e) => {
        e.preventDefault();
        runSearch({ type: 'identity', lastname: $('#sLast').value.trim(), firstname: $('#sFirst').value.trim(), dob: $('#sDob').value.trim(), ssn: $('#sSsn').value.trim() });
    });
    $('#searchVehicle').addEventListener('submit', (e) => { e.preventDefault(); runSearch({ type: 'vehicle', query: $('#sQuery').value.trim() }); });
    $('#searchResults').addEventListener('click', (e) => {
        const b = e.target.closest('[data-result]');
        if (!b) return;
        $$('.result').forEach((x) => (x === b ? x.setAttribute('aria-current', 'true') : x.removeAttribute('aria-current')));
        showRecord(state.searchResults[Number(b.dataset.result)]);
    });
    $('#recordSheet').addEventListener('click', async (e) => {
        const b = e.target.closest('[data-record]');
        if (!b) return;
        const res = await api(`/records/${b.dataset.record}/${b.dataset.id}`);
        if (res) showRecord(res.record);
    });

    const dl = (rows) => `<dl class="info-grid">${rows.filter(([, v]) => v !== undefined && v !== null && v !== '').map(([k, v]) => `<dt>${esc(k)}</dt><dd>${v}</dd>`).join('')}</dl>`;
    const block = (title, html) => `<div class="sheet-block"><h4>${esc(title)}</h4>${html}</div>`;
    const bolosHtml = (r) => arr(r.bolos).map((b) => `<div class="alert">BOLO ${esc(b.number)} — ${esc(b.reason)}${b.possible ? ' (correspondance possible)' : ''}</div>`).join('');

    function showRecord(r) {
        if (!r) return;
        $('#recordSheet').innerHTML = r.kind === 'vehicle' ? vehicleSheet(r) : identitySheet(r);
    }

    function identitySheet(r) {
        const name = `${String(r.lastname || '').toUpperCase()} ${[r.firstname, r.middlename].filter(Boolean).join(' ')}`;
        const alerts = [
            r.condition === 'wanted' && `<div class="alert">PERSONNE RECHERCHÉE${r.wantedSince ? ` depuis le ${esc(r.wantedSince)}` : ''}${r.wantedReason ? ` — ${esc(r.wantedReason)}` : ''}</div>`,
            r.condition === 'missing' && '<div class="alert yellow">PERSONNE DISPARUE</div>',
            r.condition === 'deceased' && '<div class="alert yellow">PERSONNE DÉCÉDÉE</div>',
            ...arr(r.registrations).map((g) => `<div class="alert purple">${esc(REGISTRY[g.type] || g.type)} — niveau ${esc(g.level)} — ${esc(REG_FOLLOW[g.status] || g.status)} — inscription ${g.endDate === 'life' ? 'à vie' : `jusqu'au ${esc(g.endDate)}`}${g.lastUpdate ? ` — mise à jour ${esc(g.lastUpdate)}` : ''}</div>`),
        ].filter(Boolean).join('');
        const hasLicense = r.licenseClass && r.licenseClass !== 'N/A';
        const vehicles = arr(r.vehicles);
        const convictions = arr(r.convictions);
        const records = arr(r.records);
        const reports = arr(r.reports);
        return `
            <h3>${esc(name)}</h3>${alerts}${bolosHtml(r)}
            ${dl([['Date de naissance', `<span class="mono">${esc(r.dob)}</span>`], ['Sexe', esc({ M: 'Homme', F: 'Femme' }[r.sex] || '')],
                ['Nationalité', esc(NATIONALITY[r.nationality || 'US'] || r.nationality)], ['SSN', `<span class="mono">${esc(r.ssn)}</span>`], ['Adresse', esc(r.address)],
                ['Téléphone', `<span class="mono">${esc(r.phone)}</span>`], ['Emploi', esc(r.job)], ['Description physique', esc(r.physical)],
                ['Condition', esc(CONDITION[r.condition] || r.condition || 'Aucune')],
                ['Interdictions', esc(arr(r.restrictions).map((x) => RESTRICTION[x] || x).join(', ') || 'Aucune')]])}
            ${block('Permis de conduire', hasLicense ? dl([['Type', esc(r.licenseClass)], ['Condition', esc(LICENSE_STATUS[r.licenseStatus] || 'Valide')],
                ['N° de permis', `<span class="mono">${esc(r.licenseNumber)}</span>`], ['Délivré par', esc(r.licenseState)], ['Mentions', esc(arr(r.licenseEndorsements).join(', ') || 'Aucune')]])
                : '<span class="muted">Aucun permis de conduire.</span>')}
            ${block(`Véhicules (${vehicles.length})`, vehicles.map((v) => `<div class="entry"><button type="button" class="linkish" data-record="vehicle" data-id="${esc(v.id)}">${esc(v.plate)}</button> — ${esc([v.make, v.model].filter(Boolean).join(' '))}${v.color ? ` (${esc(v.color)})` : ''} · ${esc(REG_STATUS[v.regStatus] || '')}${v.stolen ? ' · <b>VOLÉ</b>' : ''}</div>`).join('') || '<span class="muted">Aucun véhicule.</span>')}
            ${block(`Casier judiciaire (${convictions.length + records.length})`, [
                ...convictions.map((c) => `<div class="entry"><b>${esc(CLASS[c.class] || c.class || '')}</b> — ${esc(c.label || c.offense)} <span class="muted">${esc(c.rcw || '')}</span><br><span class="muted">faits le ${esc(c.offenseDate || '—')}, jugement le ${esc(c.convictionDate || '—')}${c.sentence ? ` — ${esc(c.sentence)}` : ''}</span></div>`),
                ...records.map((x) => `<div class="entry">${esc(x.offense || '')} <span class="muted">(ancien antécédent ${esc(x.date || '')})</span></div>`),
            ].join('') || '<span class="muted">Casier vierge.</span>')}
            ${block(`Rapports (${reports.length})`, reports.map((x) => `<div class="entry"><b>${esc(x.label)}</b> <span class="mono">n°${esc(x.number)}</span>${x.callNumber ? ` — <span class="mono">${esc(x.callNumber)}</span>` : ''}<br><span class="muted">${esc(x.role || '')} — ${fmtDate(x.createdAt)} par ${esc(x.createdByName || '—')}</span>${x.summary ? `<br>${esc(x.summary)}` : ''}</div>`).join('') || '<span class="muted">Aucun rapport.</span>')}`;
    }

    function vehicleSheet(r) {
        const owner = r.ownerIdentity;
        const hist = arr(r.history);
        return `
            <h3 class="mono">${esc(r.plate)}</h3>
            ${r.stolen ? '<div class="alert">VÉHICULE VOLÉ</div>' : ''}${r.abandoned ? '<div class="alert yellow">VÉHICULE ABANDONNÉ</div>' : ''}${bolosHtml(r)}
            ${dl([['Statut', esc(REG_STATUS[r.regStatus] || r.regStatus || '')], ['Marque', esc(r.make)], ['Modèle', esc(r.model)],
                ['Année', esc(r.year)], ['Couleur', esc(r.color)], ['VIN', `<span class="mono">${esc(r.vin)}</span>`], ['Contrôle technique', esc(r.inspectionDate)],
                ['Usage', r.commercial ? 'Véhicule commercial' : 'Particulier'], ['Assurance', esc(INSURANCE[r.insuranceStatus] || r.insuranceStatus || '')],
                ['Police d\'assurance', esc(r.insurancePolicy)], ['Compagnie', esc(r.insuranceCompany)],
                ['Propriétaire', owner ? `<button type="button" class="linkish" data-record="identity" data-id="${esc(owner.id)}">${esc(String(owner.lastname || '').toUpperCase())} ${esc(owner.firstname || '')}</button> (${esc(owner.dob || '')})` : esc(r.ownerName || 'Non renseigné')]])}
            ${block(`Historique (${hist.length})`, hist.map((h) => `<div class="entry">${esc({ administrative: 'Infraction administrative', parking: 'Infraction de stationnement' }[h.type] || h.type || '')} — ${esc(h.date || '')}${h.offense ? ` — ${esc(h.offense)}` : ''}</div>`).join('') || '<span class="muted">Aucune infraction connue.</span>')}`;
    }

    // ---------------- LiveView ----------------
    // Liste affichée (ordre, épinglés, masqués) gardée dans ce navigateur ; les images ne sont jamais enregistrées.
    const live = {
        tiles: store.get('mdc.live.tiles', []), // [{ serverId, pinned, masked }]
        frames: {},                             // serverId -> { url, at, bytes, size, uploadMs, times: [] }
        selected: new Set(),
    };
    state.liveFocus = null;
    const saveTiles = () => store.set('mdc.live.tiles', live.tiles.map(({ serverId, pinned, masked }) => ({ serverId, pinned, masked })));
    const playerById = (id) => state.players.find((p) => p.serverId === id);
    const serviceOf = (p) => (p.agency === 'kcso' || p.agency === 'wsp' ? p.agency : p.agency === 'generic' ? 'generic' : 'none');
    const SERVICE_LABEL = { kcso: 'KCSO', wsp: 'WSP', generic: 'Civil', none: 'Sans MDC' };

    function orderedTiles() {
        return [...live.tiles].sort((a, b) => (b.pinned ? 1 : 0) - (a.pinned ? 1 : 0));
    }
    function liveSync() {
        if (!socket) return;
        // seuls les joueurs affichés, non masqués et connectés envoient des images ; agrandi = meilleure qualité
        const list = live.tiles.filter((t) => !t.masked && playerById(t.serverId))
            .map((t) => ({ serverId: t.serverId, mode: state.liveFocus === t.serverId ? 'focus' : 'grid' }));
        socket.emit('live:watch', list, (r) => {
            if (r && r.refused && r.refused.length) toast('error', 'LiveView', `Limite de flux atteinte : ${r.refused.length} joueur(s) non affiché(s).`);
        });
        $('#navLive').textContent = list.length;
        $('#navLive').classList.toggle('hidden', !list.length);
    }
    function renderLivePlayers() {
        const q = norm($('#liveQ').value);
        const service = $('#liveService').value;
        const unit = $('#liveUnit').value;
        const units = [...new Set(state.players.map((p) => p.unitName).filter(Boolean))].sort();
        const sel = $('#liveUnit');
        const cur = sel.value;
        sel.innerHTML = `<option value="">Toutes les unités</option>${units.map((u) => `<option ${u === cur ? 'selected' : ''}>${esc(u)}</option>`).join('')}`;
        const shown = new Set(live.tiles.map((t) => t.serverId));
        const list = state.players.filter((p) => (!service || serviceOf(p) === service) && (!unit || p.unitName === unit)
            && (!q || norm(`${p.name} ${p.serverId} ${p.unitName || ''}`).includes(q)));
        live.filtered = list;
        $('#livePlayers').innerHTML = list.map((p) => `
            <label class="lp"><input type="checkbox" data-lp="${p.serverId}" ${shown.has(p.serverId) ? 'checked' : ''} aria-label="Afficher ${esc(p.name)}">
                <span class="lp-name">${esc(p.name)}<small>ID ${p.serverId}${p.unitName ? ` · ${esc(p.unitName)}` : ''}</small></span>
                <span class="chip ${p.agency === 'kcso' ? 'go' : p.agency === 'wsp' ? 'caution' : 'steel'}">${esc(SERVICE_LABEL[serviceOf(p)])}</span></label>`).join('')
            || emptyState('Aucun joueur', state.players.length ? 'Aucun joueur pour ces filtres.' : 'Personne n\'est connecté en jeu.', 'live');
    }
    function tileHtml(t, focus) {
        const p = playerById(t.serverId);
        const f = live.frames[t.serverId];
        const fps = f && f.times.length > 1 ? (f.times.length - 1) / ((f.times[f.times.length - 1] - f.times[0]) / 1000) : 0;
        const ageMs = f ? Date.now() - f.at : null;
        const tone = !f ? '' : ageMs < 3500 ? 'go' : ageMs < 8000 ? 'caution' : 'stop';
        const screen = !p ? '<div class="placeholder">Joueur déconnecté</div>'
            : t.masked ? '<div class="placeholder">Masqué — aucune image envoyée</div>'
            : f ? `<img src="${f.url}" alt="Écran de ${esc(p.name)}">` : '<div class="placeholder">En attente de la première image…</div>';
        return `<div class="tile ${t.pinned ? 'pinned' : ''} ${t.masked ? 'masked' : ''}" data-tile="${t.serverId}" ${focus ? '' : 'draggable="true"'}>
            <div class="tile-head">
                ${focus ? '' : `<span class="grip" title="Glisser pour réorganiser">${icon('grip')}</span>`}
                <span class="t-name">${esc(p ? p.name : `Joueur ${t.serverId}`)}<small>#${t.serverId}${p && p.unitName ? ` · ${esc(p.unitName)}` : ''}</small></span>
                ${p ? `<span class="chip plain">${esc(SERVICE_LABEL[serviceOf(p)])}</span>` : ''}
                <button type="button" class="btn ghost small icon" data-tact="pin" title="${t.pinned ? 'Désépingler' : 'Épingler en tête'}" aria-pressed="${t.pinned}">${icon('pin')}</button>
                <button type="button" class="btn ghost small icon" data-tact="mask" title="${t.masked ? 'Réafficher' : 'Masquer (stoppe le flux)'}">${icon(t.masked ? 'eye' : 'eyeoff')}</button>
                <button type="button" class="btn ghost small icon" data-tact="focus" title="${focus ? 'Réduire (Échap)' : 'Agrandir'}">${icon(focus ? 'x' : 'expand')}</button>
                ${focus ? '' : `<button type="button" class="btn ghost small icon" data-tact="remove" title="Retirer de la vue">${icon('x')}</button>`}
            </div>
            <div class="tile-screen">${screen}</div>
            <div class="tile-foot" data-foot="${t.serverId}">${footHtml(t.serverId, f, fps, ageMs, tone)}</div>
        </div>`;
    }
    function footHtml(id, f, fps, ageMs, tone) {
        if (!f) return '<span class="muted">pas d\'image</span>';
        return `<span class="q"><span class="dot ${tone}"></span>${ageMs < 1000 ? 'direct' : `${(ageMs / 1000).toFixed(0)} s`}</span>
            <span title="Images par seconde reçues">${fps ? fps.toFixed(1) : '—'} i/s</span>
            <span title="Latence d'envoi du jeu vers le site">${f.uploadMs ? `${Math.round(f.uploadMs)} ms` : '— ms'}</span>
            <span title="Poids de la dernière image">${Math.round(f.bytes / 1024)} Ko</span>
            <span title="Résolution">${esc(f.size || '')}</span>`;
    }
    function renderLive() {
        if (state.view !== 'live') return;
        $('#liveUnavailable').classList.toggle('hidden', state.liveAvailable || !state.fivem.online);
        $('#liveUnavailable').textContent = 'LiveView indisponible : la ressource screenshot-basic n\'est pas démarrée sur le serveur FiveM.';
        renderLivePlayers();
        const tiles = orderedTiles();
        $('#liveGrid').innerHTML = tiles.map((t) => tileHtml(t, false)).join('')
            || emptyState('Aucun écran affiché', 'Cochez des joueurs à gauche, ou « Afficher la sélection ».', 'live');
        renderLiveFocus();
    }
    function renderLiveFocus() {
        let box = $('#liveFocus');
        if (!state.liveFocus) { if (box) box.remove(); return; }
        const t = live.tiles.find((x) => x.serverId === state.liveFocus);
        if (!t) { state.liveFocus = null; if (box) box.remove(); return; }
        if (!box) {
            box = document.createElement('div');
            box.id = 'liveFocus';
            box.className = 'live-focus';
            box.setAttribute('role', 'dialog');
            box.setAttribute('aria-label', 'Écran agrandi');
            document.body.appendChild(box);
        }
        box.innerHTML = tileHtml(t, true);
    }
    function setLiveFocus(id) {
        state.liveFocus = id;
        renderLiveFocus();
        liveSync();
    }
    function updateTileFrame(id) { // nouvelle image : seule l'image et le pied changent
        const f = live.frames[id];
        for (const tile of $$(`[data-tile="${id}"]`)) {
            const screen = tile.querySelector('.tile-screen');
            const img = screen.querySelector('img');
            if (img) img.src = f.url; else if (!tile.classList.contains('masked')) screen.innerHTML = `<img src="${f.url}" alt="Écran du joueur ${id}">`;
            const fps = f.times.length > 1 ? (f.times.length - 1) / ((f.times[f.times.length - 1] - f.times[0]) / 1000) : 0;
            tile.querySelector('.tile-foot').innerHTML = footHtml(id, f, fps, 0, 'go');
        }
    }
    setInterval(() => { // fraîcheur des images (indicateur)
        if (state.view !== 'live' && !state.liveFocus) return;
        for (const [id, f] of Object.entries(live.frames)) {
            const ageMs = Date.now() - f.at;
            const fps = f.times.length > 1 ? (f.times.length - 1) / ((f.times[f.times.length - 1] - f.times[0]) / 1000) : 0;
            const tone = ageMs < 3500 ? 'go' : ageMs < 8000 ? 'caution' : 'stop';
            $$(`[data-foot="${id}"]`).forEach((el) => { el.innerHTML = footHtml(Number(id), f, fps, ageMs, tone); });
        }
    }, 1000);

    $('#livePlayers').addEventListener('change', (e) => {
        const cb = e.target.closest('[data-lp]');
        if (!cb) return;
        const id = Number(cb.dataset.lp);
        if (cb.checked) { if (!live.tiles.some((t) => t.serverId === id)) live.tiles.push({ serverId: id, pinned: false, masked: false }); }
        else removeTile(id);
        saveTiles();
        renderLive();
        liveSync();
    });
    function removeTile(id) {
        live.tiles = live.tiles.filter((t) => t.serverId !== id);
        if (live.frames[id]) { URL.revokeObjectURL(live.frames[id].url); delete live.frames[id]; }
        if (state.liveFocus === id) state.liveFocus = null;
    }
    $('#liveAddAll').addEventListener('click', () => {
        for (const p of live.filtered || []) if (!live.tiles.some((t) => t.serverId === p.serverId)) live.tiles.push({ serverId: p.serverId, pinned: false, masked: false });
        saveTiles(); renderLive(); liveSync();
    });
    $('#liveClear').addEventListener('click', () => {
        for (const t of [...live.tiles]) removeTile(t.serverId);
        saveTiles(); renderLive(); liveSync();
    });
    ['#liveQ'].forEach((s) => $(s).addEventListener('input', renderLivePlayers));
    ['#liveService', '#liveUnit'].forEach((s) => $(s).addEventListener('change', renderLivePlayers));
    document.addEventListener('click', (e) => {
        const b = e.target.closest('[data-tact]');
        if (!b) return;
        const id = Number(b.closest('[data-tile]').dataset.tile);
        const t = live.tiles.find((x) => x.serverId === id);
        if (!t) return;
        const act = b.dataset.tact;
        if (act === 'pin') t.pinned = !t.pinned;
        if (act === 'mask') { t.masked = !t.masked; if (t.masked && live.frames[id]) { URL.revokeObjectURL(live.frames[id].url); delete live.frames[id]; } }
        if (act === 'remove') removeTile(id);
        if (act === 'focus') { setLiveFocus(state.liveFocus === id ? null : id); saveTiles(); renderLive(); return; }
        saveTiles();
        renderLive();
        liveSync();
    });
    // glisser-déposer : réorganisation de la mosaïque
    let dragId = null;
    $('#liveGrid').addEventListener('dragstart', (e) => {
        const tile = e.target.closest('[data-tile]');
        if (!tile) return;
        dragId = Number(tile.dataset.tile);
        tile.classList.add('dragging');
        e.dataTransfer.effectAllowed = 'move';
        e.dataTransfer.setData('text/plain', String(dragId));
    });
    $('#liveGrid').addEventListener('dragend', () => { dragId = null; $$('.tile').forEach((t) => t.classList.remove('dragging', 'drop-target')); });
    $('#liveGrid').addEventListener('dragover', (e) => {
        const tile = e.target.closest('[data-tile]');
        if (!tile || dragId === null) return;
        e.preventDefault();
        $$('.tile').forEach((t) => t.classList.toggle('drop-target', t === tile && Number(tile.dataset.tile) !== dragId));
    });
    $('#liveGrid').addEventListener('drop', (e) => {
        const tile = e.target.closest('[data-tile]');
        if (!tile || dragId === null) return;
        e.preventDefault();
        const to = Number(tile.dataset.tile);
        const from = live.tiles.findIndex((t) => t.serverId === dragId);
        const target = live.tiles.findIndex((t) => t.serverId === to);
        if (from < 0 || target < 0 || from === target) return;
        const [moved] = live.tiles.splice(from, 1);
        live.tiles.splice(target, 0, moved);
        saveTiles();
        renderLive();
    });

    function onLiveFrame(f) {
        if (!f || !f.data) return;
        const id = Number(f.serverId);
        const t = live.tiles.find((x) => x.serverId === id);
        if (!t || t.masked) return;
        const prev = live.frames[id];
        const url = URL.createObjectURL(new Blob([f.data], { type: 'image/jpeg' }));
        const times = prev ? prev.times.concat(Date.now()).slice(-8) : [Date.now()];
        live.frames[id] = { url, at: Date.now(), bytes: f.bytes, size: f.size, uploadMs: f.uploadMs, times };
        if (prev) setTimeout(() => URL.revokeObjectURL(prev.url), 1000);
        updateTileFrame(id);
    }

    // ---------------- historique ----------------
    const dateToS = (v, end) => (v ? Math.floor(new Date(`${v}T${end ? '23:59:59' : '00:00:00'}`).getTime() / 1000) : 0);
    async function loadHistory() {
        $('#historyBody').innerHTML = '<tr><td colspan="8" class="empty-cell"><div class="loading-bar"></div></td></tr>';
        const p = new URLSearchParams({ q: $('#historyQ').value.trim(), status: $('#historyStatus').value,
            from: dateToS($('#historyFrom').value), to: dateToS($('#historyTo').value, true), page: state.historyPage });
        const res = await api(`/history?${p}`);
        if (!res) { $('#historyBody').innerHTML = emptyRow(8, 'Historique indisponible', 'Réessayez dans un instant.'); return; }
        $('#historyBody').innerHTML = res.calls.map((c) => `
            <tr data-call="${c.id}" class="prio-${esc(c.priority)}">
                <td class="num">${esc(c.number)}</td><td>${prioChip(c.priority)}</td><td><b>${esc(c.title)}</b></td>
                <td>${esc(c.address)}</td><td>${agencyChips(c.agency)}</td><td>${statusChip(c.status)}</td>
                <td class="mono">${fmtDate(c.createdAt)}</td><td class="mono">${fmtDate(c.closedAt)}${c.clear ? ` <span class="muted">Clear ${esc(c.clear)}</span>` : ''}</td>
            </tr>`).join('') || emptyRow(8, 'Aucun résultat', 'Élargissez la période ou le filtre.');
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
        $('#logBody').innerHTML = '<tr><td colspan="5" class="empty-cell"><div class="loading-bar"></div></td></tr>';
        const res = await api(`/log?source=${$('#logSource').value}&page=${state.logPage}`);
        if (!res) { $('#logBody').innerHTML = emptyRow(5, 'Journal indisponible', ''); return; }
        const detail = (l) => {
            const d = l.details || {};
            const parts = [d.number, d.unit, d.title, d.name && `écran de ${d.name} (#${d.serverId})`, d.reason && `motif : ${d.reason}`,
                d.from && d.to && `${UNIT_STATUS[d.from] || d.from} → ${UNIT_STATUS[d.to] || d.to}`,
                d.clear && `Clear ${d.clear}`, Array.isArray(d.units) && d.units.length && `unités : ${d.units.join(', ')}`, d.count && `${d.count} appel(s)`,
                Array.isArray(d.changes) && d.changes.map((c) => c.label || c.field).join(', ')].filter(Boolean);
            return parts.map(esc).join(' — ');
        };
        $('#logBody').innerHTML = res.entries.map((l) => `
            <tr><td class="mono">${fmtDate(l.at)}</td><td><span class="chip plain">${esc({ dispatch: 'Dispatch', game: 'Jeu', web: 'Site' }[l.source] || l.source)}</span></td>
                <td>${esc(l.actorName || '—')}</td><td>${esc(ACTIONS[l.action] || l.action)}</td><td>${detail(l)}</td></tr>`).join('')
            || emptyRow(5, 'Journal vide', '');
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
        const connected = state.units.filter((u) => u.connected).length;
        $('#navUnits').textContent = connected;
        $('#navUnits').classList.toggle('hidden', !connected);
        $$('tr[data-call]').forEach((tr) => tr.classList.toggle('sel', Number(tr.dataset.call) === state.drawerId));
        updateTitle();
    }

    // ---------------- temps réel ----------------
    let socket = null;
    function connect() {
        socket = io({ withCredentials: true });
        socket.on('connect', () => { $('#indRealtime').classList.add('on'); refreshState().then(liveSync); });
        socket.on('disconnect', () => $('#indRealtime').classList.remove('on'));
        socket.on('connect_error', (err) => {
            $('#indRealtime').classList.remove('on');
            if (err && err.message === 'unauthorized') location.href = '/login';
        });
        socket.on('revoked', () => { location.href = '/denied?reason=role'; });
        socket.on('station', (s) => { state.station = s; renderHeader(); if (state.editMode && state.drawerId) socket.emit('edit:start', state.drawerId); });
        socket.on('calls', (calls) => {
            state.calls = calls;
            renderAll();
            if (state.drawerId && !state.editMode) refreshDrawer(); // (en modification : avertissement via « call:edited »)
        });
        socket.on('units', (units) => { state.units = units; renderAll(); if (state.drawerCall && !state.editMode) renderDrawer(); if (state.newOpen) renderNewUnits(); });
        socket.on('dispatch', (d) => { state.dispatch = d; renderAll(); });
        socket.on('fivem', (f) => { state.fivem = f; if (f.dispatch) state.dispatch = f.dispatch; renderAll(); if (state.view === 'live') renderLive(); });
        socket.on('presence', (p) => { state.presence = p; renderHeader(); });
        socket.on('conversations', (list) => { state.conversations = list; renderChatList(); });
        socket.on('positions', (map) => { state.positions = map || {}; if (state.view === 'units') renderUnits(); else if (state.view === 'dashboard') renderDashboard(); });
        socket.on('position', (p) => { state.positions[p.unitId] = p.location; updatePosition(p.unitId); });
        socket.on('players', (d) => {
            state.players = d.players || [];
            state.liveAvailable = !!d.liveview;
            if (state.view === 'live') renderLive();
            liveSync();
        });
        socket.on('editing', (map) => {
            state.editing = map || {};
            if (state.view === 'calls') renderCalls();
            updateEditBanners();
        });
        socket.on('call:edited', (d) => {
            if (state.drawerId === d.id && state.editMode && state.editBase && d.rev !== state.editBase.rev) {
                // modifiée ailleurs pendant ma modification : avertissement tout de suite (l'enregistrement le dirait aussi)
                state.editConflict = { rev: d.rev };
                updateEditBanners();
            }
        });
        socket.on('message', (m) => {
            if (state.chat === m.channel && !state.chatMessages.some((x) => x.id === m.id)) {
                state.chatMessages.push(m);
                renderChat();
                if (m.senderType !== 'dispatch' && state.view === 'messages') markRead(m.channel);
            }
            if (state.observeOn && /^u:/.test(m.channel || '')) loadObserve();
            if (state.drawerCall && m.channel === `d:c:${state.drawerCall.id}` && !state.editMode) refreshDrawer();
            // message reçu : SON SEUL (le même pour tous les messages), aucune notification visuelle
            if (m.senderType !== 'dispatch' && !(state.chat === m.channel && state.view === 'messages' && document.hasFocus())) SOUND.message();
        });
        socket.on('alert', (a) => {
            if (a.type === 'awaiting') {
                SOUND.awaiting();
                toast('awaiting', `Nouvelle intervention à valider — ${a.number}`, a.title || '', () => openCall(a.id), 0);
            } else if (a.type === 'new') {
                SOUND.call();
                toast('new', `${a.kind === 'incident' ? 'Nouvel incident' : 'Nouvelle intervention'} — ${a.number}`, a.title || '', () => openCall(a.id));
            }
        });
        socket.on('live:frame', onLiveFrame);
        socket.on('live:error', (e) => { if (state.view === 'live') { $('#liveUnavailable').textContent = e.error; $('#liveUnavailable').classList.remove('hidden'); } });
        socket.on('live:gone', (d) => { delete live.frames[d.serverId]; if (state.view === 'live') renderLive(); });
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
            dispatch: res.dispatch, presence: res.presence, positions: res.positions || {}, players: res.players || [], editing: res.editing || {} });
        const pl = await api('/players');
        if (pl) { state.players = pl.players; state.liveAvailable = !!pl.liveview; }
        renderAll();
        renderChatList();
        if (state.view === 'live') renderLive();
    }

    // ---------------- démarrage ----------------
    (async () => {
        renderSound();
        renderTheme();
        const me = await api('/me');
        if (!me) return;
        state.me = me.user;
        state.csrf = me.csrf;
        const start = location.hash.slice(1);
        showView(VIEWS.includes(start) ? start : 'dashboard', false);
        await refreshState();
        connect();
    })();
})();
