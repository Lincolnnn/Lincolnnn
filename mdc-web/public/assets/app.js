// =====================================================================================================================
// KING COUNTY DISPATCH — MDC Web 6 : console de dispatch (style CAD).
// Tableau : Unités (glisser une unité sur une intervention = l'affecter) · En attente · Actives ; panneau d'outil à
// droite (intervention, note de service, messagerie, recherche, registres, LiveView, terminées, journaux).
// Ligne de commande en haut (Ctrl + K). Lecture : API REST + temps réel (Socket.IO). Actions : API REST (CSRF),
// exécutées par le serveur FiveM. LiveView : vidéo WebRTC du jeu, signalisation par le site.
// =====================================================================================================================
(() => {
    'use strict';
    const $ = (s, root = document) => root.querySelector(s);
    const $$ = (s, root = document) => [...root.querySelectorAll(s)];
    const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
    const icon = (name) => `<svg class="i" aria-hidden="true"><use href="#i-${name}"/></svg>`;
    const store = {
        get(key, def) { try { const v = localStorage.getItem(key); return v === null ? def : JSON.parse(v); } catch (e) { return def; } },
        set(key, v) { try { localStorage.setItem(key, JSON.stringify(v)); } catch (e) { /* stockage indisponible */ } },
    };

    // ---------------- libellés (identiques au MDC en jeu) ----------------
    const PRIORITY = { px: 'Priorité X', k1: 'Priorité 1', k2: 'Priorité 2', k3: 'Priorité 3', k4: 'Priorité 4', k0: 'Priorité 0', nonurgent: 'Non urgent', p1: 'Priorité 1', p2: 'Priorité 2', p3: 'Priorité 3' };
    const PRIO_SHORT = { px: 'PX', k1: 'P1', k2: 'P2', k3: 'P3', k4: 'P4', k0: 'P0', nonurgent: 'NU', p1: 'P1', p2: 'P2', p3: 'P3' };
    const PRIORITY_MEANING = { px: 'Critique (danger de mort)', k1: 'Immédiat', k2: 'Rapide', k3: 'Routine', k4: 'Quand disponible', k0: '911 coupé sans info' };
    const PRIO_LEVEL = { px: 'crit', k1: 'crit', p1: 'crit', k2: 'high', p2: 'high', k3: 'mid', p3: 'mid', k4: 'low', k0: 'low', nonurgent: 'low' };
    const PRIO_RANK = { px: 0, k1: 1, p1: 1, k2: 2, p2: 2, k3: 3, p3: 3, k4: 4, nonurgent: 4, k0: 5 };
    const KCSO_PRIORITIES = ['px', 'k1', 'k2', 'k3', 'k4', 'k0'];
    const WSP_PRIORITIES = ['p1', 'p2', 'p3', 'nonurgent'];
    const RESPONSE = { 1: 'Code 1 — normal', 2: 'Code 2 — urgent, sans sirène', 3: 'Code 3 — urgent, gyrophares et sirène' };
    const CALL_STATUS = { awaiting: 'À valider', pending: 'Sans unité', ongoing: 'En cours', closed: 'Terminée', refused: 'Refusée', cancelled: 'Annulée' };
    const STATUS_TONE = { awaiting: 'stop', pending: 'caution', ongoing: 'go', closed: '', refused: 'stop', cancelled: '' };
    const UNIT_STATUS = { available: 'Disponible', en_route: 'En route', on_scene: 'Sur place', unavailable: 'Indisponible' };
    const UNIT_CODE = { available: 'DI', en_route: 'ER', on_scene: 'SP', unavailable: 'IN' };
    const CODE_STATUS = { DI: 'available', DISPO: 'available', AV: 'available', ER: 'en_route', ROUTE: 'en_route', EN: 'en_route', SP: 'on_scene', OS: 'on_scene', PLACE: 'on_scene', IN: 'unavailable', INDISPO: 'unavailable', UN: 'unavailable' };
    const CLEAR = { A: 'Clear A — Notice of Infraction (ticket)', B: 'Clear B — Arrestation, retenue ou criminal citation', C: 'Clear C — Warning' };
    const AGENCY = { kcso: 'KCSO', wsp: 'WSP', generic: 'Civil' };
    const KCSO_AREAS = { uninc: 'Non-incorporé', maplevalley: 'Maple Valley', kenmore: 'Kenmore' };
    const areasText = (list) => Object.keys(KCSO_AREAS).filter((k) => (list || []).includes(k)).map((k) => KCSO_AREAS[k]).join(', ');
    const FIELD_LABEL = { title: 'Intitulé', address: 'Adresse', crossStreet: 'Croisement', block: 'Bloc', sector: 'Secteur', description: 'Description',
        caller: 'Requérant', phone: 'Téléphone', priority: 'Priorité', responseCode: 'Code de réponse', idealUnits: 'Unités idéales', agency: 'Police', kcsoAreas: 'Secteur KCSO' };
    const KIND_LABEL = { identity: 'Identité', vehicle: 'Véhicule', report: 'Rapport', bolo: 'BOLO', call: 'Intervention', conversation: 'Conversation', note: 'Note de service' };
    const AUDIT_ACTION = { update: 'Modification', delete: 'Suppression', empty: 'Messages vidés', reopen: 'Réouverture', restore: 'Restauration', purge: 'Purge' };
    const ACTIONS = {
        'dispatch.enable': 'Mode Dispatch activé', 'dispatch.disable': 'Mode Dispatch désactivé', 'dispatch.release': 'Appels transmis automatiquement',
        'call.validate': 'Intervention validée', 'call.refuse': 'Intervention refusée', 'call.cancel': 'Intervention annulée', 'call.close': 'Intervention clôturée',
        'call.assign': 'Unité affectée', 'call.unassign': 'Unité retirée', 'call.note': 'Note du dispatch', 'call.edit': 'Intervention modifiée',
        'call.dispatch': 'Intervention créée (dispatch)', 'incident.dispatch': 'Incident créé (dispatch)', 'call.reopen': 'Intervention rouverte',
        'call.delete': 'Intervention supprimée', 'call.create': 'Intervention créée (jeu)', 'incident.create': 'Incident déclaré (jeu)',
        'unit.status': 'Statut d\'unité changé', 'unit.create': 'Unité créée (jeu)', 'unit.delete': 'Unité supprimée (jeu)', 'note.service': 'Note de service modifiée',
        'web.login': 'Connexion au panel', 'web.logout': 'Déconnexion', 'web.denied': 'Connexion refusée (rôle)', 'web.revoked': 'Accès retiré (rôle)', 'live.view': 'LiveView : écran consulté',
    };
    const CONDITION = { none: 'Aucune', wanted: 'Recherché', missing: 'Personne disparue', deceased: 'Personne décédée' };
    const LICENSE_STATUS = { valid: 'Valide', suspended: 'Suspension', revoked: 'Révocation', cancelled: 'Annulation', disqualified: 'Disqualification' };
    const REG_STATUS = { valid: 'Valide', invalid: 'Invalide', suspended: 'Suspendue' };
    const INSURANCE = { valid: 'Valide', invalid: 'Invalide', cancelled: 'Résiliée', none: 'Non assuré' };
    const RESTRICTION = { weapon: 'Port d\'arme', daylight: 'Conduite de jour uniquement', nointerstate: 'Interdiction de rouler sur Interstate' };
    const REGISTRY = { sex: 'Sex Offender', kidnap: 'Kidnapping Offender' };
    const REG_FOLLOW = { compliant: 'Conforme', noncompliant: 'Non conforme', absconded: 'En fuite' };
    const RISK = { 1: 'I — faible', 2: 'II — modéré', 3: 'III — élevé' };
    const NATIONALITY = { US: 'Américaine', CA: 'Canadienne', USCA: 'Américaine et canadienne' };
    const CLASS = { M: 'Misdemeanor', GM: 'Gross misdemeanor', FC: 'Felony C', FB: 'Felony B', FA: 'Felony A', TI: 'Traffic Infraction', CI: 'Civil Infraction' };
    const BOLO_KIND = { person: 'Individu', vehicle: 'Véhicule' };

    const state = {
        csrf: '', station: '', calls: [], units: [], conversations: [], observe: [], dispatch: null, fivem: { online: false },
        presence: [], positions: {}, players: [], editing: {}, serviceNote: { text: '', by: '', at: 0 },
        tool: store.get('mdc6.tool', 'call'), callId: null, call: null, editMode: false, editBase: null, editDraft: null, editConflict: null, noteFilter: 'all',
        unitAgency: store.get('mdc6.unitAgency', ''), closedGroups: store.get('mdc6.closedGroups', { off: true }),
        chat: null, chatMessages: [], chatCat: 'civil', observeOn: false, historyPage: 1, logPage: 1, auditPage: 1,
        soundOn: store.get('mdc.sound', true), searchType: 'identity', searchResults: [],
        reg: { tab: 'sex', list: [], sel: null, page: 1, total: 0, types: null }, seen: new Set(), svcEditing: false,
    };

    // ---------------- outils ----------------
    const nowS = () => Math.floor(Date.now() / 1000);
    const pad = (n) => String(n).padStart(2, '0');
    const fmtTime = (t) => { const d = new Date(t * 1000); return `${pad(d.getHours())}:${pad(d.getMinutes())}`; };
    const fmtDate = (t) => { if (!t) return '—'; const d = new Date(t * 1000); return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}`; };
    const fmtShort = (t) => { if (!t) return ''; const d = new Date(t * 1000); return d.toDateString() === new Date().toDateString() ? fmtTime(t) : `${pad(d.getDate())}/${pad(d.getMonth() + 1)}`; };
    const age = (t) => { const s = Math.max(0, nowS() - t); if (s < 60) return `${s}s`; if (s < 3600) return `${Math.floor(s / 60)}m ${pad(s % 60)}s`; return `${Math.floor(s / 3600)}h ${pad(Math.floor((s % 3600) / 60))}m`; };
    const norm = (v) => String(v ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
    const arr = (v) => (Array.isArray(v) ? v : v && typeof v === 'object' ? Object.values(v) : []);
    const prioChip = (p) => (PRIORITY[p] ? `<span class="chip ${PRIO_LEVEL[p] || 'low'}" title="${esc(PRIORITY[p])}${PRIORITY_MEANING[p] ? ` — ${esc(PRIORITY_MEANING[p])}` : ''}">${esc(PRIO_SHORT[p] || p)}</span>` : '');
    const statusChip = (s) => `<span class="chip ${STATUS_TONE[s] || ''}">${esc(CALL_STATUS[s] || s)}</span>`;
    const agencyChips = (list) => (list || []).map((a) => `<span class="chip ${esc(a)}">${esc(AGENCY[a] || String(a).toUpperCase())}</span>`).join(' ');
    const unitTag = (u, extra = '') => { const st = u.connected === false ? 'off' : u.status; return `<span class="ut ${esc(st)}" title="${esc(u.name)} — ${esc(u.connected === false ? 'hors service' : UNIT_STATUS[u.status] || u.status)}"><b>${esc(u.name)}</b><i>${esc(u.connected === false ? 'HS' : UNIT_CODE[u.status] || '?')}</i>${extra}</span>`; };
    const emptyState = (title, text) => `<div class="empty"><b>${esc(title)}</b>${text ? `<span>${esc(text)}</span>` : ''}</div>`;
    const skeleton = (n = 5) => `<div class="skel" aria-hidden="true">${'<i></i>'.repeat(n)}</div>`;
    const unitById = (id) => state.units.find((u) => u.id === Number(id));
    const callById = (id) => state.calls.find((c) => c.id === Number(id));

    async function api(path, body, opts = {}) {
        const init = body === undefined ? { headers: { Accept: 'application/json' } }
            : { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': state.csrf }, body: JSON.stringify(body) };
        let res;
        try { res = await fetch(`/api${path}`, { credentials: 'same-origin', ...init }); } catch (e) {
            if (!opts.quiet) toast('error', 'Réseau', 'Le site ne répond pas.');
            return null;
        }
        if (res.status === 401) { location.href = '/login'; return null; }
        const data = await res.json().catch(() => null);
        if (res.status === 409 && data && data.conflict) return data;
        if (!data || data.ok !== true) {
            if (!opts.quiet && (body !== undefined || opts.loud)) toast('error', 'Action refusée', (data && data.error) || `Erreur ${res.status}`);
            return null;
        }
        return data;
    }

    // ---------------- sons ----------------
    let audio = null;
    function tone(freqs, dur = 0.16, gap = 0.05, type = 'sine', vol = 0.18) {
        if (!state.soundOn) return;
        try {
            audio = audio || new (window.AudioContext || window.webkitAudioContext)();
            if (audio.state === 'suspended') audio.resume();
            let t = audio.currentTime;
            for (const f of freqs) {
                const o = audio.createOscillator(); const g = audio.createGain();
                o.type = type; o.frequency.value = f;
                g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(vol, t + 0.01); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
                o.connect(g); g.connect(audio.destination); o.start(t); o.stop(t + dur + 0.02);
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
        $('#soundBtn').innerHTML = icon(state.soundOn ? 'sound' : 'mute');
        $('#soundBtn').setAttribute('aria-pressed', state.soundOn ? 'true' : 'false');
        $('#soundBtn').title = state.soundOn ? 'Sons : activés' : 'Sons : coupés';
    }
    $('#soundBtn').addEventListener('click', () => { state.soundOn = !state.soundOn; store.set('mdc.sound', state.soundOn); renderSound(); if (state.soundOn) SOUND.message(); });

    // ---------------- notifications, confirmation, menu ----------------
    function toast(kind, title, text, onClick, duration = 6000, callId) {
        const el = document.createElement('div');
        if (callId) el.dataset.call = callId;
        el.className = `toast ${kind}`;
        el.setAttribute('role', kind === 'error' ? 'alert' : 'status');
        el.innerHTML = `<b>${esc(title)}</b><div>${esc(text || '')}</div>`;
        el.addEventListener('click', () => { el.remove(); if (onClick) onClick(); });
        $('#toasts').prepend(el);
        while ($('#toasts').children.length > 5) $('#toasts').lastChild.remove();
        if (duration) setTimeout(() => el.remove(), kind === 'ok' ? Math.min(duration, 3500) : duration);
        if (kind === 'error') SOUND.error();
    }
    /** Confirmation (et motif facultatif) : résout { value } ou null */
    function confirmBox({ title, text, ok = 'Confirmer', danger = true, input = false, placeholder = '' }) {
        return new Promise((resolve) => {
            const m = $('#confirmModal');
            $('#confirmTitle').textContent = title;
            $('#confirmText').innerHTML = text;
            $('#confirmInput').classList.toggle('hidden', !input);
            $('#confirmInput').value = '';
            $('#confirmInput').placeholder = placeholder;
            $('#confirmOk').textContent = ok;
            $('#confirmOk').className = `btn ${danger ? 'danger' : 'primary'}`;
            m.classList.remove('hidden');
            (input ? $('#confirmInput') : $('#confirmOk')).focus();
            const done = (v) => { m.classList.add('hidden'); $('#confirmForm').onsubmit = null; $('#confirmCancel').onclick = null; m.onkeydown = null; resolve(v); };
            $('#confirmForm').onsubmit = (e) => { e.preventDefault(); done({ value: $('#confirmInput').value.trim() }); };
            $('#confirmCancel').onclick = () => done(null);
            m.onkeydown = (e) => { if (e.key === 'Escape') { e.stopPropagation(); done(null); } };
        });
    }
    function menu(x, y, items) {
        const m = $('#menu');
        m.innerHTML = items.map((it, i) => (it.sep ? '<hr>' : it.title ? `<div class="m-title">${esc(it.title)}</div>`
            : `<button type="button" role="menuitem" data-mi="${i}" class="${it.danger ? 'danger' : ''}">${it.icon ? icon(it.icon) : ''}${esc(it.label)}</button>`)).join('');
        m.classList.remove('hidden');
        const r = m.getBoundingClientRect();
        m.style.left = `${Math.min(x, innerWidth - r.width - 8)}px`;
        m.style.top = `${Math.min(y, innerHeight - r.height - 8)}px`;
        m.onclick = (e) => { const b = e.target.closest('[data-mi]'); if (!b) return; hideMenu(); items[Number(b.dataset.mi)].action(); };
    }
    const hideMenu = () => $('#menu').classList.add('hidden');
    document.addEventListener('mousedown', (e) => { if (!e.target.closest('#menu')) hideMenu(); });
    window.addEventListener('blur', hideMenu);

    // ---------------- en-tête ----------------
    setInterval(() => {
        const d = new Date();
        $('#clock').textContent = `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
        $$('[data-age]').forEach((el) => { el.textContent = age(Number(el.dataset.age)); });
    }, 1000);
    function renderHeader() {
        const d = state.dispatch || {};
        $('#modeSwitch').setAttribute('aria-checked', d.enabled ? 'true' : 'false');
        $('#modeLabel').textContent = d.enabled ? 'Dispatch actif' : 'Dispatch inactif';
        $('#modeHint').textContent = d.enabled ? (d.effective ? 'Appels des civils à valider' : 'Actif, jeu sans poste en ligne') : 'Appels transmis directement';
        $('#indFivem').classList.toggle('on', !!state.fivem.online);
        $('#fivemBanner').classList.toggle('hidden', !!state.fivem.online);
        document.body.classList.toggle('banner-on', !state.fivem.online);
        $('#indPlayers').textContent = typeof state.fivem.players === 'number' ? `${state.fivem.players} joueur(s)` : '';
        $('#indDispatchers').textContent = `${state.presence.length} poste(s)`;
        $('#station').textContent = state.station;
    }
    $('#modeSwitch').addEventListener('click', async () => {
        const enable = !(state.dispatch && state.dispatch.enabled);
        if (!enable && state.calls.some((c) => c.status === 'awaiting')) {
            const ok = await confirmBox({ title: 'Désactiver le mode Dispatch', text: 'Des interventions attendent votre validation : elles partiront <b>directement aux unités</b>.', ok: 'Désactiver' });
            if (!ok) return;
        }
        const res = await api('/dispatch/mode', { enabled: enable });
        if (res && res.dispatch) { state.dispatch = res.dispatch; renderHeader(); renderBoard(); }
    });
    $('#logoutBtn').addEventListener('click', async () => {
        const ok = await confirmBox({ title: 'Déconnexion', text: 'Fermer votre session sur ce poste ?', ok: 'Se déconnecter', danger: false });
        if (!ok) return;
        await fetch('/auth/logout', { method: 'POST', headers: { 'X-CSRF-Token': state.csrf }, credentials: 'same-origin' });
        location.href = '/login';
    });
    $$('[data-close-modal]').forEach((b) => b.addEventListener('click', () => b.closest('.modal').classList.add('hidden')));
    $$('.modal').forEach((m) => m.addEventListener('mousedown', (e) => { if (e.target === m && m.id !== 'confirmModal') m.classList.add('hidden'); }));
    function updateTitle() {
        const awaiting = state.calls.filter((c) => c.status === 'awaiting').length;
        const unread = state.conversations.reduce((n, c) => n + (c.unread || 0), 0);
        document.title = awaiting + unread ? `(${awaiting + unread}) King County Dispatch` : 'King County Dispatch';
        setBadge('messages', unread);
    }
    function setBadge(tool, n) { const b = $(`[data-badge="${tool}"]`); if (b) { b.textContent = n > 99 ? '99+' : String(n); b.classList.toggle('hidden', !n); } }
    setInterval(() => { if (state.dispatch && state.dispatch.effective && state.calls.some((c) => c.status === 'awaiting' && nowS() - c.createdAt > 20)) SOUND.awaiting(); }, 20000);

    // =================================================================================================================
    // NOTE DE SERVICE : bandeau toujours visible + outil (lecture, modification). Commune au site et au jeu.
    // =================================================================================================================
    function renderServiceNote(flash) {
        const n = state.serviceNote || {};
        const t = $('#svcText');
        t.textContent = n.text ? n.text.replace(/\s*\n\s*/g, ' · ') : 'Aucune note de service. Cliquez sur « Modifier » pour en écrire une (visible par toutes les unités en jeu).';
        t.classList.toggle('empty', !n.text);
        t.title = n.text || '';
        $('#svcMeta').textContent = n.at ? `${n.by || '—'} · ${fmtDate(n.at)}` : '';
        if (flash) { const bar = $('#svcBar'); bar.classList.remove('flash'); void bar.offsetWidth; bar.classList.add('flash'); }
        if (state.tool === 'note' && !state.svcEditing) renderTool();
    }
    $('#svcEdit').addEventListener('click', () => { state.svcEditing = true; openTool('note'); });
    $('#svcText').addEventListener('click', () => openTool('note'));
    function noteToolHtml() {
        const n = state.serviceNote || {};
        if (state.svcEditing) {
            return `<form class="svc-editor" id="svcForm"><textarea id="svcInput" maxlength="1500" placeholder="Consignes, effectifs, secteurs à surveiller, événements prévus…">${esc(n.text || '')}</textarea>
                <p class="form-note">Affichée en haut de cette console et du MDC de police en jeu (toutes les unités KCSO et WSP). Les agents de police peuvent aussi la modifier en jeu.</p></form>`;
        }
        return `<div class="svc-view">${n.text ? esc(n.text) : '<span class="muted">Aucune note de service.</span>'}</div>
            <p class="form-note">${n.at ? `Dernière modification : ${esc(n.by || '—')}, le ${fmtDate(n.at)}.` : ''} Visible en jeu en haut du MDC de police.</p>`;
    }
    function noteToolFoot() {
        return state.svcEditing
            ? `<button type="button" class="btn primary" data-svc="save">${icon('check')}Enregistrer</button><button type="button" class="btn ghost" data-svc="cancel">Annuler</button><span class="grow"></span><span class="hint">Ctrl + Entrée</span>`
            : `<button type="button" class="btn primary" data-svc="edit">${icon('edit')}Modifier</button>${state.serviceNote.text ? '<button type="button" class="btn ghost" data-svc="clear">Effacer</button>' : ''}`;
    }
    async function saveServiceNote(text) {
        const res = await api('/service-note', { text });
        if (!res) return;
        state.svcEditing = false;
        if (res.note) state.serviceNote = res.note;
        renderServiceNote(false);
        renderTool();
        toast('ok', 'Note de service', res.unchanged ? 'Aucun changement.' : 'Enregistrée : visible en jeu par toutes les unités.');
    }

    // =================================================================================================================
    // TABLEAU : unités, en attente, actives
    // =================================================================================================================
    const ACTIVE = ['awaiting', 'pending', 'ongoing'];
    const prioRank = (c) => PRIO_RANK[c.priority] ?? (c.kind === 'incident' ? 2.5 : 6);

    function unitGroups() {
        const agency = state.unitAgency;
        const q = norm($('#unitsQ').value);
        const list = state.units.filter((u) => (!agency || u.agency === agency) && (!q || norm([u.name, u.tag, ...(u.members || []).map((m) => m.name),
            (state.positions[u.id] || {}).street, ...(u.calls || []).map((c) => c.number)].join(' ')).includes(q)));
        const groups = { available: [], busy: [], unavailable: [], off: [] };
        for (const u of list) {
            if (!u.connected) groups.off.push(u);
            else if (u.status === 'unavailable') groups.unavailable.push(u);
            else if (u.status === 'available' && !(u.calls || []).length) groups.available.push(u);
            else groups.busy.push(u);
        }
        const byName = (a, b) => norm(a.name).localeCompare(norm(b.name), 'fr', { numeric: true });
        Object.values(groups).forEach((g) => g.sort(byName));
        return groups;
    }
    const GROUP_LABEL = { available: 'Disponibles', busy: 'Affectées et occupées', unavailable: 'Indisponibles', off: 'Hors service' };
    function unitRow(u) {
        const p = state.positions[u.id] || {};
        const calls = u.calls || [];
        const who = calls.length ? calls.map((c) => `<span class="call-ref">${esc(c.number)} · ${esc(c.title)}</span>`).join('')
            : `<b>${esc((u.members || []).map((m) => m.name).join(', ') || (u.connected ? '' : 'aucun agent'))}</b>${p.street ? ` · ${esc(p.street)}` : ''}`;
        return `<div class="urow" draggable="${u.connected ? 'true' : 'false'}" data-unit="${u.id}" title="${esc(u.name)} — ${esc((u.members || []).map((m) => m.name).join(', ') || 'aucun agent')}${p.street ? ` — ${esc(p.street)}${p.crossing ? ` × ${esc(p.crossing)}` : ''}` : ''}">
            ${unitTag(u)}<span class="who">${who}</span>${u.connected ? `<time data-age="${u.statusAt}">${age(u.statusAt)}</time>` : '<time></time>'}</div>`;
    }
    function renderUnits() {
        const g = unitGroups();
        const connected = state.units.filter((u) => u.connected).length;
        $('#unitsCount').textContent = connected;
        $$('#unitsAgency [data-agency]').forEach((b) => b.setAttribute('aria-pressed', b.dataset.agency === state.unitAgency ? 'true' : 'false'));
        $('#unitsList').innerHTML = Object.entries(g).filter(([k, list]) => list.length || k !== 'off').map(([k, list]) => `
            <div class="ugroup ${state.closedGroups[k] ? 'closed' : ''}" data-group="${k}">
                <button type="button" class="ugroup-head" data-ugroup="${k}">${icon('chev')}${esc(GROUP_LABEL[k])}<span class="count">${list.length}</span></button>
                ${list.map(unitRow).join('') || (state.closedGroups[k] ? '' : '<div class="muted ugroup-empty">—</div>')}
            </div>`).join('') || emptyState('Aucune unité', 'Les unités créées en jeu apparaissent ici.');
    }
    $('#unitsAgency').addEventListener('click', (e) => { const b = e.target.closest('[data-agency]'); if (!b) return; state.unitAgency = b.dataset.agency; store.set('mdc6.unitAgency', state.unitAgency); renderUnits(); });
    $('#unitsQ').addEventListener('input', renderUnits);
    $('#unitsList').addEventListener('click', (e) => {
        const gh = e.target.closest('[data-ugroup]');
        if (gh) { state.closedGroups[gh.dataset.ugroup] = !state.closedGroups[gh.dataset.ugroup]; store.set('mdc6.closedGroups', state.closedGroups); renderUnits(); return; }
        const row = e.target.closest('[data-unit]');
        if (row) { const r = row.getBoundingClientRect(); unitMenu(unitById(row.dataset.unit), r.left + 40, r.bottom - 4); }
    });
    $('#unitsList').addEventListener('dblclick', (e) => { const row = e.target.closest('[data-unit]'); if (row) { openTool('messages'); openChat(`d:u:${row.dataset.unit}`); } });

    function unitMenu(u, x, y) {
        if (!u) return;
        const selected = state.call && !state.call.closed && state.call.status !== 'awaiting' && !state.call.units.some((v) => v.id === u.id) ? state.call : null;
        const players = state.players.filter((p) => p.unitId === u.id);
        menu(x, y, [
            { title: `${u.name} — ${u.connected ? UNIT_STATUS[u.status] : 'hors service'}` },
            ...(selected && u.connected ? [{ label: `Affecter à ${selected.number}`, icon: 'check', action: () => assign(selected.id, u.id) }] : []),
            ...(u.connected ? Object.entries(UNIT_STATUS).filter(([k]) => k !== u.status).map(([k, v]) => ({ label: `Statut : ${v}`, icon: 'units', action: () => setUnitStatus(u.id, k) })) : []),
            { sep: true },
            { label: `Écrire à ${u.name}`, icon: 'msg', action: () => { openTool('messages'); openChat(`d:u:${u.id}`); } },
            ...(u.calls || []).map((c) => ({ label: `Ouvrir ${c.number} — ${c.title}`, icon: 'call', action: () => openCall(c.id) })),
            ...players.map((p) => ({ label: `LiveView : ${p.name}`, icon: 'live', action: () => openPip(p.serverId) })),
        ]);
    }
    async function setUnitStatus(unitId, status) { if (await api(`/units/${unitId}/status`, { status })) toast('ok', unitById(unitId) ? unitById(unitId).name : 'Unité', `Statut : ${UNIT_STATUS[status]}.`); }
    async function assign(callId, unitId) {
        const c = callById(callId) || (state.call && state.call.id === callId ? state.call : null);
        const u = unitById(unitId);
        if (!c || !u) return;
        if (c.units.some((x) => x.id === u.id)) { toast('error', c.number, `${u.name} est déjà sur cette intervention.`); return; }
        if (c.status === 'awaiting') {
            if (await api(`/calls/${c.id}/validate`, { units: [u.id] })) toast('ok', c.number, `Validée et transmise à ${u.name}.`);
            return;
        }
        if (await api(`/calls/${c.id}/assign`, { unitId: u.id })) toast('ok', c.number, `${u.name} affectée.`);
    }

    // cartes d'intervention
    function cardHtml(c) {
        const editing = (state.editing[c.id] || []).filter((s) => s !== state.station);
        const fresh = !state.seen.has(c.id);
        const lvl = PRIO_LEVEL[c.priority] ? `p-${PRIO_LEVEL[c.priority]}` : (c.kind === 'incident' ? 'p-high' : 'p-low');
        const note = c.lastNote ? `${c.lastNote.by ? `${c.lastNote.by} : ` : ''}${c.lastNote.text}` : c.description;
        return `<article class="card ${lvl} ${c.status === 'awaiting' ? 'awaiting' : ''} ${c.id === state.callId ? 'sel' : ''} ${fresh ? 'fresh' : ''}" data-call="${c.id}" tabindex="0">
            <div class="c-top"><span class="c-num">${esc(c.number)}</span><span class="c-type">${esc(c.title)}</span><span class="grow"></span>
                ${c.status === 'awaiting' ? '<span class="chip draft">À VALIDER</span>' : ''}${c.kind === 'incident' ? '<span class="chip accent">INCIDENT</span>' : ''}${prioChip(c.priority)}${c.responseCode ? `<span class="chip">C${esc(c.responseCode)}</span>` : ''}</div>
            <div class="c-addr">${esc(c.address)}${c.block ? ` <span class="muted">· ${esc(c.block)}</span>` : ''}
                <small>${agencyChips(c.agency)}${(c.kcsoAreas || []).length ? ` ${esc(areasText(c.kcsoAreas))}` : ''} · <span data-age="${c.createdAt}">${age(c.createdAt)}</span>${c.caller ? ` · ${esc(c.caller)}` : ''}</small></div>
            ${c.units.length ? `<div class="c-units">${c.units.map((u) => unitTag({ ...u, connected: true })).join('')}</div>` : ''}
            ${note ? `<div class="c-note">${icon('note')}<span>${esc(note)}</span></div>` : ''}
            ${editing.length ? `<div class="c-editing">${icon('edit')} ${esc(editing.join(', '))} modifie cette fiche</div>` : ''}
            ${c.status === 'awaiting' ? `<div class="c-actions"><button type="button" class="btn xs go" data-quick="validate" data-id="${c.id}">${icon('check')}Valider</button>
                <button type="button" class="btn xs danger" data-quick="refuse" data-id="${c.id}">Refuser</button><span class="grow"></span><span class="hint">ou glissez une unité ici</span></div>` : ''}
        </article>`;
    }
    function renderPending() {
        const awaiting = state.calls.filter((c) => c.status === 'awaiting').sort((a, b) => a.createdAt - b.createdAt);
        const pending = state.calls.filter((c) => c.status === 'pending').sort((a, b) => prioRank(a) - prioRank(b) || a.createdAt - b.createdAt);
        $('#pendingCount').textContent = awaiting.length + pending.length;
        const d = state.dispatch || {};
        $('#pendingList').innerHTML = (awaiting.length ? `<div class="sep-label">À valider (dispatch) · ${awaiting.length}</div><div class="pending-list">${awaiting.map(cardHtml).join('')}</div>` : '')
            + (pending.length ? `<div class="sep-label">Sans unité · ${pending.length}</div><div class="pending-list">${pending.map(cardHtml).join('')}</div>` : '')
            || emptyState('Aucune intervention en attente', d.effective ? 'Les appels des civils à valider apparaissent ici.' : 'Nouvelle intervention : bouton ci-dessus ou touche N.');
    }
    function renderActive() {
        const sort = $('#activeSort').value; const agency = $('#activeAgency').value;
        const list = state.calls.filter((c) => c.status === 'ongoing' && (!agency || (c.agency || []).includes(agency)));
        list.sort(sort === 'recent' ? (a, b) => b.createdAt - a.createdAt : sort === 'old' ? (a, b) => a.createdAt - b.createdAt : (a, b) => prioRank(a) - prioRank(b) || a.createdAt - b.createdAt);
        $('#activeCount').textContent = list.length;
        $('#activeList').innerHTML = list.map(cardHtml).join('') || emptyState('Aucune intervention en cours', 'Glissez une unité sur une intervention en attente pour l\'affecter.');
    }
    ['#activeSort', '#activeAgency'].forEach((s) => $(s).addEventListener('change', () => { store.set(`mdc6.${s.slice(1)}`, $(s).value); renderActive(); }));
    $('#activeSort').value = store.get('mdc6.activeSort', 'prio'); $('#activeAgency').value = store.get('mdc6.activeAgency', '');
    function renderBoard() {
        renderUnits(); renderPending(); renderActive(); updateTitle();
        state.calls.forEach((c) => state.seen.add(c.id));
    }

    // glisser une unité sur une intervention = l'affecter (à valider : validée avec cette unité)
    let dragUnit = null;
    document.addEventListener('dragstart', (e) => {
        const row = e.target.closest && e.target.closest('.urow[data-unit]');
        if (!row) return;
        dragUnit = Number(row.dataset.unit);
        row.classList.add('dragging');
        e.dataTransfer.effectAllowed = 'copy';
        e.dataTransfer.setData('text/plain', `unit:${dragUnit}`);
    });
    document.addEventListener('dragend', () => { dragUnit = null; $$('.urow.dragging').forEach((r) => r.classList.remove('dragging')); $$('.card.drop').forEach((c) => c.classList.remove('drop')); });
    document.addEventListener('dragover', (e) => {
        if (dragUnit === null) return;
        const card = e.target.closest('.card[data-call]');
        $$('.card.drop').forEach((c) => { if (c !== card) c.classList.remove('drop'); });
        if (!card) return;
        e.preventDefault();
        e.dataTransfer.dropEffect = 'copy';
        card.classList.add('drop');
    });
    document.addEventListener('drop', (e) => {
        const card = e.target.closest('.card[data-call]');
        if (dragUnit === null || !card) return;
        e.preventDefault();
        const unitId = dragUnit;
        card.classList.remove('drop');
        assign(Number(card.dataset.call), unitId);
    });

    // clic sur une carte : fiche dans le panneau ; actions rapides
    document.addEventListener('click', async (e) => {
        const quick = e.target.closest('[data-quick]');
        if (quick) {
            const id = Number(quick.dataset.id);
            const c = callById(id);
            if (quick.dataset.quick === 'validate') { if (await api(`/calls/${id}/validate`, { units: [] })) toast('ok', c ? c.number : '', 'Intervention transmise aux unités.'); }
            else {
                const r = await confirmBox({ title: `Refuser ${c ? c.number : ''}`, text: 'Motif du refus (communiqué au civil, facultatif) :', input: true, ok: 'Refuser' });
                if (r && await api(`/calls/${id}/refuse`, { reason: r.value })) toast('ok', c ? c.number : '', 'Intervention refusée.');
            }
            return;
        }
        const card = e.target.closest('.card[data-call]');
        if (card && !e.target.closest('button, a, select, input')) { openCall(Number(card.dataset.call)); return; }
        const open = e.target.closest('[data-open]');
        if (open) { e.preventDefault(); openCall(Number(open.dataset.open)); }
    });
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && e.target.classList && e.target.classList.contains('card')) openCall(Number(e.target.dataset.call));
    });

    // =================================================================================================================
    // PANNEAU LATÉRAL : outils
    // =================================================================================================================
    const TOOLS = {
        call: { title: 'Intervention', render: renderCallTool },
        note: { title: 'Note de service', render: () => setSide(noteToolHtml(), noteToolFoot(), ''), after: () => { const t = $('#svcInput'); if (t) { t.focus(); t.setSelectionRange(t.value.length, t.value.length); } } },
        messages: { title: 'Messagerie', render: renderMessagesTool, flush: true },
        search: { title: 'Recherche', render: renderSearchTool },
        registries: { title: 'Registres', render: renderRegistriesTool, flush: true },
        live: { title: 'LiveView', render: renderLiveTool, flush: true, wide: true },
        history: { title: 'Terminées et historique', render: renderHistoryTool },
        log: { title: 'Journal des actions', render: renderLogTool },
        audit: { title: 'Journal d\'audit', render: renderAuditTool },
    };
    const TOOL_KEYS = Object.keys(TOOLS);
    function setSide(body, foot, meta) {
        $('#sideBody').innerHTML = body;
        $('#sideFoot').innerHTML = foot || '';
        $('#sideFoot').classList.toggle('hidden', !foot);
        if (meta !== undefined) $('#sideMeta').textContent = meta;
    }
    function openTool(tool) {
        if (!TOOLS[tool]) return;
        if (state.tool === 'call' && tool !== 'call' && state.editMode && !window.confirm('Quitter la modification en cours sans l\'enregistrer ?')) return;
        if (tool !== 'call' && state.editMode) leaveEdit(true);
        if (state.tool === 'note' && tool !== 'note') state.svcEditing = false;
        const was = state.tool;
        state.tool = tool;
        store.set('mdc6.tool', tool);
        $('#board').classList.remove('side-collapsed');
        if (was === 'live' && tool !== 'live') { $('#board').classList.remove('side-wide'); setTimeout(liveSync, 0); }
        renderTool();
        if (tool === 'live') liveSync();
    }
    function renderTool() {
        const t = TOOLS[state.tool] || TOOLS.call;
        $$('#rail [data-tool]').forEach((b) => b.setAttribute('aria-current', b.dataset.tool === state.tool ? 'true' : 'false'));
        $('#sideTitle').textContent = t.title;
        $('#sideMeta').textContent = '';
        $('#sideBody').classList.toggle('flush', !!t.flush);
        t.render();
        if (t.after) t.after();
    }
    $('#rail').addEventListener('click', (e) => {
        const b = e.target.closest('[data-tool]');
        if (b) { if (state.tool === b.dataset.tool && !$('#board').classList.contains('side-collapsed')) return; openTool(b.dataset.tool); return; }
        if (e.target.closest('#railCollapse')) { $('#board').classList.toggle('side-collapsed'); $('#board').classList.remove('side-wide'); liveSync(); }
    });
    $('#sideWide').addEventListener('click', () => { $('#board').classList.toggle('side-wide'); liveSync(); });
    // largeur du panneau : glisser son bord gauche (gardée dans ce navigateur)
    (function resizable() {
        const set = (w) => document.documentElement.style.setProperty('--side-w', `${Math.round(Math.max(340, Math.min(innerWidth * 0.6, w)))}px`);
        const saved = store.get('mdc6.sideW', 0);
        if (saved) set(saved);
        $('#sideResize').addEventListener('pointerdown', (e) => {
            e.preventDefault();
            const move = (ev) => set(innerWidth - ev.clientX - 46);
            const up = () => { removeEventListener('pointermove', move); removeEventListener('pointerup', up); store.set('mdc6.sideW', parseInt(getComputedStyle(document.documentElement).getPropertyValue('--side-w'), 10)); };
            addEventListener('pointermove', move); addEventListener('pointerup', up);
        });
    })();

    // délégation : boutons du panneau
    $('#sideFoot').addEventListener('click', (e) => sideClick(e));
    $('#sideBody').addEventListener('click', (e) => sideClick(e));
    async function sideClick(e) {
        const svc = e.target.closest('[data-svc]');
        if (svc) {
            const a = svc.dataset.svc;
            if (a === 'edit') { state.svcEditing = true; renderTool(); }
            if (a === 'cancel') { state.svcEditing = false; renderTool(); }
            if (a === 'save') await saveServiceNote($('#svcInput').value);
            if (a === 'clear') { const ok = await confirmBox({ title: 'Effacer la note de service', text: 'La note disparaît du site et du MDC de toutes les unités.', ok: 'Effacer' }); if (ok) await saveServiceNote(''); }
            return;
        }
        if (state.tool === 'call') return callClick(e);
        return null;
    }

    // =================================================================================================================
    // FICHE D'INTERVENTION : actions, modification (en cours, terminée…), notes, messages, suppression définitive
    // =================================================================================================================
    async function openCall(id) {
        if (state.editMode && state.callId !== id && !window.confirm('Quitter la modification en cours sans l\'enregistrer ?')) return;
        if (state.callId !== id) leaveEdit(true);
        state.callId = id;
        if (state.tool !== 'call') { state.tool = 'call'; store.set('mdc6.tool', 'call'); }
        $('#board').classList.remove('side-collapsed', 'side-wide');
        if (!state.call || state.call.id !== id) { state.call = null; renderTool(); $('#sideBody').innerHTML = skeleton(8); }
        $$('.card.sel').forEach((c) => c.classList.toggle('sel', Number(c.dataset.call) === id));
        $$(`.card[data-call="${id}"]`).forEach((c) => c.classList.add('sel'));
        const res = await api(`/calls/${id}`, undefined, { loud: true });
        if (!res || state.callId !== id) return;
        state.call = res.call;
        if (state.tool === 'call') renderTool();
        markRead(`d:c:${id}`);
    }
    const othersEditing = (id) => (state.editing[id] || []).filter((s) => s !== state.station);
    const fieldText = (field, v) => (field === 'kcsoAreas' ? areasText(String(v || '').split('+')) : field === 'priority' ? PRIORITY[v] || v : field === 'agency' ? String(v || '').split('+').map((a) => AGENCY[a] || a).join(' + ') : field === 'responseCode' ? (v ? `Code ${v}` : '') : v);
    const changesHtml = (details) => arr(details && details.changes).map((ch) => `<span class="change">${esc(ch.label || FIELD_LABEL[ch.field] || ch.field)} : ${ch.field === 'description' ? '<ins>modifiée</ins>'
        : `<del>${esc(fieldText(ch.field, ch.from) || '—')}</del> → <ins>${esc(fieldText(ch.field, ch.to) || '—')}</ins>`}</span>`).join('');
    function editLockHtml() {
        const others = state.call ? othersEditing(state.call.id) : [];
        return others.length ? `<div class="warn-line">${esc(others.join(', '))} modifie ${state.editMode ? 'aussi ' : ''}cette intervention en ce moment${state.editMode ? ' : la dernière modification enregistrée l\'emporte, vous serez prévenu' : ''}.</div>` : '';
    }
    const conflictHtml = () => (state.editConflict ? `<div class="error-line" role="alert"><b>Modifiée entre-temps</b> (autre poste ou unité en jeu) : vos valeurs ne sont pas encore enregistrées.
        <div class="row"><button type="button" class="btn sm danger" data-act="force">Enregistrer quand même</button><button type="button" class="btn sm" data-act="reload">Reprendre les valeurs actuelles</button></div></div>` : '');
    function updateEditBanners() {
        if ($('#editLock')) $('#editLock').innerHTML = editLockHtml();
        if ($('#editConflict')) $('#editConflict').innerHTML = conflictHtml();
    }
    function noteHtml(n) {
        const journal = n.unitName === 'JOURNAL';
        return `<div class="note ${n.dispatch ? 'dispatch' : ''} ${journal ? 'journal' : ''}"><div class="note-head"><span>${esc(journal ? `Journal — ${n.authorName}` : n.dispatch ? 'Dispatch' : `${n.unitName} — ${n.authorName}`)}</span><span>${fmtDate(n.createdAt)}</span></div><div class="note-text">${esc(n.text)}</div></div>`;
    }
    const bubble = (m) => {
        const mine = m.senderType === 'dispatch';
        const who = mine ? 'Dispatch' : m.senderType === 'civil' ? `${m.author} · civil` : m.author;
        const today = new Date(m.at * 1000).toDateString() === new Date().toDateString();
        return `<div class="bubble ${mine ? 'mine' : ''}"><div class="b-meta"><b>${esc(who)}</b><time>${today ? fmtTime(m.at) : fmtDate(m.at)}</time></div><div class="b-text">${esc(m.text)}</div></div>`;
    };

    function renderCallTool() {
        const c = state.call;
        if (!c) {
            setSide(state.callId ? skeleton(8) : emptyState('Aucune intervention choisie', 'Cliquez sur une carte du tableau, ou tapez son numéro dans la ligne de commande.'), '', '');
            return;
        }
        $('#sideTitle').textContent = c.kind === 'incident' ? 'Incident' : 'Intervention';
        $('#sideMeta').textContent = `${c.number} · ${CALL_STATUS[c.status] || c.status}`;
        if (state.editMode) { renderEditForm(); return; }
        const keep = { note: $('#noteInput') && $('#noteInput').value, msg: $('#drawerMsg') && $('#drawerMsg').value, assign: $('#assignSelect') && $('#assignSelect').value,
            focus: document.activeElement && document.activeElement.id, picks: $$('[data-pick]:checked').map((x) => x.value), scroll: $('#sideBody').scrollTop };
        const open = !c.closed;
        const candidates = state.units.filter((u) => u.connected && ['kcso', 'wsp'].includes(u.agency) && !c.units.some((x) => x.id === u.id));
        const info = [
            ['Priorité', c.priority ? `${prioChip(c.priority)} ${esc(PRIORITY[c.priority] || '')} <span class="muted">${esc(PRIORITY_MEANING[c.priority] || '')}</span>` : '—'],
            ['Code de réponse', c.responseCode ? esc(RESPONSE[c.responseCode]) : '—'],
            ['Adresse', `${esc(c.address)}${c.crossStreet ? ` × ${esc(c.crossStreet)}` : ''}`], ['Bloc', esc(c.block || '—')],
            ...((c.kcsoAreas || []).length ? [['Secteur KCSO', esc(areasText(c.kcsoAreas))]] : []),
            ...(c.sector ? [['Secteur', esc(c.sector)]] : []),
            ['Requérant', `${esc(c.caller || '—')}${c.phone ? ` <span class="muted">${esc(c.phone)}</span>` : ''}`],
            ...(c.kind === 'intervention' ? [['Unités idéales', c.idealUnits ? esc(c.idealUnits) : '—']] : [['Déclaré par', esc(c.unitName || '—')]]),
            ['Créée', `${fmtDate(c.createdAt)} par ${esc(c.createdByName || '—')}`],
            ...(c.updatedAt ? [['Modifiée', `${fmtDate(c.updatedAt)} · version ${esc(c.rev)}`]] : []),
            ...(c.closed ? [['Clôture', `${fmtDate(c.closedAt)} par ${esc(c.closedByName || '—')}${c.clear ? ` — ${esc(CLEAR[c.clear])}` : ''}`]] : []),
        ];
        const notes = c.notes.filter((n) => state.noteFilter === 'all' || (state.noteFilter === 'journal' ? n.unitName === 'JOURNAL' : n.unitName !== 'JOURNAL'));
        const edits = c.log.filter((l) => l.action === 'call.edit');
        const body = `
            <div class="d-head"><div class="d-num">${esc(c.number)} · ${c.kind === 'incident' ? 'Incident' : 'Intervention'}</div><div class="d-title">${esc(c.title)}</div>
                <div class="d-chips">${statusChip(c.status)} ${prioChip(c.priority)} ${agencyChips(c.agency)}</div></div>
            <div id="editLock">${editLockHtml()}</div>
            ${c.status === 'awaiting' ? `<div class="d-sec"><h3>Unités à affecter en validant <span class="grow"></span><span class="muted">facultatif</span></h3>
                <div class="unit-pick">${candidates.map((u) => `<label class="check"><input type="checkbox" value="${u.id}" data-pick> ${unitTag(u)}</label>`).join('') || '<span class="muted">Aucune unité en service.</span>'}</div></div>` : ''}
            <div class="d-sec"><h3>Unités affectées · ${c.units.length}</h3>
                <div class="assigned">${c.units.map((u) => `<span class="a-unit">${unitTag({ ...u, connected: true })}${open ? `<button type="button" title="Retirer de l'intervention" data-unassign="${u.id}">${icon('x')}</button>` : ''}</span>`).join('') || '<span class="muted">Aucune unité. Glissez une unité de la colonne Unités sur la carte.</span>'}</div>
                ${open && c.status !== 'awaiting' ? `<div class="inline-form"><select id="assignSelect" aria-label="Unité à affecter"><option value="">Affecter une unité en service…</option>${candidates.map((u) => `<option value="${u.id}">${esc(u.name)} (${esc(AGENCY[u.agency])}) — ${esc(UNIT_STATUS[u.status])}${state.positions[u.id] && state.positions[u.id].street ? ` — ${esc(state.positions[u.id].street)}` : ''}</option>`).join('')}</select>
                    <button type="button" class="btn primary" data-act="assign">Affecter</button></div>` : ''}</div>
            <div class="d-sec"><h3>Informations</h3><dl class="info">${info.map(([k, v]) => `<dt>${esc(k)}</dt><dd>${v}</dd>`).join('')}</dl></div>
            <div class="d-sec"><h3>Description</h3><div class="desc">${esc(c.description || '—')}</div></div>
            ${c.links.length ? `<div class="d-sec"><h3>Personnes et véhicules liés</h3>${c.links.map((l) => `<div>${l.kind === 'vehicle' ? 'Véhicule' : 'Identité'} : <b>${esc(l.label)}</b> <span class="muted">(${esc(l.addedBy)})</span></div>`).join('')}</div>` : ''}
            <div class="d-sec"><h3>Déroulé et notes <span class="grow"></span>
                <span class="seg small" role="group" aria-label="Filtre des notes">${[['all', 'Tout'], ['notes', 'Notes'], ['journal', 'Journal']].map(([k, l]) => `<button type="button" data-nf="${k}" aria-pressed="${state.noteFilter === k}">${l}</button>`).join('')}</span></h3>
                <div class="timeline">${notes.map(noteHtml).join('') || '<span class="muted">Rien pour ce filtre.</span>'}</div>
                <div class="inline-form"><input id="noteInput" maxlength="500" placeholder="Note du dispatch (visible en jeu)${c.closed ? ' — intervention terminée' : ''}" aria-label="Note"><button type="button" class="btn" data-act="note">Ajouter</button></div></div>
            ${c.status !== 'awaiting' ? `<div class="d-sec"><h3>Messages avec les unités</h3>
                <div class="chat-body call-chat" id="drawerChat">${c.messages.map(bubble).join('') || '<span class="muted">Aucun message.</span>'}</div>
                ${open ? `<div class="inline-form"><input id="drawerMsg" maxlength="300" placeholder="Message aux unités de l'intervention" aria-label="Message"><button type="button" class="btn primary" data-act="msg">Envoyer</button></div>` : ''}</div>` : ''}
            <div class="d-sec"><h3>Historique des modifications · ${edits.length}</h3>
                ${edits.length ? edits.slice().reverse().map((l) => `<div class="hist-item"><time>${fmtDate(l.at)}</time><div><b>${esc(l.actorName || 'Dispatch')}</b>${l.details && l.details.forced ? ' <span class="chip caution">écrasée après avertissement</span>' : ''}${changesHtml(l.details)}</div></div>`).join('') : '<span class="muted">Aucune modification depuis la création.</span>'}</div>`;
        let foot;
        if (c.status === 'awaiting') {
            foot = `<button type="button" class="btn go" data-act="validate">${icon('check')}Valider</button><button type="button" class="btn" data-act="edit">${icon('edit')}Modifier</button>
                <span class="grow"></span><button type="button" class="btn danger" data-act="refuse">Refuser…</button><button type="button" class="btn ghost" data-act="cancel">Annuler…</button>`;
        } else if (open) {
            const sheriff = (c.agency || []).includes('kcso');
            foot = `<button type="button" class="btn" data-act="edit">${icon('edit')}Modifier</button><span class="grow"></span>
                ${sheriff ? '' : `<select id="clearSelect" aria-label="Code de clôture"><option value="">Clôturer sans code</option>${Object.entries(CLEAR).map(([k, v]) => `<option value="${k}">${esc(v)}</option>`).join('')}</select>`}
                <button type="button" class="btn primary" data-act="close">Clôturer</button><button type="button" class="btn ghost" data-act="cancel">Annuler…</button>`;
        } else {
            foot = `<button type="button" class="btn" data-act="edit">${icon('edit')}Modifier</button><button type="button" class="btn go" data-act="reopen">${icon('reopen')}Rouvrir</button><span class="grow"></span>`;
        }
        foot += `<button type="button" class="ibtn" data-act="delete" title="Supprimer définitivement">${icon('trash')}</button>`;
        setSide(body, foot);
        const chat = $('#drawerChat');
        if (chat) chat.scrollTop = chat.scrollHeight;
        if (keep.note && $('#noteInput')) $('#noteInput').value = keep.note;
        if (keep.msg && $('#drawerMsg')) $('#drawerMsg').value = keep.msg;
        if (keep.assign && $('#assignSelect')) $('#assignSelect').value = keep.assign;
        keep.picks.forEach((v) => { const el = $(`[data-pick][value="${v}"]`); if (el) el.checked = true; });
        if (keep.focus && $(`#${keep.focus}`)) $(`#${keep.focus}`).focus();
        $('#sideBody').scrollTop = keep.scroll;
    }

    function editValues(c) {
        return { title: c.title, priority: c.priority, responseCode: c.responseCode ? String(c.responseCode) : '', agency: [...(c.agency || [])], kcsoAreas: [...(c.kcsoAreas || [])], address: c.address,
            crossStreet: c.crossStreet, block: c.block, sector: c.sector, caller: c.caller, phone: c.phone, idealUnits: c.idealUnits ? String(c.idealUnits) : '', description: c.description };
    }
    function enterEdit() {
        const c = state.call;
        if (!c) return;
        state.editMode = true;
        state.editBase = { rev: c.rev, values: editValues(c) };
        state.editConflict = null;
        if (socket) socket.emit('edit:start', c.id);
        renderTool();
        const first = $('#sideBody input, #sideBody select');
        if (first) first.focus();
    }
    function leaveEdit(silent) {
        if (!state.editMode) return;
        state.editMode = false; state.editBase = null; state.editConflict = null; state.editDraft = null;
        if (socket) socket.emit('edit:stop');
        if (!silent) renderTool();
    }
    function callFormHtml(v, kind, full) {
        const kcso = (v.agency || []).includes('kcso');
        const prios = kcso ? KCSO_PRIORITIES : WSP_PRIORITIES;
        return `<div class="form-grid ${full ? '' : 'quick'}">
            <label class="field"><span>${kind === 'incident' ? 'Type d\'incident' : 'Type d\'intervention'} <b>*</b></span><input name="title" maxlength="60" value="${esc(v.title || '')}" required placeholder="ex : Accident matériel"></label>
            <div class="field"><span>Police <b>*</b></span><div class="toolbar">${['kcso', 'wsp'].map((a) => `<label class="check"><input type="checkbox" name="agency" value="${a}" ${(v.agency || []).includes(a) ? 'checked' : ''}> ${AGENCY[a]}</label>`).join(' ')}</div></div>
            ${kcso ? `<div class="field span-2"><span>Secteur KCSO <b>*</b> <small class="muted">un ou plusieurs</small></span><div class="toolbar">${Object.entries(KCSO_AREAS).map(([k, l]) => `<label class="check"><input type="checkbox" name="kcsoAreas" value="${k}" ${(v.kcsoAreas || []).includes(k) ? 'checked' : ''}> ${esc(l)}</label>`).join(' ')}</div></div>` : ''}
            ${kind === 'intervention' ? `<label class="field"><span>Priorité <b>*</b></span><select name="priority" required><option value="">Choisir…</option>${prios.map((p) => `<option value="${p}" ${p === v.priority ? 'selected' : ''}>${esc(PRIORITY[p])}${PRIORITY_MEANING[p] ? ` — ${esc(PRIORITY_MEANING[p])}` : ''}</option>`).join('')}</select></label>
            ${kcso ? `<label class="field"><span>Code de réponse <b>*</b></span><select name="responseCode" required><option value="">Choisir…</option>${[1, 2, 3].map((n) => `<option value="${n}" ${String(n) === String(v.responseCode) ? 'selected' : ''}>${esc(RESPONSE[n])}</option>`).join('')}</select></label>` : '<span></span>'}` : ''}
            <label class="field"><span>Adresse <b>*</b></span><input name="address" maxlength="80" value="${esc(v.address || '')}" required></label>
            <label class="field"><span>Bloc <b>*</b></span><input name="block" maxlength="40" value="${esc(v.block || '')}" required></label>
            <div class="detail-only">
                <label class="field"><span>Croisement</span><input name="crossStreet" maxlength="80" value="${esc(v.crossStreet || '')}"></label>
                <label class="field"><span>Secteur</span><input name="sector" maxlength="40" value="${esc(v.sector || '')}"></label>
                ${kind === 'intervention' ? `<label class="field"><span>Requérant</span><input name="caller" maxlength="60" value="${esc(v.caller || '')}" placeholder="Dispatch (911)"></label>
                <label class="field"><span>Téléphone</span><input name="phone" maxlength="20" value="${esc(v.phone || '')}" placeholder="généré si vide"></label>
                <label class="field"><span>Unités idéales</span><input name="idealUnits" type="number" min="1" max="20" value="${esc(v.idealUnits || '')}" placeholder="1"></label><span></span>` : ''}
                <label class="field span-2"><span>Description</span><textarea name="description" rows="4" maxlength="2000">${esc(v.description || '')}</textarea></label>
            </div></div>`;
    }
    function readForm(root, kind) {
        const val = (n) => { const el = root.querySelector(`[name="${n}"]`); return el ? el.value.trim() : undefined; };
        const out = { title: val('title'), address: val('address'), block: val('block'), crossStreet: val('crossStreet'), sector: val('sector'), description: val('description'),
            agency: $$('[name="agency"]:checked', root).map((x) => x.value), kcsoAreas: $$('[name="kcsoAreas"]:checked', root).map((x) => x.value) };
        if (kind === 'intervention') Object.assign(out, { priority: val('priority'), responseCode: val('responseCode') || null, caller: val('caller'), phone: val('phone'), idealUnits: val('idealUnits') });
        Object.keys(out).forEach((k) => out[k] === undefined && delete out[k]);
        return out;
    }
    function renderEditForm() {
        const c = state.call;
        const v = state.editDraft || state.editBase.values;
        setSide(`<div class="d-head"><div class="d-num">${esc(c.number)}</div><div class="d-title">Modifier ${c.closed ? '(terminée)' : c.status === 'awaiting' ? '(avant envoi)' : '(en cours)'}</div></div>
            <div id="editLock">${editLockHtml()}</div><div id="editConflict">${conflictHtml()}</div>
            <form id="editForm" novalidate>${callFormHtml(v, c.kind, true)}
                <p class="form-note">${c.closed ? 'Intervention terminée : la modification est ajoutée à son journal, sans la rouvrir.' : 'Les unités de l\'intervention sont prévenues ; la modification est ajoutée au journal.'}</p></form>`,
        `<button type="button" class="btn primary" data-act="save">${icon('check')}Enregistrer</button><button type="button" class="btn ghost" data-act="cancelEdit">Annuler</button><span class="grow"></span><span class="hint">Ctrl + Entrée · Échap</span>`);
        const form = $('#editForm');
        form.addEventListener('change', (e) => { if (e.target.name === 'agency') { state.editDraft = readForm(form, c.kind); renderEditForm(); } });
        form.addEventListener('input', () => { state.editDraft = readForm(form, c.kind); });
        form.addEventListener('submit', (e) => { e.preventDefault(); saveEdit(false); });
    }
    async function saveEdit(force) {
        const c = state.call;
        const form = $('#editForm');
        if (!c || !form) return;
        const values = readForm(form, c.kind);
        const base = state.editBase.values;
        const fields = {};
        for (const [k, v] of Object.entries(values)) {
            const before = Array.isArray(base[k]) ? [...base[k]].sort().join('+') : String(base[k] ?? '');
            const after = Array.isArray(v) ? [...v].sort().join('+') : String(v ?? '');
            if (before !== after) fields[k] = v;
        }
        if (fields.priority !== undefined || fields.agency !== undefined) { fields.priority = values.priority; fields.agency = values.agency; if (values.responseCode !== undefined) fields.responseCode = values.responseCode; }
        if (fields.agency !== undefined || fields.kcsoAreas !== undefined) fields.kcsoAreas = values.kcsoAreas;
        if (!Object.keys(fields).length) { leaveEdit(); return; }
        const res = await api(`/calls/${c.id}/edit`, { rev: state.editBase.rev, force, fields });
        if (!res) return;
        if (res.conflict) {
            state.editConflict = { rev: res.rev }; state.editDraft = values; SOUND.error();
            const fresh = await api(`/calls/${c.id}`);
            if (fresh) state.call = fresh.call;
            renderTool();
            return;
        }
        toast('ok', c.number, res.unchanged ? 'Aucun changement.' : 'Intervention modifiée.');
        leaveEdit(true);
        const fresh = await api(`/calls/${c.id}`);
        if (fresh) state.call = fresh.call;
        renderTool();
    }
    async function callAction(act, btn) {
        const c = state.call;
        if (!c) return;
        if (btn) btn.disabled = true;
        try {
            if (act === 'validate') {
                const units = $$('[data-pick]:checked').map((x) => Number(x.value));
                if (await api(`/calls/${c.id}/validate`, { units })) toast('ok', c.number, 'Intervention validée et transmise.');
            } else if (act === 'refuse' || act === 'cancel') {
                const r = await confirmBox({ title: act === 'refuse' ? `Refuser ${c.number}` : `Annuler ${c.number}`, input: true, ok: act === 'refuse' ? 'Refuser' : 'Annuler l\'intervention',
                    text: act === 'refuse' ? 'Motif du refus (communiqué au civil qui a appelé, facultatif) :' : 'Motif de l\'annulation (communiqué aux unités, facultatif) :' });
                if (r && await api(`/calls/${c.id}/${act}`, { reason: r.value })) toast('ok', c.number, act === 'refuse' ? 'Intervention refusée.' : 'Intervention annulée.');
            } else if (act === 'close') {
                const ok = await confirmBox({ title: `Clôturer ${c.number}`, text: 'Terminer cette intervention ? Elle reste <b>modifiable</b> et peut être <b>rouverte</b>.', ok: 'Clôturer', danger: false });
                if (ok && await api(`/calls/${c.id}/close`, { clear: $('#clearSelect') ? $('#clearSelect').value : '' })) toast('ok', c.number, 'Intervention clôturée.');
            } else if (act === 'reopen') {
                if (await api(`/calls/${c.id}/reopen`, {})) toast('ok', c.number, 'Intervention rouverte : unités prévenues.');
            } else if (act === 'delete') {
                const ok = await confirmBox({ title: `Supprimer ${c.number}`, text: `<b>${esc(c.title)}</b> sera <b>supprimée définitivement</b> (jeu et site), avec ses notes et ses unités. Une trace reste dans le journal d'audit. Action irréversible.`, ok: 'Supprimer définitivement' });
                if (ok && await api(`/calls/${c.id}/delete`, {})) { toast('ok', c.number, 'Intervention supprimée.'); state.callId = null; state.call = null; renderTool(); }
            } else if (act === 'assign') {
                const unitId = Number($('#assignSelect').value);
                if (!unitId) { toast('error', 'Affectation', 'Choisissez une unité.'); return; }
                await assign(c.id, unitId);
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
                if (fresh) state.call = fresh.call;
                state.editDraft = null; state.editConflict = null; state.editBase = { rev: state.call.rev, values: editValues(state.call) };
                renderTool();
            } else if (act === 'cancelEdit') leaveEdit();
        } finally { if (btn && btn.isConnected) btn.disabled = false; }
    }
    async function callClick(e) {
        const c = state.call;
        if (!c) return;
        const nf = e.target.closest('[data-nf]');
        if (nf) { state.noteFilter = nf.dataset.nf; renderTool(); return; }
        const un = e.target.closest('[data-unassign]');
        if (un) {
            const u = c.units.find((x) => x.id === Number(un.dataset.unassign));
            const ok = await confirmBox({ title: 'Retirer l\'unité', text: `Retirer <b>${esc(u ? u.name : '')}</b> de ${esc(c.number)} ?`, ok: 'Retirer' });
            if (ok) await api(`/calls/${c.id}/unassign`, { unitId: Number(un.dataset.unassign) });
            return;
        }
        const b = e.target.closest('[data-act]');
        if (b) callAction(b.dataset.act, b);
    }
    document.addEventListener('keydown', (e) => {
        if (e.key !== 'Enter' || e.shiftKey) return;
        if (e.target.id === 'noteInput') { e.preventDefault(); callAction('note'); }
        if (e.target.id === 'drawerMsg') { e.preventDefault(); callAction('msg'); }
        if (e.ctrlKey && $('#editForm') && e.target.closest('#editForm')) { e.preventDefault(); saveEdit(false); }
        if (e.ctrlKey && e.target.id === 'svcInput') { e.preventDefault(); saveServiceNote($('#svcInput').value); }
    });

    // ---------------- nouvelle intervention / nouvel incident ----------------
    const draft = { kind: 'intervention', mode: store.get('mdc.newMode', 'quick'), values: { agency: ['kcso'] }, units: [] };
    const candidatesNew = () => state.units.filter((u) => u.connected && ['kcso', 'wsp'].includes(u.agency));
    const newUnitsHtml = () => candidatesNew().map((u) => `<label class="check"><input type="checkbox" value="${u.id}" data-newunit ${draft.units.includes(u.id) ? 'checked' : ''}> ${unitTag(u)}</label>`).join('') || '<span class="muted">Aucune unité en service.</span>';
    function openNew(kind, preset = {}) {
        draft.kind = kind; draft.values = { agency: draft.values.agency || ['kcso'], ...preset }; draft.units = [];
        renderNew();
        $('#newModal').classList.remove('hidden');
        $('#newBody [name="title"]').focus();
    }
    function renderNew() {
        $('#newTitle').textContent = draft.kind === 'incident' ? 'Nouvel incident' : 'Nouvelle intervention';
        $$('[data-nkind]').forEach((b) => b.setAttribute('aria-pressed', b.dataset.nkind === draft.kind ? 'true' : 'false'));
        $$('[data-nmode]').forEach((b) => b.setAttribute('aria-pressed', b.dataset.nmode === draft.mode ? 'true' : 'false'));
        $('#newBody').innerHTML = `${callFormHtml(draft.values, draft.kind, draft.mode === 'full')}
            <div class="d-sec"><h3>Affecter tout de suite <span class="grow"></span><span class="muted">facultatif</span></h3><div class="unit-pick" id="newUnits">${newUnitsHtml()}</div></div>
            ${draft.mode === 'quick' ? '<p class="form-note">Rapide : requérant « Dispatch (911) », 1 unité idéale, description = intitulé.</p>' : ''}`;
        $('#newSubmit').textContent = draft.kind === 'incident' ? 'Créer l\'incident' : 'Créer et transmettre';
    }
    function keepNew() { draft.values = { ...draft.values, ...readForm($('#newBody'), draft.kind) }; draft.units = $$('[data-newunit]:checked').map((x) => Number(x.value)); }
    $$('[data-nkind]').forEach((b) => b.addEventListener('click', () => { keepNew(); draft.kind = b.dataset.nkind; renderNew(); }));
    $$('[data-nmode]').forEach((b) => b.addEventListener('click', () => { keepNew(); draft.mode = b.dataset.nmode; store.set('mdc.newMode', draft.mode); renderNew(); }));
    $('#newBody').addEventListener('change', (e) => { if (e.target.name === 'agency') { keepNew(); renderNew(); } });
    $('#newForm').addEventListener('keydown', (e) => { if (e.key === 'Enter' && e.ctrlKey) { e.preventDefault(); $('#newForm').requestSubmit(); } });
    $('#newForm').addEventListener('submit', async (e) => {
        e.preventDefault();
        keepNew();
        const v = draft.values;
        const missing = [!v.title && 'intitulé', !(v.agency || []).length && 'police', !v.address && 'adresse', !v.block && 'bloc',
            draft.kind === 'intervention' && !v.priority && 'priorité', draft.kind === 'intervention' && (v.agency || []).includes('kcso') && !v.responseCode && 'code de réponse',
            (v.agency || []).includes('kcso') && !(v.kcsoAreas || []).length && 'secteur KCSO (Non-incorporé, Maple Valley, Kenmore)'].filter(Boolean);
        if (missing.length) { toast('error', 'Champs obligatoires', `À remplir : ${missing.join(', ')}.`); return; }
        $('#newSubmit').disabled = true;
        const body = { kind: draft.kind, title: v.title, address: v.address, block: v.block, crossStreet: v.crossStreet, sector: v.sector, description: v.description, agencies: v.agency, kcsoAreas: v.kcsoAreas || [], units: draft.units };
        if (draft.kind === 'intervention') Object.assign(body, { priority: v.priority, responseCode: v.responseCode || null, caller: v.caller, phone: v.phone, idealUnits: v.idealUnits });
        const res = await api('/calls', body);
        $('#newSubmit').disabled = false;
        if (!res) return;
        $('#newModal').classList.add('hidden');
        draft.values = { agency: v.agency };
        toast('ok', res.number, draft.kind === 'incident' ? 'Incident créé.' : 'Intervention créée et transmise aux unités.');
        openCall(res.id);
    });
    document.addEventListener('click', (e) => { const n = e.target.closest('[data-new]'); if (n) openNew(n.dataset.new); });

    // =================================================================================================================
    // MESSAGERIE (groupe civil, civils, unités ; observation entre unités)
    // =================================================================================================================
    const catOf = (c) => (c.kind === 'civil' ? 'civil' : c.kind === 'private' ? 'private' : c.kind === 'unit' ? 'unit' : 'call');
    function renderMessagesTool() {
        setSide(`<div class="chat">
            <div class="chat-side"><div class="tools">
                <div class="seg" role="tablist" id="chatTabs">${[['civil', 'Groupe'], ['private', 'Civils'], ['unit', 'Unités']].map(([k, l]) => `<button type="button" data-cat="${k}" aria-selected="false">${l} <span data-catcount="${k}" class="hidden"></span></button>`).join('')}</div>
                <input id="chatQ" type="search" placeholder="Filtrer…" aria-label="Filtrer les conversations">
                <label class="check" title="Conversations entre unités, en lecture seule"><input type="checkbox" id="observeChk"> Observer les unités</label></div>
                <div class="conv-list" id="chatList" role="listbox"></div></div>
            <div class="chat-main"><div class="chat-head" id="chatHead"><span class="muted">Choisissez une conversation.</span></div>
                <div class="chat-body" id="chatBody"></div>
                <div class="readonly hidden" id="readonlyNote">Observation : lecture seule, rien n'est marqué comme lu.</div>
                <form class="chat-form hidden" id="chatForm"><textarea id="chatInput" maxlength="300" placeholder="Écrire un message… (Entrée pour envoyer)" aria-label="Message"></textarea><button type="submit" class="btn primary">Envoyer</button></form></div>
        </div>`, '', '');
        $('#chatList').addEventListener('click', (e) => { const b = e.target.closest('[data-conv]'); if (b) openChat(b.dataset.conv); });
        $('#chatQ').addEventListener('input', renderChatList);
        $('#chatTabs').addEventListener('click', (e) => { const b = e.target.closest('[data-cat]'); if (!b) return; state.chatCat = b.dataset.cat; state.observeOn = false; renderChatList(); });
        $('#observeChk').addEventListener('change', () => { state.observeOn = $('#observeChk').checked; if (state.observeOn) loadObserve(); else renderChatList(); });
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
        $('#chatInput').addEventListener('keydown', (e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); $('#chatForm').requestSubmit(); } });
        $('#chatHead').addEventListener('click', (e) => { const b = e.target.closest('[data-convdel]'); if (b) deleteConversation(state.chat, b.dataset.convdel); });
        renderChatList();
        if (state.chat) openChat(state.chat);
    }
    function renderChatList() {
        updateTitle();
        if (!$('#chatList')) return;
        const q = norm($('#chatQ').value);
        for (const cat of ['civil', 'private', 'unit']) {
            const n = state.conversations.filter((c) => catOf(c) === cat).reduce((s, c) => s + (c.unread || 0), 0);
            const el = $(`[data-catcount="${cat}"]`);
            if (el) { el.textContent = `(${n})`; el.classList.toggle('hidden', !n); }
        }
        $$('#chatTabs [data-cat]').forEach((b) => b.setAttribute('aria-selected', !state.observeOn && b.dataset.cat === state.chatCat ? 'true' : 'false'));
        $('#observeChk').checked = state.observeOn;
        let items;
        if (state.observeOn) items = state.observe.filter((c) => !q || norm(c.label).includes(q) || norm(c.last && c.last.text).includes(q));
        else {
            items = state.conversations.filter((c) => catOf(c) === state.chatCat && (!q || norm(c.label).includes(q) || norm(c.last && c.last.text).includes(q)));
            items.sort((a, b) => ((b.last ? b.last.at : 0) - (a.last ? a.last.at : 0)) || ((b.unread || 0) - (a.unread || 0)));
        }
        $('#chatList').innerHTML = items.map((c) => `
            <button type="button" class="conv ${c.unread ? 'unread' : ''}" data-conv="${esc(c.channel)}" ${state.chat === c.channel ? 'aria-current="true"' : ''}>
                <span class="conv-name">${esc(c.label)}${c.kind === 'unit' && !c.connected ? ' <span class="muted">· hors service</span>' : ''}${c.kind === 'private' ? ` <span class="muted">· ${c.online ? 'connecté' : 'hors ligne'}</span>` : ''}</span>
                <span class="conv-time">${c.last ? fmtShort(c.last.at) : ''}</span>
                <span class="conv-last">${c.last ? `${c.last.senderType === 'dispatch' ? 'Vous : ' : `${esc(c.last.author)} : `}${esc(c.last.text)}` : (c.kind === 'private' ? 'Aucun message — écrivez-lui' : 'Aucun message')}</span>
                ${c.unread ? `<span class="cnt">${c.unread}</span>` : ''}
            </button>`).join('') || emptyState(state.observeOn ? 'Aucune conversation entre unités' : 'Aucune conversation', state.chatCat === 'private' && !state.observeOn ? 'Les civils connectés apparaissent ici, même sans message.' : '');
    }
    async function loadObserve() { const res = await api('/observe'); if (res) state.observe = res.conversations; renderChatList(); }
    async function openChat(channel) {
        if (state.tool !== 'messages') openTool('messages');
        const observing = /^u:\d+:\d+$/.test(channel);
        state.chat = channel;
        const conv = (observing ? state.observe : state.conversations).find((c) => c.channel === channel);
        if (!observing && conv && conv.kind !== 'call') state.chatCat = catOf(conv);
        const label = conv ? (conv.kind === 'unit' ? `Unité ${conv.label}` : conv.label) : channel;
        $('#chatHead').innerHTML = `<b>${esc(label)}</b>${observing ? ' <span class="chip caution">Observation</span>' : ''}${conv && conv.kind === 'civil' ? ' <span class="chip">tous les civils</span>' : ''}
            <span class="grow"></span><button type="button" class="btn xs ghost" data-convdel="empty" title="Effacer tous les messages">Vider</button><button type="button" class="ibtn" data-convdel="delete" title="Supprimer la conversation">${icon('trash')}</button>`;
        $('#chatForm').classList.toggle('hidden', observing);
        $('#readonlyNote').classList.toggle('hidden', !observing);
        $('#chatBody').innerHTML = skeleton(5);
        const res = await api(`/messages?channel=${encodeURIComponent(channel)}`);
        if (!res || state.chat !== channel || !$('#chatBody')) return;
        state.chatMessages = res.messages;
        renderChat();
        renderChatList();
        if (!observing) { markRead(channel); $('#chatInput').focus(); }
    }
    function renderChat() { if (!$('#chatBody')) return; $('#chatBody').innerHTML = state.chatMessages.map(bubble).join('') || emptyState('Aucun message', 'Écrivez le premier.'); $('#chatBody').scrollTop = $('#chatBody').scrollHeight; }
    function markRead(channel) { const conv = state.conversations.find((c) => c.channel === channel); if (conv && conv.unread) api('/messages/read', { channel }, { quiet: true }); }
    async function deleteConversation(channel, mode) {
        if (!channel) return;
        const conv = [...state.conversations, ...state.observe].find((c) => c.channel === channel);
        const name = conv ? conv.label : channel;
        const ok = await confirmBox({ title: mode === 'empty' ? 'Vider les messages' : 'Supprimer la conversation',
            text: `${mode === 'empty' ? 'Tous les messages de' : 'La conversation'} <b>${esc(name)}</b> ser${mode === 'empty' ? 'ont effacés' : 'a supprimée'} <b>définitivement</b>. Elle peut être recréée aussitôt en écrivant un nouveau message.`,
            ok: mode === 'empty' ? 'Vider' : 'Supprimer' });
        if (!ok) return;
        if (await api('/conversations/delete', { channel, mode })) {
            toast('ok', 'Messagerie', mode === 'empty' ? 'Messages effacés.' : 'Conversation supprimée.');
            if (state.chat === channel) { state.chatMessages = []; renderChat(); }
            if (state.observeOn) loadObserve();
        }
    }

    // =================================================================================================================
    // RECHERCHE + FICHES (modification, suppression définitive)
    // =================================================================================================================
    function renderSearchTool() {
        setSide(`<div class="seg mb" role="group" id="searchTabs">${[['identity', 'Identité'], ['vehicle', 'Véhicule']].map(([k, l]) => `<button type="button" data-stype="${k}" aria-pressed="${state.searchType === k}">${l}</button>`).join('')}</div>
            <form class="tool-form ${state.searchType === 'identity' ? '' : 'hidden'}" id="searchIdentity"><input id="sLast" placeholder="Nom *" maxlength="40"><input id="sFirst" placeholder="Prénom" maxlength="40">
                <input id="sDob" placeholder="JJ/MM/AAAA *" maxlength="10" inputmode="numeric"><input id="sSsn" placeholder="SSN" maxlength="11"><button type="submit" class="btn primary">${icon('search')}Chercher</button></form>
            <form class="tool-form ${state.searchType === 'vehicle' ? '' : 'hidden'}" id="searchVehicle"><input id="sQuery" placeholder="Plaque ou VIN *" maxlength="20"><button type="submit" class="btn primary">${icon('search')}Chercher</button></form>
            <div class="results" id="searchResults">${emptyState('Pas encore de recherche', 'Nom + date de naissance, ou plaque / VIN.')}</div>
            <div class="sheet" id="recordSheet"></div>`, '', '');
        $('#searchTabs').addEventListener('click', (e) => { const t = e.target.closest('[data-stype]'); if (!t) return; state.searchType = t.dataset.stype; renderSearchTool(); });
        $('#sDob').addEventListener('input', (e) => { const d = e.target.value.replace(/\D/g, '').slice(0, 8); e.target.value = [d.slice(0, 2), d.slice(2, 4), d.slice(4)].filter(Boolean).join('/'); });
        $('#searchIdentity').addEventListener('submit', (e) => { e.preventDefault(); runSearch({ type: 'identity', lastname: $('#sLast').value.trim(), firstname: $('#sFirst').value.trim(), dob: $('#sDob').value.trim(), ssn: $('#sSsn').value.trim() }); });
        $('#searchVehicle').addEventListener('submit', (e) => { e.preventDefault(); runSearch({ type: 'vehicle', query: $('#sQuery').value.trim() }); });
        $('#searchResults').addEventListener('click', (e) => {
            const b = e.target.closest('[data-result]');
            if (!b) return;
            $$('.result').forEach((x) => (x === b ? x.setAttribute('aria-current', 'true') : x.removeAttribute('aria-current')));
            showRecord(state.searchResults[Number(b.dataset.result)], '#recordSheet');
        });
        $('#recordSheet').addEventListener('click', recordSheetClick);
        (state.searchType === 'identity' ? $('#sLast') : $('#sQuery')).focus();
    }
    async function runSearch(params) {
        if (state.tool !== 'search') openTool('search');
        $('#searchResults').innerHTML = skeleton(3);
        const res = await api(`/search?${new URLSearchParams(params)}`, undefined, { loud: true });
        if (!$('#searchResults')) return;
        state.searchResults = res ? res.results : [];
        $('#searchResults').innerHTML = state.searchResults.map((r, i) => `
            <button type="button" class="result" data-result="${i}">
                ${r.kind === 'vehicle' ? `<b>${esc(r.plate)}</b> — ${esc([r.make, r.model].filter(Boolean).join(' '))}${r.stolen ? ' <span class="chip stop">Volé</span>' : ''}<small>VIN ${esc(r.vin || '—')} · ${esc(REG_STATUS[r.regStatus] || r.regStatus || '')}</small>`
                    : `<b>${esc(String(r.lastname || '').toUpperCase())}</b> ${esc([r.firstname, r.middlename].filter(Boolean).join(' '))}${r.condition === 'wanted' ? ' <span class="chip stop">Recherché</span>' : ''}${arr(r.registrations).length ? ' <span class="chip accent">Registre</span>' : ''}<small>${esc(r.dob || '')} · ${esc(r.address || '')}</small>`}
            </button>`).join('') || (res ? emptyState('Aucun résultat', 'Vérifiez l\'orthographe et la date de naissance.') : '<div class="error-line">Recherche impossible.</div>');
        if (state.searchResults.length === 1) showRecord(state.searchResults[0], '#recordSheet');
    }
    const dl = (rows) => `<dl class="info">${rows.filter(([, v]) => v !== undefined && v !== null && v !== '').map(([k, v]) => `<dt>${esc(k)}</dt><dd>${v}</dd>`).join('')}</dl>`;
    const block = (title, html) => `<div class="sheet-block"><h4>${esc(title)}</h4>${html}</div>`;
    const bolosHtml = (r) => arr(r.bolos).map((b) => `<div class="alert">BOLO ${esc(b.number)} — ${esc(b.reason)}${b.possible ? ' (correspondance possible)' : ''}</div>`).join('');
    const recordActions = (kind, id) => `<div class="toolbar mb"><button type="button" class="btn sm" data-redit="${kind}:${id}">${icon('edit')}Modifier</button><button type="button" class="btn sm danger" data-rdel="${kind}:${id}">${icon('trash')}Supprimer</button></div>`;
    const recordCache = {};
    function showRecord(r, target) {
        if (!r || !$(target)) return;
        recordCache[`${r.kind}:${r.id}`] = r;
        $(target).innerHTML = r.kind === 'vehicle' ? vehicleSheet(r) : identitySheet(r);
    }
    async function recordSheetClick(e) {
        const b = e.target.closest('[data-record]');
        if (b) { const res = await api(`/records/${b.dataset.record}/${b.dataset.id}`, undefined, { loud: true }); if (res) showRecord(res.record, `#${e.currentTarget.id}`); return; }
        const ed = e.target.closest('[data-redit]');
        if (ed) { const [kind, id] = ed.dataset.redit.split(':'); editRecord(kind, id); return; }
        const del = e.target.closest('[data-rdel]');
        if (del) { const [kind, id] = del.dataset.rdel.split(':'); deleteRecord(kind, id); }
    }
    function identitySheet(r) {
        const name = `${String(r.lastname || '').toUpperCase()} ${[r.firstname, r.middlename].filter(Boolean).join(' ')}`;
        const alerts = [r.condition === 'wanted' && `<div class="alert">PERSONNE RECHERCHÉE${r.wantedSince ? ` depuis le ${esc(r.wantedSince)}` : ''}${r.wantedReason ? ` — ${esc(r.wantedReason)}` : ''}</div>`,
            r.condition === 'missing' && '<div class="alert yellow">PERSONNE DISPARUE</div>', r.condition === 'deceased' && '<div class="alert yellow">PERSONNE DÉCÉDÉE</div>',
            ...arr(r.registrations).map((g) => `<div class="alert purple">${esc(REGISTRY[g.type] || g.type)} — niveau ${esc(g.level)} — ${esc(REG_FOLLOW[g.status] || g.status)} — inscription ${g.endDate === 'life' ? 'à vie' : `jusqu'au ${esc(g.endDate)}`}${g.lastUpdate ? ` — mise à jour ${esc(g.lastUpdate)}` : ''}</div>`)].filter(Boolean).join('');
        const hasLicense = r.licenseClass && r.licenseClass !== 'N/A';
        const vehicles = arr(r.vehicles); const convictions = arr(r.convictions); const records = arr(r.records); const reports = arr(r.reports);
        return `<h3 class="d-title">${esc(name)}</h3>${recordActions('identity', r.id)}${alerts}${bolosHtml(r)}
            ${dl([['Date de naissance', esc(r.dob)], ['Sexe', esc({ M: 'Homme', F: 'Femme' }[r.sex] || '')], ['Nationalité', esc(NATIONALITY[r.nationality || 'US'] || r.nationality)], ['SSN', esc(r.ssn)],
                ['Adresse', esc(r.address)], ['Téléphone', esc(r.phone)], ['Emploi', esc(r.job)], ['Description physique', esc(r.physical)], ['Condition', esc(CONDITION[r.condition] || r.condition || 'Aucune')],
                ['Interdictions', esc(arr(r.restrictions).map((x) => RESTRICTION[x] || x).join(', ') || 'Aucune')]])}
            ${block('Permis de conduire', hasLicense ? dl([['Type', esc(r.licenseClass)], ['Condition', esc(LICENSE_STATUS[r.licenseStatus] || 'Valide')], ['N° de permis', esc(r.licenseNumber)], ['Délivré par', esc(r.licenseState)], ['Mentions', esc(arr(r.licenseEndorsements).join(', ') || 'Aucune')]]) : '<span class="muted">Aucun permis de conduire.</span>')}
            ${block(`Véhicules (${vehicles.length})`, vehicles.map((v) => `<div class="entry"><button type="button" class="link" data-record="vehicle" data-id="${esc(v.id)}">${esc(v.plate)}</button> — ${esc([v.make, v.model].filter(Boolean).join(' '))}${v.color ? ` (${esc(v.color)})` : ''}${v.stolen ? ' · <b>VOLÉ</b>' : ''}</div>`).join('') || '<span class="muted">Aucun véhicule.</span>')}
            ${block(`Casier judiciaire (${convictions.length + records.length})`, [...convictions.map((c) => `<div class="entry"><b>${esc(CLASS[c.class] || c.class || '')}</b> — ${esc(c.label || c.offense)} <span class="muted">${esc(c.rcw || '')}</span><br><span class="muted">faits le ${esc(c.offenseDate || '—')}, jugement le ${esc(c.convictionDate || '—')}${c.sentence ? ` — ${esc(c.sentence)}` : ''}</span></div>`),
                ...records.map((x) => `<div class="entry">${esc(x.offense || '')} <span class="muted">(ancien antécédent ${esc(x.date || '')})</span></div>`)].join('') || '<span class="muted">Casier vierge.</span>')}
            ${block(`Rapports (${reports.length})`, reports.map((x) => `<div class="entry"><b>${esc(x.label)}</b> n°${esc(x.number)}${x.callNumber ? ` — ${esc(x.callNumber)}` : ''}<br><span class="muted">${esc(x.role || '')} — ${fmtDate(x.createdAt)} par ${esc(x.createdByName || '—')}</span>${x.summary ? `<br>${esc(x.summary)}` : ''}</div>`).join('') || '<span class="muted">Aucun rapport.</span>')}`;
    }
    function vehicleSheet(r) {
        const owner = r.ownerIdentity; const hist = arr(r.history);
        return `<h3 class="d-title">${esc(r.plate)}</h3>${recordActions('vehicle', r.id)}${r.stolen ? '<div class="alert">VÉHICULE VOLÉ</div>' : ''}${r.abandoned ? '<div class="alert yellow">VÉHICULE ABANDONNÉ</div>' : ''}${bolosHtml(r)}
            ${dl([['Statut', esc(REG_STATUS[r.regStatus] || r.regStatus || '')], ['Marque', esc(r.make)], ['Modèle', esc(r.model)], ['Année', esc(r.year)], ['Couleur', esc(r.color)], ['VIN', esc(r.vin)],
                ['Contrôle technique', esc(r.inspectionDate)], ['Usage', r.commercial ? 'Véhicule commercial' : 'Particulier'], ['Assurance', esc(INSURANCE[r.insuranceStatus] || r.insuranceStatus || '')],
                ['Propriétaire', owner ? `<button type="button" class="link" data-record="identity" data-id="${esc(owner.id)}">${esc(String(owner.lastname || '').toUpperCase())} ${esc(owner.firstname || '')}</button> (${esc(owner.dob || '')})` : esc(r.ownerName || 'Non renseigné')]])}
            ${block(`Historique (${hist.length})`, hist.map((h) => `<div class="entry">${esc({ administrative: 'Infraction administrative', parking: 'Infraction de stationnement' }[h.type] || h.type || '')} — ${esc(h.date || '')}${h.offense ? ` — ${esc(h.offense)}` : ''}</div>`).join('') || '<span class="muted">Aucune infraction connue.</span>')}`;
    }

    // =================================================================================================================
    // REGISTRES (identiques au jeu) : Sex / Kidnapping Offenders, BOLOs, Rapports
    // =================================================================================================================
    function renderRegistriesTool() {
        setSide(`<div class="live-tools"><div class="seg" role="tablist" id="regTabs">${[['sex', 'Sex Off.'], ['kidnap', 'Kidnap. Off.'], ['bolos', 'BOLOs'], ['reports', 'Rapports']].map(([k, l]) => `<button type="button" data-reg="${k}" aria-selected="${state.reg.tab === k}">${l}</button>`).join('')}</div>
                <input id="regQ" type="search" placeholder="Filtrer…" aria-label="Filtrer"><span id="regFilters" class="toolbar"></span><span class="meta" id="regCount"></span></div>
            <div class="split pad"><div id="regList"></div><div class="sheet" id="regDetail"></div></div><div class="pager hidden pad-x" id="regPager"></div>`, '', '');
        $('#regTabs').addEventListener('click', (e) => { const b = e.target.closest('[data-reg]'); if (!b) return; state.reg.tab = b.dataset.reg; state.reg.sel = null; state.reg.page = 1; $('#regQ').value = ''; $('#regFilters').dataset.tab = ''; loadRegistry(); });
        $('#regQ').addEventListener('input', () => { if (state.reg.tab === 'reports') { clearTimeout(state.reg.t); state.reg.t = setTimeout(() => { state.reg.page = 1; loadRegistry(); }, 300); } else renderRegistry(); });
        $('#regFilters').addEventListener('change', () => { if (state.reg.tab === 'reports') { state.reg.page = 1; loadRegistry(); } else renderRegistry(); });
        $('#regList').addEventListener('click', (e) => { const row = e.target.closest('[data-row]'); if (row) selectRegistry(row.dataset.row); });
        $('#regDetail').addEventListener('click', recordSheetClick);
        $('#regPager').addEventListener('click', (e) => { const b = e.target.closest('[data-rpage]'); if (b) { state.reg.page += Number(b.dataset.rpage); loadRegistry(); } });
        loadRegistry();
    }
    function regFiltersHtml() {
        const t = state.reg.tab;
        if (t === 'sex' || t === 'kidnap') return '<select id="regLevel" aria-label="Niveau"><option value="">Tous niveaux</option><option value="1">Niveau I</option><option value="2">Niveau II</option><option value="3">Niveau III</option></select><label class="check"><input type="checkbox" id="regEnded"> Terminées</label>';
        if (t === 'bolos') return '<select id="regBoloKind" aria-label="Type"><option value="">Individus et véhicules</option><option value="person">Individus</option><option value="vehicle">Véhicules</option></select>';
        const types = state.reg.types ? state.reg.types.types.filter((x) => !x.archived) : [];
        return `<select id="regReportType" aria-label="Type de rapport"><option value="">Tous les rapports</option>${types.map((x) => `<option value="${esc(x.id)}">${esc(x.label)}</option>`).join('')}</select>`;
    }
    async function loadRegistry() {
        if (!$('#regList')) return;
        const t = state.reg.tab;
        $$('#regTabs [data-reg]').forEach((b) => b.setAttribute('aria-selected', b.dataset.reg === t ? 'true' : 'false'));
        if (t === 'reports' && !state.reg.types) { const types = await api('/registry/report-types', undefined, { loud: true }); if (types) state.reg.types = types; }
        if (!$('#regList')) return;
        if ($('#regFilters').dataset.tab !== t) { $('#regFilters').innerHTML = regFiltersHtml(); $('#regFilters').dataset.tab = t; }
        $('#regList').innerHTML = skeleton(6);
        if (!state.reg.sel) $('#regDetail').innerHTML = emptyState('Aucune fiche choisie', 'Sélectionnez une ligne.');
        let res;
        if (t === 'sex' || t === 'kidnap') res = await api(`/registry/offenders?type=${t}`, undefined, { loud: true });
        else if (t === 'bolos') res = await api('/registry/bolos', undefined, { loud: true });
        else res = await api(`/registry/reports?${new URLSearchParams({ type: $('#regReportType') ? $('#regReportType').value : '', q: $('#regQ').value.trim(), page: state.reg.page })}`, undefined, { loud: true });
        if (state.reg.tab !== t || !$('#regList')) return;
        if (!res) { $('#regList').innerHTML = '<div class="error-line">Registre indisponible (serveur FiveM hors ligne ?).</div>'; return; }
        state.reg.list = (t === 'bolos' ? res.bolos : t === 'reports' ? res.reports : res.list) || [];
        state.reg.total = res.total || state.reg.list.length;
        renderRegistry();
        if (state.reg.sel) selectRegistry(state.reg.sel, true);
    }
    function renderRegistry() {
        if (!$('#regList')) return;
        const t = state.reg.tab;
        const q = norm($('#regQ').value);
        const table = (head, rows, cols, emptyTitle) => `<table class="table"><thead><tr>${head.map((h) => `<th>${h}</th>`).join('')}</tr></thead><tbody>${rows || `<tr><td colspan="${cols}">${emptyState(emptyTitle, '')}</td></tr>`}</tbody></table>`;
        if (t === 'sex' || t === 'kidnap') {
            const level = $('#regLevel') ? $('#regLevel').value : ''; const ended = $('#regEnded') && $('#regEnded').checked;
            const view = state.reg.list.filter((e) => (ended || e.active) && (!level || String(e.registration.level) === level)
                && (!q || norm([e.identity.lastname, e.identity.firstname, e.registration.address, e.registration.label, e.identity.dob].join(' ')).includes(q)));
            $('#regList').innerHTML = table(['Nom', 'Niv.', 'Charge', 'Adresse', 'Suivi'], view.map((e) => `<tr data-row="o:${esc(e.identity.id)}" data-ctx-rec="identity:${esc(e.identity.id)}" class="${e.active ? '' : 'ended'} ${state.reg.sel === `o:${e.identity.id}` ? 'sel' : ''}">
                <td><b>${esc(String(e.identity.lastname || '').toUpperCase())}</b> ${esc(e.identity.firstname)}<span class="sub">${esc(e.identity.dob)}</span></td>
                <td><span class="chip ${String(e.registration.level) === '3' ? 'crit' : String(e.registration.level) === '2' ? 'high' : 'mid'}">${esc(e.registration.level)}</span></td>
                <td>${esc(e.registration.label || e.registration.offense)}</td><td>${esc(e.registration.address || '—')}</td>
                <td>${e.active ? `<span class="chip ${e.registration.status === 'absconded' ? 'stop' : e.registration.status === 'noncompliant' ? 'caution' : 'go'}">${esc(REG_FOLLOW[e.registration.status] || e.registration.status)}</span>` : '<span class="chip">Terminée</span>'}</td></tr>`).join(''), 5, 'Aucune inscription');
            $('#regCount').textContent = `${view.length} / ${state.reg.list.length}`;
        } else if (t === 'bolos') {
            const kind = $('#regBoloKind') ? $('#regBoloKind').value : '';
            const view = state.reg.list.filter((b) => (!kind || b.kind === kind) && (!q || norm([b.number, b.reason, b.summary, b.location].join(' ')).includes(q)));
            $('#regList').innerHTML = table(['N°', 'Type', 'Motif', 'Émis par', 'Mis à jour'], view.map((b) => `<tr data-row="b:${esc(b.id)}" data-ctx-rec="bolo:${esc(b.id)}" class="${state.reg.sel === `b:${b.id}` ? 'sel' : ''}"><td class="num">${esc(b.number)}</td><td><span class="chip">${esc(BOLO_KIND[b.kind] || b.kind)}</span></td><td><b>${esc(b.reason)}</b><span class="sub">${esc(b.summary || '')}</span></td><td>${esc(AGENCY[b.agency] || b.agency || '')}</td><td>${fmtDate(b.updatedAt || b.createdAt)}</td></tr>`).join(''), 5, 'Aucun BOLO actif');
            $('#regCount').textContent = `${view.length} BOLO(s)`;
        } else {
            const typeLabel = (id) => { const x = state.reg.types && state.reg.types.types.find((y) => y.id === id); return x ? x.short || x.label : id; };
            $('#regList').innerHTML = table(['N°', 'Type', 'Résumé', 'Appel', 'Date'], state.reg.list.map((r) => `<tr data-row="r:${esc(r.id)}" data-ctx-rec="report:${esc(r.id)}" class="${state.reg.sel === `r:${r.id}` ? 'sel' : ''}"><td class="num">${esc(r.number)}</td><td><span class="chip">${esc(typeLabel(r.type))}</span></td><td>${esc(r.summary || '')}<span class="sub">${esc(r.createdByName || '')}${r.unitName ? ` · ${esc(r.unitName)}` : ''}</span></td><td>${esc(r.callNumber || '—')}</td><td>${fmtDate(r.createdAt)}</td></tr>`).join(''), 5, 'Aucun rapport');
            $('#regCount').textContent = `${state.reg.total} rapport(s)`;
        }
        const pages = Math.max(1, Math.ceil(state.reg.total / 25));
        $('#regPager').classList.toggle('hidden', t !== 'reports' || pages <= 1);
        if (t === 'reports') $('#regPager').innerHTML = `<span>Page ${state.reg.page} / ${pages}</span><button type="button" class="btn xs" ${state.reg.page <= 1 ? 'disabled' : ''} data-rpage="-1">Précédente</button><button type="button" class="btn xs" ${state.reg.page >= pages ? 'disabled' : ''} data-rpage="1">Suivante</button>`;
        $('#sideMeta').textContent = $('#regCount').textContent;
    }
    async function selectRegistry(key, silent) {
        state.reg.sel = key;
        if (!silent) renderRegistry();
        const i = key.indexOf(':'); const k = key.slice(0, i); const v = key.slice(i + 1);
        if (k === 'o') { const e = state.reg.list.find((x) => String(x.identity.id) === v); if (e) showRecord({ ...e.identity, kind: 'identity' }, '#regDetail'); return; }
        $('#regDetail').innerHTML = skeleton(6);
        if (k === 'b') { const res = await api(`/registry/bolos/${encodeURIComponent(v)}`); if ($('#regDetail')) $('#regDetail').innerHTML = res ? boloSheet(res.bolo) : emptyState('BOLO introuvable', ''); return; }
        if (k === 'r') {
            if (!state.reg.types) state.reg.types = await api('/registry/report-types');
            const res = await api(`/registry/reports/${encodeURIComponent(v)}`);
            if ($('#regDetail')) $('#regDetail').innerHTML = res ? reportSheet(res.report) : emptyState('Rapport introuvable', '');
        }
    }
    function boloSheet(b) {
        recordCache[`bolo:${b.id}`] = b;
        const rows = b.kind === 'vehicle'
            ? [['Immatriculation', esc(b.plate)], ['Marque / modèle', esc([b.make, b.model].filter(Boolean).join(' '))], ['Couleur', esc(b.color)], ['Type', esc(b.vtype)]]
            : [['Identité liée', b.identityLabel ? esc(b.identityLabel) : (b.identityId ? 'fiche supprimée' : '')], ['Taille', b.height ? `${esc(b.height)} cm` : ''], ['Cheveux', esc(b.hairColor)],
                ['Pilosité', esc([b.facialType, b.facialColor].filter(Boolean).join(', '))], ['Tatouages', esc(b.tattoos)], ['Peau', esc(b.skin)], ['Tenue', esc(b.clothing)], ['Origine', esc(arr(b.origins).join(', '))]];
        return `<div class="d-num">BOLO n°${esc(b.number)} · ${esc(BOLO_KIND[b.kind] || b.kind)}</div><h3 class="d-title">${esc(b.reason)}</h3>${recordActions('bolo', b.id)}
            ${dl([...rows, ['Dernier lieu', esc(b.location)], ['Émis par', `${esc(AGENCY[b.agency] || b.agency || '')}${b.unitName ? ` — ${esc(b.unitName)}` : ''}`], ['Créé', `${fmtDate(b.createdAt)} par ${esc(b.createdByName || '—')}`],
                ...(b.updatedAt ? [['Modifié', `${fmtDate(b.updatedAt)} par ${esc(b.updatedByName || '—')}`]] : [])])}
            ${b.details ? block('Détails', `<div class="desc">${esc(b.details)}</div>`) : ''}`;
    }
    function reportTypeOf(id) { return state.reg.types && state.reg.types.types.find((x) => x.id === id); }
    const optLabel = (f, v) => { const o = (f.o || []).find((x) => x[0] === v); return o ? o[1] : v; };
    function fieldValueHtml(f, v) {
        if (v === undefined || v === null || v === '' || (Array.isArray(v) && !v.length)) return '';
        if (f.t === 'check') return v ? 'Oui' : '';
        if (f.t === 'select') return esc(optLabel(f, v));
        if (f.t === 'checks') return esc(arr(v).map((x) => optLabel(f, x)).join(', '));
        if (f.t === 'offense') { const o = (state.reg.types.offenses || []).find((x) => x.id === v); return o ? `${esc(o.t)} <span class="muted">${esc(o.rcw || '')}</span>` : esc(v); }
        if (f.t === 'offclass') return esc(CLASS[v] || v);
        if (f.t === 'num' && f.money) return `${esc(v)} $`;
        if (typeof v === 'object') return esc(arr(v).join(', '));
        return esc(v);
    }
    function fieldRows(fields, data) {
        const rows = [];
        for (const f of fields || []) {
            if (f.t === 'group') rows.push(...fieldRows(f.f, data));
            else if (f.k && !['lookup', 'note', 'list', 'matrix', 'perUnit'].includes(f.t)) { const v = fieldValueHtml(f, data[f.k]); if (v) rows.push([f.l, v]); }
        }
        return rows;
    }
    function fieldsHtml(fields, data) {
        let out = dl(fieldRows(fields, data));
        for (const f of fields || []) {
            if (f.t === 'group') out += (f.f || []).filter((x) => x.t === 'list').length ? fieldsHtml((f.f || []).filter((x) => x.t === 'list'), data) : '';
            else if (f.t === 'list') {
                const items = arr(data[f.k]);
                if (items.length) out += `<div class="rv-section"><b>${esc(f.l)} (${items.length})</b>${items.map((it, i) => `<div class="rv-item"><span class="muted">${esc(f.item || '')} ${i + 1}</span>${dl(fieldRows(f.f, it || {}))}</div>`).join('')}</div>`;
            }
        }
        return out;
    }
    function reportSheet(r) {
        recordCache[`report:${r.id}`] = r;
        const type = reportTypeOf(r.type);
        return `<div class="d-num">Rapport n°${esc(r.number)} · ${esc(type ? type.label : r.type)}</div><h3 class="d-title">${esc(r.summary || '')}</h3>${recordActions('report', r.id)}
            ${dl([['Intervention', esc(r.call ? `${r.call.number} — ${r.call.title || ''}` : '—')], ['Rédigé par', `${esc(r.createdByName || '—')}${r.unitName ? ` (${esc(r.unitName)})` : ''}`], ['Date', fmtDate(r.createdAt)], ...(r.updatedAt ? [['Modifié', `${fmtDate(r.updatedAt)} par ${esc(r.updatedByName || '—')}`]] : [])])}
            ${type ? type.sections.map((s) => { const h = fieldsHtml(s.f, r.data || {}); return h.replace(/<dl class="info"><\/dl>/g, '') ? `<div class="rv-section"><h4>${esc(s.title)}</h4>${h}</div>` : ''; }).join('') : `<pre>${esc(JSON.stringify(r.data, null, 2))}</pre>`}`;
    }

    // ---------------- modification / suppression de toute fiche ----------------
    const EDIT_FIELDS = {
        identity: [['firstname', 'Prénom', 'text', 40, true], ['middlename', 'Middle name', 'text', 40], ['lastname', 'Nom de famille', 'text', 40, true], ['dob', 'Date de naissance (JJ/MM/AAAA)', 'text', 10, true],
            ['sex', 'Sexe', 'select', { '': '—', M: 'Homme', F: 'Femme' }], ['address', 'Adresse', 'text', 80, true], ['phone', 'Téléphone', 'text', 20], ['ssn', 'SSN', 'text', 11], ['job', 'Emploi', 'text', 40],
            ['physical', 'Description physique', 'text', 200], ['condition', 'Condition', 'select', CONDITION], ['wantedReason', 'Motif de recherche', 'area', 500], ['wantedSince', 'Recherché depuis (JJ/MM/AAAA)', 'text', 10],
            ['licenseStatus', 'Condition du permis', 'select', LICENSE_STATUS]],
        vehicle: [['plate', 'Immatriculation', 'text', 8, true], ['make', 'Marque', 'text', 40], ['model', 'Modèle', 'text', 40], ['year', 'Année', 'text', 4], ['color', 'Couleur', 'text', 40], ['vin', 'VIN', 'text', 17],
            ['regStatus', 'Statut', 'select', REG_STATUS], ['insuranceStatus', 'Assurance', 'select', INSURANCE], ['inspectionDate', 'Contrôle technique (JJ/MM/AAAA)', 'text', 10], ['stolen', 'Volé', 'check'], ['abandoned', 'Abandonné', 'check'], ['commercial', 'Véhicule commercial', 'check']],
        bolo: [['reason', 'Motif', 'text', 120, true], ['location', 'Dernier lieu', 'text', 120, false, 'person'], ['details', 'Détails', 'area', 2000], ['plate', 'Immatriculation (partielle)', 'text', 8, false, 'vehicle'], ['make', 'Marque', 'text', 40, false, 'vehicle'],
            ['model', 'Modèle', 'text', 40, false, 'vehicle'], ['color', 'Couleur', 'text', 40, false, 'vehicle'], ['clothing', 'Tenue', 'area', 500, false, 'person'], ['skin', 'Peau', 'text', 40, false, 'person'], ['height', 'Taille (cm)', 'text', 3, false, 'person']],
    };
    const REG_EDIT = [['status', 'Suivi', 'select', REG_FOLLOW], ['level', 'Niveau de risque', 'select', RISK], ['address', 'Adresse déclarée', 'text', 80], ['lastUpdate', 'Dernière mise à jour (JJ/MM/AAAA)', 'text', 10], ['notes', 'Notes', 'area', 600]];
    function inputHtml(name, label, type, opt, req, value) {
        const v = value ?? '';
        if (type === 'select') return `<label class="field"><span>${esc(label)}</span><select name="${esc(name)}">${Object.entries(opt).map(([k, l]) => `<option value="${esc(k)}" ${String(v) === k ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select></label>`;
        if (type === 'check') return `<label class="check"><input type="checkbox" name="${esc(name)}" ${v ? 'checked' : ''}> ${esc(label)}</label>`;
        if (type === 'area') return `<label class="field span-2"><span>${esc(label)}</span><textarea name="${esc(name)}" rows="3" maxlength="${opt}">${esc(v)}</textarea></label>`;
        return `<label class="field"><span>${esc(label)}${req ? ' <b>*</b>' : ''}</span><input name="${esc(name)}" maxlength="${opt}" value="${esc(v)}"></label>`;
    }
    async function fetchRecord(kind, id) {
        const res = kind === 'bolo' ? await api(`/registry/bolos/${encodeURIComponent(id)}`, undefined, { loud: true })
            : kind === 'report' ? await api(`/registry/reports/${encodeURIComponent(id)}`, undefined, { loud: true })
                : await api(`/records/${kind}/${encodeURIComponent(id)}`, undefined, { loud: true });
        return res ? (res.record || res.bolo || res.report) : null;
    }
    async function editRecord(kind, id) {
        const rec = await fetchRecord(kind, id);
        if (!rec) return;
        recordCache[`${kind}:${id}`] = rec;
        if (kind === 'report' && !state.reg.types) state.reg.types = await api('/registry/report-types');
        $('#recordTitle').textContent = `Modifier : ${KIND_LABEL[kind]} ${rec.number ? `n°${rec.number}` : (kind === 'identity' ? `${rec.lastname} ${rec.firstname}` : rec.plate || '')}`;
        let body = '';
        if (kind === 'report') body = reportFormHtml(reportTypeOf(rec.type), rec.data || {});
        else {
            body = `<div class="form-grid">${EDIT_FIELDS[kind].filter((f) => !f[5] || f[5] === rec.kind).map(([n, l, t, o, r]) => inputHtml(n, l, t, o, r, rec[n])).join('')}</div>`;
            if (kind === 'identity') {
                body += arr(rec.registrations).map((g) => `<div class="d-sec"><h3>Registre ${esc(REGISTRY[g.type] || g.type)}</h3><div class="form-grid" data-regtype="${esc(g.type)}">${REG_EDIT.map(([n, l, t, o]) => inputHtml(`reg.${n}`, l, t, o, false, g[n])).join('')}</div></div>`).join('');
                body += '<p class="form-note">Permis (État, type, mentions), casier et charges du registre : gardés tels quels (modifiables en jeu avec leurs assistants).</p>';
            }
        }
        $('#recordBody').innerHTML = body;
        $('#recordModal').classList.remove('hidden');
        $('#recordForm').onsubmit = async (e) => {
            e.preventDefault();
            let data;
            if (kind === 'report') data = { data: readReportForm($('#recordBody'), rec.data || {}) };
            else {
                data = JSON.parse(JSON.stringify(rec));
                for (const [n, , t] of EDIT_FIELDS[kind]) {
                    const el = $(`#recordBody [name="${n}"]`);
                    if (el) data[n] = t === 'check' ? el.checked : el.value.trim();
                }
                if (kind === 'identity') {
                    data.hasLicense = !!rec.licenseClass && rec.licenseClass !== 'N/A';
                    const regs = {};
                    for (const g of arr(rec.registrations)) {
                        const box = $(`#recordBody [data-regtype="${g.type}"]`);
                        const edited = { ...g };
                        for (const [n] of REG_EDIT) { const el = box && box.querySelector(`[name="reg.${n}"]`); if (el) edited[n] = el.value.trim(); }
                        regs[g.type] = edited;
                    }
                    data.registrations = regs;
                    data.convictions = arr(rec.convictions).filter((c) => !c.registry);
                    delete data.vehicles; delete data.bolos; delete data.reports;
                }
            }
            const ok = await api(`/records/${kind}/${encodeURIComponent(id)}`, { data });
            if (!ok) return;
            $('#recordModal').classList.add('hidden');
            toast('ok', KIND_LABEL[kind], 'Fiche modifiée (jeu et site à jour).');
            refreshOpenRecord(kind, id);
        };
    }
    function reportInput(f, v, prefix) {
        const name = `${prefix}${f.k}`;
        if (f.t === 'select') return inputHtml(name, f.l, 'select', Object.fromEntries([['', '—'], ...(f.o || [])]), f.req, v);
        if (f.t === 'check') return inputHtml(name, f.l, 'check', null, false, v);
        if (f.t === 'area') return inputHtml(name, f.l, 'area', f.max || 2000, f.req, v);
        if (['text', 'date', 'time', 'num'].includes(f.t)) return inputHtml(name, f.l, 'text', f.max || (f.t === 'date' ? 10 : f.t === 'time' ? 5 : 80), f.req, v);
        return '';
    }
    function reportFormFields(fields, data, prefix) {
        let out = '';
        for (const f of fields || []) {
            if (f.t === 'group') out += reportFormFields(f.f, data, prefix);
            else if (f.t === 'list') arr(data[f.k]).forEach((it, i) => { out += `<div class="span-2 d-sec"><h3>${esc(f.item || f.l)} ${i + 1}</h3><div class="form-grid">${reportFormFields(f.f, it || {}, `${prefix}${f.k}.${i}.`)}</div></div>`; });
            else if (f.k) out += reportInput(f, data[f.k], prefix);
        }
        return out;
    }
    function reportFormHtml(type, data) {
        if (!type) return '<div class="error-line">Modèle de rapport inconnu.</div>';
        return `${type.sections.map((s) => `<div class="d-sec"><h3>${esc(s.title)}</h3><div class="form-grid">${reportFormFields(s.f, data, '')}</div></div>`).join('')}
            <p class="form-note">Infractions, personnes liées et tableaux : gardés tels quels (modifiables en jeu).</p>`;
    }
    function readReportForm(root, original) {
        const data = JSON.parse(JSON.stringify(original));
        $$('[name]', root).forEach((el) => {
            const path = el.name.split('.');
            let obj = data;
            for (let i = 0; i < path.length - 1; i += 1) {
                const k = /^\d+$/.test(path[i]) ? Number(path[i]) : path[i];
                if (obj[k] === undefined || obj[k] === null) obj[k] = /^\d+$/.test(path[i + 1]) ? [] : {};
                obj = obj[k];
            }
            obj[path[path.length - 1]] = el.type === 'checkbox' ? el.checked : el.value.trim();
        });
        return data;
    }
    async function deleteRecord(kind, id) {
        const rec = recordCache[`${kind}:${id}`];
        const label = rec ? (kind === 'identity' ? `${String(rec.lastname || '').toUpperCase()} ${rec.firstname || ''}` : rec.number ? `n°${rec.number}` : rec.plate || id) : id;
        const ok = await confirmBox({ title: `Supprimer : ${KIND_LABEL[kind]}`, text: `<b>${esc(label)}</b> sera <b>supprimé(e) définitivement</b> du jeu et du site. Une copie reste dans le journal d'audit. Action irréversible.`, ok: 'Supprimer définitivement' });
        if (!ok) return;
        if (await api(`/records/${kind}/${encodeURIComponent(id)}/delete`, {})) {
            toast('ok', KIND_LABEL[kind], 'Supprimé(e).');
            state.reg.sel = null;
            for (const target of ['#regDetail', '#recordSheet']) if ($(target) && $(target).innerHTML.includes(`data-rdel="${kind}:${id}"`)) $(target).innerHTML = emptyState('Fiche supprimée', '');
            loadRegistry();
        }
    }
    async function refreshOpenRecord(kind, id) {
        if (kind === 'identity' || kind === 'vehicle') {
            const rec = await fetchRecord(kind, id);
            if (rec) for (const target of ['#recordSheet', '#regDetail']) if ($(target) && $(target).innerHTML.includes(`data-redit="${kind}:${id}"`)) showRecord(rec, target);
        } else if (state.reg.sel) selectRegistry(state.reg.sel, true);
        loadRegistry();
    }

    // =================================================================================================================
    // TERMINÉES / HISTORIQUE, JOURNAL DES ACTIONS, AUDIT
    // =================================================================================================================
    const dateToS = (v, end) => (v ? Math.floor(new Date(`${v}T${end ? '23:59:59' : '00:00:00'}`).getTime() / 1000) : 0);
    function pager(res, go) {
        const pages = Math.max(1, Math.ceil(res.total / res.size));
        const el = $('#toolPager');
        el.innerHTML = `<span>${res.total} résultat(s) — page ${res.page} / ${pages}</span><button type="button" class="btn xs" ${res.page <= 1 ? 'disabled' : ''} data-page="${res.page - 1}">Précédente</button><button type="button" class="btn xs" ${res.page >= pages ? 'disabled' : ''} data-page="${res.page + 1}">Suivante</button>`;
        $$('[data-page]', el).forEach((b) => b.addEventListener('click', () => go(Number(b.dataset.page))));
    }
    function renderHistoryTool() {
        setSide(`<form class="tool-form" id="historyForm"><input id="historyQ" type="search" placeholder="N°, intitulé, adresse…"><select id="historyStatus"><option value="all">Toutes</option><option value="closed">Terminées</option><option value="refused">Refusées</option><option value="cancelled">Annulées</option></select>
            <input id="historyFrom" type="date" aria-label="Du"><input id="historyTo" type="date" aria-label="Au"><button type="submit" class="btn primary">${icon('filter')}Filtrer</button></form>
            <p class="form-note top">Cliquez une intervention : fiche à droite, <b>modifiable</b> et réouvrable.</p>
            <table class="table"><thead><tr><th>N°</th><th>Intitulé</th><th>Statut</th><th>Clôture</th></tr></thead><tbody id="historyBody"></tbody></table><div class="pager" id="toolPager"></div>`, '', '');
        $('#historyForm').addEventListener('submit', (e) => { e.preventDefault(); state.historyPage = 1; loadHistory(); });
        $('#historyBody').addEventListener('click', (e) => { const r = e.target.closest('[data-hcall]'); if (r) openCall(Number(r.dataset.hcall)); });
        loadHistory();
    }
    async function loadHistory() {
        if (!$('#historyBody')) return;
        $('#historyBody').innerHTML = `<tr><td colspan="4">${skeleton(4)}</td></tr>`;
        const p = new URLSearchParams({ q: $('#historyQ').value.trim(), status: $('#historyStatus').value, from: dateToS($('#historyFrom').value), to: dateToS($('#historyTo').value, true), page: state.historyPage });
        const res = await api(`/history?${p}`);
        if (!$('#historyBody')) return;
        if (!res) { $('#historyBody').innerHTML = `<tr><td colspan="4">${emptyState('Historique indisponible', '')}</td></tr>`; return; }
        $('#historyBody').innerHTML = res.calls.map((c) => `<tr data-hcall="${c.id}" data-ctx-call="${c.id}"><td class="num">${esc(c.number)}<span class="sub">${prioChip(c.priority)}</span></td><td><b>${esc(c.title)}</b><span class="sub">${esc(c.address)}</span></td><td>${statusChip(c.status)}</td><td>${fmtDate(c.closedAt)}${c.clear ? `<span class="sub">Clear ${esc(c.clear)}</span>` : ''}</td></tr>`).join('')
            || `<tr><td colspan="4">${emptyState('Aucun résultat', '')}</td></tr>`;
        $('#sideMeta').textContent = `${res.total} intervention(s)`;
        pager(res, (page) => { state.historyPage = page; loadHistory(); });
    }
    function renderLogTool() {
        setSide(`<form class="tool-form"><select id="logSource"><option value="all">Toutes les sources</option><option value="dispatch">Dispatch</option><option value="game">Jeu</option><option value="web">Site</option></select></form>
            <table class="table"><thead><tr><th>Date</th><th>Qui</th><th>Action</th></tr></thead><tbody id="logBody"></tbody></table><div class="pager" id="toolPager"></div>`, '', '');
        $('#logSource').addEventListener('change', () => { state.logPage = 1; loadLog(); });
        loadLog();
    }
    async function loadLog() {
        if (!$('#logBody')) return;
        $('#logBody').innerHTML = `<tr><td colspan="3">${skeleton(4)}</td></tr>`;
        const res = await api(`/log?source=${$('#logSource').value}&page=${state.logPage}`);
        if (!$('#logBody')) return;
        if (!res) { $('#logBody').innerHTML = `<tr><td colspan="3">${emptyState('Journal indisponible', '')}</td></tr>`; return; }
        const detail = (l) => { const d = l.details || {}; return [d.number, d.unit, d.title, d.name && `écran de ${d.name} (#${d.serverId})`, d.reason && `motif : ${d.reason}`, d.from && d.to && `${UNIT_STATUS[d.from] || d.from} → ${UNIT_STATUS[d.to] || d.to}`, d.clear && `Clear ${d.clear}`, Array.isArray(d.units) && d.units.length && `unités : ${d.units.join(', ')}`, Array.isArray(d.changes) && d.changes.map((c) => c.label || c.field).join(', ')].filter(Boolean).map(esc).join(' — '); };
        $('#logBody').innerHTML = res.entries.map((l) => `<tr><td class="num">${fmtDate(l.at)}<span class="sub">${esc({ dispatch: 'Dispatch', game: 'Jeu', web: 'Site' }[l.source] || l.source)}</span></td><td>${esc(l.actorName || '—')}</td><td>${esc(ACTIONS[l.action] || l.action)}<span class="sub">${detail(l)}</span></td></tr>`).join('')
            || `<tr><td colspan="3">${emptyState('Journal vide', '')}</td></tr>`;
        pager(res, (page) => { state.logPage = page; loadLog(); });
    }
    function renderAuditTool() {
        setSide(`<form class="tool-form" id="auditForm"><input id="auditQ" type="search" placeholder="Fiche, n°…"><select id="auditKind"><option value="">Tout</option>${Object.entries(KIND_LABEL).map(([k, v]) => `<option value="${k}">${esc(v)}</option>`).join('')}</select>
            <select id="auditAction"><option value="">Toutes actions</option><option value="update">Modifications</option><option value="delete">Suppressions</option><option value="reopen">Réouvertures</option><option value="empty">Messages vidés</option></select></form>
            <table class="table"><thead><tr><th>Date</th><th>Action</th><th>Détail</th></tr></thead><tbody id="auditBody"></tbody></table><div class="pager" id="toolPager"></div>`, '', '');
        ['#auditKind', '#auditAction'].forEach((s) => $(s).addEventListener('change', () => { state.auditPage = 1; loadAudit(); }));
        $('#auditQ').addEventListener('input', () => { clearTimeout(state.auditT); state.auditT = setTimeout(() => { state.auditPage = 1; loadAudit(); }, 300); });
        $('#auditForm').addEventListener('submit', (e) => e.preventDefault());
        loadAudit();
    }
    const diffHtml = (before, after) => {
        if (!before && !after) return '';
        if (!before || !after) return `<span class="sub">${before ? 'copie de la fiche supprimée conservée' : ''}</span>`;
        const keys = [...new Set([...Object.keys(before), ...Object.keys(after)])].filter((k) => !['updatedAt', 'updatedByName', 'searchText'].includes(k) && typeof (after[k] ?? before[k]) !== 'object' && String(before[k] ?? '') !== String(after[k] ?? ''));
        return keys.slice(0, 8).map((k) => `<span class="change">${esc(k)} : <del>${esc(String(before[k] ?? '—').slice(0, 120))}</del> → <ins>${esc(String(after[k] ?? '—').slice(0, 120))}</ins></span>`).join('') || '<span class="sub">détails (listes) modifiés</span>';
    };
    async function loadAudit() {
        if (!$('#auditBody')) return;
        $('#auditBody').innerHTML = `<tr><td colspan="3">${skeleton(4)}</td></tr>`;
        const res = await api(`/audit?${new URLSearchParams({ kind: $('#auditKind').value, action: $('#auditAction').value, q: $('#auditQ').value.trim(), page: state.auditPage })}`);
        if (!$('#auditBody')) return;
        if (!res) { $('#auditBody').innerHTML = `<tr><td colspan="3">${emptyState('Audit indisponible', '')}</td></tr>`; return; }
        $('#auditBody').innerHTML = res.entries.map((a) => `<tr><td class="num">${fmtDate(a.at)}<span class="sub">${esc(a.actorName || '—')} · ${esc({ dispatch: 'Site', game: 'Jeu' }[a.source] || a.source)}</span></td>
            <td><span class="chip ${a.action === 'delete' || a.action === 'purge' ? 'stop' : a.action === 'reopen' ? 'go' : 'accent'}">${esc(AUDIT_ACTION[a.action] || a.action)}</span><span class="sub">${esc(KIND_LABEL[a.kind] || a.kind)}</span></td>
            <td>${esc(a.label)}${diffHtml(a.before, a.after)}</td></tr>`).join('') || `<tr><td colspan="3">${emptyState('Rien pour ces filtres', '')}</td></tr>`;
        pager(res, (page) => { state.auditPage = page; loadAudit(); });
    }

    // =================================================================================================================
    // LIVEVIEW : vidéo WebRTC envoyée par le jeu (pair à pair ou TURN), signalisation par le site.
    // Une liaison par joueur regardé : le jeu fait l'offre, ce navigateur répond. Mosaïque = image réduite ;
    // agrandi (tuile ou incrustation plein écran) = pleine taille, 30 i/s.
    // =================================================================================================================
    const live = { tiles: store.get('mdc.live.tiles', []).map((t) => ({ serverId: t.serverId, pinned: !!t.pinned, masked: !!t.masked })), focus: null,
        pips: store.get('mdc.live.pips', []), conns: new Map(), ice: [], relayOnly: false, filtered: [] };
    const saveTiles = () => { store.set('mdc.live.tiles', live.tiles); store.set('mdc.live.pips', live.pips); };
    const playerById = (id) => state.players.find((p) => p.serverId === id);
    const serviceOf = (p) => (p.agency === 'kcso' || p.agency === 'wsp' ? p.agency : p.agency === 'generic' ? 'generic' : 'none');
    const SERVICE_LABEL = { kcso: 'KCSO', wsp: 'WSP', generic: 'Civil', none: 'Sans MDC' };
    function watched() {
        const map = new Map();
        const liveOpen = state.tool === 'live' && !$('#board').classList.contains('side-collapsed');
        if (liveOpen) for (const t of live.tiles) if (!t.masked && playerById(t.serverId)) map.set(t.serverId, live.focus === t.serverId ? 'focus' : 'grid');
        for (const p of live.pips) if (playerById(p.serverId)) map.set(p.serverId, p.full ? 'focus' : (map.get(p.serverId) || 'grid'));
        return map;
    }
    let liveTimer = null;
    function liveSync() {
        clearTimeout(liveTimer);
        liveTimer = setTimeout(() => {
            if (!socket || !socket.connected) return;
            const want = watched();
            setBadge('live', want.size);
            for (const id of [...live.conns.keys()]) if (!want.has(id)) closeConn(id);
            socket.emit('live:watch', [...want].map(([serverId, mode]) => ({ serverId, mode })), (r) => {
                if (!r || !r.ok) return;
                live.ice = r.iceServers || []; live.relayOnly = !!r.relayOnly;
                if (r.refused && r.refused.length) toast('error', 'LiveView', `Limite atteinte : ${r.refused.length} écran(s) non affiché(s).`);
                for (const [id, peerId] of Object.entries(r.peers || {})) {
                    const serverId = Number(id);
                    const conn = live.conns.get(serverId);
                    if (conn && conn.peerId === peerId) continue;
                    if (conn) closeConn(serverId);
                    live.conns.set(serverId, { peerId, pc: null, session: '', pending: [], stream: null, stats: {}, state: 'attente', lastFrame: 0, lastRestart: 0, prev: null });
                    refreshScreens(serverId);
                }
            });
        }, 60);
    }
    function closeConn(serverId) {
        const c = live.conns.get(serverId);
        if (!c) return;
        live.conns.delete(serverId);
        if (c.pc) try { c.pc.close(); } catch (e) { /* déjà fermée */ }
    }
    function newPc(serverId, conn, session) {
        if (conn.pc) try { conn.pc.close(); } catch (e) { /* déjà fermée */ }
        const pc = new RTCPeerConnection({ iceServers: live.ice, iceTransportPolicy: live.relayOnly ? 'relay' : 'all', bundlePolicy: 'max-bundle' });
        conn.pc = pc; conn.session = session; conn.pending = []; conn.stream = null; conn.state = 'connexion';
        pc.ontrack = (e) => {
            try { e.receiver.jitterBufferTarget = 40; } catch (err) { /* navigateur sans réglage : valeur par défaut */ }
            conn.stream = e.streams[0] || new MediaStream([e.track]);
            refreshScreens(serverId);
        };
        pc.onicecandidate = (e) => socket.emit('live:signal', { peerId: conn.peerId, candidate: e.candidate ? e.candidate.toJSON() : null });
        pc.onconnectionstatechange = () => {
            conn.state = { connected: 'direct', connecting: 'connexion', failed: 'échec', disconnected: 'coupée', closed: 'fermée' }[pc.connectionState] || pc.connectionState;
            if (pc.connectionState === 'failed') requestRestart(serverId);
            updateFoot(serverId);
        };
        return pc;
    }
    function requestRestart(serverId) {
        const c = live.conns.get(serverId);
        if (!c || Date.now() - c.lastRestart < 15000) return;
        c.lastRestart = Date.now();
        socket.emit('live:signal', { peerId: c.peerId, restart: true });
    }
    async function onLiveSignal(msg) {
        const serverId = Number(msg && msg.serverId);
        const conn = live.conns.get(serverId);
        if (!conn || conn.peerId !== msg.peerId) return;
        try {
            if (msg.stats) { conn.pub = msg.stats; return; }
            if (msg.description && msg.description.type === 'offer') {
                const pc = conn.pc && conn.session === msg.session ? conn.pc : newPc(serverId, conn, msg.session);
                await pc.setRemoteDescription(msg.description);
                const answer = await pc.createAnswer();
                await pc.setLocalDescription(answer);
                socket.emit('live:signal', { peerId: conn.peerId, description: { type: 'answer', sdp: pc.localDescription.sdp } });
                for (const c of conn.pending.splice(0)) await pc.addIceCandidate(c).catch(() => {});
            } else if (msg.candidate !== undefined) {
                if (!conn.pc || conn.session !== msg.session || !conn.pc.remoteDescription) conn.pending.push(msg.candidate);
                else await conn.pc.addIceCandidate(msg.candidate).catch(() => {});
            }
        } catch (e) {
            requestRestart(serverId);
        }
    }
    function screens(serverId) { return $$(`[data-tile="${serverId}"] .tile-screen, [data-pip="${serverId}"] .tile-screen`); }
    function refreshScreens(serverId) {
        const c = live.conns.get(serverId);
        for (const screen of screens(serverId)) {
            if (screen.closest('.masked')) continue;
            const v = screen.querySelector('video');
            if (c && c.stream) {
                if (v && v.srcObject === c.stream) continue;
                const video = document.createElement('video');
                video.muted = true; video.autoplay = true; video.playsInline = true; video.disablePictureInPicture = true;
                video.srcObject = c.stream;
                screen.innerHTML = '<span class="lv-badge">EN DIRECT</span>';
                screen.prepend(video);
                video.play().catch(() => {});
                watchFrames(serverId, video);
            } else if (!v) {
                screen.innerHTML = `<div class="placeholder"><span class="spin"></span>${playerById(serverId) ? 'Connexion à l\'écran du joueur…' : 'Joueur déconnecté'}</div>`;
            }
        }
    }
    function watchFrames(serverId, video) { // dernière image affichée (détection d'image figée)
        if (!video.requestVideoFrameCallback) return;
        const tick = () => { const c = live.conns.get(serverId); if (c) c.lastFrame = Date.now(); if (video.isConnected) video.requestVideoFrameCallback(tick); };
        video.requestVideoFrameCallback(tick);
    }
    async function collectStats(serverId) {
        const c = live.conns.get(serverId);
        if (!c || !c.pc) return;
        const report = await c.pc.getStats().catch(() => null);
        if (!report) return;
        const st = {};
        let pair = null;
        report.forEach((s) => {
            if (s.type === 'inbound-rtp' && s.kind === 'video') {
                st.fps = s.framesPerSecond || 0; st.w = s.frameWidth; st.h = s.frameHeight; st.bytes = s.bytesReceived; st.at = s.timestamp;
                st.codec = s.codecId; st.lost = s.packetsLost || 0;
                if (s.jitterBufferEmittedCount) st.delay = Math.round((s.jitterBufferDelay / s.jitterBufferEmittedCount) * 1000);
            }
            if (s.type === 'candidate-pair' && (s.selected || s.nominated) && s.state === 'succeeded') pair = s;
        });
        if (st.codec && report.get(st.codec)) st.codecName = String(report.get(st.codec).mimeType || '').replace('video/', '');
        if (pair) {
            st.rtt = pair.currentRoundTripTime ? Math.round(pair.currentRoundTripTime * 1000) : null;
            const local = report.get(pair.localCandidateId); const remote = report.get(pair.remoteCandidateId);
            st.relay = (local && local.candidateType === 'relay') || (remote && remote.candidateType === 'relay');
        }
        if (c.prev && st.bytes !== undefined && st.at > c.prev.at) st.kbps = Math.round(((st.bytes - c.prev.bytes) * 8) / (st.at - c.prev.at));
        c.prev = { bytes: st.bytes, at: st.at };
        c.stats = st;
        // connectée mais plus aucune image depuis 5 s : redémarrage de la liaison (une fois toutes les 15 s)
        if (c.pc.connectionState === 'connected' && c.lastFrame && Date.now() - c.lastFrame > 5000) requestRestart(serverId);
    }
    function footHtml(serverId) {
        const c = live.conns.get(serverId);
        if (!c) return '<span class="dot"></span><span>arrêté</span>';
        const s = c.stats || {};
        const ok = c.pc && c.pc.connectionState === 'connected' && c.lastFrame && Date.now() - c.lastFrame < 2500;
        const tone2 = ok ? (s.fps >= 20 ? 'go' : 'caution') : (c.state === 'échec' ? 'stop' : '');
        return `<span class="dot ${tone2}"></span><span>${s.fps ? `${Math.round(s.fps)} i/s` : '— i/s'}</span><span>${s.w ? `${s.w}×${s.h}` : '—'}</span><span>${s.kbps ? `${s.kbps >= 1000 ? `${(s.kbps / 1000).toFixed(1)} Mb/s` : `${s.kbps} kb/s`}` : ''}</span>
            <span>${s.rtt != null ? `${s.rtt} ms` : ''}</span><span>${s.codecName || ''}</span><span>${c.pc && c.pc.connectionState === 'connected' ? (s.relay ? 'TURN' : 'direct') : esc(c.state)}</span>${c.pub && c.pub.fps ? `<span title="cadence capturée par le jeu">jeu ${Math.round(c.pub.fps)} i/s</span>` : ''}`;
    }
    function updateFoot(serverId) { $$(`[data-foot="${serverId}"]`).forEach((el) => { el.innerHTML = footHtml(serverId); }); }
    setInterval(async () => {
        for (const id of live.conns.keys()) { await collectStats(id); updateFoot(id); }
    }, 1000);

    function tileHtml(t) {
        const p = playerById(t.serverId);
        return `<div class="tile ${t.pinned ? 'pinned' : ''} ${t.masked ? 'masked' : ''} ${live.focus === t.serverId ? 'focus' : ''}" data-tile="${t.serverId}" draggable="true">
            <div class="tile-head"><span class="t-name">${esc(p ? p.name : `Joueur ${t.serverId}`)}<small>#${t.serverId}${p && p.unitName ? ` · ${esc(p.unitName)}` : ''}</small></span>
                ${p ? `<span class="chip ${serviceOf(p)}">${esc(SERVICE_LABEL[serviceOf(p)])}</span>` : ''}
                <button type="button" class="ibtn" data-tact="focus" title="${live.focus === t.serverId ? 'Réduire' : 'Agrandir (pleine qualité)'}">${icon('expand')}</button>
                <button type="button" class="ibtn" data-tact="pin" title="${t.pinned ? 'Désépingler' : 'Épingler en tête'}" aria-pressed="${t.pinned}">${icon('pin')}</button>
                <button type="button" class="ibtn" data-tact="mask" title="${t.masked ? 'Réafficher' : 'Masquer (coupe le flux)'}">${icon(t.masked ? 'eye' : 'eyeoff')}</button>
                <button type="button" class="ibtn" data-tact="pip" title="Incrustation (reste visible partout)">${icon('pip')}</button>
                <button type="button" class="ibtn" data-tact="remove" title="Retirer">${icon('x')}</button></div>
            <div class="tile-screen">${!p ? '<div class="placeholder">Joueur déconnecté</div>' : t.masked ? '<div class="placeholder">Masqué — aucune vidéo reçue</div>' : '<div class="placeholder"><span class="spin"></span>Connexion à l\'écran du joueur…</div>'}</div>
            <div class="tile-foot" data-foot="${t.serverId}">${footHtml(t.serverId)}</div></div>`;
    }
    function renderLiveTool() {
        $('#board').classList.add('side-wide');
        setSide(`<div class="live">
            <div class="live-tools"><input id="liveQ" type="search" placeholder="Joueur, n°, unité…" aria-label="Filtrer les joueurs">
                <select id="liveService"><option value="">Tous</option><option value="kcso">KCSO</option><option value="wsp">WSP</option><option value="generic">Civils</option><option value="none">Sans MDC</option></select>
                <select id="liveUnit"><option value="">Toutes les unités</option></select>
                <button type="button" class="btn sm" id="liveAddAll">Afficher la sélection</button><button type="button" class="btn sm ghost" id="liveClear">Tout retirer</button></div>
            <div class="live-wrap"><div class="live-players" id="livePlayers"></div><div class="live-grid" id="liveGrid"></div></div></div>`, '', 'vidéo WebRTC du jeu');
        $('#liveQ').addEventListener('input', renderLivePlayers);
        ['#liveService', '#liveUnit'].forEach((s) => $(s).addEventListener('change', renderLivePlayers));
        $('#livePlayers').addEventListener('change', (e) => {
            const cb = e.target.closest('[data-lp]');
            if (!cb) return;
            const id = Number(cb.dataset.lp);
            if (cb.checked) { if (!live.tiles.some((t) => t.serverId === id)) live.tiles.push({ serverId: id, pinned: false, masked: false }); } else live.tiles = live.tiles.filter((t) => t.serverId !== id);
            saveTiles(); renderLiveGrid(); liveSync();
        });
        $('#liveAddAll').addEventListener('click', () => { for (const p of live.filtered) if (!live.tiles.some((t) => t.serverId === p.serverId)) live.tiles.push({ serverId: p.serverId, pinned: false, masked: false }); saveTiles(); renderLivePlayers(); renderLiveGrid(); liveSync(); });
        $('#liveClear').addEventListener('click', () => { live.tiles = []; live.focus = null; saveTiles(); renderLivePlayers(); renderLiveGrid(); liveSync(); });
        let dragId = null;
        const grid = $('#liveGrid');
        grid.addEventListener('dragstart', (e) => { const tile = e.target.closest('[data-tile]'); if (!tile) return; dragId = Number(tile.dataset.tile); tile.classList.add('dragging'); e.dataTransfer.effectAllowed = 'move'; e.dataTransfer.setData('text/plain', `tile:${dragId}`); });
        grid.addEventListener('dragend', () => { dragId = null; $$('.tile').forEach((t) => t.classList.remove('dragging', 'drop-target')); });
        grid.addEventListener('dragover', (e) => { const tile = e.target.closest('[data-tile]'); if (!tile || dragId === null) return; e.preventDefault(); $$('.tile').forEach((t) => t.classList.toggle('drop-target', t === tile && Number(tile.dataset.tile) !== dragId)); });
        grid.addEventListener('drop', (e) => {
            const tile = e.target.closest('[data-tile]');
            if (!tile || dragId === null) return;
            e.preventDefault();
            const from = live.tiles.findIndex((t) => t.serverId === dragId); const to = live.tiles.findIndex((t) => t.serverId === Number(tile.dataset.tile));
            if (from < 0 || to < 0 || from === to) return;
            const [moved] = live.tiles.splice(from, 1); live.tiles.splice(to, 0, moved);
            saveTiles(); renderLiveGrid();
        });
        grid.addEventListener('click', (e) => {
            const b = e.target.closest('[data-tact]');
            if (!b) return;
            const id = Number(b.closest('[data-tile]').dataset.tile);
            const t = live.tiles.find((x) => x.serverId === id);
            if (!t) return;
            const act = b.dataset.tact;
            if (act === 'focus') live.focus = live.focus === id ? null : id;
            if (act === 'pin') t.pinned = !t.pinned;
            if (act === 'mask') t.masked = !t.masked;
            if (act === 'remove') { live.tiles = live.tiles.filter((x) => x.serverId !== id); if (live.focus === id) live.focus = null; }
            if (act === 'pip') openPip(id);
            saveTiles(); renderLivePlayers(); renderLiveGrid(); liveSync();
        });
        grid.addEventListener('dblclick', (e) => { const tile = e.target.closest('[data-tile]'); if (!tile || e.target.closest('button')) return; const id = Number(tile.dataset.tile); live.focus = live.focus === id ? null : id; renderLiveGrid(); liveSync(); });
        renderLivePlayers();
        renderLiveGrid();
    }
    function renderLivePlayers() {
        if (!$('#livePlayers')) return;
        const q = norm($('#liveQ').value); const service = $('#liveService').value; const unit = $('#liveUnit').value;
        const units = [...new Set(state.players.map((p) => p.unitName).filter(Boolean))].sort();
        $('#liveUnit').innerHTML = `<option value="">Toutes les unités</option>${units.map((u) => `<option ${u === unit ? 'selected' : ''}>${esc(u)}</option>`).join('')}`;
        const shown = new Set(live.tiles.map((t) => t.serverId));
        live.filtered = state.players.filter((p) => (!service || serviceOf(p) === service) && (!unit || p.unitName === unit) && (!q || norm(`${p.name} ${p.serverId} ${p.unitName || ''}`).includes(q)));
        $('#livePlayers').innerHTML = live.filtered.map((p) => `<label class="lp"><input type="checkbox" data-lp="${p.serverId}" ${shown.has(p.serverId) ? 'checked' : ''} aria-label="Afficher ${esc(p.name)}">
            <span class="lp-name">${esc(p.name)}<small>#${p.serverId}${p.unitName ? ` · ${esc(p.unitName)}` : ''}</small></span><span class="chip ${serviceOf(p)}">${esc(SERVICE_LABEL[serviceOf(p)])}</span></label>`).join('')
            || emptyState('Aucun joueur', state.players.length ? 'Aucun joueur pour ces filtres.' : 'Personne n\'est connecté en jeu.');
    }
    function renderLiveGrid() {
        const grid = $('#liveGrid');
        if (!grid) return;
        const tiles = [...live.tiles].sort((a, b) => (b.pinned ? 1 : 0) - (a.pinned ? 1 : 0));
        grid.classList.toggle('focus-on', live.focus !== null && tiles.some((t) => t.serverId === live.focus));
        grid.innerHTML = tiles.map(tileHtml).join('') || emptyState('Aucun écran affiché', 'Cochez des joueurs à gauche (vidéo en direct, 30 i/s en agrandi).');
        for (const t of tiles) refreshScreens(t.serverId);
    }
    // ---- incrustation (PiP) : reste visible partout, déplaçable, aimantée aux coins ----
    function openPip(serverId) {
        if (!live.pips.some((p) => p.serverId === serverId)) live.pips.push({ serverId, corner: 'br', w: 380, full: false });
        saveTiles(); renderPips(); liveSync();
    }
    function closePip(serverId) { live.pips = live.pips.filter((p) => p.serverId !== serverId); saveTiles(); renderPips(); liveSync(); }
    function pipFull() { const p = live.pips.find((x) => x.full); if (p) { p.full = false; saveTiles(); renderPips(); liveSync(); return true; } return false; }
    function placePip(el, p, i) {
        if (p.full) { ['left', 'top', 'right', 'bottom', 'width'].forEach((k) => { el.style[k] = ''; }); return; }
        el.style.width = `${p.w}px`;
        const off = 16 + i * 26;
        el.style.left = p.corner.includes('l') ? `${off}px` : 'auto'; el.style.right = p.corner.includes('r') ? `${off + 46}px` : 'auto';
        el.style.top = p.corner.includes('t') ? `calc(var(--top) + var(--svc) + ${off}px)` : 'auto'; el.style.bottom = p.corner.includes('b') ? `${off}px` : 'auto';
    }
    function renderPips() {
        $$('.pip').forEach((el) => { if (!live.pips.some((p) => String(p.serverId) === el.dataset.pip)) el.remove(); });
        live.pips.forEach((p, i) => {
            let el = $(`.pip[data-pip="${p.serverId}"]`);
            const pl = playerById(p.serverId);
            if (!el) {
                el = document.createElement('aside');
                el.className = 'pip tile';
                el.dataset.pip = p.serverId;
                el.setAttribute('aria-label', 'LiveView en incrustation');
                document.body.appendChild(el);
                el.addEventListener('click', (e) => {
                    const b = e.target.closest('[data-pact]');
                    const cur = live.pips.find((x) => x.serverId === p.serverId);
                    if (!b || !cur) return;
                    if (b.dataset.pact === 'close') closePip(cur.serverId);
                    if (b.dataset.pact === 'full') { cur.full = !cur.full; saveTiles(); renderPips(); liveSync(); }
                    if (b.dataset.pact === 'size') { cur.w = cur.w >= 640 ? 300 : cur.w + 170; saveTiles(); renderPips(); }
                });
                el.addEventListener('pointerdown', (e) => {
                    const cur = live.pips.find((x) => x.serverId === p.serverId);
                    if (e.target.closest('button') || !cur || cur.full || !e.target.closest('.tile-head')) return;
                    const r = el.getBoundingClientRect(); const ox = e.clientX - r.left; const oy = e.clientY - r.top;
                    const move = (ev) => { el.style.left = `${ev.clientX - ox}px`; el.style.top = `${ev.clientY - oy}px`; el.style.right = 'auto'; el.style.bottom = 'auto'; };
                    const up = (ev) => { removeEventListener('pointermove', move); removeEventListener('pointerup', up); cur.corner = `${ev.clientY < innerHeight / 2 ? 't' : 'b'}${ev.clientX < innerWidth / 2 ? 'l' : 'r'}`; saveTiles(); placePip(el, cur, live.pips.indexOf(cur)); };
                    addEventListener('pointermove', move); addEventListener('pointerup', up);
                });
            }
            el.classList.toggle('full', !!p.full);
            el.innerHTML = `<div class="tile-head"><span class="t-name">${esc(pl ? pl.name : `Joueur ${p.serverId}`)}<small>#${p.serverId}${pl && pl.unitName ? ` · ${esc(pl.unitName)}` : ''}</small></span>
                <button type="button" class="ibtn" data-pact="size" title="Taille">${icon('pip')}</button><button type="button" class="ibtn" data-pact="full" title="${p.full ? 'Réduire' : 'Plein écran (pleine qualité)'}">${icon('expand')}</button>
                <button type="button" class="ibtn" data-pact="close" title="Fermer">${icon('x')}</button></div>
                <div class="tile-screen">${pl ? '<div class="placeholder"><span class="spin"></span>Connexion…</div>' : '<div class="placeholder">Joueur déconnecté</div>'}</div><div class="tile-foot" data-foot="${p.serverId}">${footHtml(p.serverId)}</div>`;
            placePip(el, p, i);
            refreshScreens(p.serverId);
        });
    }

    // =================================================================================================================
    // LIGNE DE COMMANDE (Ctrl + K) : codes courts du dispatch, suggestions au fil de la frappe
    // =================================================================================================================
    const COMMANDS = [
        ['N', 'Nouvelle intervention'], ['I', 'Nouvel incident'],
        ['<unité> DI|ER|SP|IN', 'Statut d\'une unité (disponible, en route, sur place, indisponible)'],
        ['AS <unité> <n°>', 'Affecter une unité à une intervention'], ['RT <unité> <n°>', 'Retirer une unité d\'une intervention'],
        ['<n°>', 'Ouvrir une intervention (ex. 4817 ou RD4817)'], ['MOD <n°>', 'Modifier une intervention (en cours ou terminée)'],
        ['CL <n°> [A|B|C]', 'Clôturer (code Clear facultatif, WSP)'], ['RO <n°>', 'Rouvrir une intervention terminée'],
        ['AN <n°> [motif]', 'Annuler une intervention'], ['VA <n°>', 'Valider un appel en attente'],
        ['NOTE <n°> <texte>', 'Ajouter une note du dispatch'], ['MSG <unité> <texte>', 'Message à une unité'],
        ['NS <texte>', 'Remplacer la note de service'], ['P <nom> <prénom> <JJ/MM/AAAA>', 'Rechercher une identité'],
        ['V <plaque>', 'Rechercher un véhicule'], ['LIVE <unité|joueur>', 'LiveView en incrustation'], ['?', 'Aide'],
    ];
    const findUnit = (token) => {
        const t = norm(token);
        if (!t) return null;
        return state.units.find((u) => norm(u.name) === t || norm(u.tag) === t) || state.units.find((u) => norm(u.name).replace(/[\s-]/g, '') === t.replace(/[\s-]/g, ''))
            || state.units.filter((u) => u.connected).find((u) => norm(u.name).startsWith(t)) || null;
    };
    const findCall = (token) => {
        const t = String(token || '').replace(/^#/, '').toUpperCase();
        if (!t) return null;
        const pool = state.calls;
        return pool.find((c) => String(c.number).toUpperCase() === t) || pool.find((c) => String(c.number).toUpperCase().endsWith(t)) || (/^\d+$/.test(t) ? pool.find((c) => c.id === Number(t)) : null) || null;
    };
    async function callByToken(token) {
        const c = findCall(token);
        if (c) return c;
        // intervention terminée plus ancienne : recherchée dans l'historique
        const res = await api(`/history?${new URLSearchParams({ q: String(token).replace(/^#/, ''), status: 'all', page: 1 })}`);
        return res && res.calls.length ? res.calls[0] : null;
    }
    function suggestions(raw) {
        const q = raw.trim();
        const out = [];
        if (!q) return COMMANDS.slice(0, 8).map(([code, label]) => ({ code, label, fill: code.split(' ')[0] === '<n°>' ? '' : `${code.split(' ')[0]} ` }));
        const words = q.split(/\s+/);
        const head = words[0].toUpperCase();
        const n = norm(q);
        for (const [code, label] of COMMANDS) if (code.split(' ')[0] === head || norm(label).includes(n)) out.push({ code, label, fill: `${code.split(' ')[0]} ` });
        for (const c of state.calls.filter((x) => norm([x.number, x.title, x.address].join(' ')).includes(n)).slice(0, 5)) out.push({ code: c.number, label: `${c.title} — ${c.address}`, hint: CALL_STATUS[c.status], run: () => openCall(c.id) });
        const u = findUnit(q) || findUnit(words[0]);
        if (u && norm(u.name) === norm(q)) Object.entries(UNIT_CODE).filter(([k]) => k !== u.status).forEach(([k, code]) => out.push({ code: `${u.name} ${code}`, label: `${u.name} : ${UNIT_STATUS[k]}`, run: () => setUnitStatus(u.id, k) }));
        for (const unit of state.units.filter((x) => x.connected && norm([x.name, x.tag].join(' ')).includes(n)).slice(0, 4)) if (unit !== u) out.push({ code: unit.name, label: `${UNIT_STATUS[unit.status]}${(unit.calls || []).length ? ` · ${unit.calls[0].number}` : ''}`, fill: `${unit.name} ` });
        return out.slice(0, 10);
    }
    let cmdSel = 0;
    function renderCmdList() {
        const list = suggestions($('#cmd').value);
        cmdSel = Math.min(cmdSel, Math.max(0, list.length - 1));
        $('#cmdList').innerHTML = list.map((s, i) => `<div class="cmd-item" role="option" data-ci="${i}" aria-selected="${i === cmdSel}"><code>${esc(s.code)}</code><span>${esc(s.label)}</span>${s.hint ? `<small>${esc(s.hint)}</small>` : ''}</div>`).join('');
        $('#cmdList').classList.toggle('hidden', !list.length || document.activeElement !== $('#cmd'));
        $('#cmdList')._items = list;
    }
    $('#cmd').addEventListener('input', () => { cmdSel = 0; renderCmdList(); });
    $('#cmd').addEventListener('focus', renderCmdList);
    $('#cmd').addEventListener('blur', () => setTimeout(() => $('#cmdList').classList.add('hidden'), 120));
    $('#cmdList').addEventListener('mousedown', (e) => {
        const it = e.target.closest('[data-ci]');
        if (!it) return;
        e.preventDefault();
        useSuggestion($('#cmdList')._items[Number(it.dataset.ci)]);
    });
    function useSuggestion(s) {
        if (!s) return;
        if (s.run) { $('#cmd').value = ''; $('#cmd').blur(); s.run(); return; }
        $('#cmd').value = s.fill || `${s.code} `;
        $('#cmd').focus();
        renderCmdList();
    }
    $('#cmd').addEventListener('keydown', async (e) => {
        const items = $('#cmdList')._items || [];
        if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { e.preventDefault(); cmdSel = (cmdSel + (e.key === 'ArrowDown' ? 1 : -1) + items.length) % Math.max(1, items.length); renderCmdList(); return; }
        if (e.key === 'Tab' && items.length && $('#cmd').value.trim()) { e.preventDefault(); useSuggestion(items[cmdSel]); return; }
        if (e.key === 'Escape') { $('#cmd').value = ''; $('#cmd').blur(); return; }
        if (e.key !== 'Enter') return;
        e.preventDefault();
        const text = $('#cmd').value.trim();
        if (!text) { if (items[cmdSel]) useSuggestion(items[cmdSel]); return; }
        const done = await runCommand(text);
        if (done) { $('#cmd').value = ''; cmdSel = 0; renderCmdList(); }
    });
    async function runCommand(text) {
        const words = text.split(/\s+/);
        const head = words[0].toUpperCase();
        const rest = (i) => words.slice(i).join(' ');
        const needCall = async (tok) => { const c = await callByToken(tok); if (!c) toast('error', 'Commande', `Intervention « ${tok || '?'} » introuvable.`); return c; };
        const needUnit = (tok) => { const u = findUnit(tok); if (!u) toast('error', 'Commande', `Unité « ${tok || '?'} » introuvable.`); return u; };
        if (head === '?' || head === 'AIDE' || head === 'HELP') { showHelp(); return true; }
        if (head === 'N' || head === 'NOUVELLE') { openNew('intervention'); return true; }
        if (head === 'I' || head === 'INCIDENT') { openNew('incident'); return true; }
        // nom d'unité avec espaces (« Adam 12 ») : le n° d'intervention est le dernier mot
        const unitPart = (from, to) => words.slice(from, to).join(' ');
        if (head === 'AS' || head === 'AFF') { const u = needUnit(unitPart(1, -1)); if (!u) return false; const c = await needCall(words[words.length - 1]); if (!c) return false; await assign(c.id, u.id); return true; }
        if (head === 'RT') { const u = needUnit(unitPart(1, -1)); if (!u) return false; const c = await needCall(words[words.length - 1]); if (!c) return false; if (await api(`/calls/${c.id}/unassign`, { unitId: u.id })) toast('ok', c.number, `${u.name} retirée.`); return true; }
        if (head === 'CL') { const c = await needCall(words[1]); if (!c) return false; const clear = (words[2] || '').toUpperCase(); if (await api(`/calls/${c.id}/close`, { clear: ['A', 'B', 'C'].includes(clear) ? clear : '' })) toast('ok', c.number, 'Intervention clôturée.'); return true; }
        if (head === 'RO') { const c = await needCall(words[1]); if (!c) return false; if (await api(`/calls/${c.id}/reopen`, {})) toast('ok', c.number, 'Intervention rouverte.'); return true; }
        if (head === 'AN') { const c = await needCall(words[1]); if (!c) return false; if (await api(`/calls/${c.id}/cancel`, { reason: rest(2) })) toast('ok', c.number, 'Intervention annulée.'); return true; }
        if (head === 'VA') { const c = await needCall(words[1]); if (!c) return false; if (await api(`/calls/${c.id}/validate`, { units: [] })) toast('ok', c.number, 'Validée et transmise.'); return true; }
        if (head === 'MOD') { const c = await needCall(words[1]); if (!c) return false; await openCall(c.id); enterEdit(); return true; }
        if (head === 'NOTE') { const c = await needCall(words[1]); if (!c || !rest(2)) return false; if (await api(`/calls/${c.id}/note`, { text: rest(2) })) toast('ok', c.number, 'Note ajoutée.'); return true; }
        if (head === 'MSG') {
            // MSG <unité> <texte> : le nom d'unité le plus long qui correspond (« Adam 12 »)
            let u = null; let at = 2;
            for (let i = Math.min(words.length - 1, 4); i >= 2; i -= 1) { const x = findUnit(unitPart(1, i)); if (x && norm(x.name) === norm(unitPart(1, i))) { u = x; at = i; break; } }
            if (!u) u = needUnit(words[1]);
            if (!u || !rest(at)) return false;
            if (await api('/messages', { channel: `d:u:${u.id}`, text: rest(at) })) toast('ok', u.name, 'Message envoyé.');
            return true;
        }
        if (head === 'NS') { await saveServiceNote(rest(1)); return true; }
        if (head === 'P' && words.length >= 3) {
            const dob = words.find((w) => /^\d{2}\/\d{2}\/\d{4}$/.test(w)) || '';
            const names = words.slice(1).filter((w) => w !== dob);
            openTool('search'); state.searchType = 'identity'; renderTool();
            runSearch({ type: 'identity', lastname: names[0] || '', firstname: names.slice(1).join(' '), dob, ssn: '' });
            return true;
        }
        if (head === 'V' && words[1]) { openTool('search'); state.searchType = 'vehicle'; renderTool(); runSearch({ type: 'vehicle', query: words[1] }); return true; }
        if (head === 'LIVE' && words[1]) {
            const u = findUnit(words[1]);
            const p = u ? state.players.find((x) => x.unitId === u.id) : state.players.find((x) => String(x.serverId) === words[1] || norm(x.name).includes(norm(rest(1))));
            if (!p) { toast('error', 'LiveView', 'Joueur introuvable.'); return false; }
            openPip(p.serverId); return true;
        }
        // <unité> <code> : statut (« Adam 12 ER »)
        const last = words[words.length - 1].toUpperCase();
        if (words.length >= 2 && CODE_STATUS[last]) { const u = needUnit(unitPart(0, -1)); if (!u) return false; await setUnitStatus(u.id, CODE_STATUS[last]); return true; }
        // n° d'intervention seul, ou nom d'unité (menu de l'unité)
        if (words.length === 1) {
            const c = await callByToken(words[0]);
            if (c) { openCall(c.id); return true; }
        }
        const u = findUnit(text);
        if (u) { const r = $('#cmdBox').getBoundingClientRect(); unitMenu(u, r.left + 20, r.bottom + 4); return true; }
        toast('error', 'Commande inconnue', 'Tapez ? pour la liste des commandes.');
        return false;
    }
    function showHelp() {
        $('#helpBody').innerHTML = `<h4>Ligne de commande (Ctrl + K)</h4>${COMMANDS.map(([c, l]) => `<div><code>${esc(c)}</code><span>${esc(l)}</span></div>`).join('')}
            <h4>Tableau</h4><div><code>Glisser une unité</code><span>sur une carte : l'affecter (à valider : validée avec elle)</span></div><div><code>Clic sur une unité</code><span>statut, message, affectation, LiveView</span></div>
            <div><code>Clic droit</code><span>actions sur une carte, une ligne</span></div><div><code>Double-clic unité</code><span>conversation avec l'unité</span></div>
            <h4>Raccourcis</h4><div><code>N / I</code><span>nouvelle intervention / nouvel incident</span></div><div><code>1 … 9</code><span>outils du panneau (barre d'icônes)</span></div>
            <div><code>E</code><span>modifier l'intervention ouverte</span></div><div><code>V</code><span>valider l'intervention ouverte (à valider)</span></div><div><code>Échap</code><span>fermer, annuler la modification</span></div>`;
        $('#helpModal').classList.remove('hidden');
    }
    $('#helpBtn').addEventListener('click', showHelp);

    // ---------------- raccourcis clavier ----------------
    document.addEventListener('keydown', (e) => {
        if ((e.ctrlKey || e.metaKey) && (e.key === 'k' || e.key === 'K')) { e.preventDefault(); $('#cmd').focus(); $('#cmd').select(); return; }
        const field = e.target.closest('input, textarea, select, [contenteditable]');
        const typing = field && !(field.tagName === 'INPUT' && ['checkbox', 'radio', 'button', 'submit', 'range'].includes(field.type));
        if (e.key === 'Escape') {
            hideMenu();
            const modal = $$('.modal').find((m) => !m.classList.contains('hidden'));
            if (modal && modal.id !== 'confirmModal') { modal.classList.add('hidden'); return; }
            if (pipFull()) return;
            if (state.editMode) { leaveEdit(); return; }
            if (state.svcEditing && state.tool === 'note') { state.svcEditing = false; renderTool(); return; }
            if (typing) e.target.blur();
            return;
        }
        if (typing || e.ctrlKey || e.metaKey || e.altKey) return;
        if ($$('.modal').some((m) => !m.classList.contains('hidden'))) return;
        const k = e.key;
        if (/^[1-9]$/.test(k)) { e.preventDefault(); openTool(TOOL_KEYS[Number(k) - 1]); return; }
        if (k === 'n' || k === 'N') { e.preventDefault(); openNew('intervention'); return; }
        if (k === 'i' || k === 'I') { e.preventDefault(); openNew('incident'); return; }
        if (k === '?') { e.preventDefault(); showHelp(); return; }
        if (k === '/') { e.preventDefault(); $('#cmd').focus(); return; }
        if ((k === 'e' || k === 'E') && state.call && state.tool === 'call') { e.preventDefault(); enterEdit(); return; }
        if ((k === 'v' || k === 'V') && state.call && state.call.status === 'awaiting') { e.preventDefault(); callAction('validate'); }
    });

    // ---------------- menus contextuels ----------------
    document.addEventListener('contextmenu', (e) => {
        const callEl = e.target.closest('[data-call], [data-ctx-call]');
        const unitEl = e.target.closest('[data-unit]');
        const recEl = e.target.closest('[data-ctx-rec]');
        const tileEl = e.target.closest('[data-tile]');
        if (!callEl && !unitEl && !recEl && !tileEl) return;
        e.preventDefault();
        if (unitEl) { unitMenu(unitById(unitEl.dataset.unit), e.clientX, e.clientY); return; }
        if (callEl) {
            const id = Number(callEl.dataset.call || callEl.dataset.ctxCall);
            const c = callById(id) || { id, status: 'closed', number: '' };
            const free = state.units.filter((u) => u.connected && u.status === 'available' && !(u.calls || []).length && !c.units?.some((x) => x.id === u.id));
            menu(e.clientX, e.clientY, [
                { title: `${c.number || ''} ${c.title || ''}` },
                { label: 'Ouvrir', icon: 'call', action: () => openCall(id) },
                { label: 'Modifier', icon: 'edit', action: async () => { await openCall(id); enterEdit(); } },
                ...(c.status === 'awaiting' ? [{ label: 'Valider et transmettre', icon: 'check', action: async () => { if (await api(`/calls/${id}/validate`, { units: [] })) toast('ok', c.number, 'Transmise.'); } }] : []),
                ...(['pending', 'ongoing', 'awaiting'].includes(c.status) ? free.slice(0, 6).map((u) => ({ label: `Affecter ${u.name}`, icon: 'units', action: () => assign(id, u.id) })) : []),
                ...(['closed', 'refused', 'cancelled'].includes(c.status) ? [{ label: 'Rouvrir', icon: 'reopen', action: async () => { if (await api(`/calls/${id}/reopen`, {})) toast('ok', c.number, 'Rouverte.'); } }] : []),
                { sep: true },
                { label: 'Supprimer définitivement', icon: 'trash', danger: true, action: async () => { await openCall(id); callAction('delete'); } },
            ]);
        } else if (recEl) {
            const i = recEl.dataset.ctxRec.indexOf(':');
            const kind = recEl.dataset.ctxRec.slice(0, i); const rid = recEl.dataset.ctxRec.slice(i + 1);
            menu(e.clientX, e.clientY, [{ label: 'Ouvrir', icon: 'reg', action: () => { const row = recEl.closest('[data-row]'); if (row) selectRegistry(row.dataset.row); } },
                { label: 'Modifier', icon: 'edit', action: () => editRecord(kind, rid) }, { sep: true }, { label: 'Supprimer définitivement', icon: 'trash', danger: true, action: () => deleteRecord(kind, rid) }]);
        } else if (tileEl) {
            const id = Number(tileEl.dataset.tile);
            menu(e.clientX, e.clientY, [{ label: 'Incrustation (PiP)', icon: 'pip', action: () => openPip(id) },
                { label: 'Plein écran', icon: 'expand', action: () => { openPip(id); const p = live.pips.find((x) => x.serverId === id); if (p) { p.full = true; saveTiles(); renderPips(); liveSync(); } } },
                { label: 'Retirer', icon: 'x', danger: true, action: () => { live.tiles = live.tiles.filter((x) => x.serverId !== id); saveTiles(); renderLiveGrid(); liveSync(); } }]);
        }
    });

    // =================================================================================================================
    // TEMPS RÉEL
    // =================================================================================================================
    let socket = null;
    let callTimer = null;
    function refreshCall() {
        clearTimeout(callTimer);
        callTimer = setTimeout(async () => { if (!state.callId) return; const res = await api(`/calls/${state.callId}`); if (res && state.callId === res.call.id) { state.call = res.call; if (state.tool === 'call' && !state.editMode) renderTool(); } }, 150);
    }
    function connect() {
        socket = io({ withCredentials: true });
        socket.on('connect', () => { $('#indRealtime').classList.add('on'); refreshState().then(liveSync); });
        socket.on('disconnect', () => $('#indRealtime').classList.remove('on'));
        socket.on('connect_error', (err) => { $('#indRealtime').classList.remove('on'); if (err && err.message === 'unauthorized') location.href = '/login'; });
        socket.on('revoked', () => { location.href = '/denied?reason=role'; });
        socket.on('station', (s) => { state.station = s; renderHeader(); if (state.editMode && state.callId) socket.emit('edit:start', state.callId); });
        socket.on('calls', (calls) => {
            state.calls = calls;
            $$('#toasts .toast.awaiting[data-call]').forEach((t) => { if (!calls.some((c) => c.id === Number(t.dataset.call) && c.status === 'awaiting')) t.remove(); });
            renderBoard();
            if (state.callId && !state.editMode) refreshCall();
        });
        socket.on('units', (units) => {
            state.units = units; renderBoard();
            if (state.call && !state.editMode && state.tool === 'call') renderTool();
            if ($('#newUnits') && !$('#newModal').classList.contains('hidden')) { draft.units = $$('[data-newunit]:checked').map((x) => Number(x.value)); $('#newUnits').innerHTML = newUnitsHtml(); }
        });
        socket.on('dispatch', (d) => { state.dispatch = d; renderHeader(); renderPending(); });
        socket.on('fivem', (f) => { state.fivem = f; if (f.dispatch) state.dispatch = f.dispatch; renderHeader(); });
        socket.on('presence', (p) => { state.presence = p; renderHeader(); });
        socket.on('conversations', (list) => { state.conversations = list; renderChatList(); });
        socket.on('positions', (map) => { state.positions = map || {}; renderUnits(); });
        socket.on('position', (p) => { state.positions[p.unitId] = p.location; });
        socket.on('players', (d) => { state.players = d.players || []; renderLivePlayers(); renderLiveGrid(); renderPips(); liveSync(); });
        socket.on('editing', (map) => { state.editing = map || {}; renderPending(); renderActive(); updateEditBanners(); });
        socket.on('call:edited', (d) => { if (state.callId === d.id && state.editMode && state.editBase && d.rev !== state.editBase.rev) { state.editConflict = { rev: d.rev }; updateEditBanners(); } });
        socket.on('records', () => { if (state.tool === 'registries') { clearTimeout(state.regT); state.regT = setTimeout(loadRegistry, 400); } });
        socket.on('serviceNote', (n) => {
            const changed = n && n.text !== state.serviceNote.text;
            state.serviceNote = { text: String(n.text || ''), by: String(n.by || ''), at: Number(n.at) || 0 };
            renderServiceNote(changed);
            if (changed && n.by !== 'Dispatch') toast('new', 'Note de service modifiée', `par ${n.by || '—'}`, () => openTool('note'));
        });
        socket.on('message', (m) => {
            if (state.chat === m.channel && !state.chatMessages.some((x) => x.id === m.id)) {
                state.chatMessages.push(m); renderChat();
                if (m.senderType !== 'dispatch' && state.tool === 'messages') markRead(m.channel);
            }
            if (state.observeOn && /^u:/.test(m.channel || '')) loadObserve();
            if (state.call && m.channel === `d:c:${state.call.id}` && !state.editMode) refreshCall();
            if (m.senderType !== 'dispatch' && !(state.chat === m.channel && state.tool === 'messages' && document.hasFocus())) SOUND.message();
        });
        socket.on('alert', (a) => {
            if (a.type === 'awaiting') { SOUND.awaiting(); toast('awaiting', `À valider — ${a.number}`, a.title || '', () => openCall(a.id), 0, a.id); }
            else if (a.type === 'new') { SOUND.call(); toast('new', `${a.kind === 'incident' ? 'Nouvel incident' : 'Nouvelle intervention'} — ${a.number}`, a.title || '', () => openCall(a.id)); }
        });
        socket.on('live:signal', onLiveSignal);
        socket.on('live:offline', (d) => { const c = live.conns.get(Number(d.serverId)); if (c) { c.state = 'signalisation perdue'; updateFoot(Number(d.serverId)); } });
        socket.on('live:gone', (d) => { closeConn(Number(d.serverId)); renderLiveGrid(); renderPips(); });
        socket.on('live:error', (e) => toast('error', 'LiveView', e.error));
    }
    async function refreshState() {
        const res = await api('/state');
        if (!res) return;
        Object.assign(state, { calls: res.calls, units: res.units, conversations: res.conversations, fivem: res.fivem, dispatch: res.dispatch, presence: res.presence,
            positions: res.positions || {}, players: res.players || [], editing: res.editing || {}, serviceNote: res.serviceNote || state.serviceNote });
        renderHeader(); renderBoard(); renderServiceNote(false); renderChatList(); renderPips();
        if (state.tool !== 'call' || !state.callId) renderTool();
    }

    (async () => {
        renderSound();
        const me = await api('/me');
        if (!me) return;
        state.csrf = me.csrf;
        await refreshState();
        renderTool();
        connect();
    })();
})();
