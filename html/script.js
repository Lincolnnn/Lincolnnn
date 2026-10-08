/* =========================================================================
   MDC Standalone - NUI (Vanilla JS)
   - Communication NUI -> Lua : fetch(`https://<ressource>/<callback>`)
   - Communication Lua -> NUI : window 'message' (SendNUIMessage)
   ========================================================================= */
(() => {
    'use strict';

    // Nom de la ressource (permet de renommer le dossier sans casser les callbacks)
    const RESOURCE = typeof GetParentResourceName === 'function'
        ? GetParentResourceName()
        : 'mdc_standalone';

    const STATUS_LABELS = {
        available: 'Disponible',
        unavailable: 'Indisponible',
        traffic_stop: 'Contrôle Routier',
        busy: 'Occupé',
        on_scene: 'Sur Place',
        en_route: 'En route',
    };
    const PRIORITY_LABELS = { low: 'Basse', medium: 'Moyenne', high: 'Haute' };
    const GENDER_LABELS = { M: 'Homme', F: 'Femme', X: 'Autre' };
    const VEHICLE_STATUS = { valid: 'En règle', stolen: 'Volé', wanted: 'Recherché' };
    const KIND_LABELS = { identity: 'Identité', vehicle: 'Véhicule', intervention: 'Intervention' };

    // Taille de fenêtre (px)
    const MIN_W = 760, MIN_H = 480;
    const DEFAULT_W = 1280, DEFAULT_H = 780;

    const state = {
        open: false,
        page: 'units',
        status: 'available',
        serverId: null,
        name: '',
        callsign: '',
        layout: null,          // { x, y, w, h, maximized }
        createView: 'identity',
        searchResults: [],
        registry: [],
        clockTimer: null,
    };

    // ---------------------------------------------------------------------
    // Outils
    // ---------------------------------------------------------------------
    const $ = (sel) => document.querySelector(sel);
    const $$ = (sel) => document.querySelectorAll(sel);
    const win = $('#mdc');

    // Échappe le HTML (toutes les données affichées viennent des joueurs)
    const esc = (value) => String(value ?? '').replace(/[&<>"']/g, (c) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c]));

    // Lua peut sérialiser une table vide en {} au lieu de [] : on normalise.
    const toArray = (value) => Array.isArray(value) ? value : Object.values(value || {});

    const pad = (n) => String(n).padStart(2, '0');
    const formatTime = (unix) => {
        if (!unix) return '-';
        const d = new Date(unix * 1000);
        return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
    };
    const formatDate = (unix) => {
        if (!unix) return '-';
        const d = new Date(unix * 1000);
        return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
    };

    async function post(name, data = {}) {
        try {
            const res = await fetch(`https://${RESOURCE}/${name}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(data),
            });
            return await res.json();
        } catch (err) {
            return { ok: false, error: 'Callback indisponible (hors jeu ?)' };
        }
    }

    function toast(message, type = 'info') {
        const el = document.createElement('div');
        el.className = `toast ${type}`;
        el.textContent = message;
        $('#toasts').appendChild(el);
        setTimeout(() => el.remove(), 3500);
    }

    // =====================================================================
    // FENÊTRE : déplacement, redimensionnement, agrandissement
    // La position est envoyée au Lua (callback "saveLayout") après chaque
    // modification : elle est gardée tant que le joueur reste connecté.
    // =====================================================================
    function defaultLayout() {
        const w = Math.max(MIN_W, Math.min(DEFAULT_W, Math.round(innerWidth * 0.92)));
        const h = Math.max(MIN_H, Math.min(DEFAULT_H, Math.round(innerHeight * 0.88)));
        return {
            x: Math.round((innerWidth - w) / 2),
            y: Math.round((innerHeight - h) / 2),
            w, h, maximized: false,
        };
    }

    // Garde la fenêtre dans l'écran (au moins la barre de titre attrapable)
    function clampLayout(l) {
        const w = Math.max(MIN_W, Math.min(l.w, innerWidth));
        const h = Math.max(MIN_H, Math.min(l.h, innerHeight));
        const x = Math.min(Math.max(l.x, 120 - w), innerWidth - 120);
        const y = Math.min(Math.max(l.y, 0), innerHeight - 40);
        return { x: Math.round(x), y: Math.round(y), w: Math.round(w), h: Math.round(h), maximized: !!l.maximized };
    }

    function applyLayout() {
        const l = state.layout;
        win.classList.toggle('maximized', l.maximized);

        if (l.maximized) {
            Object.assign(win.style, { left: '0px', top: '0px', width: `${innerWidth}px`, height: `${innerHeight}px` });
        } else {
            Object.assign(win.style, { left: `${l.x}px`, top: `${l.y}px`, width: `${l.w}px`, height: `${l.h}px` });
        }

        const btn = $('#btnMax');
        btn.innerHTML = l.maximized ? '&#10697;' : '&#9633;';
        btn.title = l.maximized ? 'Rétrécir' : 'Agrandir';
    }

    const saveLayout = () => post('saveLayout', state.layout);

    function toggleMaximize() {
        state.layout.maximized = !state.layout.maximized;
        applyLayout();
        saveLayout();
    }

    let drag = null;

    $('#titlebar').addEventListener('mousedown', (e) => {
        if (e.button !== 0 || e.target.closest('.win-btn') || state.layout.maximized) return;
        drag = { type: 'move', sx: e.clientX, sy: e.clientY, start: { ...state.layout } };
        document.body.classList.add('dragging');
        e.preventDefault();
    });

    $('#titlebar').addEventListener('dblclick', (e) => {
        if (!e.target.closest('.win-btn')) toggleMaximize();
    });

    $$('.rz').forEach((handle) => handle.addEventListener('mousedown', (e) => {
        if (e.button !== 0 || state.layout.maximized) return;
        drag = { type: 'resize', dir: handle.dataset.dir, sx: e.clientX, sy: e.clientY, start: { ...state.layout } };
        document.body.classList.add('dragging');
        e.preventDefault();
        e.stopPropagation();
    }));

    document.addEventListener('mousemove', (e) => {
        if (!drag) return;
        const s = drag.start;
        const dx = e.clientX - drag.sx;
        const dy = e.clientY - drag.sy;
        let { x, y, w, h } = s;

        if (drag.type === 'move') {
            x = s.x + dx;
            y = s.y + dy;
        } else {
            const d = drag.dir;
            if (d.includes('e')) w = s.w + dx;
            if (d.includes('s')) h = s.h + dy;
            if (d.includes('w')) w = s.w - dx;
            if (d.includes('n')) h = s.h - dy;
            w = Math.max(MIN_W, w);
            h = Math.max(MIN_H, h);
            if (d.includes('w')) x = s.x + (s.w - w);   // le bord droit reste fixe
            if (d.includes('n')) y = s.y + (s.h - h);   // le bord bas reste fixe
        }

        state.layout = clampLayout({ x, y, w, h, maximized: false });
        applyLayout();
    });

    document.addEventListener('mouseup', () => {
        if (!drag) return;
        drag = null;
        document.body.classList.remove('dragging');
        saveLayout();
    });

    $('#btnMax').addEventListener('click', toggleMaximize);
    $('#btnReset').addEventListener('click', () => {
        state.layout = defaultLayout();
        applyLayout();
        saveLayout();
    });

    // Changement de résolution du jeu : on recadre la fenêtre
    window.addEventListener('resize', () => {
        if (!state.layout) return;
        state.layout = clampLayout(state.layout);
        applyLayout();
    });

    // =====================================================================
    // OUVERTURE / FERMETURE
    // =====================================================================
    function openUI(data = {}) {
        state.open = true;
        state.serverId = data.serverId ?? null;
        state.name = data.name || 'Agent';
        state.callsign = data.callsign || '';

        state.layout = data.layout ? clampLayout(data.layout) : defaultLayout();
        applyLayout();

        $('#profileName').textContent = state.name;
        $('#profileId').textContent = `ID serveur : ${data.serverId ?? '-'}`;
        $('#profileAvatar').textContent = state.name.trim().charAt(0).toUpperCase() || '?';
        $('#callsignInput').value = state.callsign;

        setActiveStatus(data.status || 'available');
        updateAgentCell();
        win.classList.remove('hidden');

        updateClock();
        state.clockTimer = setInterval(updateClock, 1000);

        loadPage(state.page);
    }

    function closeUI(notifyLua = true) {
        if (!state.open) return;
        state.open = false;
        drag = null;
        document.body.classList.remove('dragging');
        win.classList.add('hidden');
        clearInterval(state.clockTimer);
        state.clockTimer = null;

        // Relâche le SetNuiFocus côté Lua
        if (notifyLua) post('close');
    }

    function updateClock() {
        const d = new Date();
        $('#sbClock').textContent = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
    }

    function updateAgentCell() {
        $('#sbAgent').textContent = `Agent : ${state.name}${state.callsign ? ` [${state.callsign}]` : ''}`;
    }

    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && state.open) {
            e.preventDefault();
            closeUI();
        }
    });

    $('#btnClose').addEventListener('click', () => closeUI());

    // =====================================================================
    // NAVIGATION
    // =====================================================================
    function showPage(page) {
        state.page = page;
        $$('.tab').forEach((t) => t.classList.toggle('active', t.dataset.page === page));
        $$('.page').forEach((p) => p.classList.toggle('active', p.id === `page-${page}`));
        loadPage(page);
    }

    function loadPage(page) {
        if (page === 'units') refreshUnits();
        else if (page === 'interventions') refreshInterventions();
        else if (page === 'search') $('#searchInput').focus();
        else if (page === 'create' && state.createView === 'registry') refreshRegistry();
    }

    $$('.tab').forEach((tab) => tab.addEventListener('click', () => showPage(tab.dataset.page)));

    // =====================================================================
    // STATUTS + MATRICULE (barre latérale)
    // =====================================================================
    function setActiveStatus(status) {
        state.status = status;
        $$('.status-btn').forEach((b) => b.classList.toggle('active', b.dataset.status === status));
        const cell = $('#sbStatus');
        cell.querySelector('.sq').dataset.status = status;
        cell.lastElementChild.textContent = `Statut : ${STATUS_LABELS[status] || status}`;
    }

    async function changeStatus(status) {
        if (status === state.status) return;
        const previous = state.status;
        setActiveStatus(status);

        const res = await post('setStatus', { status });
        if (res && res.ok) {
            toast(`Statut : ${STATUS_LABELS[status]}`, 'success');
        } else {
            setActiveStatus(previous);
            toast(res?.error || 'Impossible de changer de statut.', 'error');
        }
    }

    $$('.status-btn').forEach((btn) => btn.addEventListener('click', () => changeStatus(btn.dataset.status)));

    async function saveCallsign() {
        const res = await post('setCallsign', { callsign: $('#callsignInput').value });
        if (res && res.ok) {
            state.callsign = res.callsign;
            $('#callsignInput').value = res.callsign;
            updateAgentCell();
            toast('Matricule enregistré.', 'success');
        } else {
            toast(res?.error || 'Erreur lors de l\'enregistrement.', 'error');
        }
    }

    $('#callsignSave').addEventListener('click', saveCallsign);
    $('#callsignInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') saveCallsign(); });

    // =====================================================================
    // UNITÉS
    // =====================================================================
    function renderUnits(units) {
        units = toArray(units);
        $('#unitsEmpty').classList.toggle('hidden', units.length > 0);
        $('#unitsBody').innerHTML = units.map((u) => `
            <tr class="${u.id === state.serverId ? 'me' : ''}">
                <td>${esc(u.id)}</td>
                <td>${esc(u.callsign || '-')}</td>
                <td>${esc(u.name)}</td>
                <td><span class="badge"><span class="sq" data-status="${esc(u.status)}"></span>${esc(STATUS_LABELS[u.status] || u.status)}</span></td>
                <td>${esc(formatTime(u.updatedAt))}</td>
            </tr>`).join('');
    }

    async function refreshUnits() {
        const res = await post('getUnits');
        if (res && res.ok) renderUnits(res.units);
    }

    $('#refreshUnits').addEventListener('click', refreshUnits);

    // =====================================================================
    // FICHES (affichage détaillé, commun à Recherches et Registre)
    // =====================================================================
    const row = (label, value) => `<dt>${esc(label)}</dt><dd>${value === '' || value == null ? '-' : esc(value)}</dd>`;
    const vehicleFlag = (status) => `<span class="flag flag-${esc(status)}">${esc(VEHICLE_STATUS[status] || status)}</span>`;
    const fullName = (i) => `${i.firstname} ${String(i.lastname).toUpperCase()}`;

    function renderRecord(r) {
        const foot = `<div class="sheet-foot">Fiche n°${esc(r.id)} — créée le ${esc(formatDate(r.createdAt))} par ${esc(r.createdByName || '-')}</div>`;

        if (r.kind === 'identity') {
            const vehicles = toArray(r.vehicles);
            return `
                <div class="sheet-title">FICHE D'IDENTITÉ — ${esc(fullName(r))}</div>
                <dl class="sheet">
                    ${row('Nom', String(r.lastname).toUpperCase())}
                    ${row('Prénom', r.firstname)}
                    ${row('Date de naissance', r.dob)}
                    ${row('Sexe', GENDER_LABELS[r.gender] || r.gender)}
                    ${row('Nationalité', r.nationality)}
                    ${row('Taille', r.height ? `${r.height} cm` : '')}
                    ${row('Téléphone', r.phone)}
                    ${row('Adresse', r.address)}
                    ${row('Profession', r.job)}
                    ${row('Remarques', r.notes)}
                </dl>
                <div class="sheet-sub">Véhicules enregistrés (${vehicles.length})</div>
                ${vehicles.length
                    ? `<ul class="sheet-list">${vehicles.map((v) => `<li>${vehicleFlag(v.status)} <b>${esc(v.plate)}</b> — ${esc(v.model)}${v.color ? ` (${esc(v.color)})` : ''}</li>`).join('')}</ul>`
                    : '<div class="card-meta">Aucun véhicule à ce nom.</div>'}
                ${foot}`;
        }

        if (r.kind === 'vehicle') {
            const o = r.ownerIdentity;
            return `
                <div class="sheet-title">FICHE VÉHICULE — ${esc(r.plate)}</div>
                <dl class="sheet">
                    ${row('Plaque', r.plate)}
                    ${row('Modèle', r.model)}
                    ${row('Couleur', r.color)}
                    <dt>Statut</dt><dd>${vehicleFlag(r.status)}</dd>
                    ${row('Propriétaire', r.owner)}
                    ${row('Remarques', r.notes)}
                </dl>
                <div class="sheet-sub">Identité du propriétaire</div>
                ${o
                    ? `<ul class="sheet-list"><li><b>${esc(fullName(o))}</b> — né(e) le ${esc(o.dob)}${o.phone ? ` — Tél. ${esc(o.phone)}` : ''}</li></ul>`
                    : '<div class="card-meta">Aucune identité enregistrée ne correspond au propriétaire.</div>'}
                ${foot}`;
        }

        // intervention
        return `
            <div class="sheet-title">INTERVENTION #${esc(r.id)} — ${esc(r.title)}</div>
            <dl class="sheet">
                ${row('Titre', r.title)}
                ${row('Localisation', r.location)}
                ${row('Priorité', PRIORITY_LABELS[r.priority] || r.priority)}
                <dt>État</dt><dd>${r.closed
                    ? `<span class="flag flag-closed">Clôturée</span> le ${esc(formatDate(r.closedAt))} par ${esc(r.closedByName || '-')}`
                    : '<span class="flag flag-open">En cours</span>'}</dd>
                ${row('Description', r.description)}
            </dl>
            ${foot}`;
    }

    // Sélection d'une ligne dans un tableau -> affichage de la fiche
    function bindSelectable(tbody, getList, detailEl) {
        tbody.addEventListener('click', (e) => {
            const tr = e.target.closest('tr[data-index]');
            if (!tr) return;
            tbody.querySelectorAll('tr.selected').forEach((r) => r.classList.remove('selected'));
            tr.classList.add('selected');
            const record = getList()[Number(tr.dataset.index)];
            if (record) detailEl.innerHTML = renderRecord(record);
        });
    }

    // =====================================================================
    // RECHERCHES (identités et immatriculations enregistrées)
    // =====================================================================
    const searchType = () => $('input[name="searchType"]:checked').value;

    $$('input[name="searchType"]').forEach((radio) => radio.addEventListener('change', () => {
        $('#searchInput').placeholder = searchType() === 'identity'
            ? 'Nom, prénom ou date de naissance (JJ/MM/AAAA)...'
            : 'Plaque d\'immatriculation ou modèle...';
        $('#searchInput').focus();
    }));

    function renderSearchResults(type, results) {
        state.searchResults = results;
        $('#searchCount').textContent = `(${results.length})`;
        $('#searchDetail').innerHTML = '<div class="empty">Sélectionnez un résultat.</div>';
        $('#searchEmpty').classList.toggle('hidden', results.length > 0);
        $('#searchEmpty').textContent = 'Aucun résultat.';

        if (type === 'identity') {
            $('#searchHead').innerHTML = '<tr><th>Nom</th><th>Prénom</th><th>Naissance</th><th>Véhicules</th></tr>';
            $('#searchBody').innerHTML = results.map((r, i) => `
                <tr data-index="${i}">
                    <td>${esc(String(r.lastname).toUpperCase())}</td>
                    <td>${esc(r.firstname)}</td>
                    <td>${esc(r.dob)}</td>
                    <td>${toArray(r.vehicles).length}</td>
                </tr>`).join('');
        } else {
            $('#searchHead').innerHTML = '<tr><th>Plaque</th><th>Modèle</th><th>Propriétaire</th><th>Statut</th></tr>';
            $('#searchBody').innerHTML = results.map((r, i) => `
                <tr data-index="${i}">
                    <td><b>${esc(r.plate)}</b></td>
                    <td>${esc(r.model)}</td>
                    <td>${esc(r.owner || '-')}</td>
                    <td>${vehicleFlag(r.status)}</td>
                </tr>`).join('');
        }

        // Un seul résultat : on ouvre directement la fiche
        if (results.length === 1) $('#searchBody tr').click();
    }

    $('#searchForm').addEventListener('submit', async (e) => {
        e.preventDefault();
        const type = searchType();
        const res = await post('search', { type, query: $('#searchInput').value.trim() });

        if (!res || !res.ok) {
            toast(res?.error || 'Erreur de recherche.', 'error');
            return;
        }
        renderSearchResults(type, toArray(res.results));
    });

    bindSelectable($('#searchBody'), () => state.searchResults, $('#searchDetail'));

    // =====================================================================
    // INTERVENTIONS
    // =====================================================================
    function renderInterventions(list) {
        list = toArray(list);
        const container = $('#interventionsList');

        if (!list.length) {
            container.innerHTML = '<div class="empty">Aucune intervention en cours. Créez-en une depuis l\'onglet « Créations ».</div>';
            return;
        }

        const me = String(state.serverId);

        container.innerHTML = list.map((i) => {
            const units = i.units || {};
            const attached = Object.prototype.hasOwnProperty.call(units, me);
            const unitNames = Object.values(units);
            const prio = PRIORITY_LABELS[i.priority] ? i.priority : 'medium';

            return `
            <div class="card prio-${prio}">
                <div class="card-head">
                    <span>#${esc(i.id)} — ${esc(i.title)}</span>
                    <span>${esc(formatTime(i.createdAt))}</span>
                </div>
                <div class="card-body">
                    <div class="card-meta">Priorité : ${esc(PRIORITY_LABELS[prio])}${i.location ? ` — Lieu : ${esc(i.location)}` : ''}</div>
                    <div class="card-meta">Créée par ${esc(i.createdByName || '-')}</div>
                    ${i.description ? `<div class="card-desc">${esc(i.description)}</div>` : ''}
                    <div class="card-meta">Unités : ${unitNames.length ? unitNames.map(esc).join(', ') : 'aucune'}</div>
                </div>
                <div class="card-actions">
                    ${attached
                        ? `<button class="btn" data-action="detach" data-id="${esc(i.id)}">Se retirer</button>`
                        : `<button class="btn btn-default" data-action="attach" data-id="${esc(i.id)}">Prendre l'appel</button>`}
                    <span class="grow"></span>
                    <button class="btn btn-danger" data-action="close" data-id="${esc(i.id)}">Clôturer</button>
                </div>
            </div>`;
        }).join('');
    }

    async function refreshInterventions() {
        const res = await post('getInterventions');
        if (res && res.ok) renderInterventions(res.interventions);
    }

    $('#interventionsList').addEventListener('click', async (e) => {
        const btn = e.target.closest('button[data-action]');
        if (!btn) return;

        btn.disabled = true;
        const action = btn.dataset.action;
        const res = await post('updateIntervention', { id: Number(btn.dataset.id), action });
        btn.disabled = false;

        if (!res || !res.ok) {
            toast(res?.error || 'Action impossible.', 'error');
            return;
        }

        if (action === 'attach') changeStatus('en_route'); // prendre un appel = "En route"
        if (action === 'close') toast('Intervention clôturée.', 'success');
        refreshInterventions();
    });

    $('#refreshInterventions').addEventListener('click', refreshInterventions);

    // =====================================================================
    // CRÉATIONS (identité / véhicule / intervention) + REGISTRE
    // =====================================================================
    function showCreateView(view) {
        state.createView = view;
        $$('.subtab').forEach((b) => b.classList.toggle('active', b.dataset.view === view));
        $$('.view').forEach((v) => v.classList.toggle('active', v.id === `view-${view}`));
        if (view === 'registry') refreshRegistry();
    }

    $$('.subtab').forEach((btn) => btn.addEventListener('click', () => showCreateView(btn.dataset.view)));

    $$('form.view').forEach((form) => form.addEventListener('submit', async (e) => {
        e.preventDefault();
        const submit = form.querySelector('button[type="submit"]');
        const payload = Object.fromEntries(new FormData(form).entries());
        payload.kind = form.dataset.kind;

        submit.disabled = true;
        const res = await post('create', payload);
        submit.disabled = false;

        if (res && res.ok) {
            toast(`${KIND_LABELS[payload.kind]} enregistrée (n°${res.id}).`, 'success');
            form.reset();
            if (payload.kind === 'intervention') showPage('interventions');
        } else {
            toast(res?.error || 'Erreur lors de l\'enregistrement.', 'error');
        }
    }));

    // Plaque : majuscules, lettres et chiffres uniquement
    $('input[name="plate"]').addEventListener('input', (e) => {
        e.target.value = e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, '');
    });

    // Date de naissance : insère automatiquement les "/"
    $('input[name="dob"]').addEventListener('input', (e) => {
        const digits = e.target.value.replace(/\D/g, '').slice(0, 8);
        e.target.value = [digits.slice(0, 2), digits.slice(2, 4), digits.slice(4)].filter(Boolean).join('/');
    });

    const registryRef = (r) => {
        if (r.kind === 'identity') return `${String(r.lastname).toUpperCase()} ${r.firstname} (${r.dob})`;
        if (r.kind === 'vehicle') return `${r.plate} — ${r.model}`;
        return `${r.title}${r.closed ? ' [clôturée]' : ''}`;
    };

    function renderRegistry() {
        const filter = $('#registryFilter').value;
        const list = state.registry.filter((r) => filter === 'all' || r.kind === filter);
        state.registryView = list;

        $('#registryCount').textContent = `(${list.length})`;
        $('#registryEmpty').classList.toggle('hidden', list.length > 0);
        $('#registryDetail').innerHTML = '<div class="empty">Sélectionnez une entrée.</div>';
        $('#registryBody').innerHTML = list.map((r, i) => `
            <tr data-index="${i}">
                <td>${esc(KIND_LABELS[r.kind] || r.kind)}</td>
                <td>${esc(r.id)}</td>
                <td>${esc(registryRef(r))}</td>
                <td>${esc(formatDate(r.createdAt))}</td>
            </tr>`).join('');
    }

    async function refreshRegistry() {
        const res = await post('getRegistry');
        if (!res || !res.ok) {
            toast(res?.error || 'Impossible de charger le registre.', 'error');
            return;
        }
        state.registry = toArray(res.records);
        renderRegistry();
    }

    $('#registryFilter').addEventListener('change', renderRegistry);
    $('#refreshRegistry').addEventListener('click', refreshRegistry);
    bindSelectable($('#registryBody'), () => state.registryView || [], $('#registryDetail'));

    // =====================================================================
    // MESSAGES Lua -> NUI
    // =====================================================================
    window.addEventListener('message', ({ data }) => {
        if (!data || !data.action) return;

        switch (data.action) {
            case 'open':
                openUI(data.data);
                break;
            case 'close':
                closeUI(false);
                break;
            case 'units':
                renderUnits(data.data);
                break;
            case 'interventions':
                renderInterventions(data.data);
                break;
        }
    });
})();
