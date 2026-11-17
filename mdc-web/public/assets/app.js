// =====================================================================================================================
// KING COUNTY DISPATCH — MDC Web 5 (fenêtres flottantes : assets/wm.js).
// Lecture : API REST (MySQL) + temps réel (Socket.IO). Actions : API REST (CSRF), exécutées par le serveur FiveM.
// Notifications visuelles : nouvelles interventions / incidents seulement ; les messages ne font qu'un son.
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
    const on = (sel, ev, fn) => { const el = $(sel); if (el) el.addEventListener(ev, fn); };

    // ---------------- libellés (identiques au MDC en jeu) ----------------
    const PRIORITY = { px: 'Priorité X', k1: 'Priorité 1', k2: 'Priorité 2', k3: 'Priorité 3', k4: 'Priorité 4', k0: 'Priorité 0', nonurgent: 'Non urgent', p1: 'Priorité 1', p2: 'Priorité 2', p3: 'Priorité 3' };
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
    // Secteurs du KCSO (case KCSO cochée : au moins un, jusqu'aux trois) — mêmes clés que Config.KcsoAreas (rp_mdc)
    const KCSO_AREAS = { uninc: 'Non-incorporé', maplevalley: 'Maple Valley', kenmore: 'Kenmore' };
    const areasText = (list) => Object.keys(KCSO_AREAS).filter((k) => (list || []).includes(k)).map((k) => KCSO_AREAS[k]).join(', ');
    const FIELD_LABEL = { title: 'Intitulé', address: 'Adresse', crossStreet: 'Croisement', block: 'Bloc', sector: 'Secteur', description: 'Description',
        caller: 'Requérant', phone: 'Téléphone', priority: 'Priorité', responseCode: 'Code de réponse', idealUnits: 'Unités idéales', agency: 'Police', kcsoAreas: 'Secteur KCSO' };
    const KIND_LABEL = { identity: 'Identité', vehicle: 'Véhicule', report: 'Rapport', bolo: 'BOLO', call: 'Intervention', conversation: 'Conversation' };
    const AUDIT_ACTION = { update: 'Modification', delete: 'Suppression', empty: 'Messages vidés', restore: 'Restauration', reopen: 'Réouverture', purge: 'Purge définitive' };
    const ACTIONS = {
        'dispatch.enable': 'Mode Dispatch activé', 'dispatch.disable': 'Mode Dispatch désactivé', 'dispatch.release': 'Appels transmis automatiquement',
        'call.validate': 'Intervention validée', 'call.refuse': 'Intervention refusée', 'call.cancel': 'Intervention annulée', 'call.close': 'Intervention clôturée',
        'call.assign': 'Unité affectée', 'call.unassign': 'Unité retirée', 'call.note': 'Note du dispatch', 'call.edit': 'Intervention modifiée',
        'call.dispatch': 'Intervention créée (dispatch)', 'incident.dispatch': 'Incident créé (dispatch)', 'call.reopen': 'Intervention rouverte',
        'call.delete': 'Intervention supprimée (corbeille)', 'call.create': 'Intervention créée (jeu)', 'incident.create': 'Incident déclaré (jeu)',
        'unit.status': 'Statut d\'unité changé', 'unit.create': 'Unité créée (jeu)', 'unit.delete': 'Unité supprimée (jeu)',
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
        me: null, csrf: '', station: '', calls: [], units: [], conversations: [], observe: [], dispatch: null, fivem: { online: false },
        presence: [], positions: {}, players: [], liveAvailable: false, editing: {},
        callFilter: 'active', kbIndex: -1, callId: null, call: null, editMode: false, editBase: null, editDraft: null, editConflict: null, noteFilter: 'all',
        chat: null, chatMessages: [], chatCat: 'civil', observeOn: false, historyPage: 1, logPage: 1, auditPage: 1,
        soundOn: store.get('mdc.sound', true), unitSort: store.get('mdc.unitSort', { key: 'status', dir: 1 }),
        searchType: 'identity', searchResults: [], reg: { tab: 'sex', list: [], view: [], sel: null, page: 1, total: 0, types: null }, trash: [],
    };

    // ---------------- outils ----------------
    const nowS = () => Math.floor(Date.now() / 1000);
    const pad = (n) => String(n).padStart(2, '0');
    const fmtTime = (t) => { const d = new Date(t * 1000); return `${pad(d.getHours())}:${pad(d.getMinutes())}`; };
    const fmtDate = (t) => { if (!t) return '—'; const d = new Date(t * 1000); return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}`; };
    const fmtShort = (t) => { if (!t) return ''; const d = new Date(t * 1000); return d.toDateString() === new Date().toDateString() ? fmtTime(t) : `${pad(d.getDate())}/${pad(d.getMonth() + 1)}`; };
    const age = (t) => { const s = Math.max(0, nowS() - t); if (s < 60) return `${s} s`; if (s < 3600) return `${Math.floor(s / 60)} min`; return `${Math.floor(s / 3600)} h ${pad(Math.floor((s % 3600) / 60))}`; };
    const norm = (v) => String(v ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
    const arr = (v) => (Array.isArray(v) ? v : v && typeof v === 'object' ? Object.values(v) : []);
    const prioChip = (p) => (PRIORITY[p] ? `<span class="chip ${PRIO_TONE[p] || ''}" title="${esc(PRIORITY_MEANING[p] || '')}">${esc(PRIORITY[p])}</span>` : '<span class="muted">—</span>');
    const statusChip = (s) => `<span class="chip ldot ${STATUS_TONE[s] || ''}">${esc(CALL_STATUS[s] || s)}</span>`;
    const unitSt = (s) => `<span class="st ${esc(s)}">${esc(UNIT_STATUS[s] || s)}</span>`;
    const agencyChips = (list) => (list || []).map((a) => `<span class="chip agency ${esc(a)}">${esc(AGENCY[a] || String(a).toUpperCase())}</span>`).join(' ');
    const unitLabel = (u) => `${u.tag ? `<span class="tag">${esc(u.tag)}</span> ` : ''}${esc(u.name)}`;
    const emptyState = (title, text, ic = 'inbox') => `<div class="empty">${icon(ic)}<b>${esc(title)}</b>${text ? `<span>${esc(text)}</span>` : ''}</div>`;
    const emptyRow = (cols, title, text) => `<tr><td colspan="${cols}" class="empty-cell">${emptyState(title, text)}</td></tr>`;
    const skeleton = (n = 5) => `<div class="skel" aria-hidden="true">${'<i></i>'.repeat(n)}</div>`;
    const skelRow = (cols) => `<tr><td colspan="${cols}" class="empty-cell">${skeleton(4)}</td></tr>`;

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

    // ---------------- sons (UN seul son pour tous les messages) ----------------
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
    on('#soundBtn', 'click', () => { state.soundOn = !state.soundOn; store.set('mdc.sound', state.soundOn); renderSound(); if (state.soundOn) SOUND.message(); });

    // ---------------- thème, transparence réduite ----------------
    function renderTheme() {
        const day = document.documentElement.dataset.theme === 'day';
        $('#themeBtn').innerHTML = icon(day ? 'moon' : 'sun');
        const lite = document.documentElement.classList.contains('lite');
        $('#liteBtn').setAttribute('aria-pressed', lite ? 'true' : 'false');
    }
    on('#themeBtn', 'click', () => {
        const day = document.documentElement.dataset.theme !== 'day';
        document.documentElement.dataset.theme = day ? 'day' : 'night';
        try { localStorage.setItem('mdc.theme', day ? 'day' : 'night'); } catch (e) { /* stockage indisponible */ }
        renderTheme();
    });
    if (store.get('mdc.lite', false)) document.documentElement.classList.add('lite');
    on('#liteBtn', 'click', () => {
        const lite = !document.documentElement.classList.contains('lite');
        document.documentElement.classList.toggle('lite', lite);
        store.set('mdc.lite', lite);
        renderTheme();
    });
    // rendu lent mesuré au démarrage : repli automatique sans flou
    (function measure() {
        let frames = 0; const start = performance.now();
        const step = () => { frames += 1; if (performance.now() - start < 1000) requestAnimationFrame(step); else if (frames < 24 && !store.get('mdc.lite.auto', false)) { document.documentElement.classList.add('lite'); store.set('mdc.lite.auto', true); renderTheme(); } };
        requestAnimationFrame(step);
    })();

    // ---------------- notifications visuelles (interventions seulement) ----------------
    function toast(kind, title, text, onClick, duration = 6000, callId) {
        const el = document.createElement('div');
        if (callId) el.dataset.call = callId;
        el.className = `toast glass ${kind}`;
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
        document.title = awaiting + unread ? `(${awaiting + unread}) King County Dispatch` : 'King County Dispatch';
        WM.setBadge('queue', awaiting);
        WM.setBadge('messages', unread);
    }
    setInterval(() => { if (state.dispatch && state.dispatch.effective && state.calls.some((c) => c.status === 'awaiting' && nowS() - c.createdAt > 20)) SOUND.awaiting(); }, 20000);

    // ---------------- en-tête ----------------
    setInterval(() => {
        const d = new Date();
        $('#clock').textContent = `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
        $$('[data-age]').forEach((el) => { el.textContent = age(Number(el.dataset.age)); });
    }, 1000);
    function renderHeader() {
        const d = state.dispatch || {};
        $('#modeSwitch').setAttribute('aria-checked', d.enabled ? 'true' : 'false');
        $('#modeLabel').textContent = `Mode dispatch : ${d.enabled ? 'actif' : 'inactif'}`;
        $('#modeHint').textContent = d.enabled ? (d.effective ? 'Les appels des civils attendent votre validation' : 'Activé, mais le jeu ne voit aucun dispatch en ligne') : 'Les appels partent directement aux unités';
        $('#indFivem').classList.toggle('on', !!state.fivem.online);
        $('#fivemBanner').classList.toggle('hidden', !!state.fivem.online);
        $('#indPlayers').textContent = typeof state.fivem.players === 'number' ? `${state.fivem.players} joueurs` : '';
        $('#indDispatchers').textContent = `${state.presence.length} poste(s)`;
        $('#station').textContent = state.station;
    }
    on('#modeSwitch', 'click', async () => {
        const enable = !(state.dispatch && state.dispatch.enabled);
        if (!enable && state.calls.some((c) => c.status === 'awaiting')) {
            const ok = await WM.confirm({ title: 'Désactiver le mode Dispatch', text: 'Des interventions attendent votre validation : elles partiront <b>directement aux unités</b>.', ok: 'Désactiver' });
            if (!ok) return;
        }
        const res = await api('/dispatch/mode', { enabled: enable });
        if (res && res.dispatch) { state.dispatch = res.dispatch; renderHeader(); renderKpi(); renderQueue(); }
    });
    on('#logoutBtn', 'click', async () => {
        const ok = await WM.confirm({ title: 'Déconnexion', text: 'Fermer votre session sur ce poste ?', ok: 'Se déconnecter', danger: false });
        if (!ok) return;
        await fetch('/auth/logout', { method: 'POST', headers: { 'X-CSRF-Token': state.csrf }, credentials: 'same-origin' });
        location.href = '/login';
    });
    on('#helpBtn', 'click', () => $('#helpModal').classList.remove('hidden'));
    $$('[data-close-modal]').forEach((b) => b.addEventListener('click', () => b.closest('.modal').classList.add('hidden')));
    $$('.modal').forEach((m) => m.addEventListener('mousedown', (e) => { if (e.target === m && m.id !== 'modal') m.classList.add('hidden'); }));

    // =================================================================================================================
    // FENÊTRES
    // =================================================================================================================
    const APPS = [
        { id: 'kpi', title: 'Indicateurs', short: 'Indic.', icon: 'dash', color: 'var(--text-2)', template: 'tpl-kpi', key: '1', onOpen: () => renderKpi() },
        { id: 'queue', title: 'File de validation', short: 'Validation', icon: 'queue', color: 'var(--dispatch)', template: 'tpl-queue', key: '2', onOpen: () => renderQueue() },
        { id: 'calls', title: 'Interventions', short: 'Appels', icon: 'calls', color: 'var(--text-2)', template: 'tpl-calls', key: '3', onOpen: bindCalls },
        { id: 'units', title: 'Unités', icon: 'units', color: 'var(--kcso)', template: 'tpl-units', key: '4', onOpen: bindUnits },
        { id: 'messages', title: 'Messagerie', short: 'Messages', icon: 'msg', color: 'var(--wsp)', template: 'tpl-messages', key: '5', rect: { x: 0.18, y: 0.04, w: 0.62, h: 0.88 }, onOpen: bindMessages },
        { id: 'search', title: 'Recherche', icon: 'search', color: 'var(--text-2)', template: 'tpl-search', key: '6', rect: { x: 0.1, y: 0.05, w: 0.6, h: 0.85 }, onOpen: bindSearch },
        { id: 'registries', title: 'Registres', icon: 'reg', color: 'var(--dispatch)', template: 'tpl-registries', key: '7', rect: { x: 0.2, y: 0.04, w: 0.62, h: 0.9 }, onOpen: bindRegistries },
        { id: 'live', title: 'LiveView', icon: 'live', color: 'var(--stop)', template: 'tpl-live', key: '8', rect: { x: 0.05, y: 0.03, w: 0.75, h: 0.92 }, onOpen: bindLive, onClose: () => setTimeout(liveSync, 0) },
        { id: 'history', title: 'Historique', icon: 'history', color: 'var(--text-3)', template: 'tpl-history', key: '9', rect: { x: 0.15, y: 0.06, w: 0.62, h: 0.82 }, onOpen: bindHistory },
        { id: 'log', title: 'Journal des actions', short: 'Journal', icon: 'log', color: 'var(--text-3)', template: 'tpl-log', rect: { x: 0.2, y: 0.08, w: 0.6, h: 0.8 }, onOpen: bindLog },
        { id: 'audit', title: 'Journal d\'audit', short: 'Audit', icon: 'audit', color: 'var(--caution)', template: 'tpl-audit', rect: { x: 0.18, y: 0.06, w: 0.64, h: 0.84 }, onOpen: bindAudit },
        { id: 'trash', title: 'Corbeille', icon: 'trash', color: 'var(--stop)', template: 'tpl-trash', rect: { x: 0.25, y: 0.1, w: 0.5, h: 0.7 }, onOpen: bindTrash },
        { id: 'call', title: 'Intervention', icon: 'calls', color: 'var(--dispatch)', template: 'tpl-call', dock: false, transient: true, rect: { x: 0.52, y: 0.02, w: 0.46, h: 0.96 },
            canClose: () => !state.editMode || window.confirm('Quitter la modification en cours sans l\'enregistrer ?'),
            onClose: () => { if (state.editMode) leaveEdit(true); state.callId = null; state.call = null; renderCalls(); } },
    ];
    APPS.forEach((a) => WM.register(a));

    // ---------------- raccourcis clavier ----------------
    document.addEventListener('keydown', (e) => {
        const field = e.target.closest('input, textarea, select, [contenteditable]');
        const typing = field && !(field.tagName === 'INPUT' && ['checkbox', 'radio', 'button', 'submit', 'range'].includes(field.type));
        if (e.key === 'Escape') {
            const modal = $$('.modal').find((m) => !m.classList.contains('hidden'));
            if (modal && modal.id !== 'modal') { modal.classList.add('hidden'); return; }
            if (pipFull()) return;
            if (state.editMode) { leaveEdit(); return; }
            if (typing) e.target.blur();
            return;
        }
        if (typing || e.ctrlKey || e.metaKey || e.altKey || WM.palette.isOpen()) return;
        if ($$('.modal').some((m) => !m.classList.contains('hidden'))) return;
        const k = e.key;
        const app = APPS.find((a) => a.key === k);
        if (app) { e.preventDefault(); WM.open(app.id); return; }
        if (k === 'n' || k === 'N') { e.preventDefault(); openNew('intervention'); return; }
        if (k === 'i' || k === 'I') { e.preventDefault(); openNew('incident'); return; }
        if (k === '?') { e.preventDefault(); $('#helpModal').classList.remove('hidden'); return; }
        if ((k === 'e' || k === 'E') && state.call) { e.preventDefault(); enterEdit(); return; }
        if ((k === 'v' || k === 'V') && state.call && state.call.status === 'awaiting') { e.preventDefault(); callAction('validate'); return; }
        if (WM.isOpen('calls') && (k === 'j' || k === 'k' || k === 'Enter')) {
            const rows = $$('#callsBody tr[data-call]');
            if (!rows.length) return;
            e.preventDefault();
            if (k === 'Enter') { const r = rows[Math.max(0, state.kbIndex)]; if (r) openCall(Number(r.dataset.call)); return; }
            state.kbIndex = Math.max(0, Math.min(rows.length - 1, state.kbIndex + (k === 'j' ? 1 : -1)));
            rows.forEach((r, i) => r.classList.toggle('kb', i === state.kbIndex));
            rows[state.kbIndex].scrollIntoView({ block: 'nearest' });
        }
    });

    // =================================================================================================================
    // INDICATEURS, FILE DE VALIDATION
    // =================================================================================================================
    const ACTIVE = ['awaiting', 'pending', 'ongoing'];
    const counts = () => { const c = { awaiting: 0, pending: 0, ongoing: 0 }; for (const x of state.calls) if (c[x.status] !== undefined) c[x.status] += 1; return c; };
    function renderKpi() {
        if (!$('#kpiAwaiting')) return;
        const c = counts();
        const connected = state.units.filter((u) => u.connected);
        $('#kpiAwaiting').textContent = c.awaiting; $('#kpiPending').textContent = c.pending; $('#kpiOngoing').textContent = c.ongoing;
        $('#kpiUnits').textContent = connected.length; $('#kpiAvailable').textContent = connected.filter((u) => u.status === 'available').length;
    }
    function renderQueue() {
        if (!$('#dashQueue')) return;
        const d = state.dispatch || {};
        WM.setMeta('queue', d.effective ? 'appels des civils à valider' : 'mode Dispatch inactif');
        const queue = state.calls.filter((x) => x.status === 'awaiting').sort((a, b) => a.createdAt - b.createdAt);
        $('#dashQueue').innerHTML = queue.length ? queue.map((x) => `
            <div class="qcard" data-open="${x.id}" data-ctx-call="${x.id}">
                <div class="q-top"><span class="num">${esc(x.number)}</span>${prioChip(x.priority)}${x.responseCode ? `<span class="chip">Code ${esc(x.responseCode)}</span>` : ''}
                    <span class="q-title">${esc(x.title)}</span><span class="q-age" data-age="${x.createdAt}">${age(x.createdAt)}</span></div>
                <div class="q-meta">${esc(x.address)}${x.block ? ` · bloc ${esc(x.block)}` : ''} · ${agencyChips(x.agency)}${(x.kcsoAreas || []).length ? ` <span class="muted">${esc(areasText(x.kcsoAreas))}</span>` : ''} · requérant ${esc(x.caller || '—')}</div>
                <div class="q-actions"><button type="button" class="btn go small" data-quick="validate" data-id="${x.id}">${icon('check')}Valider</button>
                    <button type="button" class="btn small" data-open="${x.id}">Ouvrir</button>
                    <button type="button" class="btn stop small" data-quick="refuse" data-id="${x.id}">Refuser</button></div>
            </div>`).join('') : emptyState('Aucun appel à valider', d.effective ? 'Les appels des civils apparaîtront ici.' : 'Activez le mode Dispatch pour valider les appels des civils.');
    }

    // =================================================================================================================
    // INTERVENTIONS (liste)
    // =================================================================================================================
    function callRow(c) {
        const editing = state.editing[c.id];
        return `<tr data-call="${c.id}" data-ctx-call="${c.id}" class="prio-${esc(c.priority)} status-${esc(c.status)} ${c.id === state.callId ? 'sel' : ''}">
            <td class="num">${esc(c.number)}</td>
            <td>${prioChip(c.priority)}${c.responseCode ? ` <span class="muted">C${esc(c.responseCode)}</span>` : ''}</td>
            <td><b>${esc(c.title)}</b>${c.kind === 'incident' ? ' <span class="tag">Incident</span>' : ''}${editing ? ` <span class="chip caution" title="${esc(editing.join(', '))} modifie cette fiche">${icon('edit')}</span>` : ''}</td>
            <td>${esc(c.address)}${c.block ? `<span class="sub">bloc ${esc(c.block)}${c.crossStreet ? ` · × ${esc(c.crossStreet)}` : ''}</span>` : ''}</td>
            <td>${agencyChips(c.agency)}${(c.kcsoAreas || []).length ? `<span class="sub">${esc(areasText(c.kcsoAreas))}</span>` : ''}</td>
            <td>${c.units.map((u) => esc(u.name)).join(', ') || '<span class="muted">—</span>'}</td>
            <td>${statusChip(c.status)}</td>
            <td>${fmtTime(c.createdAt)}<span class="sub" data-age="${c.createdAt}">${age(c.createdAt)}</span></td>
        </tr>`;
    }
    function filteredCalls() {
        const f = state.callFilter;
        const q = norm($('#callsQ') ? $('#callsQ').value : '');
        const agency = $('#callsAgency') ? $('#callsAgency').value : '';
        return state.calls.filter((x) => (f === 'active' ? ACTIVE.includes(x.status) : f === 'recent' ? ['closed', 'refused', 'cancelled'].includes(x.status) : x.status === f)
            && (!agency || (x.agency || []).includes(agency)) && (!q || norm([x.number, x.title, x.address, x.crossStreet, x.block, x.caller].join(' ')).includes(q)));
    }
    function renderCalls() {
        if (!$('#callsBody')) return;
        const c = counts();
        $$('[data-count]').forEach((b) => { const n = c[b.dataset.count] || 0; b.textContent = n ? `(${n})` : ''; });
        const list = filteredCalls();
        $('#callsBody').innerHTML = list.map(callRow).join('') || emptyRow(8, 'Aucune intervention', $('#callsQ').value ? 'Aucun résultat pour ce filtre.' : 'Rien dans cette liste pour le moment.');
        const rows = $$('#callsBody tr[data-call]');
        if (state.kbIndex >= rows.length) state.kbIndex = rows.length - 1;
        rows.forEach((r, i) => r.classList.toggle('kb', i === state.kbIndex));
        WM.setMeta('calls', `${c.ongoing} en cours · ${c.pending} sans unité`);
    }
    function bindCalls() {
        $$('#callTabs button').forEach((t) => t.addEventListener('click', () => {
            state.callFilter = t.dataset.filter; state.kbIndex = -1;
            $$('#callTabs button').forEach((x) => x.setAttribute('aria-pressed', x === t ? 'true' : 'false'));
            renderCalls();
        }));
        on('#callsQ', 'input', () => { state.kbIndex = -1; renderCalls(); });
        on('#callsAgency', 'change', renderCalls);
        renderCalls();
    }

    // =================================================================================================================
    // FICHE D'INTERVENTION (fenêtre) : actions, modification, journal, suppression, réouverture
    // =================================================================================================================
    async function openCall(id) {
        if (state.editMode && state.callId !== id && !window.confirm('Quitter la modification en cours sans l\'enregistrer ?')) return;
        if (state.callId !== id) leaveEdit(true);
        state.callId = id;
        WM.open('call');
        if (!state.call || state.call.id !== id) $('#drawerBody').innerHTML = skeleton(8);
        const res = await api(`/calls/${id}`);
        if (!res || state.callId !== id) return;
        state.call = res.call;
        renderCall();
        renderCalls();
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
        <div class="toolbar flat"><button type="button" class="btn small stop" data-act="force">Enregistrer quand même</button><button type="button" class="btn small" data-act="reload">Reprendre les valeurs actuelles</button></div></div>` : '');
    function updateEditBanners() {
        if ($('#editLock')) $('#editLock').innerHTML = editLockHtml();
        if ($('#editConflict')) $('#editConflict').innerHTML = conflictHtml();
    }
    function noteHtml(n) {
        const journal = n.unitName === 'JOURNAL';
        return `<div class="note ${n.dispatch ? 'dispatch' : ''} ${journal ? 'journal' : ''}"><div class="note-head"><span>${esc(journal ? `Journal — ${n.authorName}` : n.dispatch ? 'Dispatch' : `${n.unitName} — ${n.authorName}`)}</span><span>${fmtDate(n.createdAt)}</span></div><div class="note-text">${esc(n.text)}</div></div>`;
    }

    function renderCall() {
        const c = state.call;
        if (!c || !$('#drawerBody')) return;
        WM.setTitle('call', `${c.number} — ${c.title}`);
        WM.setMeta('call', c.kind === 'incident' ? 'Incident' : 'Intervention');
        if (state.editMode) { renderEditForm(); return; }
        const keep = { note: $('#noteInput') && $('#noteInput').value, msg: $('#drawerMsg') && $('#drawerMsg').value, assign: $('#assignSelect') && $('#assignSelect').value,
            focus: document.activeElement && document.activeElement.id, picks: $$('[data-pick]:checked').map((x) => x.value), scroll: $('#drawerBody').parentElement.scrollTop };
        const open = !c.closed;
        const candidates = state.units.filter((u) => u.connected && ['kcso', 'wsp'].includes(u.agency) && !c.units.some((x) => x.id === u.id));
        const info = [
            ['Priorité', `${prioChip(c.priority)} <span class="muted">${esc(PRIORITY_MEANING[c.priority] || '')}</span>`],
            ['Code de réponse', c.responseCode ? esc(RESPONSE[c.responseCode]) : '—'],
            ['Requérant', `${esc(c.caller || '—')}${c.phone ? ` <span class="muted">${esc(c.phone)}</span>` : ''}`],
            ...((c.kcsoAreas || []).length ? [['Secteur KCSO', esc(areasText(c.kcsoAreas))]] : []),
            ['Adresse', `${esc(c.address)}${c.crossStreet ? ` × ${esc(c.crossStreet)}` : ''}`], ['Bloc', esc(c.block || '—')],
            ...(c.sector ? [['Secteur', esc(c.sector)]] : []),
            ...(c.kind === 'intervention' ? [['Unités idéales', c.idealUnits ? esc(c.idealUnits) : '—']] : [['Déclaré par', esc(c.unitName || '—')]]),
            ['Créée', `${fmtDate(c.createdAt)} par ${esc(c.createdByName || '—')}`],
            ...(c.updatedAt ? [['Modifiée', `${fmtDate(c.updatedAt)} · version ${esc(c.rev)}`]] : []),
            ...(c.closed ? [['Clôture', `${fmtDate(c.closedAt)} par ${esc(c.closedByName || '—')}${c.clear ? ` — ${esc(CLEAR[c.clear])}` : ''}`]] : []),
        ];
        const notes = c.notes.filter((n) => state.noteFilter === 'all' || (state.noteFilter === 'journal' ? n.unitName === 'JOURNAL' : n.unitName !== 'JOURNAL'));
        const edits = c.log.filter((l) => l.action === 'call.edit');
        $('#drawerBody').innerHTML = `
            <div class="d-head"><div class="d-num">${esc(c.number)} · ${c.kind === 'incident' ? 'Incident' : 'Intervention'}</div><div class="d-title">${esc(c.title)}</div>
                <div class="d-chips">${statusChip(c.status)} ${prioChip(c.priority)} ${agencyChips(c.agency)}</div></div>
            <div id="editLock">${editLockHtml()}</div>
            ${c.status === 'awaiting' ? `<div class="d-section"><h3>Unités à affecter en validant <span class="grow"></span><span class="muted">facultatif</span></h3>
                <div class="unit-pick">${candidates.map((u) => `<label class="check"><input type="checkbox" value="${u.id}" data-pick> ${esc(u.name)} ${unitSt(u.status)}</label>`).join('') || '<span class="muted">Aucune unité en service.</span>'}</div></div>` : ''}
            <div class="d-section"><h3>Informations</h3><dl class="info-grid">${info.map(([k, v]) => `<dt>${esc(k)}</dt><dd>${v}</dd>`).join('')}</dl></div>
            <div class="d-section"><h3>Description</h3><div class="desc">${esc(c.description || '—')}</div></div>
            <div class="d-section"><h3>Unités affectées <span class="muted">(${c.units.length})</span></h3>
                <div class="assigned">${c.units.map((u) => `<span>${unitLabel(u)} ${unitSt(u.status)}${open ? `<button type="button" title="Retirer de l'intervention" data-unassign="${u.id}">${icon('x')}</button>` : ''}</span>`).join('') || '<span class="muted">Aucune unité.</span>'}</div>
                ${open && c.status !== 'awaiting' ? `<div class="inline-form"><select id="assignSelect" aria-label="Unité à affecter"><option value="">Choisir une unité en service…</option>${candidates.map((u) => `<option value="${u.id}">${esc(u.name)} (${esc(AGENCY[u.agency])}) — ${esc(UNIT_STATUS[u.status])}${state.positions[u.id] && state.positions[u.id].street ? ` — ${esc(state.positions[u.id].street)}` : ''}</option>`).join('')}</select>
                    <button type="button" class="btn primary" data-act="assign">Affecter</button></div>` : ''}
            </div>
            ${c.links.length ? `<div class="d-section"><h3>Personnes et véhicules liés</h3>${c.links.map((l) => `<div>${l.kind === 'vehicle' ? 'Véhicule' : 'Identité'} : <b>${esc(l.label)}</b> <span class="muted">(${esc(l.addedBy)})</span></div>`).join('')}</div>` : ''}
            <div class="d-section"><h3>Déroulé, notes et journal automatique <span class="grow"></span>
                <span class="seg" role="group" aria-label="Filtre des notes">${[['all', 'Tout'], ['notes', 'Notes'], ['journal', 'Journal']].map(([k, l]) => `<button type="button" data-nf="${k}" aria-pressed="${state.noteFilter === k}">${l}</button>`).join('')}</span></h3>
                <div class="timeline">${notes.map(noteHtml).join('') || '<span class="muted">Rien pour ce filtre.</span>'}</div>
                ${open ? `<div class="inline-form"><input id="noteInput" maxlength="500" placeholder="Note du dispatch (visible en jeu)" aria-label="Note"><button type="button" class="btn" data-act="note">Ajouter</button></div>` : ''}
            </div>
            ${c.status !== 'awaiting' ? `<div class="d-section"><h3>Messages avec les unités</h3>
                <div class="chat-body" id="drawerChat">${c.messages.map(bubble).join('') || '<span class="muted">Aucun message.</span>'}</div>
                ${open ? `<div class="inline-form"><input id="drawerMsg" maxlength="300" placeholder="Message aux unités de l'intervention" aria-label="Message"><button type="button" class="btn primary" data-act="msg">Envoyer</button></div>` : ''}</div>` : ''}
            <div class="d-section"><h3>Historique des modifications <span class="muted">(${edits.length})</span></h3>
                ${edits.length ? edits.slice().reverse().map((l) => `<div class="history-item"><time>${fmtDate(l.at)}</time><div><b>${esc(l.actorName || 'Dispatch')}</b>${l.details && l.details.forced ? ' <span class="chip caution">écrasée après avertissement</span>' : ''}${changesHtml(l.details)}</div></div>`).join('') : '<span class="muted">Aucune modification depuis la création.</span>'}
            </div>`;
        let foot = '';
        if (c.status === 'awaiting') {
            foot = `<button type="button" class="btn go" data-act="validate">${icon('check')}Valider<span class="kbd">V</span></button>
                <button type="button" class="btn" data-act="edit">${icon('edit')}Modifier<span class="kbd">E</span></button><span class="push"></span>
                <button type="button" class="btn stop" data-act="refuse">Refuser…</button><button type="button" class="btn ghost" data-act="cancel">Annuler…</button>`;
        } else if (open) {
            const sheriff = (c.agency || []).includes('kcso');
            foot = `<button type="button" class="btn" data-act="edit">${icon('edit')}Modifier<span class="kbd">E</span></button><span class="push"></span>
                ${sheriff ? '' : `<select id="clearSelect" aria-label="Code de clôture"><option value="">Clôturer sans code</option>${Object.entries(CLEAR).map(([k, v]) => `<option value="${k}">${esc(v)}</option>`).join('')}</select>`}
                <button type="button" class="btn" data-act="close">Clôturer</button><button type="button" class="btn stop" data-act="cancel">Annuler…</button>`;
        } else {
            foot = `<button type="button" class="btn" data-act="edit">${icon('edit')}Modifier<span class="kbd">E</span></button><button type="button" class="btn go" data-act="reopen">${icon('reopen')}Rouvrir</button><span class="push"></span>`;
        }
        foot += `<button type="button" class="btn ghost icon" data-act="delete" title="Supprimer (corbeille)" aria-label="Supprimer (corbeille)">${icon('trash')}</button>`;
        $('#drawerFoot').innerHTML = foot;
        $('#drawerFoot').classList.remove('hidden');
        const chat = $('#drawerChat');
        if (chat) chat.scrollTop = chat.scrollHeight;
        if (keep.note && $('#noteInput')) $('#noteInput').value = keep.note;
        if (keep.msg && $('#drawerMsg')) $('#drawerMsg').value = keep.msg;
        if (keep.assign && $('#assignSelect')) $('#assignSelect').value = keep.assign;
        keep.picks.forEach((v) => { const el = $(`[data-pick][value="${v}"]`); if (el) el.checked = true; });
        if (keep.focus && $(`#${keep.focus}`)) $(`#${keep.focus}`).focus();
        $('#drawerBody').parentElement.scrollTop = keep.scroll;
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
        renderCall();
        const first = $('#drawerBody input, #drawerBody select');
        if (first) first.focus();
    }
    function leaveEdit(silent) {
        if (!state.editMode) return;
        state.editMode = false; state.editBase = null; state.editConflict = null; state.editDraft = null;
        if (socket) socket.emit('edit:stop');
        if (!silent) renderCall();
    }
    function callFormHtml(v, kind, full) {
        const kcso = (v.agency || []).includes('kcso');
        const prios = kcso ? KCSO_PRIORITIES : WSP_PRIORITIES;
        return `<div class="form-grid ${full ? '' : 'quick'}">
            <label class="field"><span>${kind === 'incident' ? 'Type d\'incident' : 'Type d\'intervention'} <b>*</b></span><input name="title" maxlength="60" value="${esc(v.title || '')}" required placeholder="ex : Accident matériel"></label>
            <div class="field"><span>Police <b>*</b></span><div class="toolbar flat">${['kcso', 'wsp'].map((a) => `<label class="check"><input type="checkbox" name="agency" value="${a}" ${(v.agency || []).includes(a) ? 'checked' : ''}> ${AGENCY[a]}</label>`).join(' ')}</div></div>
            ${kcso ? `<div class="field kcso-areas"><span>Secteur KCSO <b>*</b> <small class="muted">un ou plusieurs</small></span><div class="toolbar flat">${Object.entries(KCSO_AREAS).map(([k, l]) => `<label class="check"><input type="checkbox" name="kcsoAreas" value="${k}" ${(v.kcsoAreas || []).includes(k) ? 'checked' : ''}> ${esc(l)}</label>`).join(' ')}</div></div>` : ''}
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
        $('#drawerBody').innerHTML = `
            <div class="d-head"><div class="d-num">${esc(c.number)}</div><div class="d-title">Modifier ${c.closed ? '(terminée)' : c.status === 'awaiting' ? '(avant envoi)' : '(en cours)'}</div></div>
            <div id="editLock">${editLockHtml()}</div><div id="editConflict">${conflictHtml()}</div>
            <form class="d-section" id="editForm" novalidate>${callFormHtml(v, c.kind, true)}
                <p class="form-note">Les unités de l'intervention sont prévenues par un son ; la modification est ajoutée au journal de l'intervention.</p></form>`;
        $('#drawerFoot').innerHTML = `<button type="button" class="btn primary" data-act="save">${icon('check')}Enregistrer</button><button type="button" class="btn ghost" data-act="cancelEdit">Annuler</button><span class="push form-note">Échap : annuler</span>`;
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
        if (fields.agency !== undefined || fields.kcsoAreas !== undefined) fields.kcsoAreas = values.kcsoAreas; // secteurs revérifiés avec les polices
        if (!Object.keys(fields).length) { leaveEdit(); return; }
        const res = await api(`/calls/${c.id}/edit`, { rev: state.editBase.rev, force, fields });
        if (!res) return;
        if (res.conflict) {
            state.editConflict = { rev: res.rev }; state.editDraft = values; SOUND.error();
            const fresh = await api(`/calls/${c.id}`);
            if (fresh) state.call = fresh.call;
            renderCall();
            return;
        }
        toast('ok', c.number, res.unchanged ? 'Aucun changement.' : 'Intervention modifiée : unités prévenues.');
        leaveEdit(true);
        const fresh = await api(`/calls/${c.id}`);
        if (fresh) state.call = fresh.call;
        renderCall();
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
                const r = await WM.confirm({ title: act === 'refuse' ? `Refuser ${c.number}` : `Annuler ${c.number}`, input: true, ok: act === 'refuse' ? 'Refuser' : 'Annuler l\'intervention',
                    text: act === 'refuse' ? 'Motif du refus (communiqué au civil qui a appelé, facultatif) :' : 'Motif de l\'annulation (communiqué aux unités, facultatif) :' });
                if (r && await api(`/calls/${c.id}/${act}`, { reason: r.value })) toast('ok', c.number, act === 'refuse' ? 'Intervention refusée.' : 'Intervention annulée.');
            } else if (act === 'close') {
                const ok = await WM.confirm({ title: `Clôturer ${c.number}`, text: 'Terminer cette intervention ? Elle pourra être <b>rouverte</b> ensuite.', ok: 'Clôturer', danger: false });
                if (ok && await api(`/calls/${c.id}/close`, { clear: $('#clearSelect') ? $('#clearSelect').value : '' })) toast('ok', c.number, 'Intervention clôturée.');
            } else if (act === 'reopen') {
                if (await api(`/calls/${c.id}/reopen`, {})) toast('ok', c.number, 'Intervention rouverte : unités prévenues.');
            } else if (act === 'delete') {
                const ok = await WM.confirm({ title: `Supprimer ${c.number}`, text: `<b>${esc(c.title)}</b> part à la <b>corbeille</b> : masquée pour tout le monde (jeu et site), restaurable pendant 30 jours.`, ok: 'Mettre à la corbeille' });
                if (ok && await api(`/calls/${c.id}/delete`, {})) { toast('ok', c.number, 'Intervention mise à la corbeille.'); WM.close('call'); }
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
                if (fresh) state.call = fresh.call;
                state.editDraft = null; state.editConflict = null; state.editBase = { rev: state.call.rev, values: editValues(state.call) };
                renderCall();
            } else if (act === 'cancelEdit') leaveEdit();
        } finally { if (btn) btn.disabled = false; }
    }
    document.addEventListener('click', async (e) => {
        if (!e.target.closest('[data-win="call"]')) return;
        const c = state.call;
        if (!c) return;
        const nf = e.target.closest('[data-nf]');
        if (nf) { state.noteFilter = nf.dataset.nf; renderCall(); return; }
        const un = e.target.closest('[data-unassign]');
        if (un) {
            const u = c.units.find((x) => x.id === Number(un.dataset.unassign));
            const ok = await WM.confirm({ title: 'Retirer l\'unité', text: `Retirer <b>${esc(u ? u.name : '')}</b> de ${esc(c.number)} ?`, ok: 'Retirer' });
            if (ok) await api(`/calls/${c.id}/unassign`, { unitId: Number(un.dataset.unassign) });
            return;
        }
        const b = e.target.closest('[data-act]');
        if (b) callAction(b.dataset.act, b);
    });
    document.addEventListener('keydown', (e) => {
        if (e.key !== 'Enter' || e.shiftKey) return;
        if (e.target.id === 'noteInput') { e.preventDefault(); callAction('note'); }
        if (e.target.id === 'drawerMsg') { e.preventDefault(); callAction('msg'); }
        if (e.ctrlKey && $('#editForm') && e.target.closest('#editForm')) { e.preventDefault(); saveEdit(false); }
    });

    // ---------------- nouvelle intervention / nouvel incident ----------------
    const draft = { kind: 'intervention', mode: store.get('mdc.newMode', 'quick'), values: { agency: ['kcso'] }, units: [] };
    const candidatesNew = () => state.units.filter((u) => u.connected && ['kcso', 'wsp'].includes(u.agency));
    const newUnitsHtml = () => candidatesNew().map((u) => `<label class="check"><input type="checkbox" value="${u.id}" data-newunit ${draft.units.includes(u.id) ? 'checked' : ''}> ${esc(u.name)} ${unitSt(u.status)}</label>`).join('') || '<span class="muted">Aucune unité en service.</span>';
    function openNew(kind) {
        draft.kind = kind; draft.values = { agency: draft.values.agency || ['kcso'] }; draft.units = [];
        renderNew();
        $('#newModal').classList.remove('hidden');
        $('#newBody [name="title"]').focus();
    }
    function renderNew() {
        $('#newTitle').textContent = draft.kind === 'incident' ? 'Nouvel incident' : 'Nouvelle intervention';
        $$('[data-nkind]').forEach((b) => b.setAttribute('aria-pressed', b.dataset.nkind === draft.kind ? 'true' : 'false'));
        $$('[data-nmode]').forEach((b) => b.setAttribute('aria-pressed', b.dataset.nmode === draft.mode ? 'true' : 'false'));
        $('#newBody').innerHTML = `${callFormHtml(draft.values, draft.kind, draft.mode === 'full')}
            <div class="d-section"><h3>Affecter tout de suite <span class="grow"></span><span class="muted">facultatif</span></h3><div class="unit-pick" id="newUnits">${newUnitsHtml()}</div></div>
            ${draft.mode === 'quick' ? '<p class="form-note">Rapide : requérant « Dispatch (911) », 1 unité idéale, description = intitulé.</p>' : ''}`;
        $('#newSubmit').textContent = draft.kind === 'incident' ? 'Créer l\'incident' : 'Créer et transmettre';
    }
    function keepNew() { draft.values = { ...draft.values, ...readForm($('#newBody'), draft.kind) }; draft.units = $$('[data-newunit]:checked').map((x) => Number(x.value)); }
    $$('[data-nkind]').forEach((b) => b.addEventListener('click', () => { keepNew(); draft.kind = b.dataset.nkind; renderNew(); }));
    $$('[data-nmode]').forEach((b) => b.addEventListener('click', () => { keepNew(); draft.mode = b.dataset.nmode; store.set('mdc.newMode', draft.mode); renderNew(); }));
    on('#newBody', 'change', (e) => { if (e.target.name === 'agency') { keepNew(); renderNew(); } });
    on('#newForm', 'keydown', (e) => { if (e.key === 'Enter' && e.ctrlKey) { e.preventDefault(); $('#newForm').requestSubmit(); } });
    on('#newForm', 'submit', async (e) => {
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

    // délégation : ouvrir, actions rapides, statuts, affectations, messages
    document.addEventListener('click', async (e) => {
        const quick = e.target.closest('[data-quick]');
        if (quick) {
            const id = Number(quick.dataset.id);
            const c = state.calls.find((x) => x.id === id);
            if (quick.dataset.quick === 'validate') { if (await api(`/calls/${id}/validate`, { units: [] })) toast('ok', c ? c.number : '', 'Intervention transmise aux unités.'); }
            else {
                const r = await WM.confirm({ title: `Refuser ${c ? c.number : ''}`, text: 'Motif du refus (communiqué au civil, facultatif) :', input: true, ok: 'Refuser' });
                if (r && await api(`/calls/${id}/refuse`, { reason: r.value })) toast('ok', c ? c.number : '', 'Intervention refusée.');
            }
            return;
        }
        const openBtn = e.target.closest('[data-open]');
        if (openBtn && !e.target.closest('select')) { e.preventDefault(); openCall(Number(openBtn.dataset.open)); return; }
        const row = e.target.closest('tr[data-call]');
        if (row && !e.target.closest('select, button, a')) { openCall(Number(row.dataset.call)); return; }
        const chatBtn = e.target.closest('[data-chat]');
        if (chatBtn) { WM.open('messages'); openChat(chatBtn.dataset.chat); }
    });
    document.addEventListener('change', async (e) => {
        const st = e.target.closest('[data-unit-status]');
        if (st) {
            const unit = state.units.find((u) => u.id === Number(st.dataset.unitStatus));
            if (!await api(`/units/${st.dataset.unitStatus}/status`, { status: st.value }) && unit) st.value = unit.status;
            return;
        }
        const as = e.target.closest('[data-assign-unit]');
        if (as && as.value) { if (await api(`/calls/${as.value}/assign`, { unitId: Number(as.dataset.assignUnit) })) toast('ok', 'Affectation', 'Unité affectée.'); as.value = ''; }
    });

    // =================================================================================================================
    // UNITÉS (rue et croisement en temps réel)
    // =================================================================================================================
    function positionHtml(unitId) {
        const p = state.positions[unitId];
        if (!p || !p.street) return '<span class="muted">Position inconnue</span>';
        const stale = nowS() - (p.at || 0) > 120;
        return `<span class="pos ${stale ? 'stale' : ''}"><b>${esc(p.street)}</b><small>${p.crossing ? `× ${esc(p.crossing)} · ` : ''}${p.at ? `il y a <span data-age="${p.at}">${age(p.at)}</span>` : ''}</small></span>`;
    }
    const statusSelect = (u) => `<select class="status st-${esc(u.status)}" data-unit-status="${u.id}" aria-label="Statut de ${esc(u.name)}">${Object.entries(UNIT_STATUS).map(([k, v]) => `<option value="${k}" ${k === u.status ? 'selected' : ''}>${esc(v)}</option>`).join('')}</select>`;
    function unitSortValue(u, key) {
        const p = state.positions[u.id] || {};
        return key === 'status' ? (UNIT_ORDER[u.status] ?? 9) : key === 'street' ? norm(p.street || '~') : key === 'zone' ? norm(p.zone || '~') : key === 'since' ? (u.statusAt || 0) : norm(u.name);
    }
    function renderUnits() {
        if (!$('#unitsBody')) return;
        const onlyConnected = $('#unitsConnected').checked; const agency = $('#unitsAgency').value; const status = $('#unitsStatus').value; const sector = $('#unitsSector').value;
        const q = norm($('#unitsQ').value);
        const zones = [...new Set(state.units.map((u) => (state.positions[u.id] || {}).zone).filter(Boolean))].sort();
        $('#unitsSector').innerHTML = `<option value="">Tous secteurs</option>${zones.map((z) => `<option ${z === sector ? 'selected' : ''}>${esc(z)}</option>`).join('')}`;
        const list = state.units.filter((u) => {
            const p = state.positions[u.id] || {};
            return (!onlyConnected || u.connected) && (!agency || u.agency === agency) && (!status || u.status === status) && (!sector || p.zone === sector)
                && (!q || norm([u.name, u.tag, p.street, p.crossing, p.zone, ...u.members.map((m) => m.name)].join(' ')).includes(q));
        });
        const { key, dir } = state.unitSort;
        list.sort((a, b) => { const x = unitSortValue(a, key); const y = unitSortValue(b, key); return (x < y ? -1 : x > y ? 1 : 0) * dir || norm(a.name).localeCompare(norm(b.name)); });
        $$('#unitsTable th[data-sort]').forEach((th) => th.setAttribute('aria-sort', th.dataset.sort === key ? (dir > 0 ? 'ascending' : 'descending') : 'none'));
        const active = state.calls.filter((x) => ['pending', 'ongoing'].includes(x.status));
        $('#unitsBody').innerHTML = list.map((u) => {
            const p = state.positions[u.id] || {};
            return `<tr data-ctx-unit="${u.id}">
                <td><span class="unitcell"><span class="bar ${esc(u.agency)}"></span><span>${unitLabel(u)} ${agencyChips([u.agency])}<span class="sub">${u.members.map((m) => esc(m.name)).join(', ') || (u.connected ? '' : 'hors service')}</span></span></span></td>
                <td>${statusSelect(u)}</td>
                <td data-pos="${u.id}">${u.connected ? positionHtml(u.id) : '<span class="muted">—</span>'}</td>
                <td>${esc(p.zone || '') || '<span class="muted">—</span>'}</td>
                <td>${u.calls.map((c) => `<button type="button" class="linkish" data-open="${c.id}">${esc(c.number)}</button><span class="sub">${esc(c.title)}</span>`).join('') || '<span class="muted">—</span>'}</td>
                <td><span data-age="${u.statusAt}">${age(u.statusAt)}</span></td>
                <td><div class="toolbar flat"><button type="button" class="btn small icon" data-chat="d:u:${u.id}" title="Écrire à ${esc(u.name)}" aria-label="Écrire à ${esc(u.name)}">${icon('msg')}</button>
                    ${active.length ? `<select data-assign-unit="${u.id}" aria-label="Affecter ${esc(u.name)}"><option value="">Affecter à…</option>${active.filter((c) => !c.units.some((x) => x.id === u.id)).map((c) => `<option value="${c.id}">${esc(c.number)} — ${esc(c.title)}</option>`).join('')}</select>` : ''}</div></td>
            </tr>`;
        }).join('') || emptyRow(7, 'Aucune unité', 'Aucune unité ne correspond à ces filtres.');
        const connected = state.units.filter((u) => u.connected).length;
        WM.setMeta('units', `${connected} en service`);
    }
    function bindUnits() {
        ['#unitsConnected', '#unitsAgency', '#unitsStatus', '#unitsSector'].forEach((s) => on(s, 'change', renderUnits));
        on('#unitsQ', 'input', renderUnits);
        $$('#unitsTable th[data-sort]').forEach((th) => th.addEventListener('click', () => {
            const key = th.dataset.sort;
            state.unitSort = { key, dir: state.unitSort.key === key ? -state.unitSort.dir : 1 };
            store.set('mdc.unitSort', state.unitSort);
            renderUnits();
        }));
        renderUnits();
    }
    function updatePosition(unitId) { const cell = $(`#unitsBody [data-pos="${unitId}"]`); if (cell) cell.innerHTML = positionHtml(unitId); }

    // =================================================================================================================
    // MESSAGERIE (groupe civil, civils, unités ; observation) — suppression / vidage
    // =================================================================================================================
    const bubble = (m) => {
        const mine = m.senderType === 'dispatch';
        const who = mine ? 'Dispatch' : m.senderType === 'civil' ? `${m.author} · civil` : m.author;
        const today = new Date(m.at * 1000).toDateString() === new Date().toDateString();
        return `<div class="bubble ${mine ? 'mine' : ''}"><div class="b-meta"><b>${esc(who)}</b><time>${today ? fmtTime(m.at) : fmtDate(m.at)}</time></div><div class="b-text">${esc(m.text)}</div></div>`;
    };
    const catOf = (c) => (c.kind === 'civil' ? 'civil' : c.kind === 'private' ? 'private' : c.kind === 'unit' ? 'unit' : 'call');
    function renderChatList() {
        if (!$('#chatList')) { updateTitle(); return; }
        const q = norm($('#chatQ').value);
        for (const cat of ['civil', 'private', 'unit']) {
            const n = state.conversations.filter((c) => catOf(c) === cat).reduce((s, c) => s + (c.unread || 0), 0);
            const el = $(`[data-catcount="${cat}"]`);
            if (el) { el.textContent = n; el.classList.toggle('hidden', !n); }
        }
        $$('#chatTabs [data-cat]').forEach((b) => b.setAttribute('aria-selected', !state.observeOn && b.dataset.cat === state.chatCat ? 'true' : 'false'));
        $('#observeToggle').classList.toggle('on', state.observeOn);
        $('#observeChk').checked = state.observeOn;
        let items;
        if (state.observeOn) items = state.observe.filter((c) => !q || norm(c.label).includes(q) || norm(c.last && c.last.text).includes(q));
        else {
            items = state.conversations.filter((c) => catOf(c) === state.chatCat && (!q || norm(c.label).includes(q) || norm(c.last && c.last.text).includes(q)));
            items.sort((a, b) => ((b.last ? b.last.at : 0) - (a.last ? a.last.at : 0)) || ((b.unread || 0) - (a.unread || 0)));
        }
        $('#chatList').innerHTML = items.map((c) => `
            <button type="button" class="conv ${c.unread ? 'unread' : ''}" data-conv="${esc(c.channel)}" data-ctx-conv="${esc(c.channel)}" role="option" ${state.chat === c.channel ? 'aria-current="true"' : ''}>
                <span class="conv-name">${c.kind === 'unit' ? `${unitLabel({ name: c.label, tag: c.tag })} ${agencyChips([c.agency])}` : esc(c.label)}
                    ${c.kind === 'private' ? `<span class="dot ${c.online ? 'go' : ''}" title="${c.online ? 'Connecté' : 'Hors ligne'}"></span>` : ''}
                    ${c.kind === 'unit' && !c.connected ? '<span class="muted">hors service</span>' : ''}</span>
                <span class="conv-time">${c.last ? fmtShort(c.last.at) : ''}</span>
                <span class="conv-last">${c.last ? `${c.last.senderType === 'dispatch' ? 'Vous : ' : `${esc(c.last.author)} : `}${esc(c.last.text)}` : (c.kind === 'private' ? 'Aucun message — écrivez-lui' : 'Aucun message')}</span>
                ${c.unread ? `<span class="count">${c.unread}</span>` : (c.count ? `<span class="count dim">${c.count}</span>` : '')}
            </button>`).join('') || emptyState(state.observeOn ? 'Aucune conversation entre unités' : 'Aucune conversation', state.chatCat === 'private' && !state.observeOn ? 'Les civils connectés apparaissent ici, même sans message.' : '', 'msg');
        updateTitle();
    }
    function bindMessages() {
        on('#chatList', 'click', (e) => { const b = e.target.closest('[data-conv]'); if (b) openChat(b.dataset.conv); });
        on('#chatQ', 'input', renderChatList);
        $$('#chatTabs [data-cat]').forEach((b) => b.addEventListener('click', () => { state.chatCat = b.dataset.cat; state.observeOn = false; renderChatList(); }));
        on('#observeChk', 'change', () => { state.observeOn = $('#observeChk').checked; if (state.observeOn) loadObserve(); else renderChatList(); });
        on('#chatForm', 'submit', async (e) => {
            e.preventDefault();
            const text = $('#chatInput').value.trim();
            if (!text || !state.chat || /^u:/.test(state.chat)) return;
            $('#chatInput').disabled = true;
            const ok = await api('/messages', { channel: state.chat, text });
            $('#chatInput').disabled = false;
            if (ok) $('#chatInput').value = '';
            $('#chatInput').focus();
        });
        on('#chatInput', 'keydown', (e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); $('#chatForm').requestSubmit(); } });
        on('#chatHead', 'click', (e) => { const b = e.target.closest('[data-convdel]'); if (b) deleteConversation(state.chat, b.dataset.convdel); });
        renderChatList();
        if (state.chat) openChat(state.chat);
    }
    async function loadObserve() { const res = await api('/observe'); if (res) state.observe = res.conversations; renderChatList(); }
    async function openChat(channel) {
        if (!$('#chatBody')) WM.open('messages');
        const observing = /^u:\d+:\d+$/.test(channel);
        state.chat = channel;
        const conv = (observing ? state.observe : state.conversations).find((c) => c.channel === channel);
        if (!observing && conv && conv.kind !== 'call') state.chatCat = catOf(conv);
        const label = conv ? (conv.kind === 'unit' ? `Unité ${conv.label}` : conv.label) : channel;
        $('#chatHead').innerHTML = `<b>${esc(label)}</b>${observing ? '<span class="chip caution">Observation</span>' : ''}${conv && conv.kind === 'private' ? `<span class="chip">privée${conv.online ? ' · connecté' : ' · hors ligne'}</span>` : ''}${conv && conv.kind === 'civil' ? '<span class="chip">tous les civils</span>' : ''}
            <span class="grow"></span><button type="button" class="btn small ghost" data-convdel="empty" title="Vider les messages (corbeille)">Vider</button><button type="button" class="btn small ghost icon" data-convdel="delete" title="Supprimer la conversation (corbeille)" aria-label="Supprimer la conversation">${icon('trash')}</button>`;
        $('#chatForm').classList.toggle('hidden', observing);
        $('#readonlyNote').classList.toggle('hidden', !observing);
        $('#chatBody').innerHTML = skeleton(5);
        const res = await api(`/messages?channel=${encodeURIComponent(channel)}`);
        if (!res || state.chat !== channel) return;
        state.chatMessages = res.messages;
        renderChat();
        renderChatList();
        if (!observing) { markRead(channel); $('#chatInput').focus(); }
    }
    function renderChat() { if (!$('#chatBody')) return; $('#chatBody').innerHTML = state.chatMessages.map(bubble).join('') || emptyState('Aucun message', 'Écrivez le premier.', 'msg'); $('#chatBody').scrollTop = $('#chatBody').scrollHeight; }
    function markRead(channel) { const conv = state.conversations.find((c) => c.channel === channel); if (conv && conv.unread) api('/messages/read', { channel }, { quiet: true }); }
    async function deleteConversation(channel, mode) {
        if (!channel) return;
        const conv = [...state.conversations, ...state.observe].find((c) => c.channel === channel);
        const name = conv ? conv.label : channel;
        const ok = await WM.confirm({ title: mode === 'empty' ? 'Vider les messages' : 'Supprimer la conversation',
            text: `${mode === 'empty' ? 'Tous les messages de' : 'La conversation'} <b>${esc(name)}</b> part${mode === 'empty' ? 'ent' : ''} à la <b>corbeille</b> (restaurable 30 jours). Elle peut être recréée aussitôt en écrivant un nouveau message.`,
            ok: mode === 'empty' ? 'Vider' : 'Supprimer' });
        if (!ok) return;
        if (await api('/conversations/delete', { channel, mode })) {
            toast('ok', 'Messagerie', mode === 'empty' ? 'Messages vidés.' : 'Conversation supprimée.');
            if (state.chat === channel) { state.chatMessages = []; renderChat(); }
            if (state.observeOn) loadObserve();
        }
    }

    // =================================================================================================================
    // RECHERCHE + FICHES (avec modification / suppression)
    // =================================================================================================================
    function bindSearch() {
        $('#recordSheet').innerHTML = emptyState('Aucune fiche', 'Lancez une recherche puis choisissez un résultat.', 'search');
        $('#searchResults').innerHTML = emptyState('Pas encore de recherche', 'Nom + date de naissance, ou plaque / VIN.', 'search');
        $$('#searchTabs [data-stype]').forEach((t) => t.addEventListener('click', () => {
            state.searchType = t.dataset.stype;
            $$('#searchTabs [data-stype]').forEach((x) => x.setAttribute('aria-pressed', x === t ? 'true' : 'false'));
            $('#searchIdentity').classList.toggle('hidden', state.searchType !== 'identity');
            $('#searchVehicle').classList.toggle('hidden', state.searchType !== 'vehicle');
        }));
        on('#sDob', 'input', (e) => { const d = e.target.value.replace(/\D/g, '').slice(0, 8); e.target.value = [d.slice(0, 2), d.slice(2, 4), d.slice(4)].filter(Boolean).join('/'); });
        on('#searchIdentity', 'submit', (e) => { e.preventDefault(); runSearch({ type: 'identity', lastname: $('#sLast').value.trim(), firstname: $('#sFirst').value.trim(), dob: $('#sDob').value.trim(), ssn: $('#sSsn').value.trim() }); });
        on('#searchVehicle', 'submit', (e) => { e.preventDefault(); runSearch({ type: 'vehicle', query: $('#sQuery').value.trim() }); });
        on('#searchResults', 'click', (e) => {
            const b = e.target.closest('[data-result]');
            if (!b) return;
            $$('.result').forEach((x) => (x === b ? x.setAttribute('aria-current', 'true') : x.removeAttribute('aria-current')));
            showRecord(state.searchResults[Number(b.dataset.result)], '#recordSheet');
        });
        on('#recordSheet', 'click', recordSheetClick);
    }
    async function runSearch(params) {
        $('#searchResults').innerHTML = skeleton(4);
        const res = await api(`/search?${new URLSearchParams(params)}`, undefined, { loud: true });
        state.searchResults = res ? res.results : [];
        $('#searchResults').innerHTML = state.searchResults.map((r, i) => `
            <button type="button" class="result" data-result="${i}">
                ${r.kind === 'vehicle' ? `<b>${esc(r.plate)}</b> — ${esc([r.make, r.model].filter(Boolean).join(' '))}${r.stolen ? ' <span class="chip stop">Volé</span>' : ''}<small>VIN ${esc(r.vin || '—')} · ${esc(REG_STATUS[r.regStatus] || r.regStatus || '')}</small>`
                    : `<b>${esc(String(r.lastname || '').toUpperCase())}</b> ${esc([r.firstname, r.middlename].filter(Boolean).join(' '))}${r.condition === 'wanted' ? ' <span class="chip stop">Recherché</span>' : ''}${arr(r.registrations).length ? ' <span class="chip accent">Registre</span>' : ''}<small>${esc(r.dob || '')} · ${esc(r.address || '')}</small>`}
            </button>`).join('') || (res ? emptyState('Aucun résultat', 'Vérifiez l\'orthographe et la date de naissance.', 'search') : '<div class="error-line">Recherche impossible.</div>');
        if (state.searchResults.length === 1) showRecord(state.searchResults[0], '#recordSheet');
    }
    const dl = (rows) => `<dl class="info-grid">${rows.filter(([, v]) => v !== undefined && v !== null && v !== '').map(([k, v]) => `<dt>${esc(k)}</dt><dd>${v}</dd>`).join('')}</dl>`;
    const block = (title, html) => `<div class="sheet-block"><h4>${esc(title)}</h4>${html}</div>`;
    const bolosHtml = (r) => arr(r.bolos).map((b) => `<div class="alert">BOLO ${esc(b.number)} — ${esc(b.reason)}${b.possible ? ' (correspondance possible)' : ''}</div>`).join('');
    const recordActions = (kind, id) => `<div class="toolbar flat"><button type="button" class="btn small" data-redit="${kind}:${id}">${icon('edit')}Modifier</button><button type="button" class="btn small stop" data-rdel="${kind}:${id}">${icon('trash')}Supprimer</button></div>`;
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
            ${block(`Véhicules (${vehicles.length})`, vehicles.map((v) => `<div class="entry"><button type="button" class="linkish" data-record="vehicle" data-id="${esc(v.id)}">${esc(v.plate)}</button> — ${esc([v.make, v.model].filter(Boolean).join(' '))}${v.color ? ` (${esc(v.color)})` : ''}${v.stolen ? ' · <b>VOLÉ</b>' : ''}</div>`).join('') || '<span class="muted">Aucun véhicule.</span>')}
            ${block(`Casier judiciaire (${convictions.length + records.length})`, [...convictions.map((c) => `<div class="entry"><b>${esc(CLASS[c.class] || c.class || '')}</b> — ${esc(c.label || c.offense)} <span class="muted">${esc(c.rcw || '')}</span><br><span class="muted">faits le ${esc(c.offenseDate || '—')}, jugement le ${esc(c.convictionDate || '—')}${c.sentence ? ` — ${esc(c.sentence)}` : ''}</span></div>`),
                ...records.map((x) => `<div class="entry">${esc(x.offense || '')} <span class="muted">(ancien antécédent ${esc(x.date || '')})</span></div>`)].join('') || '<span class="muted">Casier vierge.</span>')}
            ${block(`Rapports (${reports.length})`, reports.map((x) => `<div class="entry"><b>${esc(x.label)}</b> n°${esc(x.number)}${x.callNumber ? ` — ${esc(x.callNumber)}` : ''}<br><span class="muted">${esc(x.role || '')} — ${fmtDate(x.createdAt)} par ${esc(x.createdByName || '—')}</span>${x.summary ? `<br>${esc(x.summary)}` : ''}</div>`).join('') || '<span class="muted">Aucun rapport.</span>')}`;
    }
    function vehicleSheet(r) {
        const owner = r.ownerIdentity; const hist = arr(r.history);
        return `<h3 class="d-title">${esc(r.plate)}</h3>${recordActions('vehicle', r.id)}${r.stolen ? '<div class="alert">VÉHICULE VOLÉ</div>' : ''}${r.abandoned ? '<div class="alert yellow">VÉHICULE ABANDONNÉ</div>' : ''}${bolosHtml(r)}
            ${dl([['Statut', esc(REG_STATUS[r.regStatus] || r.regStatus || '')], ['Marque', esc(r.make)], ['Modèle', esc(r.model)], ['Année', esc(r.year)], ['Couleur', esc(r.color)], ['VIN', esc(r.vin)],
                ['Contrôle technique', esc(r.inspectionDate)], ['Usage', r.commercial ? 'Véhicule commercial' : 'Particulier'], ['Assurance', esc(INSURANCE[r.insuranceStatus] || r.insuranceStatus || '')],
                ['Propriétaire', owner ? `<button type="button" class="linkish" data-record="identity" data-id="${esc(owner.id)}">${esc(String(owner.lastname || '').toUpperCase())} ${esc(owner.firstname || '')}</button> (${esc(owner.dob || '')})` : esc(r.ownerName || 'Non renseigné')]])}
            ${block(`Historique (${hist.length})`, hist.map((h) => `<div class="entry">${esc({ administrative: 'Infraction administrative', parking: 'Infraction de stationnement' }[h.type] || h.type || '')} — ${esc(h.date || '')}${h.offense ? ` — ${esc(h.offense)}` : ''}</div>`).join('') || '<span class="muted">Aucune infraction connue.</span>')}`;
    }

    // =================================================================================================================
    // REGISTRES (identiques au jeu) : Sex / Kidnapping Offenders, BOLOs, Rapports
    // =================================================================================================================
    function bindRegistries() {
        $$('#regTabs [data-reg]').forEach((b) => b.addEventListener('click', () => { state.reg.tab = b.dataset.reg; state.reg.sel = null; state.reg.page = 1; $('#regQ').value = ''; loadRegistry(); }));
        on('#regQ', 'input', () => { if (state.reg.tab === 'reports') { clearTimeout(state.reg.t); state.reg.t = setTimeout(() => { state.reg.page = 1; loadRegistry(); }, 300); } else renderRegistry(); });
        on('#regFilters', 'change', () => { if (state.reg.tab === 'reports') { state.reg.page = 1; loadRegistry(); } else renderRegistry(); });
        on('#regList', 'click', (e) => { const row = e.target.closest('[data-row]'); if (row) selectRegistry(row.dataset.row); });
        on('#regDetail', 'click', recordSheetClick);
        on('#regPager', 'click', (e) => { const b = e.target.closest('[data-rpage]'); if (b) { state.reg.page += Number(b.dataset.rpage); loadRegistry(); } });
        loadRegistry();
    }
    function regFiltersHtml() {
        const t = state.reg.tab;
        if (t === 'sex' || t === 'kidnap') return '<select id="regLevel" aria-label="Niveau"><option value="">Tous niveaux</option><option value="1">Niveau I</option><option value="2">Niveau II</option><option value="3">Niveau III</option></select><label class="check"><input type="checkbox" id="regEnded"> Inscriptions terminées</label>';
        if (t === 'bolos') return '<select id="regBoloKind" aria-label="Type"><option value="">Individus et véhicules</option><option value="person">Individus</option><option value="vehicle">Véhicules</option></select>';
        const types = state.reg.types ? state.reg.types.types.filter((x) => !x.archived) : [];
        return `<select id="regReportType" aria-label="Type de rapport"><option value="">Tous les rapports</option>${types.map((x) => `<option value="${esc(x.id)}">${esc(x.label)}</option>`).join('')}</select>`;
    }
    async function loadRegistry() {
        if (!$('#regList')) return;
        const t = state.reg.tab;
        $$('#regTabs [data-reg]').forEach((b) => b.setAttribute('aria-selected', b.dataset.reg === t ? 'true' : 'false'));
        if (t === 'reports' && !state.reg.types) { const types = await api('/registry/report-types', undefined, { loud: true }); if (types) state.reg.types = types; }
        if ($('#regFilters').dataset.tab !== t || (t === 'reports' && !$('#regReportType option[value]:not([value=""])') && state.reg.types)) { $('#regFilters').innerHTML = regFiltersHtml(); $('#regFilters').dataset.tab = t; }
        $('#regList').innerHTML = skeleton(8);
        if (!state.reg.sel) $('#regDetail').innerHTML = emptyState('Aucune fiche choisie', 'Sélectionnez une ligne.', 'reg');
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
        let rows = '';
        if (t === 'sex' || t === 'kidnap') {
            const level = $('#regLevel') ? $('#regLevel').value : ''; const ended = $('#regEnded') && $('#regEnded').checked;
            const view = state.reg.list.filter((e) => (ended || e.active) && (!level || String(e.registration.level) === level)
                && (!q || norm([e.identity.lastname, e.identity.firstname, e.registration.address, e.registration.label, e.identity.dob].join(' ')).includes(q)));
            state.reg.view = view;
            rows = view.map((e) => `<tr data-row="o:${esc(e.identity.id)}" data-ctx-rec="identity:${esc(e.identity.id)}" class="${e.active ? '' : 'ended'} ${state.reg.sel === `o:${e.identity.id}` ? 'sel' : ''}">
                <td><b>${esc(String(e.identity.lastname || '').toUpperCase())}</b> ${esc(e.identity.firstname)}<span class="sub">${esc(e.identity.dob)}${e.registration.lastUpdate ? ` · maj ${esc(e.registration.lastUpdate)}` : ''}</span></td>
                <td><span class="chip ${String(e.registration.level) === '3' ? 'stop' : String(e.registration.level) === '2' ? 'accent' : 'caution'}">Niveau ${esc(e.registration.level)}</span></td>
                <td>${esc(e.registration.label || e.registration.offense)}</td><td>${esc(e.registration.address || '—')}</td>
                <td>${e.active ? `<span class="chip ${e.registration.status === 'absconded' ? 'stop' : e.registration.status === 'noncompliant' ? 'caution' : 'go'}">${esc(REG_FOLLOW[e.registration.status] || e.registration.status)}</span>` : '<span class="chip">Terminée</span>'}</td></tr>`).join('');
            $('#regList').innerHTML = `<table class="grid"><thead><tr><th>Nom</th><th>Niveau</th><th>Charge</th><th>Adresse déclarée</th><th>Suivi</th></tr></thead><tbody>${rows || emptyRow(5, 'Aucune inscription', 'Rien pour ces filtres.')}</tbody></table>`;
            $('#regCount').textContent = `${view.length} / ${state.reg.list.length}`;
        } else if (t === 'bolos') {
            const kind = $('#regBoloKind') ? $('#regBoloKind').value : '';
            const view = state.reg.list.filter((b) => (!kind || b.kind === kind) && (!q || norm([b.number, b.reason, b.summary, b.location].join(' ')).includes(q)));
            state.reg.view = view;
            rows = view.map((b) => `<tr data-row="b:${esc(b.id)}" data-ctx-rec="bolo:${esc(b.id)}" class="${state.reg.sel === `b:${b.id}` ? 'sel' : ''}"><td class="num">${esc(b.number)}</td><td><span class="chip">${esc(BOLO_KIND[b.kind] || b.kind)}</span></td><td><b>${esc(b.reason)}</b><span class="sub">${esc(b.summary || '')}</span></td><td>${esc(AGENCY[b.agency] || b.agency || '')}</td><td>${fmtDate(b.updatedAt || b.createdAt)}</td></tr>`).join('');
            $('#regList').innerHTML = `<table class="grid"><thead><tr><th>N°</th><th>Type</th><th>Motif</th><th>Émis par</th><th>Mis à jour</th></tr></thead><tbody>${rows || emptyRow(5, 'Aucun BOLO actif', '')}</tbody></table>`;
            $('#regCount').textContent = `${view.length} BOLO(s)`;
        } else {
            const typeLabel = (id) => { const x = state.reg.types && state.reg.types.types.find((y) => y.id === id); return x ? x.short || x.label : id; };
            rows = state.reg.list.map((r) => `<tr data-row="r:${esc(r.id)}" data-ctx-rec="report:${esc(r.id)}" class="${state.reg.sel === `r:${r.id}` ? 'sel' : ''}"><td class="num">${esc(r.number)}</td><td><span class="chip">${esc(typeLabel(r.type))}</span></td><td>${esc(r.summary || '')}<span class="sub">${esc(r.createdByName || '')}${r.unitName ? ` · ${esc(r.unitName)}` : ''}</span></td><td>${esc(r.callNumber || '—')}</td><td>${fmtDate(r.createdAt)}</td></tr>`).join('');
            $('#regList').innerHTML = `<table class="grid"><thead><tr><th>N°</th><th>Type</th><th>Résumé</th><th>Appel</th><th>Date</th></tr></thead><tbody>${rows || emptyRow(5, 'Aucun rapport', 'Rien pour ces filtres.')}</tbody></table>`;
            $('#regCount').textContent = `${state.reg.total} rapport(s)`;
        }
        const pages = Math.max(1, Math.ceil(state.reg.total / 25));
        $('#regPager').classList.toggle('hidden', t !== 'reports' || pages <= 1);
        if (t === 'reports') $('#regPager').innerHTML = `<span>Page ${state.reg.page} / ${pages}</span><button type="button" class="btn small" ${state.reg.page <= 1 ? 'disabled' : ''} data-rpage="-1">Précédente</button><button type="button" class="btn small" ${state.reg.page >= pages ? 'disabled' : ''} data-rpage="1">Suivante</button>`;
        WM.setMeta('registries', $('#regCount').textContent);
    }
    async function selectRegistry(key, silent) {
        state.reg.sel = key;
        if (!silent) renderRegistry();
        const i = key.indexOf(':'); const k = key.slice(0, i); const v = key.slice(i + 1);
        if (k === 'o') { const e = state.reg.list.find((x) => String(x.identity.id) === v); if (e) showRecord({ ...e.identity, kind: 'identity' }, '#regDetail'); return; }
        $('#regDetail').innerHTML = skeleton(8);
        if (k === 'b') { const res = await api(`/registry/bolos/${encodeURIComponent(v)}`); $('#regDetail').innerHTML = res ? boloSheet(res.bolo) : emptyState('BOLO introuvable', ''); return; }
        if (k === 'r') {
            if (!state.reg.types) state.reg.types = await api('/registry/report-types');
            const res = await api(`/registry/reports/${encodeURIComponent(v)}`);
            $('#regDetail').innerHTML = res ? reportSheet(res.report) : emptyState('Rapport introuvable', '');
        }
    }
    function boloSheet(b) {
        recordCache[`bolo:${b.id}`] = b;
        const rows = b.kind === 'vehicle'
            ? [['Immatriculation', esc(b.plate)], ['Marque / modèle', esc([b.make, b.model].filter(Boolean).join(' '))], ['Couleur', esc(b.color)], ['Type', esc(b.vtype)]]
            : [['Identité liée', b.identityLabel ? esc(b.identityLabel) : (b.identityId ? 'fiche supprimée' : '')], ['Taille', b.height ? `${esc(b.height)} cm` : ''], ['Cheveux', esc(b.hairColor)],
                ['Pilosité', esc([b.facialType, b.facialColor].filter(Boolean).join(', '))], ['Tatouages', esc(b.tattoos)], ['Peau', esc(b.skin)], ['Tenue', esc(b.clothing)], ['Origine', esc(arr(b.origins).join(', '))]];
        return `<div class="win-pad"><div class="d-num">BOLO n°${esc(b.number)} · ${esc(BOLO_KIND[b.kind] || b.kind)}</div><h3 class="d-title">${esc(b.reason)}</h3>${recordActions('bolo', b.id)}
            ${dl([...rows, ['Dernier lieu', esc(b.location)], ['Émis par', `${esc(AGENCY[b.agency] || b.agency || '')}${b.unitName ? ` — ${esc(b.unitName)}` : ''}`], ['Créé', `${fmtDate(b.createdAt)} par ${esc(b.createdByName || '—')}`],
                ...(b.updatedAt ? [['Modifié', `${fmtDate(b.updatedAt)} par ${esc(b.updatedByName || '—')}`]] : [])])}
            ${b.details ? block('Détails', `<div class="desc">${esc(b.details)}</div>`) : ''}</div>`;
    }
    // rapport : rendu générique à partir des modèles du jeu (mêmes sections, mêmes libellés)
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
        return `<div class="win-pad report-view"><div class="d-num">Rapport n°${esc(r.number)} · ${esc(type ? type.label : r.type)}</div><h3 class="d-title">${esc(r.summary || '')}</h3>${recordActions('report', r.id)}
            ${dl([['Intervention', esc(r.call ? `${r.call.number} — ${r.call.title || ''}` : '—')], ['Rédigé par', `${esc(r.createdByName || '—')}${r.unitName ? ` (${esc(r.unitName)})` : ''}`], ['Date', fmtDate(r.createdAt)], ...(r.updatedAt ? [['Modifié', `${fmtDate(r.updatedAt)} par ${esc(r.updatedByName || '—')}`]] : [])])}
            ${type ? type.sections.map((s) => { const h = fieldsHtml(s.f, r.data || {}); return h.replace(/<dl class="info-grid"><\/dl>/g, '') ? `<div class="rv-section"><h4>${esc(s.title)}</h4>${h}</div>` : ''; }).join('') : `<pre>${esc(JSON.stringify(r.data, null, 2))}</pre>`}</div>`;
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
                body += arr(rec.registrations).map((g) => `<div class="d-section"><h3>Registre ${esc(REGISTRY[g.type] || g.type)}</h3><div class="form-grid" data-regtype="${esc(g.type)}">${REG_EDIT.map(([n, l, t, o]) => inputHtml(`reg.${n}`, l, t, o, false, g[n])).join('')}</div></div>`).join('');
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
    // formulaire de rapport généré depuis le modèle du jeu (champs simples ; listes : champs simples de chaque élément)
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
            else if (f.t === 'list') arr(data[f.k]).forEach((it, i) => { out += `<div class="span-2 d-section"><h3>${esc(f.item || f.l)} ${i + 1}</h3><div class="form-grid">${reportFormFields(f.f, it || {}, `${prefix}${f.k}.${i}.`)}</div></div>`; });
            else if (f.k) out += reportInput(f, data[f.k], prefix);
        }
        return out;
    }
    function reportFormHtml(type, data) {
        if (!type) return '<div class="error-line">Modèle de rapport inconnu.</div>';
        return `${type.sections.map((s) => `<div class="d-section"><h3>${esc(s.title)}</h3><div class="form-grid">${reportFormFields(s.f, data, '')}</div></div>`).join('')}
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
        const ok = await WM.confirm({ title: `Supprimer : ${KIND_LABEL[kind]}`, text: `<b>${esc(label)}</b> part à la <b>corbeille</b> : retiré(e) du jeu et du site, restaurable pendant 30 jours.`, ok: 'Mettre à la corbeille' });
        if (!ok) return;
        if (await api(`/records/${kind}/${encodeURIComponent(id)}/delete`, {})) {
            toast('ok', KIND_LABEL[kind], 'Mis à la corbeille.');
            state.reg.sel = null;
            for (const target of ['#regDetail', '#recordSheet']) if ($(target) && $(target).innerHTML.includes(`data-rdel="${kind}:${id}"`)) $(target).innerHTML = emptyState('Fiche supprimée', 'Restaurable depuis la corbeille.', 'trash');
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
    // CORBEILLE, JOURNAL D'AUDIT, HISTORIQUE, JOURNAL DES ACTIONS
    // =================================================================================================================
    function bindTrash() { on('#trashBody', 'click', trashClick); loadTrash(); }
    async function loadTrash() {
        if (!$('#trashBody')) return;
        $('#trashBody').innerHTML = skelRow(5);
        const res = await api('/trash');
        if (!$('#trashBody')) return;
        state.trash = res ? res.items : [];
        $('#trashBody').innerHTML = state.trash.map((t) => `<tr><td><span class="chip">${esc(KIND_LABEL[t.kind] || t.kind)}</span> <b>${esc(t.label)}</b></td><td>${esc(t.deletedBy || '—')}</td><td>${fmtDate(t.deletedAt)}</td><td>${fmtDate(t.expiresAt)}</td>
            <td><div class="toolbar flat"><button type="button" class="btn small go" data-trestore="${t.id}">${icon('undo')}Restaurer</button><button type="button" class="btn small ghost icon" data-tpurge="${t.id}" title="Supprimer définitivement" aria-label="Supprimer définitivement">${icon('trash')}</button></div></td></tr>`).join('')
            || emptyRow(5, 'Corbeille vide', 'Les éléments supprimés y restent 30 jours.');
        WM.setMeta('trash', `${state.trash.length} élément(s)`);
        WM.setBadge('trash', 0);
    }
    async function trashClick(e) {
        const r = e.target.closest('[data-trestore]');
        if (r) { r.disabled = true; if (await api(`/trash/${r.dataset.trestore}/restore`, {})) { toast('ok', 'Corbeille', 'Élément restauré.'); loadTrash(); } else r.disabled = false; return; }
        const p = e.target.closest('[data-tpurge]');
        if (p) {
            const t = state.trash.find((x) => x.id === Number(p.dataset.tpurge));
            const ok = await WM.confirm({ title: 'Suppression définitive', text: `<b>${esc(t ? t.label : '')}</b> sera <b>effacé(e) pour de bon</b>. Cette action est irréversible.`, ok: 'Effacer définitivement' });
            if (ok && await api(`/trash/${p.dataset.tpurge}/purge`, {})) { toast('ok', 'Corbeille', 'Effacé définitivement.'); loadTrash(); }
        }
    }
    function bindAudit() {
        ['#auditKind', '#auditAction'].forEach((s) => on(s, 'change', () => { state.auditPage = 1; loadAudit(); }));
        on('#auditQ', 'input', () => { clearTimeout(state.auditT); state.auditT = setTimeout(() => { state.auditPage = 1; loadAudit(); }, 300); });
        loadAudit();
    }
    const diffHtml = (before, after) => {
        if (!before && !after) return '<span class="muted">—</span>';
        if (!before || !after) return `<span class="muted">${before ? 'contenu conservé dans la corbeille' : 'restauré'}</span>`;
        const keys = [...new Set([...Object.keys(before), ...Object.keys(after)])].filter((k) => !['updatedAt', 'updatedByName', 'searchText'].includes(k) && typeof (after[k] ?? before[k]) !== 'object' && String(before[k] ?? '') !== String(after[k] ?? ''));
        return keys.slice(0, 8).map((k) => `<span class="change">${esc(k)} : <del>${esc(before[k] ?? '—')}</del> → <ins>${esc(after[k] ?? '—')}</ins></span>`).join('') || '<span class="muted">détails (listes) modifiés</span>';
    };
    async function loadAudit() {
        if (!$('#auditBody')) return;
        $('#auditBody').innerHTML = skelRow(5);
        const res = await api(`/audit?${new URLSearchParams({ kind: $('#auditKind').value, action: $('#auditAction').value, q: $('#auditQ').value.trim(), page: state.auditPage })}`);
        if (!$('#auditBody')) return;
        if (!res) { $('#auditBody').innerHTML = emptyRow(5, 'Audit indisponible', ''); return; }
        $('#auditBody').innerHTML = res.entries.map((a) => `<tr><td>${fmtDate(a.at)}</td><td>${esc(a.actorName || '—')}<span class="sub">${esc({ dispatch: 'Site', game: 'Jeu' }[a.source] || a.source)}</span></td><td><span class="chip ${a.action === 'purge' || a.action === 'delete' ? 'stop' : a.action === 'restore' || a.action === 'reopen' ? 'go' : 'accent'}">${esc(AUDIT_ACTION[a.action] || a.action)}</span></td>
            <td><span class="chip">${esc(KIND_LABEL[a.kind] || a.kind)}</span> ${esc(a.label)}</td><td>${diffHtml(a.before, a.after)}</td></tr>`).join('') || emptyRow(5, 'Rien pour ces filtres', '');
        pager('#auditPager', res, (page) => { state.auditPage = page; loadAudit(); });
    }
    const dateToS = (v, end) => (v ? Math.floor(new Date(`${v}T${end ? '23:59:59' : '00:00:00'}`).getTime() / 1000) : 0);
    function bindHistory() { on('#historyForm', 'submit', (e) => { e.preventDefault(); state.historyPage = 1; loadHistory(); }); loadHistory(); }
    async function loadHistory() {
        if (!$('#historyBody')) return;
        $('#historyBody').innerHTML = skelRow(7);
        const p = new URLSearchParams({ q: $('#historyQ').value.trim(), status: $('#historyStatus').value, from: dateToS($('#historyFrom').value), to: dateToS($('#historyTo').value, true), page: state.historyPage });
        const res = await api(`/history?${p}`);
        if (!$('#historyBody')) return;
        if (!res) { $('#historyBody').innerHTML = emptyRow(7, 'Historique indisponible', ''); return; }
        $('#historyBody').innerHTML = res.calls.map((c) => `<tr data-call="${c.id}" data-ctx-call="${c.id}"><td class="num">${esc(c.number)}</td><td>${prioChip(c.priority)}</td><td><b>${esc(c.title)}</b></td><td>${esc(c.address)}</td><td>${statusChip(c.status)}</td><td>${fmtDate(c.createdAt)}</td><td>${fmtDate(c.closedAt)}${c.clear ? ` <span class="muted">Clear ${esc(c.clear)}</span>` : ''}</td></tr>`).join('') || emptyRow(7, 'Aucun résultat', '');
        pager('#historyPager', res, (page) => { state.historyPage = page; loadHistory(); });
    }
    function pager(sel, res, go) {
        const pages = Math.max(1, Math.ceil(res.total / res.size));
        $(sel).innerHTML = `<span>${res.total} résultat(s) — page ${res.page} / ${pages}</span><button type="button" class="btn small" ${res.page <= 1 ? 'disabled' : ''} data-page="${res.page - 1}">Précédente</button><button type="button" class="btn small" ${res.page >= pages ? 'disabled' : ''} data-page="${res.page + 1}">Suivante</button>`;
        $$('[data-page]', $(sel)).forEach((b) => b.addEventListener('click', () => go(Number(b.dataset.page))));
    }
    function bindLog() { on('#logSource', 'change', () => { state.logPage = 1; loadLog(); }); loadLog(); }
    async function loadLog() {
        if (!$('#logBody')) return;
        $('#logBody').innerHTML = skelRow(5);
        const res = await api(`/log?source=${$('#logSource').value}&page=${state.logPage}`);
        if (!$('#logBody')) return;
        if (!res) { $('#logBody').innerHTML = emptyRow(5, 'Journal indisponible', ''); return; }
        const detail = (l) => { const d = l.details || {}; return [d.number, d.unit, d.title, d.name && `écran de ${d.name} (#${d.serverId})`, d.reason && `motif : ${d.reason}`, d.from && d.to && `${UNIT_STATUS[d.from] || d.from} → ${UNIT_STATUS[d.to] || d.to}`, d.clear && `Clear ${d.clear}`, Array.isArray(d.units) && d.units.length && `unités : ${d.units.join(', ')}`, Array.isArray(d.changes) && d.changes.map((c) => c.label || c.field).join(', ')].filter(Boolean).map(esc).join(' — '); };
        $('#logBody').innerHTML = res.entries.map((l) => `<tr><td>${fmtDate(l.at)}</td><td><span class="chip">${esc({ dispatch: 'Dispatch', game: 'Jeu', web: 'Site' }[l.source] || l.source)}</span></td><td>${esc(l.actorName || '—')}</td><td>${esc(ACTIONS[l.action] || l.action)}</td><td>${detail(l)}</td></tr>`).join('') || emptyRow(5, 'Journal vide', '');
        pager('#logPager', res, (page) => { state.logPage = page; loadLog(); });
    }

    // =================================================================================================================
    // LIVEVIEW : vidéo WebRTC (serveur relais LiveKit) ; repli : images si le relais n'est pas configuré
    // =================================================================================================================
    const live = { tiles: store.get('mdc.live.tiles', []), pips: store.get('mdc.live.pips', []), rooms: new Map(), frames: {}, stats: {}, filtered: [], rtc: false };
    const saveTiles = () => { store.set('mdc.live.tiles', live.tiles.map(({ serverId, pinned, masked }) => ({ serverId, pinned, masked }))); store.set('mdc.live.pips', live.pips); };
    const playerById = (id) => state.players.find((p) => p.serverId === id);
    const serviceOf = (p) => (p.agency === 'kcso' || p.agency === 'wsp' ? p.agency : p.agency === 'generic' ? 'generic' : 'none');
    const SERVICE_LABEL = { kcso: 'KCSO', wsp: 'WSP', generic: 'Civil', none: 'Sans MDC' };
    // vidéo reçue récemment pour ce joueur (sinon : images de repli)
    const hasVideo = (id) => { const st = live.stats[id]; return !!(st && st.at && Date.now() - st.at < 6000); };
    function watched() {
        const map = new Map();
        if (WM.isOpen('live')) for (const t of live.tiles) if (!t.masked && playerById(t.serverId)) map.set(t.serverId, 'grid');
        for (const p of live.pips) if (playerById(p.serverId)) map.set(p.serverId, p.full ? 'focus' : (map.get(p.serverId) || 'grid'));
        return map;
    }
    // le site vérifie la session, journalise la consultation et donne un jeton lecteur par joueur (une salle par joueur)
    function liveSync() {
        if (!socket) return;
        const want = watched();
        const list = [...want].map(([serverId, mode]) => ({ serverId, mode }));
        WM.setBadge('live', list.length);
        for (const id of [...live.rooms.keys()]) if (!want.has(id)) leaveRoom(id);
        socket.emit('live:watch', list, (r) => {
            if (!r) return;
            if (r.refused && r.refused.length) toast('error', 'LiveView', `Limite de flux atteinte : ${r.refused.length} joueur(s) non affiché(s).`);
            live.rtc = !!r.rtc;
            if (r.rtc && window.LivekitClient) for (const [id, token] of Object.entries(r.rtc.tokens || {})) joinRoom(Number(id), r.rtc.url, token);
        });
    }
    async function joinRoom(serverId, url, token) {
        if (live.rooms.has(serverId) || !watched().has(serverId)) return;
        const { Room, RoomEvent } = window.LivekitClient;
        const room = new Room({ adaptiveStream: true, dynacast: false });
        const entry = { room, connected: false };
        live.rooms.set(serverId, entry);
        room.on(RoomEvent.TrackSubscribed, (track) => attachTrack(serverId, track));
        room.on(RoomEvent.TrackUnsubscribed, (track) => { track.detach().forEach((el) => el.remove()); delete live.stats[serverId]; refreshScreens(serverId); });
        room.on(RoomEvent.ConnectionQualityChanged, (q, participant) => { if (!participant.isLocal) live.stats[serverId] = { ...(live.stats[serverId] || {}), quality: q }; });
        room.on(RoomEvent.Disconnected, () => { if (live.rooms.get(serverId) === entry) live.rooms.delete(serverId); delete live.stats[serverId]; refreshScreens(serverId); });
        try { await room.connect(url, token, { autoSubscribe: true }); entry.connected = true; } catch (e) { live.rooms.delete(serverId); }
        if (!watched().has(serverId)) leaveRoom(serverId);
    }
    function leaveRoom(serverId) { const e = live.rooms.get(serverId); if (e) { live.rooms.delete(serverId); e.room.disconnect(); } delete live.stats[serverId]; }
    function videoTargets(serverId) { return $$(`[data-tile="${serverId}"] .tile-screen, [data-pip="${serverId}"] .tile-screen`); }
    function attachTrack(serverId, track) {
        if (track.kind !== 'video') return;
        for (const screen of videoTargets(serverId)) {
            if (screen.querySelector('video') || screen.closest('.masked')) continue;
            const v = track.attach();
            v.muted = true; v.playsInline = true;
            screen.innerHTML = '';
            screen.appendChild(v);
            measureVideo(serverId, v);
        }
    }
    function measureVideo(id, v) { // images / s et résolution réelles affichées
        const frames = [];
        const tick = (now) => {
            const st = live.stats[id] = live.stats[id] || {};
            frames.push(now); while (frames.length && now - frames[0] > 3000) frames.shift();
            st.fps = frames.length > 1 ? (frames.length - 1) / ((frames[frames.length - 1] - frames[0]) / 1000) : 0;
            st.size = `${v.videoWidth}x${v.videoHeight}`; st.at = Date.now();
            if (v.isConnected) v.requestVideoFrameCallback(tick);
        };
        if (v.requestVideoFrameCallback) v.requestVideoFrameCallback(tick);
    }
    async function latencyOf(id) { // délai de réception (gigue + décodage), en ms
        const e = live.rooms.get(id);
        if (!e || !e.connected) return null;
        for (const p of e.room.remoteParticipants.values()) {
            for (const pub of p.trackPublications.values()) {
                if (!pub.track || !pub.track.receiver) continue;
                const report = await pub.track.receiver.getStats();
                let ms = null;
                report.forEach((s) => { if (s.type === 'inbound-rtp' && s.jitterBufferEmittedCount) ms = Math.round((s.jitterBufferDelay / s.jitterBufferEmittedCount) * 1000); });
                return ms;
            }
        }
        return null;
    }
    function reattachAll() {
        for (const [id, e] of live.rooms) for (const p of e.room.remoteParticipants.values()) for (const pub of p.trackPublications.values()) if (pub.track) attachTrack(id, pub.track);
    }
    function refreshScreens(id) { // vidéo perdue : image de repli ou attente
        for (const screen of videoTargets(id)) if (!screen.querySelector('video')) { const f = live.frames[id]; screen.innerHTML = f ? `<img src="${f.url}" alt="Écran du joueur ${id}">` : '<div class="placeholder">Connexion au flux…</div>'; }
    }
    function screenHtml(t, p) {
        if (!p) return '<div class="placeholder">Joueur déconnecté</div>';
        if (t.masked) return '<div class="placeholder">Masqué — aucune image envoyée</div>';
        const f = live.frames[t.serverId];
        if (f && !hasVideo(t.serverId)) return `<img src="${f.url}" alt="Écran de ${esc(p.name)}">`;
        return '<div class="placeholder">Connexion au flux…</div>';
    }
    function footHtml(id) {
        const st = live.stats[id] || {};
        const f = live.frames[id];
        const useRtc = hasVideo(id);
        const fresh = useRtc ? Date.now() - st.at : (f ? Date.now() - f.at : null);
        const tone2 = fresh === null ? '' : fresh < 3500 ? 'go' : fresh < 8000 ? 'caution' : 'stop';
        const q = { excellent: 'excellente', good: 'bonne', poor: 'faible', lost: 'perdue' }[st.quality] || '';
        const fps = useRtc ? st.fps : f && f.fps;
        const ms = useRtc ? st.latency : f && f.uploadMs;
        return `<span class="dot ${tone2}"></span><span>${fps ? fps.toFixed(1) : '—'} i/s</span><span>${ms != null ? `${Math.round(ms)} ms` : '— ms'}</span><span>${esc((useRtc ? st.size : f && f.size) || '')}</span>${useRtc && q ? `<span>liaison ${q}</span>` : ''}<span>${useRtc ? 'WebRTC' : f ? 'images' : (live.rtc ? 'WebRTC' : 'images')}</span>`;
    }
    function tileHtml(t) {
        const p = playerById(t.serverId);
        return `<div class="tile ${t.pinned ? 'pinned' : ''} ${t.masked ? 'masked' : ''}" data-tile="${t.serverId}" draggable="true">
            <div class="tile-head"><span class="grip" title="Glisser pour réorganiser">${icon('grip')}</span><span class="t-name">${esc(p ? p.name : `Joueur ${t.serverId}`)}<small>#${t.serverId}${p && p.unitName ? ` · ${esc(p.unitName)}` : ''}</small></span>
                ${p ? `<span class="chip">${esc(SERVICE_LABEL[serviceOf(p)])}</span>` : ''}
                <button type="button" class="win-ctl" data-tact="pin" title="${t.pinned ? 'Désépingler' : 'Épingler en tête'}" aria-pressed="${t.pinned}">${icon('pin')}</button>
                <button type="button" class="win-ctl" data-tact="mask" title="${t.masked ? 'Réafficher' : 'Masquer (stoppe le flux)'}">${icon(t.masked ? 'eye' : 'eyeoff')}</button>
                <button type="button" class="win-ctl" data-tact="pip" title="Détacher en incrustation (PiP)">${icon('pip')}</button>
                <button type="button" class="win-ctl close" data-tact="remove" title="Retirer de la mosaïque">${icon('x')}</button></div>
            <div class="tile-screen">${screenHtml(t, p)}</div><div class="tile-foot" data-foot="${t.serverId}">${footHtml(t.serverId)}</div></div>`;
    }
    function renderLivePlayers() {
        if (!$('#livePlayers')) return;
        const q = norm($('#liveQ').value); const service = $('#liveService').value; const unit = $('#liveUnit').value;
        const units = [...new Set(state.players.map((p) => p.unitName).filter(Boolean))].sort();
        $('#liveUnit').innerHTML = `<option value="">Toutes les unités</option>${units.map((u) => `<option ${u === unit ? 'selected' : ''}>${esc(u)}</option>`).join('')}`;
        const shown = new Set(live.tiles.map((t) => t.serverId));
        live.filtered = state.players.filter((p) => (!service || serviceOf(p) === service) && (!unit || p.unitName === unit) && (!q || norm(`${p.name} ${p.serverId} ${p.unitName || ''}`).includes(q)));
        $('#livePlayers').innerHTML = live.filtered.map((p) => `<label class="lp"><input type="checkbox" data-lp="${p.serverId}" ${shown.has(p.serverId) ? 'checked' : ''} aria-label="Afficher ${esc(p.name)}">
            <span class="lp-name">${esc(p.name)}<small>#${p.serverId}${p.unitName ? ` · ${esc(p.unitName)}` : ''}</small></span><span class="chip ${p.agency === 'kcso' ? 'go' : p.agency === 'wsp' ? 'accent' : ''}">${esc(SERVICE_LABEL[serviceOf(p)])}</span></label>`).join('')
            || emptyState('Aucun joueur', state.players.length ? 'Aucun joueur pour ces filtres.' : 'Personne n\'est connecté en jeu.', 'live');
    }
    function renderLive() {
        if (!$('#liveGrid')) return;
        $('#liveUnavailable').classList.toggle('hidden', state.liveAvailable || !state.fivem.online);
        $('#liveUnavailable').textContent = 'LiveView indisponible : la ressource screenshot-basic n\'est pas démarrée sur le serveur FiveM.';
        renderLivePlayers();
        const tiles = [...live.tiles].sort((a, b) => (b.pinned ? 1 : 0) - (a.pinned ? 1 : 0));
        $('#liveGrid').innerHTML = tiles.map(tileHtml).join('') || emptyState('Aucun écran affiché', 'Cochez des joueurs à gauche.', 'live');
        reattachAll();
    }
    function bindLive() {
        on('#livePlayers', 'change', (e) => {
            const cb = e.target.closest('[data-lp]');
            if (!cb) return;
            const id = Number(cb.dataset.lp);
            if (cb.checked) { if (!live.tiles.some((t) => t.serverId === id)) live.tiles.push({ serverId: id, pinned: false, masked: false }); } else live.tiles = live.tiles.filter((t) => t.serverId !== id);
            saveTiles(); renderLive(); liveSync();
        });
        on('#liveAddAll', 'click', () => { for (const p of live.filtered) if (!live.tiles.some((t) => t.serverId === p.serverId)) live.tiles.push({ serverId: p.serverId, pinned: false, masked: false }); saveTiles(); renderLive(); liveSync(); });
        on('#liveClear', 'click', () => { live.tiles = []; saveTiles(); renderLive(); liveSync(); });
        on('#liveQ', 'input', renderLivePlayers);
        ['#liveService', '#liveUnit'].forEach((s) => on(s, 'change', renderLivePlayers));
        let dragId = null;
        on('#liveGrid', 'dragstart', (e) => { const tile = e.target.closest('[data-tile]'); if (!tile) return; dragId = Number(tile.dataset.tile); tile.classList.add('dragging'); e.dataTransfer.effectAllowed = 'move'; e.dataTransfer.setData('text/plain', String(dragId)); });
        on('#liveGrid', 'dragend', () => { dragId = null; $$('.tile').forEach((t) => t.classList.remove('dragging', 'drop-target')); });
        on('#liveGrid', 'dragover', (e) => { const tile = e.target.closest('[data-tile]'); if (!tile || dragId === null) return; e.preventDefault(); $$('.tile').forEach((t) => t.classList.toggle('drop-target', t === tile && Number(tile.dataset.tile) !== dragId)); });
        on('#liveGrid', 'drop', (e) => {
            const tile = e.target.closest('[data-tile]');
            if (!tile || dragId === null) return;
            e.preventDefault();
            const from = live.tiles.findIndex((t) => t.serverId === dragId); const to = live.tiles.findIndex((t) => t.serverId === Number(tile.dataset.tile));
            if (from < 0 || to < 0 || from === to) return;
            const [moved] = live.tiles.splice(from, 1); live.tiles.splice(to, 0, moved);
            saveTiles(); renderLive();
        });
        on('#liveGrid', 'click', (e) => {
            const b = e.target.closest('[data-tact]');
            if (!b) return;
            const id = Number(b.closest('[data-tile]').dataset.tile);
            const t = live.tiles.find((x) => x.serverId === id);
            if (!t) return;
            const act = b.dataset.tact;
            if (act === 'pin') t.pinned = !t.pinned;
            if (act === 'mask') t.masked = !t.masked;
            if (act === 'remove') live.tiles = live.tiles.filter((x) => x.serverId !== id);
            if (act === 'pip') openPip(id);
            saveTiles(); renderLive(); liveSync();
        });
        renderLive();
        liveSync();
    }
    // ---- incrustation (PiP) : reste visible partout, déplaçable, aimantée aux coins ----
    function openPip(serverId) {
        if (!live.pips.some((p) => p.serverId === serverId)) live.pips.push({ serverId, corner: 'br', w: 360, full: false });
        saveTiles(); renderPips(); liveSync();
    }
    function closePip(serverId) { live.pips = live.pips.filter((p) => p.serverId !== serverId); saveTiles(); renderPips(); liveSync(); }
    function pipFull() { const p = live.pips.find((x) => x.full); if (p) { p.full = false; saveTiles(); renderPips(); liveSync(); return true; } return false; }
    function placePip(el, p, i) {
        if (p.full) { el.style.left = ''; el.style.top = ''; el.style.right = ''; el.style.bottom = ''; el.style.width = ''; return; }
        el.style.width = `${p.w}px`;
        const off = 16 + i * 24;
        el.style.left = p.corner.includes('l') ? `${off}px` : 'auto'; el.style.right = p.corner.includes('r') ? `${off}px` : 'auto';
        el.style.top = p.corner.includes('t') ? `calc(var(--top) + ${off}px)` : 'auto'; el.style.bottom = p.corner.includes('b') ? `calc(var(--dock) + ${off}px)` : 'auto';
    }
    function renderPips() {
        $$('.pip').forEach((el) => { if (!live.pips.some((p) => String(p.serverId) === el.dataset.pip)) el.remove(); });
        live.pips.forEach((p, i) => {
            let el = $(`.pip[data-pip="${p.serverId}"]`);
            const pl = playerById(p.serverId);
            if (!el) {
                el = document.createElement('aside');
                el.className = 'pip glass';
                el.dataset.pip = p.serverId;
                el.setAttribute('aria-label', 'LiveView en incrustation');
                document.body.appendChild(el);
                el.addEventListener('click', (e) => {
                    const b = e.target.closest('[data-pact]');
                    const cur = live.pips.find((x) => x.serverId === p.serverId);
                    if (!b || !cur) return;
                    if (b.dataset.pact === 'close') closePip(cur.serverId);
                    if (b.dataset.pact === 'full') { cur.full = !cur.full; saveTiles(); renderPips(); liveSync(); }
                    if (b.dataset.pact === 'back') { if (!live.tiles.some((t) => t.serverId === cur.serverId)) live.tiles.push({ serverId: cur.serverId, pinned: false, masked: false }); closePip(cur.serverId); WM.open('live'); renderLive(); }
                    if (b.dataset.pact === 'size') { cur.w = cur.w >= 560 ? 280 : cur.w + 140; saveTiles(); renderPips(); }
                });
                el.addEventListener('pointerdown', (e) => {
                    const cur = live.pips.find((x) => x.serverId === p.serverId);
                    if (e.target.closest('button') || !cur || cur.full) return;
                    const r = el.getBoundingClientRect(); const ox = e.clientX - r.left; const oy = e.clientY - r.top;
                    const move = (ev) => { el.style.left = `${ev.clientX - ox}px`; el.style.top = `${ev.clientY - oy}px`; el.style.right = 'auto'; el.style.bottom = 'auto'; };
                    const up = (ev) => { removeEventListener('pointermove', move); removeEventListener('pointerup', up); cur.corner = `${ev.clientY < innerHeight / 2 ? 't' : 'b'}${ev.clientX < innerWidth / 2 ? 'l' : 'r'}`; saveTiles(); placePip(el, cur, live.pips.indexOf(cur)); };
                    addEventListener('pointermove', move); addEventListener('pointerup', up);
                });
            }
            el.classList.toggle('full', !!p.full);
            const f = live.frames[p.serverId];
            el.innerHTML = `<div class="tile-head"><span class="t-name">${esc(pl ? pl.name : `Joueur ${p.serverId}`)}<small>#${p.serverId}${pl && pl.unitName ? ` · ${esc(pl.unitName)}` : ''}</small></span>
                <button type="button" class="win-ctl" data-pact="size" title="Taille">${icon('max')}</button><button type="button" class="win-ctl" data-pact="full" title="${p.full ? 'Réduire' : 'Plein écran'}">${icon('expand')}</button>
                <button type="button" class="win-ctl" data-pact="back" title="Remettre dans la mosaïque">${icon('live')}</button><button type="button" class="win-ctl close" data-pact="close" title="Fermer">${icon('x')}</button></div>
                <div class="tile-screen">${pl ? (f && !hasVideo(p.serverId) ? `<img src="${f.url}" alt="Écran de ${esc(pl.name)}">` : '<div class="placeholder">Connexion au flux…</div>') : '<div class="placeholder">Joueur déconnecté</div>'}</div><div class="tile-foot" data-foot="${p.serverId}">${footHtml(p.serverId)}</div>`;
            placePip(el, p, i);
        });
        reattachAll();
    }
    setInterval(async () => { // indicateurs (i/s, latence, résolution) : flux affichés seulement
        for (const id of watched().keys()) {
            if (live.rooms.has(id)) { const ms = await latencyOf(id).catch(() => null); if (ms !== null) live.stats[id] = { ...(live.stats[id] || {}), latency: ms }; }
            $$(`[data-foot="${id}"]`).forEach((el) => { el.innerHTML = footHtml(id); });
        }
    }, 1000);
    function onLiveFrame(f) { // repli sans relais WebRTC : images compressées
        if (!f || !f.data) return;
        const id = Number(f.serverId);
        const prev = live.frames[id];
        const url = URL.createObjectURL(new Blob([f.data], { type: 'image/jpeg' }));
        const times = prev ? prev.times.concat(Date.now()).slice(-8) : [Date.now()];
        live.frames[id] = { url, at: Date.now(), size: f.size, uploadMs: f.uploadMs, times, fps: times.length > 1 ? (times.length - 1) / ((times[times.length - 1] - times[0]) / 1000) : 0 };
        if (prev) setTimeout(() => URL.revokeObjectURL(prev.url), 1000);
        for (const screen of videoTargets(id)) {
            if (screen.closest('.masked') || screen.querySelector('video')) continue;
            const img = screen.querySelector('img');
            if (img) img.src = url; else screen.innerHTML = `<img src="${url}" alt="Écran du joueur ${id}">`;
        }
    }

    // =================================================================================================================
    // PALETTE DE COMMANDES (Ctrl+K) ET MENUS CONTEXTUELS
    // =================================================================================================================
    WM.palette.add((q) => {
        const n = norm(q);
        const items = APPS.filter((a) => a.dock !== false && (!n || norm(a.title).includes(n))).map((a) => ({ label: `Ouvrir : ${a.title}`, icon: a.icon, key: a.key, action: () => WM.open(a.id) }));
        const extra = [{ label: 'Nouvelle intervention', icon: 'plus', key: 'N', action: () => openNew('intervention') }, { label: 'Nouvel incident', icon: 'plus', key: 'I', action: () => openNew('incident') },
            { label: 'Réinitialiser la disposition de cet espace', icon: 'dash', action: () => WM.resetWorkspace() }, { label: 'Raccourcis clavier', icon: 'keys', key: '?', action: () => $('#helpModal').classList.remove('hidden') }]
            .filter((x) => !n || norm(x.label).includes(n));
        return { title: 'Actions', items: [...extra, ...items] };
    });
    WM.palette.add((q) => {
        const n = norm(q);
        if (!n) return null;
        return { title: 'Interventions', items: state.calls.filter((c) => norm([c.number, c.title, c.address, c.caller].join(' ')).includes(n)).slice(0, 8)
            .map((c) => ({ label: `${c.number} — ${c.title}`, hint: `${c.address} · ${CALL_STATUS[c.status]}`, icon: 'calls', action: () => openCall(c.id) })) };
    });
    WM.palette.add((q) => {
        const n = norm(q);
        if (!n) return null;
        return { title: 'Unités', items: state.units.filter((u) => norm([u.name, u.tag, ...u.members.map((m) => m.name)].join(' ')).includes(n)).slice(0, 6)
            .map((u) => ({ label: u.name, hint: `${UNIT_STATUS[u.status]}${state.positions[u.id] && state.positions[u.id].street ? ` · ${state.positions[u.id].street}` : ''}`, icon: 'units', action: () => openChat(`d:u:${u.id}`) })) };
    });
    WM.palette.add((q) => {
        const n = norm(q);
        if (!n) return null;
        return { title: 'Conversations', items: state.conversations.filter((c) => c.kind !== 'call' && norm(c.label).includes(n)).slice(0, 6).map((c) => ({ label: c.label, hint: { civil: 'groupe civil', private: 'civil', unit: 'unité' }[c.kind], icon: 'msg', action: () => openChat(c.channel) })) };
    });
    WM.palette.add((q) => {
        const n = norm(q);
        if (n.length < 2) return null;
        return { title: 'Joueurs (LiveView)', items: state.players.filter((p) => norm(`${p.name} ${p.serverId}`).includes(n)).slice(0, 5).map((p) => ({ label: `${p.name} #${p.serverId}`, hint: SERVICE_LABEL[serviceOf(p)], icon: 'pip', action: () => openPip(p.serverId) })) };
    });
    on('#omnibox', 'click', () => WM.palette.open());

    document.addEventListener('contextmenu', (e) => {
        const callEl = e.target.closest('[data-ctx-call]');
        const unitEl = e.target.closest('[data-ctx-unit]');
        const convEl = e.target.closest('[data-ctx-conv]');
        const recEl = e.target.closest('[data-ctx-rec]');
        const tileEl = e.target.closest('[data-tile]');
        if (!callEl && !unitEl && !convEl && !recEl && !tileEl) return;
        e.preventDefault();
        if (callEl) {
            const id = Number(callEl.dataset.ctxCall);
            const c = state.calls.find((x) => x.id === id) || { id, status: 'closed', number: '' };
            WM.menu(e.clientX, e.clientY, [
                { label: 'Ouvrir', icon: 'calls', action: () => openCall(id) },
                { label: 'Modifier', icon: 'edit', action: async () => { await openCall(id); enterEdit(); } },
                ...(c.status === 'awaiting' ? [{ label: 'Valider et transmettre', icon: 'check', action: async () => { if (await api(`/calls/${id}/validate`, { units: [] })) toast('ok', c.number, 'Transmise.'); } }] : []),
                ...(['closed', 'refused', 'cancelled'].includes(c.status) ? [{ label: 'Rouvrir', icon: 'reopen', action: async () => { if (await api(`/calls/${id}/reopen`, {})) toast('ok', c.number, 'Rouverte.'); } }] : []),
                { sep: true },
                { label: 'Supprimer (corbeille)', icon: 'trash', danger: true, action: async () => { await openCall(id); callAction('delete'); } },
            ]);
        } else if (unitEl) {
            const u = state.units.find((x) => x.id === Number(unitEl.dataset.ctxUnit));
            if (!u) return;
            WM.menu(e.clientX, e.clientY, [
                { label: `Écrire à ${u.name}`, icon: 'msg', action: () => openChat(`d:u:${u.id}`) },
                ...Object.entries(UNIT_STATUS).filter(([k]) => k !== u.status).map(([k, v]) => ({ label: `Statut : ${v}`, icon: 'units', action: () => api(`/units/${u.id}/status`, { status: k }) })),
                ...state.players.filter((p) => p.unitId === u.id).map((p) => ({ label: `LiveView : ${p.name}`, icon: 'pip', action: () => openPip(p.serverId) })),
            ]);
        } else if (convEl) {
            const ch = convEl.dataset.ctxConv;
            WM.menu(e.clientX, e.clientY, [{ label: 'Ouvrir', icon: 'msg', action: () => openChat(ch) }, { sep: true },
                { label: 'Vider les messages', icon: 'trash', danger: true, action: () => deleteConversation(ch, 'empty') }, { label: 'Supprimer la conversation', icon: 'trash', danger: true, action: () => deleteConversation(ch, 'delete') }]);
        } else if (recEl) {
            const i = recEl.dataset.ctxRec.indexOf(':');
            const kind = recEl.dataset.ctxRec.slice(0, i); const id = recEl.dataset.ctxRec.slice(i + 1);
            WM.menu(e.clientX, e.clientY, [{ label: 'Ouvrir', icon: 'reg', action: () => { const row = recEl.closest('[data-row]'); if (row) selectRegistry(row.dataset.row); } },
                { label: 'Modifier', icon: 'edit', action: () => editRecord(kind, id) }, { sep: true }, { label: 'Supprimer (corbeille)', icon: 'trash', danger: true, action: () => deleteRecord(kind, id) }]);
        } else if (tileEl) {
            const id = Number(tileEl.dataset.tile);
            WM.menu(e.clientX, e.clientY, [{ label: 'Détacher en incrustation (PiP)', icon: 'pip', action: () => openPip(id) },
                { label: 'Plein écran', icon: 'expand', action: () => { openPip(id); const p = live.pips.find((x) => x.serverId === id); if (p) { p.full = true; saveTiles(); renderPips(); liveSync(); } } },
                { label: 'Retirer de la mosaïque', icon: 'x', danger: true, action: () => { live.tiles = live.tiles.filter((x) => x.serverId !== id); saveTiles(); renderLive(); liveSync(); } }]);
        }
    });

    // =================================================================================================================
    // RENDU GÉNÉRAL, TEMPS RÉEL
    // =================================================================================================================
    function renderAll() { renderHeader(); renderKpi(); renderQueue(); renderCalls(); renderUnits(); updateTitle(); }
    let socket = null;
    function connect() {
        socket = io({ withCredentials: true });
        socket.on('connect', () => { $('#indRealtime').classList.add('on'); refreshState().then(liveSync); });
        socket.on('disconnect', () => $('#indRealtime').classList.remove('on'));
        socket.on('connect_error', (err) => { $('#indRealtime').classList.remove('on'); if (err && err.message === 'unauthorized') location.href = '/login'; });
        socket.on('revoked', () => { location.href = '/denied?reason=role'; });
        socket.on('station', (s) => { state.station = s; renderHeader(); if (state.editMode && state.callId) socket.emit('edit:start', state.callId); });
        socket.on('calls', (calls) => {
            state.calls = calls;
            // alerte « à valider » retirée dès que l'appel n'attend plus (validé, refusé, annulé, sur un autre poste)
            $$('#toasts .toast.awaiting[data-call]').forEach((t) => { if (!calls.some((c) => c.id === Number(t.dataset.call) && c.status === 'awaiting')) t.remove(); });
            renderAll(); if (state.callId && !state.editMode) refreshCall(); });
        socket.on('units', (units) => { state.units = units; renderAll(); if (state.call && !state.editMode) renderCall(); if ($('#newUnits') && !$('#newModal').classList.contains('hidden')) { draft.units = $$('[data-newunit]:checked').map((x) => Number(x.value)); $('#newUnits').innerHTML = newUnitsHtml(); } });
        socket.on('dispatch', (d) => { state.dispatch = d; renderAll(); });
        socket.on('fivem', (f) => { state.fivem = f; if (f.dispatch) state.dispatch = f.dispatch; renderAll(); renderLive(); });
        socket.on('presence', (p) => { state.presence = p; renderHeader(); });
        socket.on('conversations', (list) => { state.conversations = list; renderChatList(); });
        socket.on('positions', (map) => { state.positions = map || {}; renderUnits(); });
        socket.on('position', (p) => { state.positions[p.unitId] = p.location; updatePosition(p.unitId); });
        socket.on('players', (d) => { state.players = d.players || []; state.liveAvailable = !!d.liveview; renderLive(); renderPips(); liveSync(); });
        socket.on('editing', (map) => { state.editing = map || {}; renderCalls(); updateEditBanners(); });
        socket.on('call:edited', (d) => { if (state.callId === d.id && state.editMode && state.editBase && d.rev !== state.editBase.rev) { state.editConflict = { rev: d.rev }; updateEditBanners(); } });
        socket.on('records', () => { if (WM.isOpen('registries')) { clearTimeout(state.regT); state.regT = setTimeout(loadRegistry, 400); } });
        socket.on('trash', () => { if (WM.isOpen('trash')) loadTrash(); else WM.setBadge('trash', 1); if (WM.isOpen('audit')) loadAudit(); });
        socket.on('message', (m) => {
            if (state.chat === m.channel && !state.chatMessages.some((x) => x.id === m.id)) {
                state.chatMessages.push(m); renderChat();
                if (m.senderType !== 'dispatch' && WM.isOpen('messages')) markRead(m.channel);
            }
            if (state.observeOn && /^u:/.test(m.channel || '')) loadObserve();
            if (state.call && m.channel === `d:c:${state.call.id}` && !state.editMode) refreshCall();
            if (m.senderType !== 'dispatch' && !(state.chat === m.channel && WM.isOpen('messages') && document.hasFocus())) SOUND.message(); // son seul
        });
        socket.on('alert', (a) => {
            if (a.type === 'awaiting') { SOUND.awaiting(); toast('awaiting', `Nouvelle intervention à valider — ${a.number}`, a.title || '', () => openCall(a.id), 0, a.id); }
            else if (a.type === 'new') { SOUND.call(); toast('new', `${a.kind === 'incident' ? 'Nouvel incident' : 'Nouvelle intervention'} — ${a.number}`, a.title || '', () => openCall(a.id)); }
        });
        socket.on('live:frame', onLiveFrame);
        socket.on('live:error', (e) => { if ($('#liveUnavailable')) { $('#liveUnavailable').textContent = e.error; $('#liveUnavailable').classList.remove('hidden'); } });
        socket.on('live:gone', (d) => { delete live.frames[d.serverId]; leaveRoom(d.serverId); renderLive(); renderPips(); });
    }
    let callTimer = null;
    function refreshCall() {
        clearTimeout(callTimer);
        callTimer = setTimeout(async () => { if (!state.callId) return; const res = await api(`/calls/${state.callId}`); if (res && state.callId === res.call.id) { state.call = res.call; renderCall(); } }, 150);
    }
    async function refreshState() {
        const res = await api('/state');
        if (!res) return;
        Object.assign(state, { calls: res.calls, units: res.units, conversations: res.conversations, fivem: res.fivem, dispatch: res.dispatch, presence: res.presence,
            positions: res.positions || {}, players: res.players || [], editing: res.editing || {} });
        const pl = await api('/players');
        if (pl) { state.players = pl.players; state.liveAvailable = !!pl.liveview; }
        renderAll(); renderChatList(); renderLive(); renderPips();
    }

    // ---------------- disposition des fenêtres (par dispatcher, gardée sur le serveur) ----------------
    WM.onSave((layout) => { store.set('mdc.layout', layout); api('/layout', { layout }, { quiet: true }); });

    (async () => {
        renderSound(); renderTheme();
        const me = await api('/me');
        if (!me) return;
        state.me = me.user; state.csrf = me.csrf;
        const saved = await api('/layout', undefined, { quiet: true });
        WM.restore((saved && saved.layout) || store.get('mdc.layout', null));
        await refreshState();
        connect();
    })();
})();
