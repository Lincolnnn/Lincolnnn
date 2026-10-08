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
    const VEHICLE_STATUS = { valid: 'En règle', stolen: 'Volé', wanted: 'Recherché' };
    const KIND_LABELS = { identity: 'Identité', vehicle: 'Véhicule', intervention: 'Intervention' };
    const KIND_SAVED = { identity: 'Identité enregistrée', vehicle: 'Véhicule enregistré', intervention: 'Intervention enregistrée' };

    // Identité : condition et interdictions (clés identiques à server.lua)
    const CONDITION_LABELS = { none: 'N/A', wanted: 'Recherché', missing: 'Personne disparue', deceased: 'Personne décédée' };
    const CONDITION_FLAG = { wanted: 'flag-stolen', missing: 'flag-missing', deceased: 'flag-deceased' };
    const RESTRICTION_LABELS = { weapon: 'Port d\'arme' };

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
        const box = $('#toasts');
        while (box.children.length >= 4) box.firstElementChild.remove(); // 4 notifications max à l'écran
        box.appendChild(el);
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
    const fullName = (i) => [i.firstname, i.middlename, String(i.lastname).toUpperCase()].filter(Boolean).join(' ');
    const conditionFlag = (c) => (c && c !== 'none')
        ? `<span class="flag ${CONDITION_FLAG[c] || ''}">${esc(CONDITION_LABELS[c] || c)}</span>`
        : 'N/A';
    const restrictionFlags = (list) => {
        list = toArray(list);
        return list.length
            ? list.map((k) => `<span class="flag flag-${esc(k)}">${esc(RESTRICTION_LABELS[k] || k)}</span>`).join(' ')
            : 'N/A';
    };

    // Bandeau d'alerte en haut d'une fiche d'identité
    function conditionAlert(r) {
        if (r.condition === 'wanted') {
            return `<div class="sheet-alert">&#9888; PERSONNE RECHERCHÉE${r.wantedSince ? ` depuis le ${esc(r.wantedSince)}` : ''}${r.wantedReason ? ` — ${esc(r.wantedReason)}` : ''}</div>`;
        }
        if (r.condition === 'missing') return '<div class="sheet-alert missing">&#9888; PERSONNE DISPARUE</div>';
        if (r.condition === 'deceased') return '<div class="sheet-alert deceased">PERSONNE DÉCÉDÉE</div>';
        return '';
    }

    function renderRecord(r) {
        const foot = `<div class="sheet-foot">Fiche n°${esc(r.id)} — créée le ${esc(formatDate(r.createdAt))} par ${esc(r.createdByName || '-')}</div>`;

        if (r.kind === 'identity') {
            const vehicles = toArray(r.vehicles);
            return `
                <div class="sheet-title">FICHE D'IDENTITÉ — ${esc(fullName(r))}</div>
                ${conditionAlert(r)}
                <dl class="sheet">
                    ${row('Prénom', r.firstname)}
                    ${row('Middle name', r.middlename)}
                    ${row('Nom de famille', String(r.lastname).toUpperCase())}
                    ${row('Date de naissance', r.dob)}
                    ${row('Adresse', r.address)}
                    ${row('SSN', r.ssn)}
                    ${row('Emploi', r.job)}
                    ${row('Licence de conduite', r.licenseClass || 'N/A')}
                    ${row('N° de licence', r.licenseNumber)}
                    ${row('État d\'émission', r.licenseState)}
                    <dt>Interdictions</dt><dd>${restrictionFlags(r.restrictions)}</dd>
                    <dt>Condition</dt><dd>${conditionFlag(r.condition)}</dd>
                    ${r.condition === 'wanted' ? row('Raison si recherché', r.wantedReason) + row('Recherché depuis le', r.wantedSince) : ''}
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
                    ? `<ul class="sheet-list"><li><b>${esc(fullName(o))}</b> — né(e) le ${esc(o.dob)}${o.ssn ? ` — SSN ${esc(o.ssn)}` : ''}${o.condition && o.condition !== 'none' ? ` ${conditionFlag(o.condition)}` : ''}</li></ul>`
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
            ? 'Nom, prénom, date de naissance (JJ/MM/AAAA), SSN ou n° de licence...'
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
            $('#searchHead').innerHTML = '<tr><th>Nom</th><th>Prénom</th><th>Naissance</th><th>SSN</th><th>Condition</th></tr>';
            $('#searchBody').innerHTML = results.map((r, i) => `
                <tr data-index="${i}" class="${r.condition === 'wanted' ? 'row-wanted' : ''}">
                    <td>${esc(String(r.lastname).toUpperCase())}</td>
                    <td>${esc([r.firstname, r.middlename].filter(Boolean).join(' '))}</td>
                    <td>${esc(r.dob)}</td>
                    <td>${esc(r.ssn || '-')}</td>
                    <td>${conditionFlag(r.condition)}</td>
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
    // GÉNÉRATEUR D'IDENTITÉS ALÉATOIRES (bouton "Remplissage aléatoire")
    // Ajoutez librement des entrées dans les listes ci-dessous.
    // =====================================================================
    const Random = (() => {
        const MALE = ['James', 'Michael', 'Robert', 'John', 'David', 'William', 'Richard', 'Joseph', 'Thomas', 'Christopher',
            'Charles', 'Daniel', 'Matthew', 'Anthony', 'Mark', 'Steven', 'Paul', 'Andrew', 'Joshua', 'Kevin', 'Brian',
            'Ryan', 'Jacob', 'Tyler', 'Brandon', 'Marcus', 'Luis', 'Carlos', 'Jamal', 'Tyrone', 'Hector', 'Dylan',
            'Logan', 'Ethan', 'Mason', 'Caleb', 'Travis', 'Wade', 'Dwayne', 'Frank'];
        const FEMALE = ['Mary', 'Patricia', 'Jennifer', 'Linda', 'Elizabeth', 'Barbara', 'Susan', 'Jessica', 'Sarah', 'Karen',
            'Lisa', 'Nancy', 'Betty', 'Sandra', 'Ashley', 'Emily', 'Michelle', 'Amanda', 'Melissa', 'Stephanie',
            'Rebecca', 'Laura', 'Megan', 'Brittany', 'Hannah', 'Olivia', 'Chloe', 'Madison', 'Kayla', 'Rosa',
            'Maria', 'Gabriela', 'Keisha', 'Tanya', 'Crystal', 'Amber', 'Destiny', 'Holly', 'Erin', 'Grace'];
        const MIDDLE_M = ['Lee', 'Allen', 'James', 'Ray', 'Wayne', 'Edward', 'Lewis', 'Scott', 'Dean', 'Alan', 'Jay', 'Earl', 'Joseph', 'Michael'];
        const MIDDLE_F = ['Marie', 'Ann', 'Lynn', 'Rose', 'Jean', 'Mae', 'Grace', 'Louise', 'Elizabeth', 'Nicole', 'Renee', 'Kay', 'Dawn', 'Faith'];
        const LAST = ['Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis', 'Rodriguez', 'Martinez',
            'Hernandez', 'Lopez', 'Gonzalez', 'Wilson', 'Anderson', 'Thomas', 'Taylor', 'Moore', 'Jackson', 'Martin',
            'Lee', 'Perez', 'Thompson', 'White', 'Harris', 'Sanchez', 'Clark', 'Ramirez', 'Lewis', 'Robinson',
            'Walker', 'Young', 'Allen', 'King', 'Wright', 'Scott', 'Torres', 'Nguyen', 'Hill', 'Flores',
            'Green', 'Adams', 'Nelson', 'Baker', 'Hall', 'Rivera', 'Campbell', 'Mitchell', 'Carter', 'Roberts',
            'Kowalski', 'O\'Brien', 'McAllister', 'Delgado', 'Washington', 'Fitzgerald', 'Novak', 'Reyes', 'Bishop', 'Crowley'];
        const STREETS = [
            ['Grove Street', 'Los Santos'], ['Forum Drive', 'Los Santos'], ['Vespucci Boulevard', 'Los Santos'],
            ['Alta Street', 'Los Santos'], ['Strawberry Avenue', 'Los Santos'], ['Davis Avenue', 'Los Santos'],
            ['Macdonald Street', 'Los Santos'], ['Carson Avenue', 'Los Santos'], ['Jamestown Street', 'Los Santos'],
            ['Innocence Boulevard', 'Los Santos'], ['Elgin Avenue', 'Los Santos'], ['Mirror Park Boulevard', 'Los Santos'],
            ['Nikola Avenue', 'Los Santos'], ['West Eclipse Boulevard', 'Los Santos'], ['Palomino Avenue', 'Los Santos'],
            ['Prosperity Street', 'Los Santos'], ['Magellan Avenue', 'Los Santos'], ['Hawick Avenue', 'Los Santos'],
            ['Power Street', 'Los Santos'], ['San Andreas Avenue', 'Los Santos'], ['Sinner Street', 'Los Santos'],
            ['Popular Street', 'Los Santos'], ['Integrity Way', 'Los Santos'], ['Las Lagunas Boulevard', 'Los Santos'],
            ['Clinton Avenue', 'Los Santos'], ['Vinewood Boulevard', 'Los Santos'], ['Boulevard Del Perro', 'Los Santos'],
            ['Bay City Avenue', 'Los Santos'], ['Little Bighorn Avenue', 'Los Santos'], ['Tongva Drive', 'Los Santos'],
            ['Algonquin Boulevard', 'Sandy Shores'], ['Marina Drive', 'Sandy Shores'], ['Niland Avenue', 'Sandy Shores'],
            ['Zancudo Avenue', 'Sandy Shores'], ['Grapeseed Main Street', 'Grapeseed'], ['Paleto Boulevard', 'Paleto Bay'],
            ['Procopio Drive', 'Paleto Bay'], ['Duluoz Avenue', 'Paleto Bay'],
        ];
        const JOBS = ['Mécanicien', 'Chauffeur de taxi', 'Agent immobilier', 'Infirmier', 'Cuisinier', 'Livreur', 'Barman',
            'Électricien', 'Plombier', 'Vendeur', 'Agriculteur', 'Pêcheur', 'Routier', 'Comptable', 'Avocat', 'Journaliste',
            'Ouvrier du bâtiment', 'Agent de sécurité', 'Étudiant', 'Sans emploi', 'Garagiste', 'Coiffeur', 'Photographe',
            'Pilote', 'Docker', 'Mineur', 'Développeur', 'Enseignant', 'Médecin', 'Pompiste', 'Serveur', 'Caissier'];
        const STATES = ['Alabama', 'Arizona', 'Colorado', 'Florida', 'Georgia', 'Illinois', 'Louisiana', 'Nevada',
            'New Jersey', 'New York', 'North Yankton', 'Ohio', 'Oregon', 'Texas', 'Utah', 'Washington'];
        const WANTED_REASONS = ['Vol à main armée', 'Délit de fuite', 'Agression', 'Trafic de stupéfiants',
            'Non-présentation au tribunal', 'Vol de véhicule', 'Violation de probation', 'Fraude', 'Recel',
            'Évasion', 'Port d\'arme illégal', 'Cambriolage'];
        // [valeur, poids] : plus le poids est grand, plus la valeur sort souvent
        const LICENSES = [['N/A', 10], ['Class C - Standard', 50], ['Class F - Lourd', 4], ['Class E - Combiné', 4],
            ['Class M - Moto', 7], ['CDL A', 4], ['CDL B', 3], ['CDL C', 3], ['Prob - Class CP', 5],
            ['Prob - Class D', 5], ['Prob - Class MP', 5]];
        const CONDITIONS = [['none', 80], ['wanted', 12], ['missing', 5], ['deceased', 3]];

        const int = (min, max) => Math.floor(Math.random() * (max - min + 1)) + min;
        const pick = (list) => list[int(0, list.length - 1)];
        const weighted = (list) => {
            let roll = Math.random() * list.reduce((sum, [, w]) => sum + w, 0);
            for (const [value, w] of list) { if ((roll -= w) < 0) return value; }
            return list[0][0];
        };
        const dateString = (d) => `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()}`;

        // SSN au format XXX-XX-XXXX (zone 001-899 hors 666, comme les vrais SSN)
        function ssn() {
            let area;
            do { area = int(1, 899); } while (area === 666);
            return `${String(area).padStart(3, '0')}-${String(int(1, 99)).padStart(2, '0')}-${String(int(1, 9999)).padStart(4, '0')}`;
        }

        function identity() {
            const male = Math.random() < 0.5;
            const [street, city] = pick(STREETS);
            const now = new Date();
            const birth = new Date(now.getFullYear() - int(18, 75), int(0, 11), int(1, 28));
            const licenseClass = weighted(LICENSES);
            const condition = weighted(CONDITIONS);

            return {
                firstname: pick(male ? MALE : FEMALE),
                middlename: pick(male ? MIDDLE_M : MIDDLE_F),
                lastname: pick(LAST),
                dob: dateString(birth),
                address: `${int(100, 9999)} ${street}, ${city}`,
                ssn: ssn(),
                job: pick(JOBS),
                licenseClass,
                licenseNumber: licenseClass === 'N/A' ? '' : `${String.fromCharCode(65 + int(0, 25))}${int(1000000, 9999999)}`,
                licenseState: licenseClass === 'N/A' ? '' : (Math.random() < 0.85 ? 'San Andreas' : pick(STATES)),
                restrictions: Math.random() < 0.15 ? ['weapon'] : [],
                condition,
                wantedReason: condition === 'wanted' ? pick(WANTED_REASONS) : '',
                wantedSince: condition === 'wanted' ? dateString(new Date(now.getTime() - int(0, 90) * 86400000)) : '',
            };
        }

        return { ssn, identity };
    })();

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
        const formData = new FormData(form);
        const payload = Object.fromEntries(formData.entries());
        payload.kind = form.dataset.kind;
        if (payload.kind === 'identity') {
            // Choix multiples : on envoie la liste (sans "N/A")
            payload.restrictions = formData.getAll('restrictions').filter((v) => v !== 'none');
        }

        submit.disabled = true;
        const res = await post('create', payload);
        submit.disabled = false;

        if (res && res.ok) {
            toast(`${KIND_SAVED[payload.kind]} (n°${res.id}).`, 'success');
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

    // Dates (JJ/MM/AAAA) : insère automatiquement les "/"
    $$('.date-input').forEach((input) => input.addEventListener('input', () => {
        const digits = input.value.replace(/\D/g, '').slice(0, 8);
        input.value = [digits.slice(0, 2), digits.slice(2, 4), digits.slice(4)].filter(Boolean).join('/');
    }));

    // SSN (XXX-XX-XXXX) : insère automatiquement les "-"
    $('.ssn-input').addEventListener('input', (e) => {
        const digits = e.target.value.replace(/\D/g, '').slice(0, 9);
        e.target.value = [digits.slice(0, 3), digits.slice(3, 5), digits.slice(5)].filter(Boolean).join('-');
    });

    // =====================================================================
    // FORMULAIRE IDENTITÉ : interdictions, condition, SSN, remplissage aléatoire
    // =====================================================================
    const identityForm = $('#view-identity');
    const field = (name) => identityForm.elements.namedItem(name);

    // ---- Interdictions (menu déroulant à choix multiples) ----
    const multi = $('#restrictionsSelect');
    const multiPanel = multi.querySelector('.multi-panel');
    const multiInputs = () => [...multi.querySelectorAll('input[type="checkbox"]')];

    function updateRestrictionsLabel() {
        const keys = multiInputs().filter((i) => i.checked && i.value !== 'none').map((i) => i.value);
        multi.querySelector('.multi-value').textContent = keys.length
            ? keys.map((k) => RESTRICTION_LABELS[k] || k).join(', ')
            : 'N/A';
    }

    function setRestrictions(keys) {
        multiInputs().forEach((i) => { i.checked = i.value === 'none' ? keys.length === 0 : keys.includes(i.value); });
        updateRestrictionsLabel();
    }

    multi.querySelector('.multi-btn').addEventListener('click', () => multiPanel.classList.toggle('hidden'));
    document.addEventListener('mousedown', (e) => {
        if (!multi.contains(e.target)) multiPanel.classList.add('hidden');
    });

    // "N/A" est exclusif : le cocher décoche le reste, et inversement
    multi.addEventListener('change', (e) => {
        const input = e.target;
        const none = multi.querySelector('input[value="none"]');
        if (input.value === 'none' && input.checked) {
            multiInputs().forEach((i) => { if (i !== none) i.checked = false; });
        } else if (input.checked) {
            none.checked = false;
        }
        if (!multiInputs().some((i) => i.checked)) none.checked = true;
        updateRestrictionsLabel();
    });

    // ---- Condition : cases supplémentaires si "Recherché" ----
    const todayString = () => {
        const d = new Date();
        return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()}`;
    };

    function updateWantedFields() {
        const wanted = field('condition').value === 'wanted';
        identityForm.querySelectorAll('.wanted-only').forEach((el) => el.classList.toggle('hidden', !wanted));
        if (wanted && !field('wantedSince').value) field('wantedSince').value = todayString();
    }

    field('condition').addEventListener('change', updateWantedFields);

    // ---- SSN prérempli aléatoirement (le serveur en génère un aussi si vide) ----
    $('#regenSSN').addEventListener('click', () => { field('ssn').value = Random.ssn(); });

    // Après "Effacer" / un enregistrement : on remet l'état par défaut
    identityForm.addEventListener('reset', () => setTimeout(() => {
        updateRestrictionsLabel();
        updateWantedFields();
        field('ssn').value = Random.ssn();
    }, 0));

    // ---- Remplissage aléatoire ----
    $('#randomIdentity').addEventListener('click', () => {
        const id = Random.identity();
        Object.entries(id).forEach(([name, value]) => {
            if (name !== 'restrictions') field(name).value = value;
        });
        setRestrictions(id.restrictions);
        updateWantedFields();
        toast('Identité générée aléatoirement : vérifiez puis enregistrez.', 'info');
    });

    field('ssn').value = Random.ssn();

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
