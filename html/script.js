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

    // ---------------------------------------------------------------------
    // Libellés (clés identiques à server.lua)
    // ---------------------------------------------------------------------
    const STATUS_LABELS = {
        available: 'Disponible',
        unavailable: 'Indisponible',
        traffic_stop: 'Contrôle Routier',
        busy: 'Occupé',
        on_scene: 'Sur Place',
        en_route: 'En route',
    };
    const PRIORITY_LABELS = { low: 'Basse', medium: 'Moyenne', high: 'Haute' };
    const KIND_LABELS = { identity: 'Identité', vehicle: 'Véhicule', intervention: 'Intervention' };
    const KIND_SAVED = { identity: 'Identité enregistrée', vehicle: 'Véhicule enregistré', intervention: 'Intervention enregistrée' };

    // Identité
    const CONDITION_LABELS = { none: 'N/A', wanted: 'Recherché', missing: 'Personne disparue', deceased: 'Personne décédée' };
    const CONDITION_COLOR = { wanted: 'c-red', missing: 'c-yellow', deceased: 'c-orange' };
    const RESTRICTION_LABELS = { weapon: 'Port d\'arme' };
    const LICENSE_STATUS_LABELS = { valid: 'Valide', suspended: 'Suspension', revoked: 'Révocation', cancelled: 'Annulation', disqualified: 'Disqualification' };
    const LICENSE_STATUS_COLOR = { valid: 'c-green', suspended: 'c-orange', revoked: 'c-red', cancelled: 'c-red', disqualified: 'c-red' };

    // Véhicule
    const REG_STATUS_LABELS = { valid: 'Valide', invalid: 'Invalide', suspended: 'Suspendue' };
    const REG_STATUS_COLOR = { valid: 'c-green', invalid: 'c-red', suspended: 'c-orange' };
    const INSURANCE_LABELS = { valid: 'Valide', invalid: 'Invalide', cancelled: 'Résiliée', none: 'Non-Assuré' };
    const INSURANCE_COLOR = { valid: 'c-green', invalid: 'c-red', cancelled: 'c-orange', none: 'c-red' };
    const HISTORY_LABELS = { administrative: 'Infraction administrative', parking: 'Infraction de stationnement' };

    // Taille de fenêtre (px)
    const MIN_W = 760, MIN_H = 480;
    const DEFAULT_W = 1280, DEFAULT_H = 780;

    const state = {
        open: false,
        page: 'units',
        status: 'available',
        serverId: null,
        rpName: '',
        callsign: '',
        editingRpName: false,
        layout: null,          // { x, y, w, h, maximized }
        createView: 'identity',
        editing: null,         // { kind, id } lorsqu'une fiche du registre est en cours de modification
        searchResults: [],
        registry: [],
        registryView: [],
        clockTimer: null,
    };

    // ---------------------------------------------------------------------
    // Outils
    // ---------------------------------------------------------------------
    const $ = (sel, root = document) => root.querySelector(sel);
    const $$ = (sel, root = document) => root.querySelectorAll(sel);
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
    const dateString = (d) => `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()}`;
    const parseDate = (str) => {
        const m = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(str || '');
        return m ? new Date(Number(m[3]), Number(m[2]) - 1, Number(m[1])) : null;
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
        state.rpName = data.rpName || '';
        state.callsign = data.callsign || '';
        state.editingRpName = false;

        state.layout = data.layout ? clampLayout(data.layout) : defaultLayout();
        applyLayout();

        renderProfile();
        setActiveStatus(data.status || 'available');
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
        else if (page === 'create') loadCreateView(state.createView);
    }

    $$('.tab').forEach((tab) => tab.addEventListener('click', () => showPage(tab.dataset.page)));

    // =====================================================================
    // PROFIL : nom RP (affiché seulement une fois créé) et matricule
    // =====================================================================
    function renderProfile() {
        const showName = state.rpName !== '' && !state.editingRpName;
        $('#rpDisplay').classList.toggle('hidden', !showName);
        $('#rpForm').classList.toggle('hidden', showName);
        $('#rpNameText').textContent = state.rpName;
        $('#rpCallsignText').textContent = state.callsign ? `Matricule ${state.callsign}` : '';
        $('#rpNameInput').value = state.rpName;
        $('#callsignInput').value = state.callsign;
    }

    async function saveProfile(changes) {
        const res = await post('setProfile', changes);
        if (res && res.ok) {
            state.rpName = res.rpName ?? state.rpName;
            state.callsign = res.callsign ?? state.callsign;
            state.editingRpName = false;
            renderProfile();
            toast('Profil enregistré.', 'success');
        } else {
            toast(res?.error || 'Erreur lors de l\'enregistrement.', 'error');
        }
    }

    const saveRpName = () => saveProfile({ rpName: $('#rpNameInput').value });
    const saveCallsign = () => saveProfile({ callsign: $('#callsignInput').value });

    $('#rpSave').addEventListener('click', saveRpName);
    $('#rpNameInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') saveRpName(); });
    $('#callsignSave').addEventListener('click', saveCallsign);
    $('#callsignInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') saveCallsign(); });
    $('#rpEdit').addEventListener('click', () => {
        state.editingRpName = true;
        renderProfile();
        $('#rpNameInput').focus();
    });

    // =====================================================================
    // STATUTS (barre latérale)
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

    // =====================================================================
    // UNITÉS (nom RP uniquement, jamais le pseudo du joueur)
    // =====================================================================
    function renderUnits(units) {
        units = toArray(units);
        $('#unitsEmpty').classList.toggle('hidden', units.length > 0);
        $('#unitsBody').innerHTML = units.map((u) => `
            <tr class="${u.id === state.serverId ? 'me' : ''}">
                <td>${esc(u.callsign || '-')}</td>
                <td>${u.rpName ? esc(u.rpName) : '<span class="muted">Nom RP non renseigné</span>'}</td>
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
    // Les éléments fondamentaux sont affichés en premier, le reste dans des
    // cases que l'on peut ouvrir / refermer.
    // =====================================================================
    const dd = (label, html) => `<dt>${esc(label)}</dt><dd>${html}</dd>`;
    const row = (label, value) => dd(label, value === '' || value == null ? '-' : esc(value));
    const flag = (color, text) => `<span class="flag ${color || ''}">${esc(text)}</span>`;
    const fold = (title, body, count) => `
        <details class="fold">
            <summary>${esc(title)}${count != null ? ` (${count})` : ''}</summary>
            <div class="fold-body">${body}</div>
        </details>`;
    const foldEmpty = (text) => `<div class="fold-empty">${esc(text)}</div>`;

    const fullName = (i) => [i.firstname, i.middlename, String(i.lastname || '').toUpperCase()].filter(Boolean).join(' ');
    const conditionFlag = (c) => (c && c !== 'none') ? flag(CONDITION_COLOR[c], CONDITION_LABELS[c] || c) : 'N/A';
    const restrictionFlags = (list) => {
        list = toArray(list);
        return list.length ? list.map((k) => flag('c-purple', RESTRICTION_LABELS[k] || k)).join(' ') : 'N/A';
    };
    const regFlag = (s) => flag(REG_STATUS_COLOR[s], REG_STATUS_LABELS[s] || s || '-');
    const insuranceFlag = (s) => flag(INSURANCE_COLOR[s], INSURANCE_LABELS[s] || s || '-');

    // Contrôle technique : expiré au-delà d'un an
    function inspectionHtml(date) {
        const d = parseDate(date);
        if (!d) return esc(date || '-');
        const expired = Date.now() - d.getTime() > 365 * 86400000;
        return `${esc(date)} ${expired ? flag('c-red', 'Expiré') : flag('c-green', 'À jour')}`;
    }

    function entriesHtml(entries, titleOf) {
        return entries.map((e) => `
            <div class="entry-view">
                <div class="entry-view-title">${esc(titleOf(e))}</div>
                <div class="entry-view-meta">Le ${esc(e.date)} à ${esc(e.time)} — ${esc(e.address)}</div>
                <div class="entry-view-text">${esc(e.details)}</div>
            </div>`).join('');
    }

    function sheetHead(title, record, editable) {
        return `
            <div class="sheet-title">
                <span>${esc(title)}</span>
                ${editable ? `<button type="button" class="btn btn-small" data-edit-kind="${esc(record.kind)}" data-edit-id="${esc(record.id)}">Modifier</button>` : ''}
            </div>`;
    }

    function sheetFoot(r) {
        const updated = r.updatedAt ? ` — modifiée le ${esc(formatDate(r.updatedAt))} par ${esc(r.updatedByName || '-')}` : '';
        return `<div class="sheet-foot">Fiche n°${esc(r.id)} — créée le ${esc(formatDate(r.createdAt))} par ${esc(r.createdByName || '-')}${updated}</div>`;
    }

    function conditionAlert(r) {
        if (r.condition === 'wanted') {
            return `<div class="sheet-alert">&#9888; PERSONNE RECHERCHÉE${r.wantedSince ? ` depuis le ${esc(r.wantedSince)}` : ''}${r.wantedReason ? ` — ${esc(r.wantedReason)}` : ''}</div>`;
        }
        if (r.condition === 'missing') return '<div class="sheet-alert yellow">&#9888; PERSONNE DISPARUE</div>';
        if (r.condition === 'deceased') return '<div class="sheet-alert orange">PERSONNE DÉCÉDÉE</div>';
        return '';
    }

    function vehicleLine(v) {
        const alerts = [v.stolen && flag('c-red', 'Volé'), v.abandoned && flag('c-orange', 'Abandonné')].filter(Boolean).join(' ');
        return `<li>${regFlag(v.regStatus)} <b>${esc(v.plate)}</b> — ${esc([v.make, v.model].filter(Boolean).join(' '))}${v.color ? ` (${esc(v.color)})` : ''} ${alerts}</li>`;
    }

    function renderIdentity(r, editable) {
        const vehicles = toArray(r.vehicles);
        const records = toArray(r.records);
        const hasLicense = r.licenseClass && r.licenseClass !== 'N/A';

        return `
            ${sheetHead(`FICHE D'IDENTITÉ — ${fullName(r)}`, r, editable)}
            ${conditionAlert(r)}
            <dl class="sheet">
                ${row('Prénom', r.firstname)}
                ${row('Middle name', r.middlename)}
                ${row('Nom de famille', String(r.lastname || '').toUpperCase())}
                ${row('Date de naissance', r.dob)}
                ${row('SSN', r.ssn)}
                ${row('Adresse', r.address)}
                ${row('Emploi', r.job)}
                ${dd('Condition', conditionFlag(r.condition))}
            </dl>
            ${fold('Licence de conduite', hasLicense ? `
                <dl class="sheet">
                    ${row('Type de licence', r.licenseClass)}
                    ${dd('Condition de la licence', flag(LICENSE_STATUS_COLOR[r.licenseStatus], LICENSE_STATUS_LABELS[r.licenseStatus] || 'Valide'))}
                    ${row('N° de licence', r.licenseNumber)}
                    ${row('État d\'émission', r.licenseState)}
                </dl>` : foldEmpty('Aucune licence de conduite (N/A).'))}
            ${fold('Véhicule(s)', vehicles.length
                ? `<ul class="sheet-list">${vehicles.map(vehicleLine).join('')}</ul>`
                : foldEmpty('Aucun véhicule enregistré au nom de cette personne.'), vehicles.length)}
            ${fold('Conditions', `
                <dl class="sheet">
                    ${dd('Interdictions', restrictionFlags(r.restrictions))}
                    ${dd('Condition', conditionFlag(r.condition))}
                    ${r.condition === 'wanted' ? row('Raison de la recherche', r.wantedReason) + row('Date de début', r.wantedSince) : ''}
                </dl>`)}
            ${fold('Antécédents', records.length
                ? entriesHtml(records, (e) => e.offense)
                : foldEmpty('Aucun antécédent connu.'), records.length)}
            ${sheetFoot(r)}`;
    }

    function renderVehicle(r, editable) {
        const owner = r.ownerIdentity;
        const history = toArray(r.history);
        const alerts = [
            r.stolen ? '<div class="sheet-alert">&#9888; VÉHICULE VOLÉ</div>' : '',
            r.abandoned ? '<div class="sheet-alert orange">&#9888; VÉHICULE ABANDONNÉ</div>' : '',
        ].join('');

        return `
            ${sheetHead(`FICHE VÉHICULE — ${r.plate}`, r, editable)}
            ${alerts}
            <dl class="sheet">
                ${row('Immatriculation', r.plate)}
                ${dd('Statut de l\'immatriculation', regFlag(r.regStatus))}
                ${row('Marque', r.make)}
                ${row('Modèle', r.model)}
                ${row('Année', r.year)}
                ${row('Couleur', r.color)}
                ${row('Propriétaire', owner ? fullName(owner) : (r.ownerName || 'Non renseigné'))}
                ${row('Numéro VIN', r.vin)}
                ${dd('Dernier contrôle technique', inspectionHtml(r.inspectionDate))}
                ${dd('Usage', r.commercial ? flag('c-blue', 'Véhicule commercial') : 'Particulier')}
            </dl>
            ${fold('Assurance', `
                <dl class="sheet">
                    ${dd('Statut de l\'assurance', insuranceFlag(r.insuranceStatus))}
                    ${r.insuranceStatus && r.insuranceStatus !== 'none'
                        ? row('N° Police d\'Assurance', r.insurancePolicy) + row('Compagnie d\'assurance', r.insuranceCompany)
                        : ''}
                </dl>`)}
            ${fold('Propriétaire', owner ? `
                <dl class="sheet">
                    ${row('Nom complet', fullName(owner))}
                    ${row('Date de naissance', owner.dob)}
                    ${row('SSN', owner.ssn)}
                    ${row('Adresse', owner.address)}
                    ${dd('Condition', conditionFlag(owner.condition))}
                </dl>` : foldEmpty('Aucune identité enregistrée comme propriétaire.'))}
            ${fold('Historique', history.length
                ? entriesHtml(history, (e) => HISTORY_LABELS[e.type] || e.type)
                : foldEmpty('Aucune infraction connue pour ce véhicule.'), history.length)}
            ${sheetFoot(r)}`;
    }

    const renderRecord = (r, editable = false) => r.kind === 'vehicle' ? renderVehicle(r, editable) : renderIdentity(r, editable);

    // Sélection d'une ligne dans un tableau -> affichage de la fiche
    function bindSelectable(tbody, getList, detailEl, editable) {
        tbody.addEventListener('click', (e) => {
            const tr = e.target.closest('tr[data-index]');
            if (!tr) return;
            tbody.querySelectorAll('tr.selected').forEach((r) => r.classList.remove('selected'));
            tr.classList.add('selected');
            const record = getList()[Number(tr.dataset.index)];
            if (record) detailEl.innerHTML = renderRecord(record, editable);
        });
    }

    // =====================================================================
    // RECHERCHES
    // =====================================================================
    const searchType = () => $('input[name="searchType"]:checked').value;

    $$('input[name="searchType"]').forEach((radio) => radio.addEventListener('change', () => {
        const identity = searchType() === 'identity';
        $('#searchIdentityForm').classList.toggle('hidden', !identity);
        $('#searchVehicleForm').classList.toggle('hidden', identity);
        $(identity ? '#searchIdentityForm input' : '#searchVehicleForm input').focus();
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
            $('#searchHead').innerHTML = '<tr><th>Immatriculation</th><th>Véhicule</th><th>Propriétaire</th><th>Statut</th></tr>';
            $('#searchBody').innerHTML = results.map((r, i) => `
                <tr data-index="${i}" class="${r.stolen ? 'row-wanted' : ''}">
                    <td><b>${esc(r.plate)}</b></td>
                    <td>${esc([r.make, r.model].filter(Boolean).join(' '))}</td>
                    <td>${esc(r.ownerIdentity ? fullName(r.ownerIdentity) : (r.ownerName || '-'))}</td>
                    <td>${regFlag(r.regStatus)}${r.stolen ? ` ${flag('c-red', 'Volé')}` : ''}</td>
                </tr>`).join('');
        }

        // Un seul résultat : on ouvre directement la fiche
        if (results.length === 1) $('#searchBody tr').click();
    }

    async function runSearch(type, payload) {
        const res = await post('search', { type, ...payload });
        if (!res || !res.ok) {
            toast(res?.error || 'Erreur de recherche.', 'error');
            return;
        }
        renderSearchResults(type, toArray(res.results));
    }

    $('#searchIdentityForm').addEventListener('submit', (e) => {
        e.preventDefault();
        const payload = Object.fromEntries(new FormData(e.currentTarget).entries());
        if (!payload.lastname.trim() || !parseDate(payload.dob)) {
            toast('Le nom de famille et la date de naissance (JJ/MM/AAAA) sont obligatoires.', 'error');
            return;
        }
        runSearch('identity', payload);
    });

    $('#searchVehicleForm').addEventListener('submit', (e) => {
        e.preventDefault();
        runSearch('vehicle', { query: e.currentTarget.elements.query.value.trim() });
    });

    bindSelectable($('#searchBody'), () => state.searchResults, $('#searchDetail'), false);

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
    // GÉNÉRATEURS ALÉATOIRES
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
        const INSURERS = ['State Farm', 'GEICO', 'Progressive', 'Allstate', 'USAA', 'Auto-Owners Assurance', 'Liberty Mutual', 'Farmers'];
        // [valeur, poids] : plus le poids est grand, plus la valeur sort souvent
        const REG_STATUSES = [['valid', 80], ['invalid', 10], ['suspended', 10]];
        const INSURANCE_STATUSES = [['valid', 70], ['invalid', 10], ['cancelled', 8], ['none', 12]];
        const VIN_CHARS = 'ABCDEFGHJKLMNPRSTUVWXYZ0123456789';

        const int = (min, max) => Math.floor(Math.random() * (max - min + 1)) + min;
        const pick = (list) => list[int(0, list.length - 1)];
        const letter = () => String.fromCharCode(65 + int(0, 25));
        const weighted = (list) => {
            let roll = Math.random() * list.reduce((sum, [, w]) => sum + w, 0);
            for (const [value, w] of list) { if ((roll -= w) < 0) return value; }
            return list[0][0];
        };

        // Formats identiques à ceux générés par server.lua
        function ssn() {
            let area;
            do { area = int(1, 899); } while (area === 666);
            return `${String(area).padStart(3, '0')}-${String(int(1, 99)).padStart(2, '0')}-${String(int(1, 9999)).padStart(4, '0')}`;
        }
        const licenseNumber = () => `${letter()}${String(int(0, 9999999)).padStart(7, '0')}`;
        const vin = () => Array.from({ length: 17 }, () => VIN_CHARS[int(0, VIN_CHARS.length - 1)]).join('');
        const policyNumber = () => `${letter()}${letter()}${String(int(0, 99999999)).padStart(8, '0')}`;

        // Identité : prénom, middle name, nom, DoB, adresse, SSN et emploi uniquement
        function identity() {
            const male = Math.random() < 0.5;
            const [street, city] = pick(STREETS);
            const birth = new Date(new Date().getFullYear() - int(18, 75), int(0, 11), int(1, 28));
            return {
                firstname: pick(male ? MALE : FEMALE),
                middlename: pick(male ? MIDDLE_M : MIDDLE_F),
                lastname: pick(LAST),
                dob: dateString(birth),
                address: `${int(100, 9999)} ${street}, ${city}`,
                ssn: ssn(),
                job: pick(JOBS),
            };
        }

        // Véhicule : statut d'immatriculation, contrôle technique et assurance uniquement
        function vehicle() {
            const insuranceStatus = weighted(INSURANCE_STATUSES);
            const insured = insuranceStatus !== 'none';
            return {
                regStatus: weighted(REG_STATUSES),
                // Jusqu'à ~2 ans en arrière : au-delà d'un an, le contrôle est expiré
                inspectionDate: dateString(new Date(Date.now() - int(0, 730) * 86400000)),
                insuranceStatus,
                insurancePolicy: insured ? policyNumber() : '',
                insuranceCompany: insured ? pick(INSURERS) : '',
            };
        }

        return { ssn, licenseNumber, vin, policyNumber, identity, vehicle };
    })();

    // =====================================================================
    // SAISIE : formats automatiques (dates, heures, SSN, majuscules, chiffres)
    // (délégation : fonctionne aussi pour les antécédents ajoutés dynamiquement)
    // =====================================================================
    document.addEventListener('input', (e) => {
        const input = e.target;
        if (!(input instanceof HTMLInputElement)) return;

        if (input.classList.contains('date-input')) {
            const digits = input.value.replace(/\D/g, '').slice(0, 8);
            input.value = [digits.slice(0, 2), digits.slice(2, 4), digits.slice(4)].filter(Boolean).join('/');
        } else if (input.classList.contains('time-input')) {
            const digits = input.value.replace(/\D/g, '').slice(0, 4);
            input.value = [digits.slice(0, 2), digits.slice(2)].filter(Boolean).join(':');
        } else if (input.classList.contains('ssn-input')) {
            const digits = input.value.replace(/\D/g, '').slice(0, 9);
            input.value = [digits.slice(0, 3), digits.slice(3, 5), digits.slice(5)].filter(Boolean).join('-');
        } else if (input.classList.contains('digits')) {
            input.value = input.value.replace(/\D/g, '');
        } else if (input.name === 'plate' || input.name === 'vin') {
            input.value = input.value.toUpperCase().replace(/[^A-Z0-9]/g, '');
        }
    });

    // =====================================================================
    // LISTES D'ENTRÉES (Antécédents d'une identité / Historique d'un véhicule)
    // =====================================================================
    const ENTRY_TEMPLATES = { identityRecords: '#tplIdentityRecord', vehicleHistory: '#tplVehicleHistory' };

    function refreshEntries(container) {
        const boxes = container.querySelectorAll('.entry-box');
        container.closest('.subgroup').querySelector('.entries-empty').classList.toggle('hidden', boxes.length > 0);
    }

    // Titre de l'entrée = infraction saisie (ou type choisi)
    function updateEntryTitle(box) {
        const source = box.querySelector('[data-title]');
        const title = box.querySelector('.entry-title');
        const text = source.tagName === 'SELECT'
            ? (source.value ? source.selectedOptions[0].textContent : '')
            : source.value.trim();
        title.textContent = text || title.dataset.default;
    }

    function addEntry(containerId, values = {}) {
        const container = $(`#${containerId}`);
        const box = $(ENTRY_TEMPLATES[containerId]).content.firstElementChild.cloneNode(true);
        box.querySelectorAll('[data-f]').forEach((el) => { el.value = values[el.dataset.f] ?? ''; });
        container.appendChild(box);
        updateEntryTitle(box);
        refreshEntries(container);
        return box;
    }

    const collectEntries = (container) => [...container.querySelectorAll('.entry-box')].map((box) =>
        Object.fromEntries([...box.querySelectorAll('[data-f]')].map((el) => [el.dataset.f, el.value.trim()])));

    function clearEntries(container) {
        container.innerHTML = '';
        refreshEntries(container);
    }

    $$('.add-entry').forEach((btn) => btn.addEventListener('click', () => {
        const box = addEntry(btn.dataset.target);
        box.querySelector('[data-f]').focus();
    }));

    $$('.entries').forEach((container) => {
        container.addEventListener('click', (e) => {
            if (!e.target.closest('.entry-remove')) return;
            e.target.closest('.entry-box').remove();
            refreshEntries(container);
        });
        const onChange = (e) => {
            const box = e.target.closest('.entry-box');
            if (box && e.target.hasAttribute('data-title')) updateEntryTitle(box);
        };
        container.addEventListener('input', onChange);
        container.addEventListener('change', onChange);
    });

    // =====================================================================
    // FORMULAIRE IDENTITÉ
    // =====================================================================
    const identityForm = $('#view-identity');
    const idField = (name) => identityForm.elements.namedItem(name);

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
    function updateWantedFields() {
        const wanted = idField('condition').value === 'wanted';
        identityForm.querySelectorAll('.wanted-only').forEach((el) => el.classList.toggle('hidden', !wanted));
        if (wanted && !idField('wantedSince').value) idField('wantedSince').value = dateString(new Date());
    }

    idField('condition').addEventListener('change', updateWantedFields);

    // ---- Licence : numéro (généré), État et condition seulement si une licence est choisie ----
    function updateLicenseFields() {
        const licenseClass = idField('licenseClass').value;
        const hasLicense = licenseClass !== 'N/A';
        identityForm.querySelectorAll('.license-only').forEach((el) => el.classList.toggle('hidden', !hasLicense));

        // "Disqualification" uniquement pour les licences CDL
        const cdl = licenseClass.startsWith('CDL');
        const status = idField('licenseStatus');
        status.querySelector('option[value="disqualified"]').disabled = !cdl;
        if (!cdl && status.value === 'disqualified') status.value = 'valid';

        if (hasLicense && !idField('licenseNumber').value) idField('licenseNumber').value = Random.licenseNumber();
    }

    idField('licenseClass').addEventListener('change', updateLicenseFields);

    function resetIdentityForm() {
        identityForm.reset();
        clearEntries($('#identityRecords'));
        setRestrictions([]);
        updateWantedFields();
        updateLicenseFields();
        idField('ssn').value = Random.ssn();
    }

    function fillIdentityForm(r) {
        resetIdentityForm();
        ['firstname', 'middlename', 'lastname', 'dob', 'address', 'ssn', 'job', 'licenseClass',
            'licenseStatus', 'licenseNumber', 'licenseState', 'condition', 'wantedReason', 'wantedSince']
            .forEach((name) => { idField(name).value = r[name] ?? ''; });
        if (!idField('licenseClass').value) idField('licenseClass').value = 'N/A';
        if (!idField('licenseStatus').value) idField('licenseStatus').value = 'valid';
        if (!idField('condition').value) idField('condition').value = 'none';
        setRestrictions(toArray(r.restrictions));
        updateLicenseFields();
        updateWantedFields();
        toArray(r.records).forEach((entry) => addEntry('identityRecords', entry));
    }

    function collectIdentity() {
        const formData = new FormData(identityForm);
        const payload = Object.fromEntries(formData.entries());
        payload.restrictions = formData.getAll('restrictions').filter((v) => v !== 'none');
        payload.records = collectEntries($('#identityRecords'));
        return payload;
    }

    // Remplissage aléatoire : prénom, middle name, nom, DoB, adresse, SSN et emploi
    $('#randomIdentity').addEventListener('click', () => {
        Object.entries(Random.identity()).forEach(([name, value]) => { idField(name).value = value; });
    });

    // =====================================================================
    // FORMULAIRE VÉHICULE
    // =====================================================================
    const vehicleForm = $('#view-vehicle');
    const vField = (name) => vehicleForm.elements.namedItem(name);

    // ---- Assurance : police + compagnie pour tous les statuts sauf "Non-Assuré" ----
    function updateInsuranceFields() {
        const status = vField('insuranceStatus').value;
        const insured = status !== '' && status !== 'none';
        vehicleForm.querySelectorAll('.insured-only').forEach((el) => el.classList.toggle('hidden', !insured));
        if (insured && !vField('insurancePolicy').value) vField('insurancePolicy').value = Random.policyNumber();
    }

    vField('insuranceStatus').addEventListener('change', updateInsuranceFields);

    // ---- Propriétaire : liste des identités créées par le joueur ----
    async function loadOwners(selectedId) {
        const select = $('#ownerSelect');
        const current = selectedId ?? select.value;
        const res = await post('getMyIdentities');
        const list = res && res.ok ? toArray(res.identities) : [];

        select.innerHTML = `<option value="">${list.length ? '— Aucun —' : '— Aucun (créez d\'abord une identité) —'}</option>`
            + list.map((i) => `<option value="${esc(i.id)}">${esc(i.label)}</option>`).join('');
        select.value = list.some((i) => String(i.id) === String(current)) ? String(current) : '';
    }

    function resetVehicleForm() {
        vehicleForm.reset();
        clearEntries($('#vehicleHistory'));
        updateInsuranceFields();
        vField('vin').value = Random.vin();
    }

    async function fillVehicleForm(r) {
        resetVehicleForm();
        ['plate', 'regStatus', 'make', 'model', 'year', 'color', 'vin', 'inspectionDate',
            'insuranceStatus', 'insurancePolicy', 'insuranceCompany']
            .forEach((name) => { vField(name).value = r[name] ?? ''; });
        ['stolen', 'abandoned', 'commercial'].forEach((name) => { vField(name).checked = !!r[name]; });
        updateInsuranceFields();
        toArray(r.history).forEach((entry) => addEntry('vehicleHistory', entry));
        await loadOwners(r.ownerId ?? '');
    }

    function collectVehicle() {
        const formData = new FormData(vehicleForm);
        const payload = Object.fromEntries(formData.entries());
        ['stolen', 'abandoned', 'commercial'].forEach((name) => { payload[name] = formData.has(name); });
        payload.history = collectEntries($('#vehicleHistory'));
        return payload;
    }

    // Véhicule actuel : modèle, marque, couleur et immatriculation du véhicule du joueur
    $('#currentVehicle').addEventListener('click', async () => {
        const res = await post('getCurrentVehicle');
        if (!res || !res.ok) {
            toast(res?.error || 'Impossible de lire le véhicule.', 'error');
            return;
        }
        ['plate', 'model', 'make', 'color'].forEach((name) => { if (res[name]) vField(name).value = res[name]; });
        vField('plate').value = vField('plate').value.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 8);
        toast('Informations du véhicule récupérées.', 'success');
    });

    // Remplissage aléatoire : statut d'immatriculation, contrôle technique et assurance
    $('#randomVehicle').addEventListener('click', () => {
        Object.entries(Random.vehicle()).forEach(([name, value]) => { vField(name).value = value; });
        updateInsuranceFields();
    });

    // =====================================================================
    // BOUTONS "GÉNÉRER" (SSN, licence, VIN, police d'assurance)
    // =====================================================================
    const GENERATORS = { ssn: Random.ssn, licenseNumber: Random.licenseNumber, vin: Random.vin, insurancePolicy: Random.policyNumber };

    $$('.regen').forEach((btn) => btn.addEventListener('click', () => {
        btn.closest('form').elements.namedItem(btn.dataset.regen).value = GENERATORS[btn.dataset.regen]();
    }));

    // =====================================================================
    // CRÉATIONS : navigation, enregistrement, modification
    // =====================================================================
    const FORMS = { identity: identityForm, vehicle: vehicleForm };

    function showCreateView(view) {
        state.createView = view;
        $$('.subtab').forEach((b) => b.classList.toggle('active', b.dataset.view === view));
        $$('.view').forEach((v) => v.classList.toggle('active', v.id === `view-${view}`));
        loadCreateView(view);
    }

    function loadCreateView(view) {
        if (view === 'registry') refreshRegistry();
        else if (view === 'vehicle' && !(state.editing && state.editing.kind === 'vehicle')) loadOwners();
    }

    $$('.subtab').forEach((btn) => btn.addEventListener('click', () => showCreateView(btn.dataset.view)));

    // Affiche le mode "modification" (bandeau, titre, bouton) sur le bon formulaire
    function updateEditUI() {
        Object.entries(FORMS).forEach(([kind, form]) => {
            const editing = state.editing && state.editing.kind === kind;
            const legend = form.querySelector('.legend');
            legend.textContent = editing ? `Modification — ${KIND_LABELS[kind]} n°${state.editing.id}` : legend.dataset.legend;
            form.querySelector('.edit-banner').classList.toggle('hidden', !editing);
            form.querySelector('.edit-text').textContent = editing
                ? 'Vous modifiez une fiche de votre registre. Les changements seront enregistrés définitivement.'
                : '';
            form.querySelector('.btn-clear').classList.toggle('hidden', !!editing);
            const submit = form.querySelector('button[type="submit"]');
            submit.textContent = editing ? 'Enregistrer les modifications' : submit.dataset.label;
        });
    }

    async function startEdit(record) {
        state.editing = { kind: record.kind, id: record.id };
        if (record.kind === 'identity') fillIdentityForm(record);
        else await fillVehicleForm(record);
        updateEditUI();
        showCreateView(record.kind);
    }

    function stopEdit() {
        const kind = state.editing && state.editing.kind;
        state.editing = null;
        if (kind === 'identity') resetIdentityForm();
        if (kind === 'vehicle') resetVehicleForm();
        updateEditUI();
    }

    $$('.cancel-edit').forEach((btn) => btn.addEventListener('click', () => {
        stopEdit();
        showCreateView('registry');
    }));

    // "Effacer" : on remet aussi les valeurs générées et les listes à zéro
    identityForm.querySelector('.btn-clear').addEventListener('click', resetIdentityForm);
    vehicleForm.querySelector('.btn-clear').addEventListener('click', resetVehicleForm);

    async function submitForm(form, payload) {
        const editing = state.editing && state.editing.kind === payload.kind ? state.editing : null;
        const submit = form.querySelector('button[type="submit"]');

        submit.disabled = true;
        const res = await post(editing ? 'update' : 'create', editing ? { ...payload, id: editing.id } : payload);
        submit.disabled = false;

        if (!res || !res.ok) {
            toast(res?.error || 'Erreur lors de l\'enregistrement.', 'error');
            return;
        }

        if (editing) {
            toast(`Modifications enregistrées (n°${res.id}).`, 'success');
            stopEdit();
            showCreateView('registry');
        } else {
            toast(`${KIND_SAVED[payload.kind]} (n°${res.id}).`, 'success');
            if (payload.kind === 'identity') resetIdentityForm();
            if (payload.kind === 'vehicle') resetVehicleForm();
        }
    }

    identityForm.addEventListener('submit', (e) => {
        e.preventDefault();
        submitForm(identityForm, { ...collectIdentity(), kind: 'identity' });
    });

    vehicleForm.addEventListener('submit', (e) => {
        e.preventDefault();
        submitForm(vehicleForm, { ...collectVehicle(), kind: 'vehicle' });
    });

    // Intervention (non conservée au redémarrage, absente du registre)
    $('#view-intervention').addEventListener('submit', async (e) => {
        e.preventDefault();
        const form = e.currentTarget;
        const payload = { ...Object.fromEntries(new FormData(form).entries()), kind: 'intervention' };
        const res = await post('create', payload);
        if (res && res.ok) {
            toast(`${KIND_SAVED.intervention} (n°${res.id}).`, 'success');
            form.reset();
            showPage('interventions');
        } else {
            toast(res?.error || 'Erreur lors de l\'enregistrement.', 'error');
        }
    });

    // =====================================================================
    // REGISTRE : mes identités et véhicules (permanents, modifiables)
    // =====================================================================
    const registryRef = (r) => r.kind === 'identity'
        ? `${String(r.lastname).toUpperCase()} ${[r.firstname, r.middlename].filter(Boolean).join(' ')} (${r.dob})`
        : `${r.plate} — ${[r.make, r.model].filter(Boolean).join(' ')}`;

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
    bindSelectable($('#registryBody'), () => state.registryView, $('#registryDetail'), true);

    // Bouton "Modifier" d'une fiche du registre
    $('#registryDetail').addEventListener('click', (e) => {
        const btn = e.target.closest('[data-edit-id]');
        if (!btn) return;
        const record = state.registry.find((r) => r.kind === btn.dataset.editKind && String(r.id) === btn.dataset.editId);
        if (record) startEdit(record);
    });

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

    // État initial des formulaires
    resetIdentityForm();
    resetVehicleForm();
    updateEditUI();
})();
