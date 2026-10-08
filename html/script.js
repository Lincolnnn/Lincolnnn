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
    // Services de police (clés identiques à DEPARTMENTS dans server.lua)
    const DEPARTMENTS = {
        apd: { label: 'Atlanta Police Department', short: 'APD' },
        gsp: { label: 'Georgia State Patrol', short: 'GSP' },
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
        callReportType: null,  // type de rapport choisi dans le détail d'une intervention
        linkChoice: null,      // fiche de l'historique choisie pour être liée à l'appel
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
        const startTab = hud.settings.mdc.startTab;
        if (startTab && startTab !== 'last') showPage(startTab);
        else loadPage(state.page);
    }

    function closeUI(notifyLua = true) {
        if (!state.open) return;
        if (hud.placing) setPlacing(false);
        state.open = false;
        drag = null;
        document.body.classList.remove('dragging');
        win.classList.add('hidden');
        clearInterval(state.clockTimer);
        state.clockTimer = null;

        // Relâche le SetNuiFocus côté Lua
        if (notifyLua) post('close');
    }

    // Heure du JEU (et non l'heure réelle), lue auprès du client Lua tant que le MDC est ouvert
    async function updateClock() {
        const res = await post('getGameTime');
        $('#sbClock').textContent = res && res.ok ? `${pad(res.hours)}:${pad(res.minutes)}` : '--:--';
    }

    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && state.open) {
            e.preventDefault();
            if (hud.placing) setPlacing(false);
            else closeUI();
        }
    });

    $('#btnClose').addEventListener('click', () => closeUI());

    // =====================================================================
    // NAVIGATION
    // =====================================================================
    function showPage(page) {
        state.page = page;
        hideSuggest();
        $$('.tab').forEach((t) => t.classList.toggle('active', t.dataset.page === page));
        $$('.page').forEach((p) => p.classList.toggle('active', p.id === `page-${page}`));
        loadPage(page);
    }

    function loadPage(page) {
        if (page === 'units') refreshUnits();
        else if (page === 'interventions') refreshInterventions();
        else if (page === 'reports') loadReportsPage();
        else if (page === 'create') loadCreateView(state.createView);
        else if (page === 'settings') renderSettings();
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
    const tagColor = (color) => (TAG_COLORS.includes(color) ? color : 'gray');
    // Tag facultatif : rien n'est affiché si l'unité n'en a pas
    const unitTag = (u) => (u.tag ? `<span class="unit-tag tag-${tagColor(u.color)}">${esc(u.tag)}</span>` : '');
    // Nom de l'unité précédé d'un carré de la couleur de son tag (appels, notes)
    const unitChip = (u) => `<span class="call-unit"><span class="unit-dot tag-${tagColor(u.color)}"></span>${esc(u.name)}</span>`;

    // Unité dont le joueur fait partie (ou null)
    const myUnit = () => state.units.find((u) => toArray(u.members).some((m) => m.id === state.serverId)) || null;

    // ---- Barre latérale : le statut affiché est celui de l'unité du joueur ----
    function renderSidebarUnit() {
        const unit = myUnit();
        $('#myUnit').innerHTML = unit
            ? `${unitTag(unit)} <span>${esc(unit.name)}</span>${DEPARTMENTS[unit.dept] ? `<span class="dept-short">${DEPARTMENTS[unit.dept].short}</span>` : ''}`
            : '<span class="muted">Aucune unité — rejoignez-en une dans l\'onglet Unités.</span>';
        $('#statusList').classList.toggle('no-unit', !unit);
        $$('.status-btn').forEach((b) => b.classList.toggle('active', !!unit && b.dataset.status === unit.status));

        const cell = $('#sbStatus');
        cell.querySelector('.sq').dataset.status = unit ? unit.status : '';
        cell.lastElementChild.textContent = unit ? `${unit.name} — ${STATUS_LABELS[unit.status] || unit.status}` : 'Hors unité';
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
            toast(`${unit.name} : ${STATUS_LABELS[status]}`, 'success');
        } else {
            toast(res?.error || 'Impossible de changer de statut.', 'error');
        }
    }

    $$('.status-btn').forEach((btn) => btn.addEventListener('click', () => changeStatus(btn.dataset.status)));

    // ---- Liste des unités ----
    // Une liste par service de police (APD / GSP)
    function renderUnits() {
        Object.keys(DEPARTMENTS).forEach((dept) => {
            const units = state.units.filter((u) => u.dept === dept);
            $(`.units-count[data-dept="${dept}"]`).textContent = `(${units.length})`;
            $(`.units-empty[data-dept="${dept}"]`).classList.toggle('hidden', units.length > 0);
            $(`.units-body[data-dept="${dept}"]`).innerHTML = unitRowsHtml(units);
        });
        renderSidebarUnit();
    }

    function unitRowsHtml(units) {
        const mine = myUnit();
        return units.map((u) => {
            const members = toArray(u.members);
            const isMine = !!mine && mine.id === u.id;
            return `
            <tr class="${isMine ? 'me' : ''}">
                <td><b>${esc(u.name)}</b></td>
                <td>${unitTag(u) || '<span class="muted">Aucun</span>'}</td>
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
        preview.textContent = String(data.get('tag') || '').trim().toUpperCase() || 'Aucun tag';
        preview.className = `unit-tag tag-${data.get('color') || 'green'}`;
    }

    // Le formulaire n'est affiché qu'après un clic sur "Créer une unité" ou "Modifier"
    function resetUnitForm() {
        state.unitEdit = null;
        unitForm.reset();
        updateTagPreview();
        $('#unitFormLegend').textContent = 'Créer une unité';
        $('#unitSubmit').textContent = 'Créer l\'unité';
        $('#unitFormGroup').classList.add('hidden');
    }

    function openUnitForm(dept) {
        resetUnitForm();
        unitForm.elements.dept.value = DEPARTMENTS[dept] ? dept : '';
        $('#unitFormGroup').classList.remove('hidden');
        unitForm.elements.name.focus();
    }

    function startUnitEdit(unit) {
        $('#unitFormGroup').classList.remove('hidden');
        state.unitEdit = unit.id;
        unitForm.elements.dept.value = DEPARTMENTS[unit.dept] ? unit.dept : '';
        unitForm.elements.name.value = unit.name;
        unitForm.elements.tag.value = unit.tag;
        const color = unitForm.querySelector(`input[name="color"][value="${TAG_COLORS.includes(unit.color) ? unit.color : 'gray'}"]`);
        color.checked = true;
        updateTagPreview();
        $('#unitFormLegend').textContent = `Modifier l'unité ${unit.name}`;
        $('#unitSubmit').textContent = 'Enregistrer';
        unitForm.elements.name.focus();
    }

    unitForm.addEventListener('input', updateTagPreview);
    unitForm.addEventListener('change', updateTagPreview);
    $('#unitCancelEdit').addEventListener('click', resetUnitForm);
    $$('[data-new-unit]').forEach((btn) => btn.addEventListener('click', () => openUnitForm(btn.dataset.newUnit)));

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

    $$('.units-body').forEach((tbody) => tbody.addEventListener('click', async (e) => {
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
    }));

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

    async function openRecordInSearch(kind, id) {
        const res = await post('getRecord', { kind, id });
        if (!res || !res.ok) {
            toast(res?.error || 'Fiche introuvable.', 'error');
            return;
        }
        const record = res.record;
        state.searchResults = [record, ...state.searchResults.filter((r) => !(r.kind === record.kind && r.id === record.id))].slice(0, 100);
        showPage('search');
        renderSearchResults(0);
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
        $('#interventionsBody').innerHTML = list.map((c) => {
            // Ligne surlignée de la couleur de sa priorité (sauf terminée : grisée)
            const prio = !c.closed && CALL_PRIORITY[c.priority] ? `prio prio-${c.priority}` : '';
            return `
            <tr data-id="${esc(c.id)}" class="${c.closed ? 'row-closed' : ''} ${prio} ${c.id === selected ? 'selected' : ''}">
                <td class="cell-ellipsis"><b>${esc(c.title)}</b></td>
                <td>${c.kind === 'incident' ? '<span class="muted">Incident</span>' : esc(CALL_PRIORITY[c.priority] ? CALL_PRIORITY[c.priority][1] : '-')}</td>
                <td class="cell-ellipsis">${esc(c.address)}${c.crossStreet ? `<span class="cross-inline"> × ${esc(c.crossStreet)}</span>` : ''}</td>
                <td>${esc(c.block)}</td>
            </tr>`;
        }).join('');
    }

    function noteHtml(note, call, unit) {
        const mine = !!unit && note.unitId === unit.id && !call.closed;
        const editing = state.noteEdit && state.noteEdit.id === note.id;
        const head = `
            <div class="note-head">
                ${unitChip({ name: note.unitName, color: note.unitColor })}
                <span>${esc(formatTime(note.createdAt))}${note.updatedAt ? ' (modifiée)' : ''}</span>
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

    // Rapport lié, affiché dans le déroulé avec les notes
    function reportLinkHtml(r) {
        return `
            <div class="note note-report">
                <div class="note-head">
                    <span class="flag c-blue">RAPPORT</span>
                    <b class="note-report-title">${esc(r.label)} — n°${esc(r.number)}</b>
                    <span class="grow"></span>
                    <button type="button" class="btn btn-small" data-report-open="${esc(r.id)}">Ouvrir</button>
                    <button type="button" class="btn btn-small" data-report-modify="${esc(r.id)}">Modifier</button>
                </div>
                ${r.summary ? `<div class="note-text">${esc(r.summary)}</div>` : ''}
                <div class="note-meta">Rédigé par ${esc(r.createdByName || '-')}${r.unitName ? ` (${esc(r.unitName)})` : ''} — ${esc(formatTime(r.createdAt))}${r.updatedAt ? ` (modifié à ${esc(formatTime(r.updatedAt))})` : ''}</div>
            </div>`;
    }

    // ---- Identités / véhicules liés à l'appel (ajoutés depuis l'historique des recherches) ----
    const linkKey = (kind, id) => `${kind}:${id}`;

    function linkLineHtml(l) {
        if (l.kind === 'vehicle') {
            return `<span class="flag c-gray">VÉHICULE</span> <b>${esc(l.plate)}</b> — ${esc([l.make, l.model].filter(Boolean).join(' '))}${l.color ? ` (${esc(l.color)})` : ''}
                ${l.owner ? `<span class="muted"> — ${esc(l.owner)}</span>` : ''} ${regFlag(l.regStatus)}${l.stolen ? ` ${flag('c-red', 'Volé')}` : ''}`;
        }
        return `<span class="flag c-gray">IDENTITÉ</span> <b>${esc(String(l.lastname || '').toUpperCase())}</b> ${esc([l.firstname, l.middlename].filter(Boolean).join(' '))} — ${esc(l.dob)}
            ${l.condition && l.condition !== 'none' ? conditionFlag(l.condition) : ''}`;
    }

    function callLinksHtml(c, onCall) {
        const links = toArray(c.links);
        const taken = new Set(links.map((l) => linkKey(l.kind, l.recordId)));
        const choices = state.searchResults.filter((r) => !taken.has(linkKey(r.kind, r.id)));
        const canEdit = onCall && !c.closed;

        let picker = '';
        if (canEdit) {
            picker = choices.length
                ? `<div class="toolbar link-picker">
                       <select id="callLinkChoice">${choices.map((r) => {
                           const key = linkKey(r.kind, r.id);
                           const label = r.kind === 'vehicle'
                               ? `Véhicule — ${r.plate} — ${[r.make, r.model].filter(Boolean).join(' ')}`
                               : `Identité — ${String(r.lastname).toUpperCase()} ${r.firstname} (${r.dob})`;
                           return `<option value="${esc(key)}" ${key === state.linkChoice ? 'selected' : ''}>${esc(label)}</option>`;
                       }).join('')}</select>
                       <button type="button" class="btn" data-call-action="linkRecord">+ Ajouter à l'appel</button>
                   </div>`
                : `<div class="hint-text link-picker">${state.searchResults.length
                    ? 'Toutes les fiches de l\'historique des recherches sont déjà liées.'
                    : 'Recherchez une identité ou une immatriculation (onglet Recherches) pour pouvoir l\'ajouter ici.'}</div>`;
        }

        return `
            <div class="sheet-sub">Personnes et véhicules (${links.length})</div>
            ${links.length ? `<div class="call-links">${links.map((l) => `
                <div class="call-link">
                    <span class="call-link-text">${linkLineHtml(l)}</span>
                    <span class="grow"></span>
                    <button type="button" class="btn btn-small" data-link-open="${esc(l.kind)}" data-id="${esc(l.recordId)}">Fiche</button>
                    ${canEdit ? `<button type="button" class="btn btn-small" data-link-remove="${esc(l.kind)}" data-id="${esc(l.recordId)}" title="Retirer de l'appel">&#10005;</button>` : ''}
                </div>`).join('')}</div>` : '<div class="muted">Aucune personne ni aucun véhicule lié.</div>'}
            ${picker}`;
    }

    // Choix du type de rapport à rédiger depuis l'intervention
    function reportStarterHtml() {
        if (!reports.types.length) {
            loadReportTypes().then((ok) => { if (ok && state.callPanel.mode === 'view') renderInterventionDetail(); });
            return '';
        }
        return `
            <div class="toolbar report-starter">
                <span class="lbl-inline">Rapport lié :</span>
                <select id="callReportType">${reports.types.map((t) => `<option value="${esc(t.id)}" ${t.id === state.callReportType ? 'selected' : ''}>${esc(t.label)}</option>`).join('')}</select>
                <button type="button" class="btn" data-call-action="writeReport">+ Rédiger un rapport</button>
            </div>`;
    }

    function callViewHtml(c) {
        const unit = myUnit();
        const units = toArray(c.units);
        const notes = toArray(c.notes);
        const linked = toArray(c.reports);
        const timeline = [
            ...notes.map((n) => ({ at: n.createdAt || 0, html: () => noteHtml(n, c, unit) })),
            ...linked.map((r) => ({ at: r.createdAt || 0, html: () => reportLinkHtml(r) })),
        ].sort((a, b) => a.at - b.at);
        const onCall = !!unit && units.some((u) => u.id === unit.id);
        const incident = c.kind === 'incident';

        let actions = '';
        if (!c.closed) {
            actions = `
                ${unit ? '' : '<div class="hint-box">Seules les unités peuvent rejoindre un appel : rejoignez d\'abord une unité (onglet Unités).</div>'}
                <div class="toolbar call-actions">
                    ${unit ? (onCall
                        ? '<button type="button" class="btn" data-call-action="leave">Quitter l\'appel</button>'
                        : `<button type="button" class="btn btn-default" data-call-action="join">Rejoindre l'appel (${esc(unit.name)})</button>`) : ''}
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
                ${row('Croisement', c.crossStreet)}
                ${row('Bloc', c.block)}
                ${row(incident ? 'Description de l\'incident' : 'Description', c.description)}
                ${row('Émise le', formatDate(c.createdAt))}
                ${c.closed ? row('Terminée le', `${formatDate(c.closedAt)} par ${c.closedByName || '-'}`) : ''}
            </dl>
            <div class="sheet-sub">Unités sur l'appel (${units.length})</div>
            <div class="call-units">${units.length
                ? units.map(unitChip).join('')
                : '<span class="muted">Aucune unité.</span>'}</div>
            ${callLinksHtml(c, onCall)}
            <div class="sheet-sub">Notes et rapports (${timeline.length})</div>
            ${timeline.length ? timeline.map((entry) => entry.html()).join('') : '<div class="muted">Aucune note ni rapport.</div>'}
            ${onCall && !c.closed ? `
                <div class="note-new">
                    <textarea id="noteDraft" class="upper-text" rows="3" maxlength="500" placeholder="AJOUTER UNE NOTE (EN MAJUSCULES)">${esc(state.noteDraft)}</textarea>
                    <div class="toolbar note-toolbar">
                        <span class="grow"></span>
                        <button type="button" class="btn btn-default" data-call-action="addNote">Ajouter la note</button>
                    </div>
                </div>` : ''}
            ${reportStarterHtml()}`;
    }

    // Formulaire : nouvel incident (call absent) ou modification d'une intervention / d'un incident
    function callFormHtml(c) {
        const isNew = !c;
        const kind = isNew ? 'incident' : c.kind;
        const unit = myUnit();
        const v = (key) => esc(c ? (c[key] ?? '') : '');
        const unitName = isNew ? (unit ? unit.name : 'Aucune unité : rejoignez une unité pour déclarer un incident') : c.unitName;
        const priorities = Object.entries(CALL_PRIORITY).map(([key, [, label]]) =>
            `<option value="${key}" ${c && c.priority === key ? 'selected' : ''}>${label}</option>`).join('');

        return `
            <form id="callForm" class="call-form" autocomplete="off" novalidate>
                <div class="toolbar">
                    <span class="hint-text">* champs obligatoires${isNew ? ' — votre unité sera automatiquement placée sur l\'incident.' : ''}</span>
                    <span class="grow"></span>
                    <button type="button" class="btn btn-small" data-fill-location title="Remplit l'adresse, le croisement et le bloc avec votre position actuelle">Position actuelle</button>
                </div>
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
                    <label class="lbl">Croisement<input name="crossStreet" type="text" maxlength="80" value="${v('crossStreet')}"></label>
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
        if (reports.draft) renderCallSelect(); // première ligne du rapport en cours de rédaction
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

    // Clic sur une ligne : affiche ses détails ; nouveau clic sur la même ligne : les masque
    $('#interventionsBody').addEventListener('click', (e) => {
        const tr = e.target.closest('tr[data-id]');
        if (!tr) return;
        const id = Number(tr.dataset.id);
        if (state.callPanel.id === id && state.callPanel.mode !== 'new') {
            state.callPanel = { mode: 'view', id: null };
            state.noteDraft = '';
            state.noteEdit = null;
            renderInterventionList();
            renderInterventionDetail();
            return;
        }
        openCall(id);
    });

    $('#newIncident').addEventListener('click', () => {
        if (!myUnit()) toast('Rejoignez une unité (onglet Unités) pour déclarer un incident.', 'error');
        state.callPanel = { mode: 'new', id: null };
        renderInterventionList();
        renderInterventionDetail();
    });

    $('#refreshInterventions').addEventListener('click', refreshInterventions);

    $('#interventionDetail').addEventListener('change', (e) => {
        if (e.target.id === 'callReportType') state.callReportType = e.target.value;
        if (e.target.id === 'callLinkChoice') state.linkChoice = e.target.value;
    });

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

        const linkOpen = e.target.closest('[data-link-open]');
        if (linkOpen) {
            openRecordInSearch(linkOpen.dataset.linkOpen, Number(linkOpen.dataset.id));
            return;
        }
        const linkRemove = e.target.closest('[data-link-remove]');
        if (linkRemove && call) {
            if (await callRequest('unlinkRecord', { id: call.id, kind: linkRemove.dataset.linkRemove, recordId: Number(linkRemove.dataset.id) }, 'Fiche retirée de l\'appel.')) {
                refreshInterventions();
            }
            return;
        }

        const openBtn = e.target.closest('[data-report-open]');
        if (openBtn) {
            showReportFromCall(Number(openBtn.dataset.reportOpen));
            return;
        }
        const modifyBtn = e.target.closest('[data-report-modify]');
        if (modifyBtn) {
            editReportFromCall(Number(modifyBtn.dataset.reportModify));
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
            if (action === 'writeReport') return startReportForCall(call.id, $('#callReportType').value);
            if (action === 'linkRecord') {
                const [kind, recordId] = String($('#callLinkChoice').value).split(':');
                if (await callRequest('linkRecord', { id: call.id, kind, recordId: Number(recordId) }, 'Fiche ajoutée à l\'appel.')) {
                    state.linkChoice = null;
                    refreshInterventions();
                }
                return;
            }

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
        // Indicatif régional de Géorgie compris entre 470 et 678 (identique à server.lua)
        const GEORGIA_AREA_CODES = [470, 478, 678];
        const phone = () => `${pick(GEORGIA_AREA_CODES)}-${int(200, 999)}-${String(int(0, 9999)).padStart(4, '0')}`;

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
    // RAPPORTS : DOT-523, Arrest Report, Incident Report, Citation,
    // Traffic Ticket, Ticket, Warning.
    // Les formulaires et les fiches sont construits à partir des modèles de
    // server/reports.lua (le serveur valide avec ces mêmes règles).
    // Les données d'un rapport en cours de rédaction sont gardées dans
    // reports.draft.data ; chaque champ y est relié par son chemin (data-path,
    // ex : "units.0.occupants.1.name").
    // =====================================================================
    const reports = {
        types: [],          // modèles, dans l'ordre d'affichage
        byId: {},
        index: {},          // [type] = { [clé] = champ } (premier niveau)
        list: [],
        selected: null,     // id du rapport affiché à droite
        current: null,      // rapport affiché (complet)
        draft: null,        // { id (null = nouveau), type, data }
        lookups: [],        // boutons "Remplir depuis..." du formulaire affiché
        queryTimer: null,
    };

    const DATA_TYPES = ['text', 'area', 'date', 'time', 'num', 'select', 'check', 'checks'];

    const pathGet = (obj, path) => path.split('.').reduce((o, k) => (o == null ? undefined : o[k]), obj);
    function pathSet(obj, path, value) {
        const keys = path.split('.');
        const last = keys.pop();
        const target = keys.reduce((o, k) => (o == null ? undefined : o[k]), obj);
        if (target != null) target[last] = value;
    }

    // Condition "show" / "reqIf" : { k, eq } | { k, any: [] } | { k, none: [] }
    function condMet(cond, obj) {
        const value = obj ? obj[cond.k] : undefined;
        const list = Array.isArray(value) ? value : [];
        if (cond.any) return list.some((v) => toArray(cond.any).includes(v));
        if (cond.none) return !list.some((v) => toArray(cond.none).includes(v));
        return value === cond.eq;
    }
    const visible = (f, obj) => !f.show || condMet(f.show, obj);
    const isRequired = (f, obj) => !!f.req || (!!f.reqIf && condMet(f.reqIf, obj));
    const optionLabel = (options, value) => {
        const found = toArray(options).find((o) => o[0] === value);
        return found ? found[1] : value;
    };

    // Index des champs du premier niveau (listes sources des tableaux "par Unit")
    function indexFields(fields, index) {
        toArray(fields).forEach((f) => {
            if (f.t === 'group') indexFields(f.f, index);
            else if (f.k) index[f.k] = f;
        });
        return index;
    }

    // ---- Valeurs par défaut d'un nouveau rapport / d'un nouvel élément de liste ----
    function defaultValue(f) {
        const now = new Date();
        if (f.def === 'today') return dateString(now);
        if (f.def === 'now') return `${pad(now.getHours())}:${pad(now.getMinutes())}`;
        if (f.def === 'unitDept') {
            const unit = myUnit();
            return unit && DEPARTMENTS[unit.dept] ? DEPARTMENTS[unit.dept].label : '';
        }
        if (f.def != null) return String(f.def);
        if (f.t === 'check') return false;
        if (f.t === 'checks') return [];
        return '';
    }

    function newObject(fields, obj = {}) {
        toArray(fields).forEach((f) => {
            if (f.t === 'group') newObject(f.f, obj);
            else if (f.t === 'list') obj[f.k] = Array.from({ length: f.min || 0 }, () => newObject(f.f));
            else if (f.k && DATA_TYPES.includes(f.t)) obj[f.k] = defaultValue(f);
        });
        return obj;
    }

    // Rapport existant : listes et cases multiples toujours en tableaux (Lua peut envoyer {})
    function normalizeFields(fields, obj, root) {
        toArray(fields).forEach((f) => {
            if (f.t === 'group') normalizeFields(f.f, obj, root);
            else if (f.t === 'list') {
                obj[f.k] = toArray(obj[f.k]).map((item) => normalizeFields(f.f, item && typeof item === 'object' ? item : {}, root));
            } else if (f.t === 'checks') obj[f.k] = toArray(obj[f.k]);
            else if (f.t === 'matrix') toArray(root[f.list]).forEach((item) => { item[f.k] = toArray(item[f.k]); });
            else if (f.t === 'check') obj[f.k] = obj[f.k] === true;
            else if (f.k && DATA_TYPES.includes(f.t) && obj[f.k] == null) obj[f.k] = '';
        });
        return obj;
    }

    const sectionsOf = (type) => toArray(type.sections);
    // Copie normalisée des données d'un rapport enregistré
    const reportData = (type, report) => {
        const data = JSON.parse(JSON.stringify(report.data || {}));
        return normalizeFields(allFields(type), data, data);
    };
    const allFields = (type) => sectionsOf(type).flatMap((s) => toArray(s.f));

    // Clés des champs d'un niveau (pour limiter le remplissage depuis une fiche)
    function fieldKeys(fields, keys = new Set()) {
        toArray(fields).forEach((f) => {
            if (f.t === 'group') fieldKeys(f.f, keys);
            else if (f.k) keys.add(f.k);
        });
        return keys;
    }

    // ---------------------------------------------------------------------
    // Formulaire
    // ---------------------------------------------------------------------
    function inputHtml(f, value, path) {
        const v = value ?? '';
        const attrs = `data-path="${esc(path)}" data-t="${esc(f.t)}"`;
        switch (f.t) {
            case 'area':
                return `<textarea ${attrs} rows="${f.rows || 3}" maxlength="${f.max || 2000}">${esc(v)}</textarea>`;
            case 'date':
                return `<input type="text" ${attrs} class="date-input" maxlength="10" placeholder="JJ/MM/AAAA" value="${esc(v)}">`;
            case 'time':
                return `<input type="text" ${attrs} class="time-input" maxlength="5" placeholder="HH:MM" value="${esc(v)}">`;
            case 'num':
                return `<input type="text" ${attrs} class="digits" maxlength="${String(f.max ?? 999999999).length}" placeholder="${esc(f.money ? '$' : (f.unit || ''))}" value="${esc(v)}">`;
            case 'select':
                return `<select ${attrs}><option value="">— Choisir —</option>${toArray(f.o).map(([key, label]) =>
                    `<option value="${esc(key)}" ${key === v ? 'selected' : ''}>${esc(label)}</option>`).join('')}</select>`;
            case 'check':
                return `<input type="checkbox" ${attrs} ${v === true ? 'checked' : ''}>`;
            default:
                return `<input type="text" ${attrs} maxlength="${f.max || 80}" ${f.upper ? 'class="upper"' : ''} placeholder="${esc(f.ph || '')}" value="${esc(v)}">`;
        }
    }

    function fieldHtml(f, obj, path, suggestId) {
        const span = f.w > 1 ? ` span-${Math.min(f.w, 4)}` : '';
        const required = isRequired(f, obj) ? ' *' : '';
        const key = path + f.k;

        // Nom de famille / immatriculation : liste déroulante de l'historique des recherches
        if (suggestId != null) {
            const input = inputHtml({ ...f, ph: 'Tapez ou choisissez dans l\'historique' }, obj[f.k], key)
                .replace('<input ', `<input data-suggest="${suggestId}" `);
            return `<label class="lbl${span}"><span>${esc(f.l)}${required} <span class="suggest-hint">&#9662; historique</span></span>${input}</label>`;
        }

        if (f.t === 'check') {
            return `<label class="check rp-check${span}">${inputHtml(f, obj[f.k], key)} ${esc(f.l)}${required}</label>`;
        }
        if (f.t === 'checks') {
            const selected = toArray(obj[f.k]);
            return `
                <div class="lbl span-4">
                    <span>${esc(f.l)}${required}${f.ph ? ` <span class="hint-text">(${esc(f.ph)})</span>` : ''}</span>
                    <div class="checks">${toArray(f.o).map(([value, label]) => `
                        <label class="check"><input type="checkbox" data-path="${esc(key)}" data-t="checks" value="${esc(value)}" ${selected.includes(value) ? 'checked' : ''}> ${esc(label)}</label>`).join('')}
                    </div>
                </div>`;
        }
        if (f.t === 'note') return `<div class="hint-box span-4">${esc(f.l)}</div>`;
        return `<label class="lbl${span}">${esc(f.l)}${f.unit ? ` (${esc(f.unit)})` : ''}${required}${inputHtml(f, obj[f.k], key)}</label>`;
    }

    // Suite de champs : les champs simples sont regroupés dans une grille de 4 colonnes,
    // les groupes / listes / tableaux forment des blocs à part.
    function blocksHtml(fields, obj, path) {
        let html = '';
        let grid = '';
        const flush = () => {
            if (grid) html += `<div class="form-grid cols-4">${grid}</div>`;
            grid = '';
        };

        // "lookup" : rien à afficher, mais le champ ancre (nom de famille ou immatriculation)
        // de ce niveau ouvre la liste de l'historique des recherches
        const anchors = {};
        toArray(fields).forEach((f) => {
            if (f.t !== 'lookup') return;
            const source = f.kind === 'identity' ? 'lastname' : 'plate';
            const anchor = Object.keys(f.map).find((key) => f.map[key] === source);
            anchors[anchor] = reports.lookups.push({ f, ctx: path, keys: fieldKeys(fields) }) - 1;
        });

        toArray(fields).forEach((f) => {
            if (!visible(f, obj)) return;
            if (f.t === 'group') {
                flush();
                html += `<div class="subgroup"><span class="subgroup-title">${esc(f.l)}</span>${blocksHtml(f.f, obj, path)}</div>`;
            } else if (f.t === 'list') {
                flush();
                html += listHtml(f, obj, path);
            } else if (f.t === 'matrix' || f.t === 'perUnit') {
                flush();
                html += unitTableHtml(f);
            } else if (f.t !== 'lookup') {
                grid += fieldHtml(f, obj, path, anchors[f.k]);
            }
        });
        flush();
        return html;
    }

    function listHtml(f, obj, path) {
        const items = toArray(obj[f.k]);
        const key = path + f.k;
        const min = f.min || 0;
        const max = f.max || 20;
        return `
            <div class="subgroup">
                <span class="subgroup-title">${esc(f.l)}${min ? ' *' : ''}</span>
                <div class="entries">${items.map((item, i) => `
                    <div class="entry-box">
                        <div class="entry-head">
                            <span class="entry-title">${esc(f.item)} ${i + 1}</span>
                            ${items.length > min ? `<button type="button" class="win-btn entry-remove" data-list-remove="${esc(key)}" data-index="${i}" title="Retirer">&#10005;</button>` : ''}
                        </div>
                        ${blocksHtml(f.f, item, `${key}.${i}.`)}
                    </div>`).join('')}
                </div>
                <div class="toolbar entries-toolbar">
                    ${items.length ? '' : `<span class="hint-text">Aucun élément.</span>`}
                    <span class="grow"></span>
                    ${items.length < max ? `<button type="button" class="btn" data-list-add="${esc(key)}">${esc(f.add || '+ Ajouter')}</button>` : ''}
                </div>
            </div>`;
    }

    // Tableau "une colonne par Unit" : causes du crash (matrix) ou informations véhicules (perUnit)
    function unitTableHtml(f) {
        const units = toArray(reports.draft.data[f.list]);
        const source = reports.index[reports.draft.type][f.list] || {};
        const head = `<tr><th></th>${units.map((u, i) => `<th class="mx-cell">${esc(source.item || '')} ${i + 1}</th>`).join('')}</tr>`;
        let body;

        if (f.t === 'matrix') {
            body = toArray(f.groups).map((group) => `
                <tr class="mx-group"><td colspan="${units.length + 1}">${esc(group.l)}</td></tr>
                ${toArray(group.o).map(([value, label]) => `
                    <tr>
                        <td>${esc(label)}</td>
                        ${units.map((u, i) => `<td class="mx-cell"><input type="checkbox" data-path="${esc(`${f.list}.${i}.${f.k}`)}" data-t="checks" value="${esc(value)}" ${toArray(u[f.k]).includes(value) ? 'checked' : ''}></td>`).join('')}
                    </tr>`).join('')}`).join('');
        } else {
            body = toArray(f.f).map((sub) => `
                <tr>
                    <td>${esc(sub.l)}${sub.unit ? ` (${esc(sub.unit)})` : ''}</td>
                    ${units.map((u, i) => `<td class="mx-cell">${visible(sub, u)
                        ? inputHtml(sub, u[sub.k], `${f.list}.${i}.${sub.k}`)
                        : '<span class="muted" title="Sans véhicule">—</span>'}</td>`).join('')}
                </tr>`).join('');
        }

        return `
            <div class="subgroup">
                <span class="subgroup-title">${esc(f.l)}</span>
                ${units.length
                    ? `<div class="mx-wrap"><table class="grid matrix">${head}${body}</table></div>`
                    : '<span class="hint-text">Ajoutez d\'abord une unit (section 1).</span>'}
            </div>`;
    }

    function renderReportForm() {
        const draft = reports.draft;
        const type = reports.byId[draft.type];
        const scroller = $('#reportForm');
        const top = scroller.scrollTop;
        reports.lookups = [];
        scroller.innerHTML = sectionsOf(type).map((section) => `
            <div class="report-section">
                <div class="report-section-title">${esc(section.title)}</div>
                ${blocksHtml(section.f, draft.data, '')}
            </div>`).join('');
        scroller.scrollTop = top;
    }

    // Intervention par défaut d'un nouveau rapport : la plus récente sur laquelle est l'unité du joueur
    function defaultCallRef() {
        const unit = myUnit();
        const call = unit && state.interventions.find((c) => !c.closed && toArray(c.units).some((u) => u.id === unit.id));
        return call ? String(call.id) : '';
    }

    // report : rapport existant (modification) ; callId : intervention choisie depuis l'onglet Interventions
    function openReportEditor(typeId, report, callId) {
        const type = reports.byId[typeId];
        if (!type) return;
        const data = report ? reportData(type, report) : newObject(allFields(type));
        let callRef = callId != null ? String(callId) : defaultCallRef();
        if (report) callRef = report.callLive && report.call ? String(report.call.id) : 'keep';

        reports.draft = {
            id: report ? report.id : null, type: typeId, data, callRef,
            call: report && report.call && report.call.number ? report.call : null, // lien actuel (modification)
        };
        $('#reportEditorTitle').textContent = report ? `Modification — ${type.label} n°${report.number}` : `Nouveau rapport — ${type.label}`;
        $('#reportsBrowse').classList.add('hidden');
        $('#reportEditor').classList.remove('hidden');
        $('#reportForm').scrollTop = 0;
        renderCallSelect();
        renderReportForm();
        refreshInterventions(); // liste à jour pour la première ligne
    }

    function closeReportEditor() {
        reports.draft = null;
        hideSuggest();
        $('#reportEditor').classList.add('hidden');
        $('#reportsBrowse').classList.remove('hidden');
    }

    // Première ligne : intervention / incident lié, en cours ou terminé
    // "12-3456 — [Incident] Course-poursuite — Route 68 (14:32)"
    const callOption = (c, selected) =>
        `<option value="${esc(c.id)}" ${selected ? 'selected' : ''}>${esc(c.number)} — ${c.kind === 'incident' ? '[Incident] ' : ''}${esc(c.title)} — ${esc(c.address)} (${esc(formatTime(c.createdAt))})</option>`;

    function renderCallSelect() {
        const draft = reports.draft;
        const select = $('#reportCallSelect');
        if (!draft || document.activeElement === select) return; // ne pas fermer la liste ouverte
        const open = state.interventions.filter((c) => !c.closed);
        const closed = state.interventions.filter((c) => c.closed);
        const keep = draft.id
            ? `<option value="keep" ${draft.callRef === 'keep' ? 'selected' : ''}>${draft.call
                ? `${esc(draft.call.number)} — ${esc(draft.call.title)} (lien actuel, intervention archivée)`
                : 'Aucune (rapport rédigé avant les liens)'}</option>`
            : '';
        $('#reportCallHint').textContent = state.interventions.length
            ? 'Interventions et incidents en cours ou terminés : le rapport apparaîtra dans leur déroulé.'
            : 'Aucune intervention ni aucun incident pour le moment : déclarez un incident (onglet Interventions) ou créez une intervention (Créations).';
        select.innerHTML = `<option value="">— Choisir dans la liste —</option>${keep}
            ${open.length ? `<optgroup label="En attente / en cours">${open.map((c) => callOption(c, draft.callRef === String(c.id))).join('')}</optgroup>` : ''}
            ${closed.length ? `<optgroup label="Terminées">${closed.map((c) => callOption(c, draft.callRef === String(c.id))).join('')}</optgroup>` : ''}`;
        // Intervention choisie disparue de la liste : on revient au choix vide
        if (select.value !== draft.callRef) draft.callRef = select.value;
    }

    $('#reportCallSelect').addEventListener('change', (e) => {
        if (!reports.draft) return;
        reports.draft.callRef = e.target.value;
        e.target.classList.remove('invalid');
    });

    // Entrée dans un champ : ne doit pas enregistrer le rapport par erreur
    $('#reportEditor').addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && e.target instanceof HTMLInputElement) e.preventDefault();
    });

    // Depuis l'onglet Interventions : rédiger / ouvrir / modifier un rapport lié
    function draftInProgress() {
        if (!reports.draft) return false;
        showPage('reports');
        toast('Un rapport est déjà en cours de rédaction : enregistrez-le ou annulez-le d\'abord.', 'error');
        return true;
    }

    async function startReportForCall(callId, typeId) {
        if (draftInProgress() || !(await loadReportTypes())) return;
        showPage('reports');
        openReportEditor(typeId, null, callId);
    }

    async function showReportFromCall(id) {
        if (draftInProgress() || !(await loadReportTypes())) return;
        showPage('reports');
        openReport(id);
    }

    async function editReportFromCall(id) {
        if (draftInProgress() || !(await loadReportTypes())) return;
        const res = await post('getReport', { id });
        if (!res || !res.ok) {
            toast(res?.error || 'Rapport introuvable.', 'error');
            return;
        }
        if (!res.report.mine) {
            toast(`Seul l'auteur du rapport (${res.report.createdByName || '?'}) peut le modifier.`, 'error');
            return;
        }
        showPage('reports');
        openReportEditor(res.report.type, res.report);
    }

    // ---- Saisie : les champs texte mettent à jour les données sans tout redessiner ----
    // (écouteur posé sur document APRÈS celui des formats automatiques : la valeur est déjà formatée)
    document.addEventListener('input', (e) => {
        const el = e.target;
        if (!reports.draft || !el.dataset || !el.dataset.path || !el.closest('#reportForm')) return;
        el.classList.remove('invalid');
        if (el.type !== 'checkbox' && el.tagName !== 'SELECT') pathSet(reports.draft.data, el.dataset.path, el.value);
        if (el.dataset.suggest != null) showSuggest(el);
    });

    // Cases / listes déroulantes : peuvent afficher ou masquer d'autres champs -> on redessine
    $('#reportForm').addEventListener('change', (e) => {
        const el = e.target;
        const path = el.dataset && el.dataset.path;
        if (!path || !reports.draft) return;

        if (el.dataset.t === 'check') {
            pathSet(reports.draft.data, path, el.checked);
        } else if (el.dataset.t === 'checks') {
            const current = toArray(pathGet(reports.draft.data, path));
            const next = el.checked ? [...new Set([...current, el.value])] : current.filter((v) => v !== el.value);
            pathSet(reports.draft.data, path, next);
        } else if (el.tagName === 'SELECT') {
            pathSet(reports.draft.data, path, el.value);
        } else {
            return;
        }
        renderReportForm();
    });

    $('#reportForm').addEventListener('click', (e) => {
        const draft = reports.draft;
        if (!draft) return;

        const add = e.target.closest('[data-list-add]');
        if (add) {
            const path = add.dataset.listAdd;
            const spec = findListSpec(reports.byId[draft.type], path);
            const list = toArray(pathGet(draft.data, path));
            list.push(newObject(spec ? spec.f : []));
            pathSet(draft.data, path, list);
            renderReportForm();
            return;
        }

        const remove = e.target.closest('[data-list-remove]');
        if (remove) {
            const path = remove.dataset.listRemove;
            const list = toArray(pathGet(draft.data, path));
            list.splice(Number(remove.dataset.index), 1);
            pathSet(draft.data, path, list);
            renderReportForm();
            return;
        }
    });

    // Retrouve la définition d'une liste à partir de son chemin (ex : "units.0.occupants")
    function findListSpec(type, path) {
        let fields = allFields(type);
        let spec = null;
        path.split('.').filter((part) => !/^\d+$/.test(part)).forEach((key) => {
            const flat = [];
            const walk = (list) => toArray(list).forEach((f) => (f.t === 'group' ? walk(f.f) : flat.push(f)));
            walk(fields);
            spec = flat.find((f) => f.k === key && f.t === 'list') || null;
            fields = spec ? spec.f : [];
        });
        return spec;
    }

    // ---- Remplissage depuis l'historique de l'onglet "Recherches" ----
    // Sur le nom de famille (identités) ou l'immatriculation (véhicules), une liste déroulante
    // propose les fiches déjà recherchées ; en choisir une remplit tous les champs liés.
    function lookupValue(record, source) {
        switch (source) {
            case 'makeModel': return [record.make, record.model].filter(Boolean).join(' ');
            case 'ownerFull': return record.ownerIdentity ? fullName(record.ownerIdentity) : (record.ownerName || '');
            case 'insurance':
                return record.insuranceStatus === 'none'
                    ? 'Non-Assuré'
                    : [record.insuranceCompany, record.insurancePolicy, INSURANCE_LABELS[record.insuranceStatus]].filter(Boolean).join(' — ');
            default: return record[source] ?? '';
        }
    }

    const suggest = { input: null, entry: null, items: [], active: 0 };
    const suggestBox = $('#suggestBox');

    function suggestMatches(entry, text) {
        const kind = entry.f.kind;
        const query = text.trim().toLowerCase();
        return state.searchResults.filter((r) => {
            if (r.kind !== kind) return false;
            if (!query) return true;
            if (kind === 'vehicle') return String(r.plate || '').toLowerCase().includes(query.replace(/[^a-z0-9]/g, ''));
            return String(r.lastname || '').toLowerCase().startsWith(query) || fullName(r).toLowerCase().includes(query);
        }).slice(0, 8);
    }

    const suggestLabel = (r) => (r.kind === 'vehicle'
        ? `<b>${esc(r.plate)}</b> — ${esc([r.make, r.model].filter(Boolean).join(' '))}<span class="muted"> — ${esc(r.ownerIdentity ? fullName(r.ownerIdentity) : (r.ownerName || 'propriétaire inconnu'))}</span>`
        : `<b>${esc(String(r.lastname).toUpperCase())}</b> ${esc([r.firstname, r.middlename].filter(Boolean).join(' '))} — ${esc(r.dob)}<span class="muted"> — SSN ${esc(r.ssn || '-')}</span>`);

    function showSuggest(input) {
        const entry = reports.lookups[Number(input.dataset.suggest)];
        if (!entry) return;
        suggest.input = input;
        suggest.entry = entry;
        suggest.items = suggestMatches(entry, input.value);
        suggest.active = 0;

        const hasHistory = state.searchResults.some((r) => r.kind === entry.f.kind);
        suggestBox.innerHTML = `<div class="suggest-title">Historique des recherches — ${entry.f.kind === 'vehicle' ? 'véhicules' : 'identités'}</div>${
            suggest.items.length
                ? suggest.items.map((r, i) => `<div class="suggest-item ${i === 0 ? 'active' : ''}" data-index="${i}">${suggestLabel(r)}</div>`).join('')
                : `<div class="suggest-empty">${hasHistory ? 'Aucune fiche correspondante dans l\'historique.' : 'Historique vide : recherchez d\'abord la fiche dans l\'onglet « Recherches ».'}</div>`}`;

        const rect = input.getBoundingClientRect();
        suggestBox.style.left = `${Math.round(rect.left)}px`;
        suggestBox.style.top = `${Math.round(rect.bottom + 2)}px`;
        suggestBox.style.width = `${Math.round(Math.max(rect.width, 360))}px`;
        suggestBox.classList.remove('hidden');
    }

    function hideSuggest() {
        suggestBox.classList.add('hidden');
        suggest.input = null;
        suggest.entry = null;
    }

    function applySuggestion(record) {
        const { f, ctx, keys } = suggest.entry;
        const obj = ctx ? pathGet(reports.draft.data, ctx.slice(0, -1)) : reports.draft.data;
        Object.entries(f.map).forEach(([to, from]) => {
            const value = lookupValue(record, from);
            if (keys.has(to) && value !== '' && value != null) obj[to] = typeof value === 'number' ? String(value) : value;
        });
        hideSuggest();
        renderReportForm();
        toast(record.kind === 'vehicle' ? `Véhicule ${record.plate} repris de l'historique.` : `${fullName(record)} repris de l'historique.`, 'success');
    }

    function moveSuggest(step) {
        if (!suggest.items.length) return;
        suggest.active = (suggest.active + step + suggest.items.length) % suggest.items.length;
        suggestBox.querySelectorAll('.suggest-item').forEach((el, i) => el.classList.toggle('active', i === suggest.active));
    }

    $('#reportForm').addEventListener('focusin', (e) => {
        if (e.target.dataset && e.target.dataset.suggest != null) showSuggest(e.target);
    });
    $('#reportForm').addEventListener('focusout', (e) => {
        if (e.target === suggest.input) hideSuggest();
    });
    $('#reportForm').addEventListener('scroll', hideSuggest);
    $('#reportForm').addEventListener('keydown', (e) => {
        if (!suggest.input || e.target !== suggest.input || suggestBox.classList.contains('hidden')) return;
        if (e.key === 'ArrowDown') { e.preventDefault(); moveSuggest(1); }
        else if (e.key === 'ArrowUp') { e.preventDefault(); moveSuggest(-1); }
        else if (e.key === 'Enter' && suggest.items.length) { e.preventDefault(); applySuggestion(suggest.items[suggest.active]); }
        else if (e.key === 'Escape') { e.stopPropagation(); hideSuggest(); } // Échap ferme la liste, pas le MDC
    });
    // mousedown (et non click) : le champ ne perd pas le focus avant le choix
    suggestBox.addEventListener('mousedown', (e) => {
        e.preventDefault();
        const item = e.target.closest('.suggest-item');
        if (item && suggest.entry) applySuggestion(suggest.items[Number(item.dataset.index)]);
    });

    // ---- Vérification avant envoi (le serveur revérifie avec les mêmes règles) ----
    const dateNum = (str) => {
        const m = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(str || '');
        return m ? Number(m[3]) * 10000 + Number(m[2]) * 100 + Number(m[1]) : null;
    };

    function checkValue(f, value, obj) {
        const required = isRequired(f, obj);
        if (f.t === 'check') return required && value !== true ? 'case obligatoire.' : null;
        if (f.t === 'checks') return required && !toArray(value).length ? 'cochez au moins une case.' : null;

        const str = String(value ?? '').trim();
        if (str === '') return required ? 'champ obligatoire.' : null;
        if (f.t === 'date') {
            const n = dateNum(str);
            const d = n && Number(str.slice(0, 2));
            const m = n && Number(str.slice(3, 5));
            if (!n || d < 1 || d > 31 || m < 1 || m > 12) return 'date invalide (JJ/MM/AAAA).';
            if (f.past && n > dateNum(dateString(new Date()))) return 'la date ne peut pas être dans le futur.';
        }
        if (f.t === 'time' && !/^([01]\d|2[0-3]):[0-5]\d$/.test(str)) return 'horaire invalide (HH:MM).';
        if (f.t === 'num') {
            const n = Number(str);
            if (!/^\d+$/.test(str) || (f.min != null && n < f.min) || (f.max != null && n > f.max)) {
                return `nombre entier attendu (${f.min ?? 0} à ${f.max ?? 999999999}).`;
            }
        }
        return null;
    }

    function validateFields(fields, obj, path, crumb) {
        for (const f of toArray(fields)) {
            if (!visible(f, obj)) continue;
            let error = null;

            if (f.t === 'group') {
                error = validateFields(f.f, obj, path, crumb);
            } else if (f.t === 'list') {
                const items = toArray(obj[f.k]);
                for (let i = 0; i < items.length && !error; i += 1) {
                    error = validateFields(f.f, items[i], `${path}${f.k}.${i}.`, [...crumb, `${f.item} ${i + 1}`]);
                }
                if (!error && items.length < (f.min || 0)) {
                    error = { path: null, message: `${f.l} : ajoutez au moins ${f.min} ${String(f.item).toLowerCase()}.` };
                }
            } else if (f.t === 'perUnit') {
                const source = reports.index[reports.draft.type][f.list] || {};
                toArray(reports.draft.data[f.list]).forEach((unit, i) => {
                    toArray(f.f).forEach((sub) => {
                        if (error || !visible(sub, unit)) return;
                        const message = checkValue(sub, unit[sub.k], unit);
                        if (message) error = { path: `${f.list}.${i}.${sub.k}`, message: `${[...crumb, `${source.item} ${i + 1}`, sub.l].join(' › ')} : ${message}` };
                    });
                });
            } else if (f.k && DATA_TYPES.includes(f.t)) {
                const message = checkValue(f, obj[f.k], obj);
                if (message) error = { path: path + f.k, message: `${[...crumb, f.l].join(' › ')} : ${message}` };
            }
            if (error) return error;
        }
        return null;
    }

    function validateDraft() {
        const type = reports.byId[reports.draft.type];
        for (const section of sectionsOf(type)) {
            const error = validateFields(section.f, reports.draft.data, '', [section.title]);
            if (error) return error;
        }
        return null;
    }

    function showFieldError(error) {
        toast(error.message, 'error');
        const el = error.path && $(`#reportForm [data-path="${CSS.escape(error.path)}"]`);
        if (el) {
            el.classList.add('invalid');
            el.scrollIntoView({ block: 'center' });
            el.focus();
        }
    }

    $('#reportEditor').addEventListener('submit', async (e) => {
        e.preventDefault();
        const draft = reports.draft;
        if (!draft) return;

        if (!draft.callRef) {
            toast('Choisissez l\'intervention ou l\'incident lié au rapport (première ligne).', 'error');
            const select = $('#reportCallSelect');
            select.classList.add('invalid');
            select.focus();
            return;
        }
        const error = validateDraft();
        if (error) {
            showFieldError(error);
            return;
        }

        const submit = $('#reportSubmit');
        submit.disabled = true;
        const res = await post('saveReport', { id: draft.id, type: draft.type, data: draft.data, callRef: draft.callRef });
        submit.disabled = false;
        if (!res || !res.ok) {
            toast(res?.error || 'Erreur lors de l\'enregistrement du rapport.', 'error');
            return;
        }

        toast(`Rapport n°${res.number} enregistré.`, 'success');
        closeReportEditor();
        reports.selected = res.id;
        await refreshReports();
        openReport(res.id);
    });

    // "Annuler" : deuxième clic pour confirmer (le brouillon est perdu)
    $('#reportCancel').addEventListener('click', (e) => {
        const btn = e.currentTarget;
        if (!btn.dataset.confirm) {
            btn.dataset.confirm = '1';
            btn.textContent = 'Abandonner le rapport ?';
            setTimeout(() => {
                delete btn.dataset.confirm;
                btn.textContent = 'Annuler';
            }, 3000);
            return;
        }
        delete btn.dataset.confirm;
        btn.textContent = 'Annuler';
        closeReportEditor();
    });

    // ---------------------------------------------------------------------
    // Fiche d'un rapport (lecture)
    // Seuls les champs remplis sont affichés.
    // ---------------------------------------------------------------------
    function valueHtml(f, value) {
        if (f.t === 'check') return value === true ? 'Oui' : '';
        if (f.t === 'checks') return toArray(value).map((v) => esc(optionLabel(f.o, v))).join(', ');
        if (value === '' || value == null) return '';
        if (f.t === 'select') return esc(optionLabel(f.o, value));
        if (f.t === 'num' && f.money) return `$${esc(Number(value).toLocaleString('en-US'))}`;
        if (f.t === 'num' && f.unit) return `${esc(value)} ${esc(f.unit)}`;
        return esc(value);
    }

    function viewBlocks(fields, obj, root, type) {
        let html = '';
        let rows = '';
        const flush = () => {
            if (rows) html += `<dl class="sheet">${rows}</dl>`;
            rows = '';
        };

        toArray(fields).forEach((f) => {
            if (!visible(f, obj)) return;
            if (f.t === 'group') {
                const inner = viewBlocks(f.f, obj, root, type);
                if (inner) {
                    flush();
                    html += `<div class="view-group">${esc(f.l)}</div>${inner}`;
                }
            } else if (f.t === 'list') {
                flush();
                const items = toArray(obj[f.k]);
                const moneyField = toArray(f.f).find((sub) => sub.money);
                html += `<div class="view-group">${esc(f.l)} (${items.length})</div>`;
                html += items.length
                    ? items.map((item, i) => `
                        <div class="entry-view">
                            <div class="entry-view-title">${esc(f.item)} ${i + 1}</div>
                            ${viewBlocks(f.f, item, root, type) || '<div class="fold-empty">Aucune information.</div>'}
                        </div>`).join('')
                    : '<div class="fold-empty">Aucun élément.</div>';
                if (moneyField && items.length) {
                    const total = items.reduce((sum, item) => sum + (Number(item[moneyField.k]) || 0), 0);
                    html += `<div class="view-total">Total : $${esc(total.toLocaleString('en-US'))}</div>`;
                }
            } else if (f.t === 'matrix' || f.t === 'perUnit') {
                flush();
                html += unitViewHtml(f, root, type);
            } else if (f.k && DATA_TYPES.includes(f.t)) {
                const value = valueHtml(f, obj[f.k]);
                if (value) rows += dd(f.l, value);
            }
        });
        flush();
        return html;
    }

    function unitViewHtml(f, root, type) {
        const units = toArray(root[f.list]);
        const source = reports.index[type.id][f.list] || {};
        if (!units.length) return '';

        if (f.t === 'matrix') {
            const all = toArray(f.groups).flatMap((g) => toArray(g.o));
            return `<div class="view-group">${esc(f.l)}</div><dl class="sheet">${units.map((u, i) => {
                const labels = toArray(u[f.k]).map((v) => optionLabel(all, v));
                return dd(`${source.item} ${i + 1}`, labels.length ? esc(labels.join(', ')) : '<span class="muted">Aucune cause cochée</span>');
            }).join('')}</dl>`;
        }

        const rows = toArray(f.f).map((sub) => {
            const cells = units.map((u) => (visible(sub, u) ? valueHtml(sub, u[sub.k]) : '') || '-');
            return cells.every((c) => c === '-') ? '' : `<tr><td>${esc(sub.l)}</td>${cells.map((c) => `<td>${c}</td>`).join('')}</tr>`;
        }).join('');
        return rows ? `
            <div class="view-group">${esc(f.l)}</div>
            <div class="mx-wrap"><table class="grid matrix">
                <tr><th></th>${units.map((u, i) => `<th>${esc(source.item)} ${i + 1}</th>`).join('')}</tr>
                ${rows}
            </table></div>` : '';
    }

    function reportViewHtml(r) {
        const type = reports.byId[r.type];
        if (!type) return '<div class="empty">Type de rapport inconnu.</div>';
        const data = reportData(type, r);

        return `
            <div class="sheet-title">
                <span>${esc(type.label)} — n°${esc(r.number)}</span>
                ${r.mine ? '<button type="button" class="btn btn-small" data-report-edit>Modifier</button>' : ''}
            </div>
            <div class="report-meta">
                Rédigé par <b>${esc(r.createdByName || '-')}</b>${r.unitName ? ` (${esc(r.unitName)})` : ''} le ${esc(formatDate(r.createdAt))}
                ${r.updatedAt ? `<br>Modifié le ${esc(formatDate(r.updatedAt))}` : ''}
            </div>
            <div class="report-link">
                <span>Intervention liée : ${r.call && r.call.number
                    ? `<b>${esc(r.call.number)} — ${esc(r.call.title)}</b>${r.call.kind === 'incident' ? ' (incident)' : ''}${r.callLive ? '' : ' <span class="muted">(archivée)</span>'}`
                    : '<span class="muted">aucune</span>'}</span>
                ${r.callLive ? `<button type="button" class="btn btn-small" data-goto-call="${esc(r.call.id)}">Voir l'intervention</button>` : ''}
            </div>
            ${sectionsOf(type).map((section) => {
                const body = viewBlocks(section.f, data, data, type);
                return body ? `<div class="report-section-title">${esc(section.title)}</div>${body}` : '';
            }).join('')}`;
    }

    // ---------------------------------------------------------------------
    // Liste des rapports
    // ---------------------------------------------------------------------
    function renderReportList() {
        const list = reports.list;
        $('#reportsCount').textContent = `(${list.length})`;
        $('#reportsEmpty').classList.toggle('hidden', list.length > 0);
        $('#reportsBody').innerHTML = list.map((r) => `
            <tr data-id="${esc(r.id)}" class="${r.id === reports.selected ? 'selected' : ''}">
                <td>${esc(r.number)}</td>
                <td>${esc(reports.byId[r.type] ? reports.byId[r.type].short : r.type)}</td>
                <td>${esc(r.callNumber || '-')}</td>
                <td class="cell-ellipsis">${esc(r.summary || '-')}</td>
                <td>${esc(formatDate(r.createdAt))}</td>
            </tr>`).join('');
    }

    async function refreshReports() {
        const res = await post('getReports', {
            type: $('#reportFilter').value,
            query: $('#reportQuery').value.trim(),
            mine: $('#reportMine').checked,
        });
        if (!res || !res.ok) {
            toast(res?.error || 'Impossible de charger les rapports.', 'error');
            return;
        }
        reports.list = toArray(res.reports);
        renderReportList();
    }

    async function openReport(id) {
        reports.selected = id;
        renderReportList();
        const detail = $('#reportDetail');
        const res = await post('getReport', { id });
        if (!res || !res.ok) {
            detail.innerHTML = `<div class="empty">${esc(res?.error || 'Rapport introuvable.')}</div>`;
            return;
        }
        reports.current = res.report;
        detail.innerHTML = reportViewHtml(res.report);
    }

    async function loadReportTypes() {
        if (reports.types.length) return true;
        const res = await post('getReportTypes');
        if (!res || !res.ok) {
            $('#reportTypeButtons').innerHTML = `<span class="hint-text">${esc(res?.error || 'Modèles indisponibles.')}</span>`;
            return false;
        }
        reports.types = toArray(res.types);
        reports.types.forEach((type) => {
            reports.byId[type.id] = type;
            reports.index[type.id] = indexFields(allFields(type), {});
        });
        $('#reportTypeButtons').innerHTML = reports.types.map((type) =>
            `<button type="button" class="btn" data-report-type="${esc(type.id)}" title="${esc(type.label)}">${esc(type.button || type.label)}</button>`).join('');
        $('#reportFilter').innerHTML = '<option value="">Tous les types</option>'
            + reports.types.map((type) => `<option value="${esc(type.id)}">${esc(type.short)}</option>`).join('');
        return true;
    }

    async function loadReportsPage() {
        if (await loadReportTypes() && !reports.draft) refreshReports();
    }

    $('#reportTypeButtons').addEventListener('click', (e) => {
        const btn = e.target.closest('[data-report-type]');
        if (btn) openReportEditor(btn.dataset.reportType, null);
    });
    $('#reportsBody').addEventListener('click', (e) => {
        const tr = e.target.closest('tr[data-id]');
        if (tr) openReport(Number(tr.dataset.id));
    });
    $('#reportDetail').addEventListener('click', (e) => {
        const goto = e.target.closest('[data-goto-call]');
        if (goto) {
            showPage('interventions');
            openCall(Number(goto.dataset.gotoCall));
            return;
        }
        if (e.target.closest('[data-report-edit]') && reports.current) openReportEditor(reports.current.type, reports.current);
    });
    $('#reportFilter').addEventListener('change', refreshReports);
    $('#reportMine').addEventListener('change', refreshReports);
    $('#refreshReports').addEventListener('click', refreshReports);
    $('#reportQuery').addEventListener('input', () => {
        clearTimeout(reports.queryTimer);
        reports.queryTimer = setTimeout(refreshReports, 300);
    });

    // =====================================================================
    // BOUTON "POSITION ACTUELLE" : adresse, croisement et bloc du joueur
    // (formulaire d'intervention de Créations et formulaire d'incident)
    // =====================================================================
    document.addEventListener('click', async (e) => {
        const btn = e.target.closest('[data-fill-location]');
        if (!btn) return;
        const form = btn.closest('form');
        const res = await post('getLocation');
        if (!res || !res.ok) {
            toast(res?.error || 'Position indisponible.', 'error');
            return;
        }
        const set = (name, value) => { if (form.elements[name] && value) form.elements[name].value = value; };
        set('address', res.street);
        set('crossStreet', res.crossing);
        set('block', res.block);
        toast('Adresse, croisement et bloc remplis avec votre position.', 'success');
    });

    // =====================================================================
    // NOTIFICATION "NOUVELLE INTERVENTION" (en haut à droite, même MDC fermé)
    // Nom, priorité, adresse, bloc. Disparaît seule ; clic pour la fermer (MDC ouvert).
    // =====================================================================
    function callNotification(c) {
        const incident = c.kind === 'incident';
        const prio = CALL_PRIORITY[c.priority];
        const el = document.createElement('div');
        el.className = `call-toast prio-${incident ? 'incident' : esc(c.priority)}`;
        el.innerHTML = `
            <div class="ct-head">
                <span>${incident ? 'NOUVEL INCIDENT' : 'NOUVELLE INTERVENTION'}</span>
                <span class="ct-number">${esc(c.number)}</span>
            </div>
            <div class="ct-title">${esc(c.title)}</div>
            <div class="ct-row"><span class="hud-label">PRIORITÉ</span>${incident
                ? `Incident${c.unitName ? ` — ${esc(c.unitName)}` : ''}`
                : (prio ? `<span class="flag ${prio[0]}">${esc(prio[1])}</span>` : '-')}</div>
            <div class="ct-row"><span class="hud-label">ADRESSE</span>${esc(c.address)}</div>
            ${c.crossStreet ? `<div class="ct-row"><span class="hud-label">CROISEMENT</span>${esc(c.crossStreet)}</div>` : ''}
            <div class="ct-row"><span class="hud-label">BLOC</span>${esc(c.block)}</div>`;
        const box = $('#toasts');
        while (box.children.length >= 5) box.firstElementChild.remove();
        box.appendChild(el);
        el.addEventListener('click', () => el.remove());
        setTimeout(() => el.remove(), 12000);
    }

    // =====================================================================
    // HUD : PLD (localisation) et display MDC (unité), séparés et déplaçables.
    // Les données viennent de client/hud.lua ; les réglages (onglet "Paramètres")
    // sont gardés chez le joueur (KVP) via le callback "saveSettings".
    // =====================================================================
    // Positions en fraction de l'écran (0 à 1, coin haut-gauche), taille en facteur (0.5 à 2)
    const HUD_DEFAULTS = {
        pld: { enabled: true, x: 0.165, y: 0.885, scale: 1, street: true, crossing: true, dir: true, block: true },
        unit: { enabled: true, x: 0.165, y: 0.765, scale: 1, name: true, tag: true, status: true, call: true },
        mdc: { zoom: 1, startTab: 'last' },
        notify: { calls: true, sound: true },
    };
    const START_TABS = ['last', 'units', 'interventions', 'search', 'reports', 'create'];
    const clone = (obj) => JSON.parse(JSON.stringify(obj));

    const hud = {
        settings: clone(HUD_DEFAULTS),
        access: false,      // accès au MDC (le PLD est toujours affiché, sauf désactivé)
        unit: null,         // unité du joueur : { name, tag, color, status, dept, callNumber, callTitle }
        pld: null,          // { street, crossing, dir, block, paused }
        placing: false,
        drag: null,
        saveTimer: null,
    };

    // Réglages enregistrés + valeurs par défaut pour les clés absentes ou invalides
    function mergeSettings(saved) {
        const out = clone(HUD_DEFAULTS);
        if (!saved || typeof saved !== 'object') return out;
        Object.keys(out).forEach((group) => {
            const src = saved[group];
            if (!src || typeof src !== 'object') return;
            Object.keys(out[group]).forEach((key) => {
                if (typeof src[key] === typeof out[group][key]) out[group][key] = src[key];
            });
        });
        ['pld', 'unit'].forEach((kind) => {
            const s = out[kind];
            s.x = Math.min(Math.max(s.x, 0), 0.98);
            s.y = Math.min(Math.max(s.y, 0), 0.98);
            s.scale = Math.min(Math.max(s.scale, 0.5), 2);
        });
        out.mdc.zoom = Math.min(Math.max(out.mdc.zoom, 0.8), 1.3);
        if (!START_TABS.includes(out.mdc.startTab)) out.mdc.startTab = 'last';
        return out;
    }

    function saveSettings() {
        clearTimeout(hud.saveTimer);
        hud.saveTimer = setTimeout(() => post('saveSettings', hud.settings), 300);
    }

    // Exemple affiché en mode placement quand il n'y a pas encore de données
    const PLD_SAMPLE = { street: 'Nom de la rue', crossing: 'Croisement', dir: 'N', block: '100' };
    const UNIT_SAMPLE = { name: 'Nom de l\'unité', tag: 'TAG', color: 'blue', status: 'available', callNumber: '00-0000' };

    function placeHud(el, cfg) {
        el.style.left = `${Math.round(cfg.x * innerWidth)}px`;
        el.style.top = `${Math.round(cfg.y * innerHeight)}px`;
        el.style.transform = `scale(${cfg.scale})`;
        el.querySelectorAll('[data-part]').forEach((part) => {
            part.classList.toggle('part-off', cfg[part.dataset.part] === false);
        });
    }

    function renderHud() {
        const paused = !!(hud.pld && hud.pld.paused);
        const pldEl = $('#hudPld');
        const unitEl = $('#hudUnit');
        const pldCfg = hud.settings.pld;
        const unitCfg = hud.settings.unit;

        // ---- PLD : toujours affiché (si activé) ----
        const loc = hud.pld || (hud.placing ? PLD_SAMPLE : null);
        const showPld = pldCfg.enabled && !!loc && (hud.placing || (hud.access && !paused));
        pldEl.classList.toggle('hidden', !showPld);
        if (showPld) {
            $('#pldDir').textContent = loc.dir || '-';
            $('#pldStreet').textContent = loc.street || '-';
            $('#pldCross').textContent = loc.crossing || '-'; // ligne toujours présente : taille stable
            $('#pldBlock').textContent = loc.block || '';
            pldEl.querySelector('[data-part="block"]').classList.toggle('part-empty', !loc.block);
            placeHud(pldEl, pldCfg);
        }

        // ---- Display MDC : uniquement dans une unité ----
        const unit = hud.unit || (hud.placing ? UNIT_SAMPLE : null);
        const showUnit = unitCfg.enabled && !!unit && (hud.placing || !paused);
        unitEl.classList.toggle('hidden', !showUnit);
        if (showUnit) {
            $('#huName').textContent = unit.name;
            const tag = $('#huTag');
            tag.textContent = unit.tag || '';
            tag.className = `unit-tag tag-${tagColor(unit.color)}`;
            tag.classList.toggle('part-empty', !unit.tag);
            $('#huSq').dataset.status = unit.status;
            $('#huStatus').textContent = STATUS_LABELS[unit.status] || unit.status;
            // N° d'incident ajouté seulement quand l'unité est sur un appel
            $('#huCall').textContent = unit.callNumber || '';
            unitEl.querySelector('[data-part="call"]').classList.toggle('part-empty', !unit.callNumber);
            placeHud(unitEl, unitCfg);
        }
    }

    window.addEventListener('resize', renderHud);

    // ---- Mode placement : déplacer (souris) et redimensionner (molette) ----
    function setPlacing(on) {
        hud.placing = on;
        document.body.classList.toggle('hud-placing', on);
        win.classList.toggle('placing-hidden', on);
        $('#hudPlacebar').classList.toggle('hidden', !on);
        renderHud();
        if (!on) {
            saveSettings();
            renderSettings();
        }
    }

    $('#hudPlace').addEventListener('click', () => setPlacing(true));
    $('#hudPlaceDone').addEventListener('click', () => setPlacing(false));

    $$('.hud').forEach((el) => {
        el.addEventListener('mousedown', (e) => {
            if (!hud.placing || e.button !== 0) return;
            const cfg = hud.settings[el.dataset.hud];
            hud.drag = { cfg, el, sx: e.clientX, sy: e.clientY, x: cfg.x, y: cfg.y };
            e.preventDefault();
        });
        el.addEventListener('wheel', (e) => {
            if (!hud.placing) return;
            e.preventDefault();
            const cfg = hud.settings[el.dataset.hud];
            cfg.scale = Math.round(Math.min(Math.max(cfg.scale + (e.deltaY < 0 ? 0.05 : -0.05), 0.5), 2) * 100) / 100;
            placeHud(el, cfg);
        }, { passive: false });
    });

    document.addEventListener('mousemove', (e) => {
        const d = hud.drag;
        if (!d) return;
        const rect = d.el.getBoundingClientRect();
        // Le HUD reste entièrement dans l'écran
        const round = (v) => Math.round(v * 10000) / 10000;
        d.cfg.x = round(Math.min(Math.max(d.x + (e.clientX - d.sx) / innerWidth, 0), Math.max(0, 1 - rect.width / innerWidth)));
        d.cfg.y = round(Math.min(Math.max(d.y + (e.clientY - d.sy) / innerHeight, 0), Math.max(0, 1 - rect.height / innerHeight)));
        placeHud(d.el, d.cfg);
    });
    document.addEventListener('mouseup', () => { hud.drag = null; });

    // ---- Onglet "Paramètres" ----
    const settingGet = (path) => path.split('.').reduce((o, k) => (o ? o[k] : undefined), hud.settings);
    const PERCENT_SETTINGS = ['pld.scale', 'unit.scale', 'mdc.zoom'];

    function renderSettings() {
        $$('[data-setting]').forEach((input) => {
            const value = settingGet(input.dataset.setting);
            if (input.type === 'checkbox') input.checked = value !== false;
            else if (PERCENT_SETTINGS.includes(input.dataset.setting)) input.value = Math.round(value * 100);
            else input.value = value;
        });
        $$('[data-setting-value]').forEach((el) => {
            el.textContent = `${Math.round(settingGet(el.dataset.settingValue) * 100)} %`;
        });
    }

    function applyMdcSettings() {
        win.style.setProperty('--ui-zoom', hud.settings.mdc.zoom);
    }

    $('#page-settings').addEventListener('input', (e) => {
        const input = e.target;
        const path = input.dataset && input.dataset.setting;
        if (!path) return;
        const [group, key] = path.split('.');
        let value = input.value;
        if (input.type === 'checkbox') value = input.checked;
        else if (PERCENT_SETTINGS.includes(path)) value = Number(input.value) / 100;
        hud.settings[group][key] = value;
        renderSettings();
        renderHud();
        applyMdcSettings();
        saveSettings();
    });

    $$('[data-hud-reset]').forEach((btn) => btn.addEventListener('click', () => {
        const kind = btn.dataset.hudReset;
        Object.assign(hud.settings[kind], { x: HUD_DEFAULTS[kind].x, y: HUD_DEFAULTS[kind].y, scale: 1 });
        renderSettings();
        renderHud();
        saveSettings();
        toast('Position et taille réinitialisées.', 'success');
    }));

    $('#mdcResetWindow').addEventListener('click', () => $('#btnReset').click());

    $('#settingsReset').addEventListener('click', (e) => {
        const btn = e.currentTarget;
        if (!btn.dataset.confirm) {
            btn.dataset.confirm = '1';
            btn.textContent = 'Confirmer ?';
            setTimeout(() => {
                delete btn.dataset.confirm;
                btn.textContent = 'Réglages par défaut';
            }, 3000);
            return;
        }
        delete btn.dataset.confirm;
        btn.textContent = 'Réglages par défaut';
        hud.settings = clone(HUD_DEFAULTS);
        renderSettings();
        renderHud();
        applyMdcSettings();
        saveSettings();
        toast('Réglages par défaut rétablis.', 'success');
    });

    // Au chargement du NUI : réglages et état du HUD (le client Lua peut démarrer un peu après)
    async function initHud(attempt = 1) {
        const res = await post('hudReady');
        if (res && res.ok) {
            hud.settings = mergeSettings(res.settings);
            hud.access = !!res.access;
            hud.unit = res.unit || null;
        } else if (attempt < 5) {
            setTimeout(() => initHud(attempt + 1), 1000);
        }
        renderSettings();
        applyMdcSettings();
        renderHud();
    }

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
            case 'hudState': // client/hud.lua : accès au MDC + unité du joueur
                hud.access = !!(data.data && data.data.access);
                hud.unit = (data.data && data.data.unit) || null;
                renderHud();
                break;
            case 'pld': // client/hud.lua : localisation (uniquement quand elle change)
                hud.pld = data.data || null;
                renderHud();
                break;
            case 'callNotify': // nouvelle intervention / nouvel incident (même MDC fermé)
                if (data.data) callNotification(data.data);
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
    initHud();
})();
