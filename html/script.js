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
    // Statuts d'une unité, dans l'ordre d'affichage
    const STATUS_LABELS = {
        available: 'Disponible',
        en_route: 'En route',
        on_scene: 'Sur place',
        unavailable: 'Indisponible',
    };
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
        serverId: null,
        rpName: '',
        editingRpName: false,
        units: [],             // unités (temps réel)
        unitEdit: null,        // id de l'unité en cours de modification
        interventions: [],     // interventions + incidents (temps réel)
        callPanel: { mode: 'view', id: null }, // panneau de droite : view | edit | new
        noteDraft: '',         // note en cours de rédaction
        noteEdit: null,        // { id, text } note en cours de modification
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
        state.editingRpName = false;

        state.layout = data.layout ? clampLayout(data.layout) : defaultLayout();
        applyLayout();

        renderProfile();
        renderSidebarUnit();
        win.classList.remove('hidden');

        updateClock();
        state.clockTimer = setInterval(updateClock, 1000);

        refreshUnits(); // statut de l'unité du joueur (barre latérale)
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
    // PROFIL : nom RP (affiché en haut à gauche seulement une fois créé)
    // =====================================================================
    function renderProfile() {
        const showName = state.rpName !== '' && !state.editingRpName;
        $('#rpDisplay').classList.toggle('hidden', !showName);
        $('#rpForm').classList.toggle('hidden', showName);
        $('#rpNameText').textContent = state.rpName;
        $('#rpNameInput').value = state.rpName;
    }

    async function saveRpName() {
        const res = await post('setProfile', { rpName: $('#rpNameInput').value });
        if (res && res.ok) {
            state.rpName = res.rpName;
            state.editingRpName = false;
            renderProfile();
            toast('Nom RP enregistré.', 'success');
        } else {
            toast(res?.error || 'Erreur lors de l\'enregistrement.', 'error');
        }
    }

    $('#rpSave').addEventListener('click', saveRpName);
    $('#rpNameInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') saveRpName(); });
    $('#rpEdit').addEventListener('click', () => {
        state.editingRpName = true;
        renderProfile();
        $('#rpNameInput').focus();
    });

    // =====================================================================
    // UNITÉS : indépendantes des joueurs, qui peuvent les rejoindre / quitter
    // =====================================================================
    const TAG_COLORS = ['green', 'purple', 'blue', 'orange', 'red', 'yellow', 'pink', 'gray'];
    const unitTag = (u) => `<span class="unit-tag tag-${TAG_COLORS.includes(u.color) ? u.color : 'gray'}">${esc(u.tag)}</span>`;

    // Unité dont le joueur fait partie (ou null)
    const myUnit = () => state.units.find((u) => toArray(u.members).some((m) => m.id === state.serverId)) || null;

    // ---- Barre latérale : le statut affiché est celui de l'unité du joueur ----
    function renderSidebarUnit() {
        const unit = myUnit();
        $('#myUnit').innerHTML = unit
            ? `${unitTag(unit)} <span>${esc(unit.name)}</span>`
            : '<span class="muted">Aucune unité — rejoignez-en une dans l\'onglet Unités.</span>';
        $('#statusList').classList.toggle('no-unit', !unit);
        $$('.status-btn').forEach((b) => b.classList.toggle('active', !!unit && b.dataset.status === unit.status));

        const cell = $('#sbStatus');
        cell.querySelector('.sq').dataset.status = unit ? unit.status : '';
        cell.lastElementChild.textContent = unit ? `${unit.tag} — ${STATUS_LABELS[unit.status] || unit.status}` : 'Hors unité';
    }

    async function changeStatus(status) {
        const unit = myUnit();
        if (!unit) {
            toast('Rejoignez une unité (onglet Unités) pour définir son statut.', 'error');
            return;
        }
        if (unit.status === status) return;

        const res = await post('setStatus', { status });
        if (res && res.ok) {
            unit.status = status;
            renderUnits();
            toast(`${unit.tag} : ${STATUS_LABELS[status]}`, 'success');
        } else {
            toast(res?.error || 'Impossible de changer de statut.', 'error');
        }
    }

    $$('.status-btn').forEach((btn) => btn.addEventListener('click', () => changeStatus(btn.dataset.status)));

    // ---- Liste des unités ----
    function renderUnits() {
        const units = state.units;
        const mine = myUnit();
        $('#unitsCount').textContent = `(${units.length})`;
        $('#unitsEmpty').classList.toggle('hidden', units.length > 0);
        $('#unitsBody').innerHTML = units.map((u) => {
            const members = toArray(u.members);
            const isMine = !!mine && mine.id === u.id;
            return `
            <tr class="${isMine ? 'me' : ''}">
                <td>${unitTag(u)}</td>
                <td>${esc(u.name)}</td>
                <td>${members.length ? members.map((m) => esc(m.name)).join(', ') : '<span class="muted">Aucun membre</span>'}</td>
                <td><span class="badge"><span class="sq" data-status="${esc(u.status)}"></span>${esc(STATUS_LABELS[u.status] || u.status)}</span></td>
                <td class="col-actions">
                    ${isMine
                        ? `<button class="btn btn-small" data-unit-action="leave" data-id="${esc(u.id)}">Quitter</button>`
                        : `<button class="btn btn-small btn-default" data-unit-action="join" data-id="${esc(u.id)}">Rejoindre</button>`}
                    <button class="btn btn-small" data-unit-action="edit" data-id="${esc(u.id)}">Modifier</button>
                    <button class="btn btn-small btn-danger" data-unit-action="delete" data-id="${esc(u.id)}">Supprimer</button>
                </td>
            </tr>`;
        }).join('');
        renderSidebarUnit();
    }

    function setUnits(units) {
        state.units = toArray(units);
        renderUnits();
        if (state.callPanel.mode === 'view') renderInterventionDetail(); // boutons "Rejoindre l'appel"
    }

    async function refreshUnits() {
        const res = await post('getUnits');
        if (res && res.ok) setUnits(res.units);
    }

    $('#refreshUnits').addEventListener('click', refreshUnits);

    // ---- Création / modification d'une unité (nom, tag, couleur du tag) ----
    const unitForm = $('#unitForm');

    function updateTagPreview() {
        const data = new FormData(unitForm);
        const preview = $('#tagPreview');
        preview.textContent = String(data.get('tag') || '').trim().toUpperCase() || 'TAG';
        preview.className = `unit-tag tag-${data.get('color') || 'green'}`;
    }

    function resetUnitForm() {
        state.unitEdit = null;
        unitForm.reset();
        updateTagPreview();
        $('#unitFormLegend').textContent = 'Créer une unité';
        $('#unitSubmit').textContent = 'Créer l\'unité';
        $('#unitCancelEdit').classList.add('hidden');
    }

    function startUnitEdit(unit) {
        state.unitEdit = unit.id;
        unitForm.elements.name.value = unit.name;
        unitForm.elements.tag.value = unit.tag;
        const color = unitForm.querySelector(`input[name="color"][value="${TAG_COLORS.includes(unit.color) ? unit.color : 'gray'}"]`);
        color.checked = true;
        updateTagPreview();
        $('#unitFormLegend').textContent = `Modifier l'unité ${unit.tag}`;
        $('#unitSubmit').textContent = 'Enregistrer';
        $('#unitCancelEdit').classList.remove('hidden');
        unitForm.elements.name.focus();
    }

    unitForm.addEventListener('input', updateTagPreview);
    unitForm.addEventListener('change', updateTagPreview);
    $('#unitCancelEdit').addEventListener('click', resetUnitForm);

    unitForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        const payload = Object.fromEntries(new FormData(unitForm).entries());
        const editing = state.unitEdit;
        const res = await post(editing ? 'updateUnit' : 'createUnit', editing ? { ...payload, id: editing } : payload);
        if (!res || !res.ok) {
            toast(res?.error || 'Erreur lors de l\'enregistrement de l\'unité.', 'error');
            return;
        }
        toast(editing ? 'Unité modifiée.' : 'Unité créée.', 'success');
        resetUnitForm();
        refreshUnits();
    });

    // ---- Rejoindre / quitter / modifier / supprimer ----
    const UNIT_ACTIONS = { join: 'joinUnit', leave: 'leaveUnit', delete: 'deleteUnit' };
    const UNIT_DONE = { join: 'Unité rejointe.', leave: 'Vous avez quitté l\'unité.', delete: 'Unité supprimée.' };

    $('#unitsBody').addEventListener('click', async (e) => {
        const btn = e.target.closest('[data-unit-action]');
        if (!btn) return;
        const id = Number(btn.dataset.id);
        const action = btn.dataset.unitAction;

        if (action === 'edit') {
            const unit = state.units.find((u) => u.id === id);
            if (unit) startUnitEdit(unit);
            return;
        }

        // Suppression : deuxième clic pour confirmer
        if (action === 'delete' && !btn.dataset.confirm) {
            btn.dataset.confirm = '1';
            btn.textContent = 'Confirmer ?';
            setTimeout(() => {
                if (!btn.isConnected) return;
                delete btn.dataset.confirm;
                btn.textContent = 'Supprimer';
            }, 3000);
            return;
        }

        btn.disabled = true;
        const res = await post(UNIT_ACTIONS[action], { id });
        btn.disabled = false;
        if (!res || !res.ok) {
            toast(res?.error || 'Action impossible.', 'error');
            return;
        }
        toast(UNIT_DONE[action], 'success');
        if (action === 'delete' && state.unitEdit === id) resetUnitForm();
        refreshUnits();
    });

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
            `;
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
            `;
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
    // RECHERCHES (avec historique : les nouveaux résultats s'ajoutent en haut,
    // les résultats des recherches précédentes restent en dessous)
    // =====================================================================
    const searchType = () => $('input[name="searchType"]:checked').value;

    $$('input[name="searchType"]').forEach((radio) => radio.addEventListener('change', () => {
        const identity = searchType() === 'identity';
        $('#searchIdentityForm').classList.toggle('hidden', !identity);
        $('#searchVehicleForm').classList.toggle('hidden', identity);
        $(identity ? '#searchIdentityForm input' : '#searchVehicleForm input').focus();
    }));

    function resultRow(r, i) {
        if (r.kind === 'identity') {
            return `
                <tr data-index="${i}" class="${r.condition === 'wanted' ? 'row-wanted' : ''}">
                    <td>Identité</td>
                    <td><b>${esc(String(r.lastname).toUpperCase())}</b> ${esc([r.firstname, r.middlename].filter(Boolean).join(' '))}</td>
                    <td>${esc(r.dob)} — SSN ${esc(r.ssn || '-')}</td>
                    <td>${conditionFlag(r.condition)}</td>
                </tr>`;
        }
        const owner = r.ownerIdentity ? fullName(r.ownerIdentity) : (r.ownerName || 'Propriétaire inconnu');
        return `
            <tr data-index="${i}" class="${r.stolen ? 'row-wanted' : ''}">
                <td>Véhicule</td>
                <td><b>${esc(r.plate)}</b></td>
                <td>${esc([r.make, r.model].filter(Boolean).join(' '))} — ${esc(owner)}</td>
                <td>${regFlag(r.regStatus)}${r.stolen ? ` ${flag('c-red', 'Volé')}` : ''}</td>
            </tr>`;
    }

    function renderSearchResults(selectIndex) {
        const list = state.searchResults;
        $('#searchCount').textContent = list.length ? `(${list.length})` : '';
        $('#searchEmpty').classList.toggle('hidden', list.length > 0);
        $('#searchBody').innerHTML = list.map(resultRow).join('');

        if (selectIndex != null && list[selectIndex]) {
            $(`#searchBody tr[data-index="${selectIndex}"]`).click(); // nouveau résultat : sélectionné (bleu) en haut
        } else {
            $('#searchDetail').innerHTML = '<div class="empty">Sélectionnez un résultat.</div>';
        }
    }

    async function runSearch(type, payload) {
        const res = await post('search', { type, ...payload });
        if (!res || !res.ok) {
            toast(res?.error || 'Erreur de recherche.', 'error');
            return;
        }

        const results = toArray(res.results);
        if (!results.length) {
            toast('Aucun résultat pour cette recherche.', 'info');
            return;
        }

        // Nouveaux résultats en haut ; une fiche déjà présente remonte au lieu d'être dupliquée
        const key = (r) => `${r.kind}:${r.id}`;
        const fresh = new Set(results.map(key));
        state.searchResults = [...results, ...state.searchResults.filter((r) => !fresh.has(key(r)))].slice(0, 100);
        renderSearchResults(0);
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

    $('#clearSearch').addEventListener('click', () => {
        state.searchResults = [];
        renderSearchResults();
    });

    bindSelectable($('#searchBody'), () => state.searchResults, $('#searchDetail'), false);

    // =====================================================================
    // INTERVENTIONS (appels créés par les civils) ET INCIDENTS (déclarés par
    // les unités). Liste de titres à gauche, détails à droite.
    // Déroulé : En Attente (aucune unité) -> En Cours (unité sur l'appel) -> Terminée
    // =====================================================================
    const CALL_PRIORITY = {
        nonurgent: ['c-purple', 'Non-Urgent'],
        p1: ['c-red', 'Priorité 1'],
        p2: ['c-orange', 'Priorité 2'],
        p3: ['c-yellow', 'Priorité 3'],
    };
    const CALL_STATUS = {
        pending: ['c-blue', 'En Attente'],
        ongoing: ['c-green', 'En Cours'],
        closed: ['c-gray', 'Terminée'],
    };
    const callFlag = (map, key) => (map[key] ? flag(map[key][0], map[key][1]) : '-');
    const findCall = (id) => state.interventions.find((c) => c.id === id) || null;

    function renderInterventionList() {
        const list = state.interventions;
        const selected = state.callPanel.id;
        $('#interventionsCount').textContent = `(${list.length})`;
        $('#interventionsEmpty').classList.toggle('hidden', list.length > 0);
        $('#interventionsBody').innerHTML = list.map((c) => `
            <tr data-id="${esc(c.id)}" class="${c.closed ? 'row-closed' : ''} ${c.id === selected ? 'selected' : ''}">
                <td>${esc(c.title)}</td>
            </tr>`).join('');
    }

    function noteHtml(note, call, unit) {
        const mine = !!unit && note.unitId === unit.id && !call.closed;
        const editing = state.noteEdit && state.noteEdit.id === note.id;
        const head = `
            <div class="note-head">
                ${unitTag({ tag: note.unitTag, color: note.unitColor })}
                <span>${esc(note.unitName)} — ${esc(formatTime(note.createdAt))}${note.updatedAt ? ' (modifiée)' : ''}</span>
                <span class="grow"></span>
                ${mine && !editing ? `<button type="button" class="btn btn-small" data-note-edit="${esc(note.id)}">Modifier</button>` : ''}
            </div>`;
        const body = editing
            ? `<textarea id="noteEditText" class="upper-text" rows="3" maxlength="500">${esc(state.noteEdit.text)}</textarea>
               <div class="toolbar note-toolbar">
                   <span class="grow"></span>
                   <button type="button" class="btn btn-small" data-note-cancel>Annuler</button>
                   <button type="button" class="btn btn-small btn-default" data-note-save="${esc(note.id)}">Enregistrer</button>
               </div>`
            : `<div class="note-text">${esc(note.text)}</div>`;
        return `<div class="note">${head}${body}</div>`;
    }

    function callViewHtml(c) {
        const unit = myUnit();
        const units = toArray(c.units);
        const notes = toArray(c.notes);
        const onCall = !!unit && units.some((u) => u.id === unit.id);
        const incident = c.kind === 'incident';

        let actions = '';
        if (!c.closed) {
            actions = `
                ${unit ? '' : '<div class="hint-box">Seules les unités peuvent rejoindre un appel : rejoignez d\'abord une unité (onglet Unités).</div>'}
                <div class="toolbar call-actions">
                    ${unit ? (onCall
                        ? '<button type="button" class="btn" data-call-action="leave">Quitter l\'appel</button>'
                        : `<button type="button" class="btn btn-default" data-call-action="join">Rejoindre l'appel (${esc(unit.tag)})</button>`) : ''}
                    <button type="button" class="btn" data-call-action="edit">Modifier</button>
                    <span class="grow"></span>
                    ${onCall ? '<button type="button" class="btn btn-danger" data-call-action="end">Intervention terminée</button>' : ''}
                </div>`;
        }

        return `
            <div class="sheet-title"><span>${esc(c.number)} — ${esc(c.title)}</span>${callFlag(CALL_STATUS, c.status)}</div>
            ${actions}
            <dl class="sheet">
                ${row('N° d\'incident', c.number)}
                ${row('Catégorie', incident ? 'Incident (déclaré par une unité)' : 'Intervention (appel)')}
                ${dd('Déroulé', callFlag(CALL_STATUS, c.status))}
                ${row(incident ? 'Type d\'incident' : 'Type d\'intervention', c.title)}
                ${incident
                    ? row('Unité déclarante', c.unitName)
                    : row('Requérant', c.caller) + row('Téléphone du requérant', c.phone) + dd('Priorité de l\'urgence', callFlag(CALL_PRIORITY, c.priority))}
                ${row('Adresse', c.address)}
                ${row('Bloc', c.block)}
                ${row(incident ? 'Description de l\'incident' : 'Description', c.description)}
                ${row('Émise le', formatDate(c.createdAt))}
                ${c.closed ? row('Terminée le', `${formatDate(c.closedAt)} par ${c.closedByName || '-'}`) : ''}
            </dl>
            <div class="sheet-sub">Unités sur l'appel (${units.length})</div>
            <div class="call-units">${units.length
                ? units.map((u) => `<span class="call-unit">${unitTag(u)} ${esc(u.name)}</span>`).join('')
                : '<span class="muted">Aucune unité.</span>'}</div>
            <div class="sheet-sub">Notes (${notes.length})</div>
            ${notes.length ? notes.map((n) => noteHtml(n, c, unit)).join('') : '<div class="muted">Aucune note.</div>'}
            ${onCall && !c.closed ? `
                <div class="note-new">
                    <textarea id="noteDraft" class="upper-text" rows="3" maxlength="500" placeholder="AJOUTER UNE NOTE (EN MAJUSCULES)">${esc(state.noteDraft)}</textarea>
                    <div class="toolbar note-toolbar">
                        <span class="grow"></span>
                        <button type="button" class="btn btn-default" data-call-action="addNote">Ajouter la note</button>
                    </div>
                </div>` : ''}`;
    }

    // Formulaire : nouvel incident (call absent) ou modification d'une intervention / d'un incident
    function callFormHtml(c) {
        const isNew = !c;
        const kind = isNew ? 'incident' : c.kind;
        const unit = myUnit();
        const v = (key) => esc(c ? (c[key] ?? '') : '');
        const unitName = isNew ? (unit ? `[${unit.tag}] ${unit.name}` : 'Aucune unité : rejoignez une unité pour déclarer un incident') : c.unitName;
        const priorities = Object.entries(CALL_PRIORITY).map(([key, [, label]]) =>
            `<option value="${key}" ${c && c.priority === key ? 'selected' : ''}>${label}</option>`).join('');

        return `
            <form id="callForm" class="call-form" autocomplete="off" novalidate>
                <div class="toolbar"><span class="hint-text">* champs obligatoires${isNew ? ' — votre unité sera automatiquement placée sur l\'incident.' : ''}</span></div>
                <div class="form-grid">
                    <label class="lbl span-2">${kind === 'incident' ? 'Type d\'incident' : 'Type d\'intervention'} *<input name="title" type="text" maxlength="60" value="${v('title')}"></label>
                    ${kind === 'incident' ? `<label class="lbl span-2">Nom de l'unité créant l'incident<input type="text" value="${esc(unitName)}" disabled></label>` : `
                        <label class="lbl">Requérant *<input name="caller" type="text" maxlength="60" value="${v('caller')}"></label>
                        <label class="lbl">N° de téléphone du requérant *
                            <span class="inline">
                                <input name="phone" type="text" maxlength="20" value="${v('phone')}">
                                <button type="button" class="btn btn-icon" data-gen-phone title="Générer un nouveau numéro">&#8635;</button>
                            </span>
                        </label>
                        <label class="lbl span-2">Priorité de l'urgence *<select name="priority">${priorities}</select></label>`}
                    <label class="lbl">Adresse *<input name="address" type="text" maxlength="80" value="${v('address')}"></label>
                    <label class="lbl">Bloc *<input name="block" type="text" maxlength="40" value="${v('block')}"></label>
                    <label class="lbl span-2">${kind === 'incident' ? 'Description de l\'incident' : 'Description'} *<textarea name="description" rows="6" maxlength="2000">${v('description')}</textarea></label>
                </div>
                <div class="form-actions">
                    <button type="button" class="btn" data-call-action="cancelForm">Annuler</button>
                    <button type="submit" class="btn btn-default">${isNew ? 'Déclarer l\'incident' : 'Enregistrer les modifications'}</button>
                </div>
            </form>`;
    }

    function renderInterventionDetail() {
        const el = $('#interventionDetail');
        const panel = state.callPanel;
        const call = findCall(panel.id);
        const title = $('#interventionPanelTitle');

        if (panel.mode === 'new') {
            title.textContent = 'Nouvel incident';
            el.innerHTML = callFormHtml(null);
            return;
        }
        if (!call) {
            title.textContent = 'Détails';
            el.innerHTML = '<div class="empty">Sélectionnez une intervention dans la liste.</div>';
            return;
        }
        if (panel.mode === 'edit') {
            title.textContent = `Modifier ${call.number}`;
            el.innerHTML = callFormHtml(call);
            return;
        }

        // Vue détaillée : on conserve le texte en cours de saisie et le focus
        const focused = document.activeElement && el.contains(document.activeElement) ? document.activeElement.id : '';
        title.textContent = call.kind === 'incident' ? 'Détails de l\'incident' : 'Détails de l\'intervention';
        el.innerHTML = callViewHtml(call);
        const field = focused && el.querySelector(`#${focused}`);
        if (field) {
            field.focus();
            field.setSelectionRange(field.value.length, field.value.length);
        }
    }

    function setInterventions(list) {
        state.interventions = toArray(list);
        renderInterventionList();
        // Les formulaires en cours de saisie ne sont pas écrasés par les mises à jour en temps réel
        if (state.callPanel.mode === 'view') renderInterventionDetail();
    }

    async function refreshInterventions() {
        const res = await post('getInterventions');
        if (res && res.ok) setInterventions(res.interventions);
    }

    function openCall(id, mode = 'view') {
        if (state.callPanel.id !== id) {
            state.noteDraft = '';
            state.noteEdit = null;
        }
        state.callPanel = { mode, id };
        renderInterventionList();
        renderInterventionDetail();
    }

    $('#interventionsBody').addEventListener('click', (e) => {
        const tr = e.target.closest('tr[data-id]');
        if (tr) openCall(Number(tr.dataset.id));
    });

    $('#newIncident').addEventListener('click', () => {
        if (!myUnit()) toast('Rejoignez une unité (onglet Unités) pour déclarer un incident.', 'error');
        state.callPanel = { mode: 'new', id: null };
        renderInterventionList();
        renderInterventionDetail();
    });

    $('#refreshInterventions').addEventListener('click', refreshInterventions);

    // Texte des notes : saisie conservée entre deux mises à jour
    $('#interventionDetail').addEventListener('input', (e) => {
        if (e.target.id === 'noteDraft') state.noteDraft = e.target.value;
        if (e.target.id === 'noteEditText' && state.noteEdit) state.noteEdit.text = e.target.value;
    });

    async function callRequest(name, payload, success) {
        const res = await post(name, payload);
        if (!res || !res.ok) {
            toast(res?.error || 'Action impossible.', 'error');
            return null;
        }
        if (success) toast(success, 'success');
        return res;
    }

    $('#interventionDetail').addEventListener('click', async (e) => {
        const call = findCall(state.callPanel.id);
        const actionBtn = e.target.closest('[data-call-action]');

        if (e.target.closest('[data-gen-phone]')) {
            $('#callForm').elements.phone.value = Random.phone();
            return;
        }

        if (actionBtn) {
            const action = actionBtn.dataset.callAction;

            if (action === 'cancelForm') {
                state.callPanel = { mode: 'view', id: call ? call.id : null };
                renderInterventionList();
                renderInterventionDetail();
                return;
            }
            if (!call) return;
            if (action === 'edit') return openCall(call.id, 'edit');

            // "Intervention terminée" : deuxième clic pour confirmer
            if (action === 'end' && !actionBtn.dataset.confirm) {
                actionBtn.dataset.confirm = '1';
                actionBtn.textContent = 'Confirmer la fin ?';
                setTimeout(() => {
                    if (!actionBtn.isConnected) return;
                    delete actionBtn.dataset.confirm;
                    actionBtn.textContent = 'Intervention terminée';
                }, 3000);
                return;
            }

            if (action === 'addNote') {
                const text = state.noteDraft.trim();
                if (!text) return toast('La note est vide.', 'error');
                if (await callRequest('addNote', { id: call.id, text }, 'Note ajoutée.')) {
                    state.noteDraft = '';
                    refreshInterventions();
                }
                return;
            }

            const messages = { join: 'Appel rejoint : unité « En route ».', leave: 'Vous avez quitté l\'appel.', end: 'Intervention terminée.' };
            actionBtn.disabled = true;
            const res = await callRequest('interventionAction', { id: call.id, action }, messages[action]);
            actionBtn.disabled = false;
            if (res) {
                refreshInterventions();
                if (action === 'join') refreshUnits();
            }
            return;
        }

        // Notes : modifier / annuler / enregistrer
        const editBtn = e.target.closest('[data-note-edit]');
        if (editBtn && call) {
            const note = toArray(call.notes).find((n) => String(n.id) === editBtn.dataset.noteEdit);
            state.noteEdit = note ? { id: note.id, text: note.text } : null;
            renderInterventionDetail();
            $('#noteEditText')?.focus();
            return;
        }
        if (e.target.closest('[data-note-cancel]')) {
            state.noteEdit = null;
            renderInterventionDetail();
            return;
        }
        const saveBtn = e.target.closest('[data-note-save]');
        if (saveBtn && call && state.noteEdit) {
            if (await callRequest('editNote', { id: call.id, noteId: state.noteEdit.id, text: state.noteEdit.text }, 'Note modifiée.')) {
                state.noteEdit = null;
                refreshInterventions();
            }
        }
    });

    // Enregistrement du formulaire (nouvel incident ou modification)
    $('#interventionDetail').addEventListener('submit', async (e) => {
        e.preventDefault();
        const form = e.target;
        const payload = Object.fromEntries(new FormData(form).entries());
        const submit = form.querySelector('button[type="submit"]');
        submit.disabled = true;

        let res;
        if (state.callPanel.mode === 'new') {
            res = await callRequest('createIncident', payload, 'Incident déclaré.');
            if (res) state.callPanel = { mode: 'view', id: res.id };
        } else {
            const id = state.callPanel.id;
            res = await callRequest('editIntervention', { ...payload, id }, 'Modifications enregistrées.');
            if (res) state.callPanel = { mode: 'view', id };
        }

        submit.disabled = false;
        if (res) refreshInterventions();
    });

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
        const phone = () => `555-${int(100, 999)}-${String(int(0, 9999)).padStart(4, '0')}`;

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

        return { ssn, licenseNumber, vin, policyNumber, phone, identity, vehicle };
    })();

    // =====================================================================
    // SAISIE : formats automatiques (dates, heures, SSN, majuscules, chiffres)
    // (délégation : fonctionne aussi pour les antécédents ajoutés dynamiquement)
    // =====================================================================
    document.addEventListener('input', (e) => {
        const input = e.target;

        // Notes d'intervention : toujours en MAJUSCULES
        if (input instanceof HTMLTextAreaElement && input.classList.contains('upper-text')) {
            const pos = input.selectionStart;
            input.value = input.value.toUpperCase();
            input.setSelectionRange(pos, pos);
            return;
        }
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
    const GENERATORS = { ssn: Random.ssn, licenseNumber: Random.licenseNumber, vin: Random.vin, insurancePolicy: Random.policyNumber, phone: Random.phone };

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

    // Intervention (civils) : apparaît dans l'onglet "Interventions", absente du registre
    const interventionForm = $('#view-intervention');

    function resetInterventionForm() {
        interventionForm.reset();
        interventionForm.elements.phone.value = Random.phone(); // téléphone du requérant généré automatiquement
    }

    interventionForm.querySelector('.btn-clear').addEventListener('click', resetInterventionForm);

    interventionForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        const payload = { ...Object.fromEntries(new FormData(interventionForm).entries()), kind: 'intervention' };
        const submit = interventionForm.querySelector('button[type="submit"]');
        submit.disabled = true;
        const res = await post('create', payload);
        submit.disabled = false;
        if (res && res.ok) {
            toast(`Intervention ${res.number} enregistrée.`, 'success');
            resetInterventionForm();
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
                setUnits(data.data);
                break;
            case 'interventions':
                setInterventions(data.data);
                break;
        }
    });

    // État initial des formulaires
    resetIdentityForm();
    resetVehicleForm();
    resetInterventionForm();
    updateEditUI();
    renderUnits();
    renderSearchResults();
})();
