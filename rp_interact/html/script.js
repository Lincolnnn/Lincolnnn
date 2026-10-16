/* =========================================================================
   RP Interact - NUI (Vanilla JS)
   Œil (Eye Target), menu d'interactions, fiche civile, résultats d'inspection
   ========================================================================= */
(() => {
    'use strict';

    const RESOURCE = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'rp_interact';
    const $ = (sel, root = document) => root.querySelector(sel);
    const $$ = (sel, root = document) => root.querySelectorAll(sel);

    const esc = (value) => String(value ?? '').replace(/[&<>"']/g, (c) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c]));
    const toArray = (value) => (Array.isArray(value) ? value : Object.values(value || {}));
    const pad = (n) => String(n).padStart(2, '0');
    const formatDate = (unix) => {
        if (!unix) return '-';
        const d = new Date(unix * 1000);
        return `${pad(d.getDate())}/${pad(d.getMonth() + 1)} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
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
            return { ok: false, error: 'Callback indisponible.' };
        }
    }

    function toast(text, type = 'info') {
        const el = document.createElement('div');
        el.className = `toast ${type}`;
        el.textContent = text;
        const box = $('#toasts');
        while (box.children.length >= 3) box.firstElementChild.remove();
        box.appendChild(el);
        setTimeout(() => el.remove(), 4000);
    }

    // Réponses par défaut affichées dans la fiche (identiques à config.lua)
    const DEFAULTS = {
        visual: 'Rien à signaler / Rien d\'anormal / Tout est correct',
        olfactory: 'Rien à signaler / Rien d\'anormal / Tout est correct',
        search: 'Rien à signaler / Aucun élément / Rien d\'illégal',
        notable: 'Aucun détail notoire',
        vehicleVisual: 'Rien d\'anormal / Tout semble normal / Rien de suspect / Rien à signaler',
        vehicleOlfactory: 'Rien d\'anormal / Rien de suspect',
        vehicleSearch: 'Rien à signaler / Aucun élément / Rien d\'illégal',
    };

    // =====================================================================
    // ŒIL
    // =====================================================================
    const ICONS = {
        eye: '<path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7S1 12 1 12Z" fill="none" stroke="currentColor" stroke-width="1.8"/><circle cx="12" cy="12" r="3.2" fill="currentColor"/>',
        nose: '<path d="M4 9c3-2 5 2 8 0s5-2 8 0M4 14c3-2 5 2 8 0s5-2 8 0" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
        search: '<circle cx="10" cy="10" r="6" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="m15 15 6 6" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',
        note: '<path d="M6 3h9l4 4v14H6Z M14 3v5h5 M9 12h7 M9 16h7" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/>',
        door: '<path d="M5 3h11v18H5Z M16 5l3 1v13l-3 2" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/><circle cx="13" cy="12" r="1" fill="currentColor"/>',
        seat: '<path d="M7 3v9h10 M7 12l-1 8 M17 12v8 M7 16h10" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
        trash: '<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v6M14 11v6" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round" stroke-linecap="round"/>',
        move: '<path d="M12 3v18M3 12h18M12 3l-3 3M12 3l3 3M12 21l-3-3M12 21l3-3M3 12l3-3M3 12l3 3M21 12l-3-3M21 12l-3 3" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round" stroke-linecap="round"/>',
        cuffs: '<circle cx="7" cy="14" r="4.2" fill="none" stroke="currentColor" stroke-width="1.8"/><circle cx="17" cy="14" r="4.2" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M9.5 10.5 12 8l2.5 2.5" fill="none" stroke="currentColor" stroke-width="1.6"/>',
        car: '<path d="M3 15v-3l2-5h14l2 5v3Z M3 15v3h3v-3 M18 15v3h3v-3 M5 12h14" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/>',
        wave: '<path d="M8 13V6a1.5 1.5 0 0 1 3 0v5V4a1.5 1.5 0 0 1 3 0v7V5.5a1.5 1.5 0 0 1 3 0V15c0 3.5-2.5 6-6 6-2.5 0-4-1.2-5.5-3.5L3.5 14a1.6 1.6 0 0 1 2.6-1.8Z" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>',
        music: '<path d="M9 18V5l11-2v13M9 18a3 3 0 1 1-3-3 3 3 0 0 1 3 3Zm11-2a3 3 0 1 1-3-3 3 3 0 0 1 3 3Z" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/>',
        hand: '<path d="M8 13V6a1.5 1.5 0 0 1 3 0v5V4a1.5 1.5 0 0 1 3 0v7V5.5a1.5 1.5 0 0 1 3 0V15c0 3.5-2.5 6-6 6-2.5 0-4-1.2-5.5-3.5L3.5 14a1.6 1.6 0 0 1 2.6-1.8Z" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>',
    };
    const icon = (name) => `<svg viewBox="0 0 24 24">${ICONS[name] || ICONS.eye}</svg>`;

    const eye = { active: false, menu: false };

    function setEye(data) {
        eye.active = !!data.active;
        $('#eye').classList.toggle('hidden', !eye.active);
        if (!eye.active) {
            eye.menu = false;
            $('#eyeOptions').classList.add('hidden');
            return;
        }
        $('#eye').classList.toggle('has-options', !!data.hasOptions);
        $('#eyeLabel').textContent = data.label || '';
        $('#eyeLabel').classList.toggle('hidden', !data.hasOptions || !data.label || eye.menu);
    }

    function showEyeOptions(data) {
        eye.menu = true;
        const list = toArray(data.options);
        $('#eyeLabel').classList.add('hidden');
        $('#eyeOptions').innerHTML = `
            ${data.label ? `<li class="opt-title">${esc(data.label)}</li>` : ''}
            ${list.map((o) => `
                <li class="opt ${o.disabled ? 'disabled' : ''}" data-index="${esc(o.index)}">
                    ${icon(o.icon)}
                    <span class="opt-label">${esc(o.label)}</span>
                    ${o.police ? '<span class="opt-police">POLICE</span>' : ''}
                </li>`).join('')}`;
        $('#eyeOptions').classList.remove('hidden');
    }

    $('#eyeOptions').addEventListener('click', (e) => {
        const li = e.target.closest('li.opt');
        if (!li || li.classList.contains('disabled')) return;
        eye.menu = false;
        post('eyeSelect', { index: Number(li.dataset.index) });
    });

    // Clic droit ou clic hors de la liste : fermer
    document.addEventListener('mousedown', (e) => {
        if (!eye.menu) return;
        if (e.button === 2 || !e.target.closest('#eyeOptions')) {
            eye.menu = false;
            post('eyeCancel');
        }
    });
    document.addEventListener('contextmenu', (e) => e.preventDefault());

    // =====================================================================
    // RÉSULTATS D'INSPECTION
    // =====================================================================
    function showResult(r) {
        const el = document.createElement('div');
        el.className = 'result';
        el.innerHTML = `
            <div class="result-head"><span>Résultat</span><span>${esc(r.subject || '')}</span></div>
            <div class="result-title">${esc(r.title)}</div>
            <div class="result-text">${esc(r.text)}</div>`;
        const box = $('#results');
        while (box.children.length >= 4) box.firstElementChild.remove();
        box.appendChild(el);
        const duration = (Number(r.duration) || 20000) + String(r.text || '').length * 40;
        setTimeout(() => {
            el.classList.add('fade');
            setTimeout(() => el.remove(), 450);
        }, duration);
    }

    // =====================================================================
    // MENU D'INTERACTIONS
    // =====================================================================
    const menu = { open: false, view: 'home', data: {} };
    const MENU_TITLES = {
        home: 'Menu Interaction', civil: 'Civil', police: 'Police', equipment: 'Équipements', 'equipment-custom': 'Customiser équipement',
        'equipment-saved': 'Équipements modifiés',
        car: 'Voiture', spawn: 'Spawn', 'spawn-police': 'Véhicules de police', 'spawn-other': 'Autres véhicules', radio: 'Radio',
    };
    // Page précédente (bouton retour / Échap)
    const MENU_PARENT = { civil: 'home', police: 'home', equipment: 'home', 'equipment-custom': 'equipment', 'equipment-saved': 'equipment', car: 'home', spawn: 'car', radio: 'car', 'spawn-police': 'spawn', 'spawn-other': 'spawn' };
    // Catégories réservées (config.lua : Permissions) : page -> catégorie
    const SECTION_OF = { equipment: 'equipment', 'equipment-custom': 'equipment', 'equipment-saved': 'equipment', car: 'car', spawn: 'car', 'spawn-police': 'car', 'spawn-other': 'car', radio: 'car' };
    const isLocked = (view) => !!(SECTION_OF[view] && menu.data.locked && menu.data.locked[SECTION_OF[view]]);
    const LOCKED_TEXT = 'Accès réservé : vous n\'avez pas la permission.';

    // Position (fraction de l'écran, coin haut-gauche) et taille choisies dans le MDC ; sinon, par défaut
    let menuLayout = null;
    function applyMenuLayout() {
        const el = $('#menu');
        const l = menuLayout;
        if (!l) {
            el.style.left = ''; el.style.top = ''; el.style.transform = ''; el.style.maxHeight = '';
            return;
        }
        const scale = Math.min(Math.max(Number(l.scale) || 1, 0.7), 1.5);
        const top = Math.round(Math.min(Math.max(Number(l.y) || 0, 0), 0.95) * innerHeight);
        el.style.left = `${Math.round(Math.min(Math.max(Number(l.x) || 0, 0), 0.95) * innerWidth)}px`;
        el.style.top = `${top}px`;
        el.style.transform = `scale(${scale})`;
        el.style.maxHeight = `${Math.max(200, Math.floor((innerHeight - top - 12) / scale))}px`; // reste dans l'écran
    }
    window.addEventListener('resize', applyMenuLayout);

    // Réglage modifié dans le MDC : menu montré un instant (accueil) s'il est fermé
    let previewTimer = null;
    function setMenuLayout(data) {
        menuLayout = data && data.layout ? data.layout : null;
        applyMenuLayout();
        if (!data || !data.preview || menu.open) return;
        const el = $('#menu');
        menu.view = 'home';
        renderMenu();
        el.classList.add('preview');
        el.classList.remove('hidden');
        clearTimeout(previewTimer);
        previewTimer = setTimeout(() => {
            el.classList.remove('preview');
            if (!menu.open) el.classList.add('hidden');
        }, 2500);
    }

    const goBack = () => {
        menu.view = MENU_PARENT[menu.view] || 'home';
        renderMenu();
    };

    function renderMenu() {
        const d = menu.data;
        if (menu.lastView !== menu.view) {
            menu.lastView = menu.view;
            post('menuView', { view: menu.view }); // la vue Police reçoit l'état des actions en direct
            if (menu.view === 'equipment' || menu.view === 'equipment-saved') loadEquipment();
            if (menu.view === 'equipment-custom') loadCustom();
            if (menu.view.startsWith('spawn')) loadVehicles();
            if (menu.view === 'radio') loadRadio();
        }
        $('#menuTitle').textContent = MENU_TITLES[menu.view];
        $$('.menu-case[data-section]').forEach((c) => {
            const locked = isLocked(c.dataset.section);
            const hint = c.querySelector('small');
            c.classList.toggle('locked', locked);
            hint.textContent = locked ? 'Accès réservé' : hint.dataset.hint;
        });
        $('#menuBack').classList.toggle('hidden', menu.view === 'home');
        $$('.menu-view').forEach((v) => v.classList.toggle('hidden', v.dataset.view !== menu.view));

        // Rappel du profil actif (Civil)
        $('#menuCivilHint').textContent = d.activeName ? `Profil actif : ${d.activeName}` : 'Aucun profil actif';
        const active = $('#menuActive');
        active.classList.toggle('none', !d.activeName);
        active.innerHTML = d.activeName
            ? `Profil actif : <b>${esc(d.activeName)}</b>`
            : 'Aucun profil actif : créez-en un (« Créer un profil »).';

        // Police : en service = dans une unité du MDC
        $('#menuPoliceHint').textContent = d.police ? `En service — ${d.police}` : 'Hors service';
        const police = $('#menuPolice');
        police.classList.toggle('on-duty', !!d.police);
        police.classList.toggle('none', !d.police);
        police.innerHTML = d.police ? `En service — unité <b>${esc(d.police)}</b>` : '<b>Hors service</b>';
        $('#menuPoliceText').innerHTML = d.police
            ? `Maintenez <b>${esc(d.targetKey || 'Alt')}</b> et visez une personne ou un véhicule : inspections, fouilles et détails notoires.`
            : `Rejoignez une unité dans le MDC pour accéder aux fouilles et aux détails notoires. Avec l'œil
               (<b>${esc(d.targetKey || 'Alt')}</b>), seules les inspections visuelles et olfactives sont possibles.`;
    }

    function renderCivilMode() {
        const d = menu.data;
        $('#civilMode').checked = !!d.civilMode;
        $('#tipsToggle').classList.toggle('hidden', !d.civilMode);
        $('#tipsToggle').classList.toggle('active', !!d.tipsManual);
        $('#tipsToggle').textContent = d.tipsManual ? 'Masquer les tips arrestation' : 'Tips arrestation';
    }

    // Case "Mode civil" (gardée chez le joueur)
    $('#civilMode').addEventListener('change', async (e) => {
        const res = await post('setCivilMode', { enabled: e.target.checked });
        menu.data.civilMode = !!(res && res.ok ? res.civilMode : e.target.checked);
        if (!menu.data.civilMode) menu.data.tipsManual = false;
        renderCivilMode();
    });

    // Tips d'arrestation à la demande (le menu se ferme pour que les touches répondent)
    $('#tipsToggle').addEventListener('click', async () => {
        const res = await post('toggleTips');
        if (!res || !res.ok) {
            toast(res?.error || 'Action impossible.', 'error');
            return;
        }
        menu.data.tipsManual = !!res.visible;
        renderCivilMode();
    });

    // ---- Actions de police (vue Police) : toujours affichées, grisées si personne n'est assez proche ----
    function setMenuActions(a) {
        const set = (action, state, label) => {
            const btn = $(`[data-police-action="${action}"]`);
            btn.disabled = !(state && state.enabled);
            if (label) btn.textContent = label;
        };
        set('cuff', a.cuff, a.cuff && a.cuff.label);
        set('drag', a.drag, a.drag && a.drag.label);
        set('place', a.place);
        set('seat', a.seat, a.seat && a.seat.label);
    }

    $$('[data-police-action]').forEach((btn) => btn.addEventListener('click', () => {
        if (btn.disabled) return;
        post('policeAction', { action: btn.dataset.policeAction });
    }));

    // ---- Secteur / service principal (vue Police, en bas) : enregistrés dès qu'ils changent ----
    function renderPoliceProfile() {
        const p = menu.data.policeProfile || {};
        if (document.activeElement !== $('#policeSector')) $('#policeSector').value = p.sector || '';
        $('#policeService').value = p.service || '';
    }

    let sectorTimer = null;
    async function savePoliceProfile() {
        clearTimeout(sectorTimer);
        const res = await post('setPoliceProfile', { sector: $('#policeSector').value, service: $('#policeService').value });
        if (res && res.ok) menu.data.policeProfile = res.profile;
    }
    $('#policeSector').addEventListener('input', () => {
        clearTimeout(sectorTimer);
        sectorTimer = setTimeout(savePoliceProfile, 400);
    });
    $('#policeSector').addEventListener('change', savePoliceProfile);
    $('#policeService').addEventListener('change', savePoliceProfile);

    function setMenu(data) {
        menu.open = !!data.open;
        clearTimeout(previewTimer);
        $('#menu').classList.remove('preview');
        $('#menu').classList.toggle('hidden', !menu.open);
        if (!menu.open) {
            menu.lastView = null;
            return;
        }
        $$('[data-police-action]').forEach((btn) => { btn.disabled = true; });
        menu.data = data;
        menuLayout = data.layout || null;
        applyMenuLayout();
        menu.view = MENU_TITLES[data.view] ? data.view : 'home'; // ex. 'radio' depuis l'œil
        if (isLocked(menu.view)) {
            toast(LOCKED_TEXT, 'error');
            menu.view = 'home';
        }
        renderMenu();
        renderCivilMode();
        renderPoliceProfile();
    }

    // ---- Équipements : équipements de service (Équipement GSP / APD / FCSO), autres lots d'armes ; tenues : menu /eup ----
    const listButtons = (items, kind, empty) => (items.length ? items.map((x) => `
        <button type="button" class="menu-item" data-kind="${kind}" data-index="${x.index}">${esc(x.name)}
            ${x.service ? `<small>${esc(x.service)}</small>` : ''}</button>`).join('') : `<div class="menu-empty">${esc(empty)}</div>`);

    // Équipement sélectionné : de base ({ key }) ou modifié ({ id }) ; c'est lui que "Customiser équipement" modifie.
    // Au départ : celui du service principal choisi dans la vue Police.
    const equip = { services: [], customs: [], max: 10, selected: null, locked: false, custom: null };
    const DEPT = { apd: 'APD', gsp: 'GSP', fcso: 'FCSO' };
    const deptChip = (code) => (DEPT[code] ? `<span class="dept-chip dept-${code}">${DEPT[code]}</span>` : '');
    const selectedKit = () => {
        const sel = equip.selected;
        if (!sel) return null;
        if (sel.id) {
            const c = equip.customs.find((x) => x.id === sel.id);
            return c ? { ...c, custom: true } : null;
        }
        return equip.services.find((x) => x.key === sel.key) || null;
    };

    function renderKits() {
        const sel = equip.selected || {};
        $('#kitList').innerHTML = equip.services.length ? equip.services.map((x) => `
            <button type="button" class="menu-item kit-item${!sel.id && x.key === sel.key ? ' selected' : ''}" data-key="${esc(x.key)}" ${equip.locked ? 'disabled' : ''}>
                <span class="kit-name">${deptChip(x.code)}${esc(x.name)}</span>
                <small>Équipement de base</small>
            </button>`).join('') : '<div class="menu-empty">Aucun équipement de service (equipment_services.json).</div>';
        const n = equip.customs.length;
        $('#savedHint').textContent = n ? `${n} enregistré${n > 1 ? 's' : ''}` : 'Aucun : « Customiser », puis « Enregistrer »';
        $('#openSaved').classList.toggle('locked', equip.locked);
        $('#savedList').innerHTML = n ? equip.customs.map((x) => `
            <div class="saved-row${sel.id === x.id ? ' selected' : ''}">
                <button type="button" class="menu-item kit-item saved-item" data-id="${x.id}" ${equip.locked ? 'disabled' : ''}>
                    <span class="kit-name">${deptChip(x.code)}${esc(x.name)}</span><small>Modifié depuis : ${esc(x.service)}</small>
                </button>
                <button type="button" class="saved-edit" data-edit="${x.id}" title="Modifier" ${equip.locked ? 'disabled' : ''}>✎</button>
            </div>`).join('')
            : '<div class="menu-empty">Aucun équipement modifié. Choisissez un équipement de base, « Customiser équipement », donnez-lui un nom puis « Enregistrer ».</div>';
        const kit = selectedKit();
        $('#equipCustomize').disabled = equip.locked || !kit;
        $('#equipCustomizeHint').textContent = kit ? kit.name : '';
    }

    async function loadEquipment() {
        const res = await post('equipmentList');
        if (!res || !res.ok) return;
        equip.locked = !!(res.policeOnly && !res.police);
        equip.services = toArray(res.services);
        equip.customs = toArray(res.customs);
        equip.max = Number(res.maxCustom) || 10;
        if (!selectedKit()) {
            // Service principal (vue Police : "apd", "gsp", "fcso", "apd+gsp"…) : le premier qui a un équipement
            const mine = String(res.policeService || '').split('+');
            const match = equip.services.find((x) => x.code && mine.includes(x.code)) || equip.services[0];
            equip.selected = match ? { key: match.key } : null;
        }
        const notice = $('#equipNotice');
        notice.classList.toggle('hidden', !equip.locked);
        notice.textContent = 'Armes réservées à la police : rejoignez une unité dans le MDC.';
        renderKits();
        const loadouts = toArray(res.loadouts);
        $('#loadoutSection').classList.toggle('hidden', !loadouts.length);
        $('#loadoutList').innerHTML = loadouts.length ? listButtons(loadouts, 'loadout', '') : '';
        $$('#loadoutList .menu-item').forEach((b) => { b.disabled = equip.locked; });
    }

    function openCustomize(selection) {
        if (selection) equip.selected = selection;
        if (!selectedKit() || equip.locked) return;
        menu.view = 'equipment-custom';
        menu.lastView = null; // rechargée même si elle était déjà ouverte
        renderMenu();
    }

    document.addEventListener('click', async (e) => {
        const kit = e.target.closest('#kitList .kit-item');
        if (kit && !kit.disabled) {
            equip.selected = { key: kit.dataset.key }; // reconnu par "Customiser équipement"
            renderKits();
            post('useEquipment', { kind: 'service', key: kit.dataset.key }); // toujours l'équipement de base
            return;
        }
        const saved = e.target.closest('#savedList .saved-item');
        if (saved && !saved.disabled) {
            equip.selected = { id: Number(saved.dataset.id) };
            renderKits();
            post('useEquipment', { kind: 'custom', id: Number(saved.dataset.id) });
            return;
        }
        const edit = e.target.closest('#savedList .saved-edit');
        if (edit && !edit.disabled) {
            openCustomize({ id: Number(edit.dataset.edit) });
            return;
        }
        const item = e.target.closest('#loadoutList .menu-item');
        if (!item || item.disabled) return;
        post('useEquipment', { kind: item.dataset.kind, index: Number(item.dataset.index) });
    });
    $('#openEup').addEventListener('click', () => post('openEup'));
    $('#weaponsRemove').addEventListener('click', () => post('useEquipment', { kind: 'removeWeapons' }));
    $('#openSaved').addEventListener('click', () => {
        if (equip.locked) return;
        menu.view = 'equipment-saved';
        renderMenu();
    });
    $('#equipCustomize').addEventListener('click', () => {
        if (!$('#equipCustomize').disabled) openCustomize();
    });

    // ---- Customiser équipement : armes du service, accessoires, teintes ; nom ; enregistré = équipement modifié ----
    const TINTS = ['Noir (d\'origine)', 'Vert', 'Or', 'Rose', 'Kaki', 'Bleu police', 'Orange', 'Platine'];

    function customHead() {
        const c = equip.custom;
        if (!c) return;
        $('#customHead').innerHTML = `${deptChip(c.code)}<b>${esc(c.id ? c.name : c.service)}</b><br><small>${c.id
            ? `Équipement modifié (depuis ${esc(c.service)}) : « Enregistrer » met à jour celui-ci.`
            : `Équipement de base : modifiez-le, nommez-le, puis « Enregistrer » : il s'ajoute aux Équipements modifiés (l'équipement de base ne change pas).`}</small>`;
        $('#customDelete').classList.toggle('hidden', !c.id);
    }

    function renderCustom() {
        const c = equip.custom;
        customHead();
        $('#customName').value = c.name || '';
        $('#customName').placeholder = c.suggested || 'Nom de l\'équipement';
        $('#customList').innerHTML = toArray(c.weapons).map((w) => {
            const choice = w.choice || {};
            const comps = toArray(choice.components);
            const groups = toArray(w.groups).map((g, gi) => {
                const choices = toArray(g.choices);
                if (choices.length === 1) {
                    const ch = choices[0];
                    return `<label class="custom-opt"><input type="checkbox" data-group="${gi}" value="${esc(ch.component)}" ${comps.includes(ch.component) ? 'checked' : ''}>
                        <span class="custom-tick"></span>${esc(ch.label || g.label)}</label>`;
                }
                return `<label class="menu-field custom-field"><span>${esc(g.label)}</span><select data-group="${gi}">
                    <option value="">Aucun</option>${choices.map((ch) => `<option value="${esc(ch.component)}" ${comps.includes(ch.component) ? 'selected' : ''}>${esc(ch.label)}</option>`).join('')}
                </select></label>`;
            }).join('');
            const tint = w.tints ? `<label class="menu-field custom-field"><span>Teinte</span><select class="custom-tint">
                ${TINTS.map((t, i) => `<option value="${i}" ${Number(choice.tint) === i ? 'selected' : ''}>${esc(t)}</option>`).join('')}</select></label>` : '';
            const on = w.required || choice.on;
            return `<div class="custom-weapon${on ? '' : ' off'}" data-weapon="${esc(w.weapon)}">
                <label class="custom-name">
                    <input type="checkbox" class="custom-on" ${on ? 'checked' : ''} ${w.required ? 'disabled' : ''}>
                    <span class="custom-tick"></span><b>${esc(w.label)}</b>${w.required ? '<small>Obligatoire</small>' : ''}
                </label>
                ${groups || tint ? `<div class="custom-opts">${groups}${tint}</div>` : ''}
            </div>`;
        }).join('') || '<div class="menu-empty">Rien à personnaliser pour cet équipement.</div>';
    }

    async function loadCustom() {
        const kit = selectedKit();
        $('#customList').innerHTML = '';
        $('#customHead').textContent = 'Chargement…';
        if (!kit) return;
        const res = await post('equipmentCustom', kit.custom ? { id: kit.id } : { key: kit.key });
        if (!res || !res.ok) {
            $('#customHead').textContent = res?.error || 'Action impossible.';
            return;
        }
        equip.custom = res;
        renderCustom();
    }

    // Arme cochée / décochée : ses accessoires grisés
    $('#customList').addEventListener('change', (e) => {
        if (!e.target.classList.contains('custom-on')) return;
        e.target.closest('.custom-weapon').classList.toggle('off', !e.target.checked);
    });

    function customChoices() {
        const weapons = {};
        $$('#customList .custom-weapon').forEach((el) => {
            const components = [];
            el.querySelectorAll('.custom-opt input:checked').forEach((i) => components.push(i.value));
            el.querySelectorAll('select[data-group]').forEach((sel) => { if (sel.value) components.push(sel.value); });
            const tint = el.querySelector('.custom-tint');
            weapons[el.dataset.weapon] = { on: el.querySelector('.custom-on').checked, components, tint: tint ? Number(tint.value) : 0 };
        });
        return { weapons };
    }

    async function customAction(action) {
        const c = equip.custom;
        if (!c) return;
        const payload = { key: c.key, id: c.id || null, action, name: $('#customName').value.trim() };
        if (action !== 'delete') payload.choices = customChoices();
        const res = await post('equipmentCustomSave', payload);
        if (!res || !res.ok) return;
        if (res.customs) equip.customs = toArray(res.customs);
        if (action === 'delete') {
            equip.custom = null;
            equip.selected = { key: c.key };
            menu.view = 'equipment-saved';
            renderMenu();
            renderKits();
            return;
        }
        if (action === 'save' && res.id) {
            // Enregistré : c'est désormais cet équipement modifié qui est sélectionné (un nouvel enregistrement le met à jour)
            c.id = res.id;
            c.name = res.name || c.name;
            $('#customName').value = c.name;
            equip.selected = { id: res.id };
            customHead();
            renderKits();
        }
    }
    $('#customApply').addEventListener('click', () => customAction('apply'));
    $('#customSave').addEventListener('click', () => customAction('save'));
    $('#customDelete').addEventListener('click', () => customAction('delete'));

    // ---- Voiture > Spawn (data/vehicles.json) ----
    async function loadVehicles() {
        const res = await post('vehicleList');
        if (!res || !res.ok) return;
        const opts = res.options || {};
        $('#spawnDeleteOld').checked = opts.deleteOld !== false;
        $('#spawnWarpInto').checked = opts.warpInto !== false;
        const all = toArray(res.vehicles);
        const locked = res.policeOnly && !res.police;
        const item = (v) => `<button type="button" class="menu-item vehicle-item" data-code="${esc(v.code)}" ${v.service !== 'other' && locked ? 'disabled' : ''}>
            ${esc(v.label)}<small>${esc(v.code)}</small></button>`;
        const fill = (sel, list, empty) => { $(sel).innerHTML = list.length ? list.map(item).join('') : `<div class="menu-empty">${esc(empty)}</div>`; };
        const apd = all.filter((v) => v.service === 'apd');
        const gsp = all.filter((v) => v.service === 'gsp');
        const fcso = all.filter((v) => v.service === 'fcso');
        const other = all.filter((v) => v.service === 'other');
        fill('#spawnApd', apd, 'Aucun véhicule APD (data/vehicles.json).');
        fill('#spawnGsp', gsp, 'Aucun véhicule GSP (data/vehicles.json).');
        fill('#spawnFcso', fcso, 'Aucun véhicule FCSO (data/vehicles.json).');
        fill('#spawnOther', other, 'Aucun véhicule (data/vehicles.json).');
        $('#spawnPoliceHint').textContent = `${apd.length} APD, ${gsp.length} GSP, ${fcso.length} FCSO${locked ? ' — réservé à la police' : ''}`;
        $('#spawnOtherHint').textContent = `${other.length} véhicule(s)`;
        const notice = $('#spawnPoliceNotice');
        notice.classList.toggle('hidden', !locked);
        notice.textContent = 'Réservé à la police : rejoignez une unité dans le MDC.';
    }

    const saveSpawnOptions = () => post('spawnOptions', { deleteOld: $('#spawnDeleteOld').checked, warpInto: $('#spawnWarpInto').checked });
    $('#spawnDeleteOld').addEventListener('change', saveSpawnOptions);
    $('#spawnWarpInto').addEventListener('change', saveSpawnOptions);
    document.addEventListener('click', (e) => {
        const btn = e.target.closest('.vehicle-item');
        if (!btn || btn.disabled) return;
        post('spawnVehicle', { code: btn.dataset.code });
        post('closeMenu');
    });

    // ---- Voiture > Radio : réglages du véhicule (le son est joué plus bas) ----
    const RADIO_QUEUE_MAX = 5;
    function renderRadio(info) {
        const status = $('#radioStatus');
        const controls = $('#radioControls');
        info = info || {};
        if (!info.available) {
            status.className = 'menu-active none';
            status.textContent = info.error || 'Montez dans un véhicule (ou visez l\'intérieur avant avec l\'œil, portière ouverte).';
            controls.classList.add('disabled');
            controls.querySelectorAll('input, button').forEach((el) => { el.disabled = true; });
            $('#radioQueue').innerHTML = '';
            return;
        }
        const radio = info.radio || null;
        const queue = radio ? toArray(radio.queue) : [];
        status.className = `menu-active ${radio ? 'on-air' : 'none'}`;
        status.innerHTML = `${info.vehicle ? `<b>${esc(info.vehicle)}</b> — ` : ''}${radio ? (radio.paused ? 'radio en pause' : 'radio allumée') : 'radio éteinte'}`
            + (radio ? `<br><small class="radio-now">${esc(radio.url)}</small>` : '')
            + (info.canControl ? '' : '<br><small>Seules les places avant peuvent la régler.</small>');
        controls.classList.toggle('disabled', !info.canControl);
        controls.querySelectorAll('input, button').forEach((el) => { el.disabled = !info.canControl; });
        ['#radioStop', '#radioNext', '#radioPause', '#radioRestart'].forEach((sel) => { $(sel).disabled = !info.canControl || !radio; });
        const paused = !!(radio && radio.paused);
        $('#radioPause').classList.toggle('is-paused', paused);
        $('#radioPause').title = paused ? 'Reprendre' : 'Pause';
        $('#radioPause').setAttribute('aria-label', paused ? 'Reprendre' : 'Pause');
        $('#radioAdd').disabled = !info.canControl || queue.length >= RADIO_QUEUE_MAX;
        const volume = radio ? radio.volume : Number($('#radioVolume').value);
        $('#radioVolume').value = volume;
        $('#radioVolumeValue').textContent = `${volume} %`;
        // File "Écouter ensuite"
        $('#radioQueueTitle').textContent = `Écouter ensuite (${queue.length} / ${RADIO_QUEUE_MAX})`;
        $('#radioQueue').innerHTML = queue.length
            ? queue.map((url, i) => `
                <div class="radio-queue-item"><span class="radio-queue-n">${i + 1}</span><span class="radio-queue-url">${esc(url)}</span>
                    ${info.canControl ? `<button type="button" class="radio-queue-del" data-unqueue="${i + 1}" title="Retirer">&#10005;</button>` : ''}</div>`).join('')
            : '<div class="menu-empty">Aucun morceau en attente : collez un lien puis « + ».</div>';
    }

    async function loadRadio() {
        renderRadio(await post('radioInfo'));
    }

    async function radioAction(action, extra = {}) {
        const res = await post('radioAction', { action, ...extra });
        if (!res || !res.ok) return toast(res?.error || 'Action impossible.', 'error');
        renderRadio(res);
        return res;
    }
    const radioUrl = () => $('#radioUrl').value.trim();
    $('#radioPlay').addEventListener('click', () => radioAction('play', { url: radioUrl(), volume: Number($('#radioVolume').value) }));
    $('#radioAdd').addEventListener('click', async () => {
        const res = await radioAction('queue', { url: radioUrl(), volume: Number($('#radioVolume').value) });
        if (res) $('#radioUrl').value = '';
    });
    $('#radioNext').addEventListener('click', () => radioAction('next'));
    $('#radioPause').addEventListener('click', () => radioAction('pause'));
    // Début du morceau ; deux appuis rapprochés (moins de 2,5 s) : morceau précédent
    const RADIO_DOUBLE_MS = 2500;
    let radioRestartAt = 0;
    $('#radioRestart').addEventListener('click', () => {
        const now = Date.now();
        const double = now - radioRestartAt < RADIO_DOUBLE_MS;
        radioRestartAt = double ? 0 : now;
        radioAction(double ? 'previous' : 'restart');
    });
    $('#radioStop').addEventListener('click', () => radioAction('stop'));
    $('#radioQueue').addEventListener('click', (e) => {
        const btn = e.target.closest('[data-unqueue]');
        if (btn) radioAction('unqueue', { index: Number(btn.dataset.unqueue) });
    });
    $('#radioVolume').addEventListener('input', () => { $('#radioVolumeValue').textContent = `${$('#radioVolume').value} %`; });
    $('#radioVolume').addEventListener('change', () => {
        if (!$('#radioStop').disabled) radioAction('volume', { volume: Number($('#radioVolume').value) });
    });

    // ---- Lecteurs de la radio des véhicules (client/radio.lua) ----
    // Lecture telle quelle, sans effet : lecteur YouTube (lien YouTube) ou lecteur audio (lien direct).
    // Le volume (distance, vitres / portières) est calculé par client/radio.lua. À la fin d'un morceau,
    // le serveur est prévenu ("radioEnded") et lance le suivant de la file pour tout le monde.
    const radios = {};
    let ytReady = null;

    function youtubeId(url) {
        const m = String(url).match(/(?:youtube\.com\/(?:watch\?(?:.*&)?v=|shorts\/|live\/|embed\/)|youtu\.be\/|music\.youtube\.com\/watch\?(?:.*&)?v=)([\w-]{11})/);
        return m ? m[1] : null;
    }

    function loadYouTube() {
        if (!ytReady) {
            ytReady = new Promise((resolve) => {
                window.onYouTubeIframeAPIReady = () => resolve(window.YT);
                const tag = document.createElement('script');
                tag.src = 'https://www.youtube.com/iframe_api';
                document.head.appendChild(tag);
            });
        }
        return ytReady;
    }

    function applyRadio(r) {
        const v = Math.min(Math.max(r.volume, 0), 1);
        if (r.player && r.player.setVolume) r.player.setVolume(Math.round(v * 100));
        if (r.audio) r.audio.volume = v;
    }

    /** Fin du morceau : une seule fois par morceau (même "start") */
    function radioEnded(r) {
        if (r.dead || r.endedSent) return;
        r.endedSent = true;
        post('radioEnded', { id: r.id, seq: r.seq });
    }

    function playYouTube(r, id) {
        const slot = document.createElement('div');
        r.holder.appendChild(slot);
        loadYouTube().then((YT) => {
            if (r.dead) return;
            r.player = new YT.Player(slot, {
                width: 200, height: 200, videoId: id,
                playerVars: { autoplay: 1, controls: 0, start: Math.floor(r.offset || 0), playsinline: 1 },
                events: {
                    onReady: (e) => {
                        applyRadio(r);
                        e.target.seekTo(Math.floor(r.offset || 0), true);
                        if (r.paused) e.target.pauseVideo(); else e.target.playVideo();
                    },
                    onStateChange: (e) => { if (e.data === 0) radioEnded(r); }, // 0 : vidéo terminée
                    onError: () => radioEnded(r), // vidéo indisponible : morceau suivant
                },
            });
        });
    }

    function playAudio(r, url) {
        const audio = new Audio(url);
        audio.addEventListener('loadedmetadata', () => {
            if (Number.isFinite(audio.duration) && r.offset < audio.duration) audio.currentTime = r.offset;
            else if (Number.isFinite(audio.duration) && r.offset >= audio.duration) radioEnded(r); // déjà fini
        }, { once: true });
        audio.addEventListener('ended', () => radioEnded(r));
        r.audio = audio;
        applyRadio(r);
        if (!r.paused) audio.play().catch(() => {});
    }

    function createRadio(d) {
        const r = { id: d.id, url: d.url, seq: d.seq, volume: d.volume, offset: d.offset, paused: !!d.paused };
        r.holder = document.createElement('div');
        r.holder.className = 'radio-player';
        $('#radioPlayers').appendChild(r.holder);
        const id = youtubeId(d.url);
        if (id) playYouTube(r, id); else playAudio(r, d.url);
        return r;
    }

    /** Pause / reprise : à la reprise, même position pour tout le monde (calculée par client/radio.lua) */
    function setRadioPaused(r, paused, offset) {
        r.paused = paused;
        if (r.player && r.player.pauseVideo) {
            if (paused) r.player.pauseVideo();
            else { r.player.seekTo(Math.floor(offset || 0), true); r.player.playVideo(); }
        }
        if (r.audio) {
            if (paused) r.audio.pause();
            else {
                if (Number.isFinite(r.audio.duration) && offset < r.audio.duration) r.audio.currentTime = offset;
                r.audio.play().catch(() => {});
            }
        }
    }

    function radioStop(id) {
        const r = radios[id];
        if (!r) return;
        r.dead = true;
        try { if (r.player && r.player.destroy) r.player.destroy(); } catch (err) { /* déjà fermé */ }
        if (r.audio) { r.audio.pause(); r.audio.removeAttribute('src'); r.audio.load(); }
        r.holder.remove();
        delete radios[id];
    }

    function radioUpdate(d) {
        if (!d || !d.id) return;
        let r = radios[d.id];
        if (r && (r.url !== d.url || r.seq !== d.seq)) { radioStop(d.id); r = null; }
        const created = !r;
        if (!r) radios[d.id] = r = createRadio(d);
        r.volume = Number(d.volume) || 0;
        r.offset = d.offset;
        applyRadio(r);
        if (!created && r.paused !== !!d.paused) setRadioPaused(r, !!d.paused, d.offset);
        if (!created && menu.open && menu.view === 'radio' && r.pausedShown !== r.paused) loadRadio();
        r.pausedShown = r.paused;
        if (created && menu.open && menu.view === 'radio') loadRadio(); // morceau suivant : page Radio à jour
    }

    // ---- Barre de chargement (fouilles, menottes) ----
    const progress = { timer: null };

    function setProgress(data) {
        const box = $('#progress');
        const bar = $('#progressBar');
        clearInterval(progress.timer);
        if (!data.show) {
            box.classList.add('hidden');
            return;
        }
        const duration = Math.max(Number(data.duration) || 0, 1);
        const endsAt = Date.now() + duration;
        $('#progressLabel').textContent = data.label || '';
        bar.style.transition = 'none';
        bar.style.width = '0%';
        box.classList.remove('hidden');
        void bar.offsetWidth; // relance la transition depuis 0
        bar.style.transition = `width ${duration}ms linear`;
        bar.style.width = '100%';
        const tick = () => { $('#progressTime').textContent = `${Math.max(0, Math.ceil((endsAt - Date.now()) / 1000))} s`; };
        tick();
        progress.timer = setInterval(tick, 250);
    }

    // ---- Tips d'arrestation (mode civil) ----
    function setTips(data) {
        const box = $('#tips');
        box.classList.toggle('hidden', !data.show);
        if (!data.show) return;
        box.classList.toggle('aimed', !!data.aimed);
        $('#tipsTitle').textContent = data.aimed ? 'Un policier vous tient en joue' : 'Tips arrestation';
        $('#tipsKeys').innerHTML = toArray(data.keys).map((k) => `
            <span class="tips-key ${k.stop ? 'stop' : ''}"><kbd>${esc(k.key)}</kbd>${esc(k.label)}</span>`).join('');
    }

    $$('[data-go]').forEach((btn) => btn.addEventListener('click', () => {
        if (isLocked(btn.dataset.go)) return toast(LOCKED_TEXT, 'error');
        menu.view = btn.dataset.go;
        renderMenu();
    }));
    $('#menuBack').addEventListener('click', goBack);
    $('#menuClose').addEventListener('click', () => post('closeMenu'));

    // "Créer un profil" / "Créer un véhicule" : ouvre la fiche (le menu se ferme)
    $$('[data-editor]').forEach((btn) => btn.addEventListener('click', async () => {
        btn.disabled = true;
        const res = await post('openEditor', { view: btn.dataset.editor });
        btn.disabled = false;
        if (!res || !res.ok) toast(res?.error || 'Ouverture impossible.', 'error');
    }));

    // =====================================================================
    // FICHE CIVILE
    // =====================================================================
    const ed = {
        open: false,
        tab: 'profiles',
        profiles: [],
        max: 20,
        selected: null,      // id du profil affiché
        mode: 'empty',       // empty | view | form
        draft: null,
        confirmDelete: false,
        vehicle: null,       // { netId, label, plate, profile, taken }
        vdraft: null,
        vconfirm: false,
    };

    const PROFILE_PARTS = [
        { key: 'visual', label: 'Visuel', defaults: 'visual', ph: 'Ce que l\'on voit : vêtements tachés, blessure, comportement…' },
        { key: 'olfactory', label: 'Olfactif', defaults: 'olfactory', ph: 'Ce que l\'on sent : alcool, cannabis, essence…' },
        { key: 'upper', label: 'Partie supérieure du corps', defaults: 'search', ph: 'Poches de veste, ceinture, sous les bras…' },
        { key: 'lower', label: 'Partie inférieure du corps', defaults: 'search', ph: 'Poches de pantalon, chaussettes, chevilles…' },
    ];

    const emptyProfile = () => ({
        id: null, name: '', notable: '',
        visualKnown: false, visual: '', olfactoryKnown: false, olfactory: '',
        upperKnown: false, upper: '', lowerKnown: false, lower: '',
    });
    const emptyVehicle = () => ({
        visualKnown: false, interior: '', exterior: '', olfactory: '', notable: '', cabin: '', rear: '', trunk: '',
    });

    const valueOrDefault = (text, defaults) => (text
        ? esc(text)
        : `<span class="default-text">${esc(DEFAULTS[defaults])}</span>`);

    // ---- Onglets ----
    function setTab(tab) {
        ed.tab = tab;
        $$('#editor .tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === tab));
        $$('#editor .page').forEach((p) => p.classList.toggle('hidden', p.dataset.page !== tab));
        $('#editorStatus').textContent = tab === 'profiles'
            ? 'Profils enregistrés de façon permanente (vous seul les voyez). Le profil actif est celui que la police découvre.'
            : 'Profil de véhicule temporaire : lié au véhicule, supprimé avec lui ou au redémarrage du serveur.';
        if (tab === 'vehicle') renderVehicle();
    }

    $$('#editor .tab').forEach((t) => t.addEventListener('click', async () => {
        if (t.dataset.tab === 'vehicle' && !ed.vehicle) await findVehicle();
        setTab(t.dataset.tab);
    }));

    // ---- Liste des profils ----
    function renderProfileList() {
        const list = ed.profiles;
        $('#profileCount').textContent = `(${list.length}/${ed.max})`;
        $('#profileEmpty').classList.toggle('hidden', list.length > 0);
        $('#profileBody').innerHTML = list.map((p) => `
            <tr data-id="${esc(p.id)}" class="${p.id === ed.selected ? 'selected' : ''}">
                <td class="name"><b>${esc(p.name)}</b></td>
                <td>${p.active ? '<span class="flag c-green">Actif</span>' : '<span class="flag c-gray">—</span>'}</td>
                <td>${esc(formatDate(p.updatedAt || p.createdAt))}</td>
            </tr>`).join('');
        $('#newProfile').disabled = list.length >= ed.max;
    }

    async function refreshProfiles() {
        const res = await post('getProfiles');
        if (res && res.ok) {
            ed.profiles = toArray(res.profiles);
            ed.max = res.max || ed.max;
        }
        renderProfileList();
    }

    $('#profileBody').addEventListener('click', (e) => {
        const tr = e.target.closest('tr[data-id]');
        if (!tr) return;
        ed.selected = Number(tr.dataset.id);
        ed.mode = 'view';
        ed.confirmDelete = false;
        renderProfileList();
        renderProfilePanel();
    });

    $('#newProfile').addEventListener('click', () => openProfileForm(emptyProfile()));

    function openProfileForm(draft) {
        ed.draft = draft;
        ed.mode = 'form';
        if (!draft.id) ed.selected = null;
        renderProfileList();
        renderProfilePanel();
        const name = $('#profileDetail [data-k="name"]');
        if (name) name.focus();
    }

    // ---- Détail / formulaire d'un profil ----
    function profileViewHtml(p) {
        const parts = (keys) => keys.map((k) => {
            const part = PROFILE_PARTS.find((x) => x.key === k);
            return `<dt>${esc(part.label)}</dt><dd>${valueOrDefault(p[`${k}Known`] ? p[k] : '', part.defaults)}</dd>`;
        }).join('');
        return `
            <div class="sheet-title">
                <span>${esc(p.name)} ${p.active ? '<span class="flag c-green">Actif</span>' : ''}</span>
                <span class="sheet-actions">
                    ${p.active
                        ? '<button type="button" class="btn btn-small" data-act="deactivate">Désactiver</button>'
                        : '<button type="button" class="btn btn-small btn-default" data-act="activate">Définir comme profil actif</button>'}
                    <button type="button" class="btn btn-small" data-act="edit">Modifier</button>
                    <button type="button" class="btn btn-small btn-danger ${ed.confirmDelete ? 'confirm' : ''}" data-act="delete">${ed.confirmDelete ? 'Confirmer ?' : 'Supprimer'}</button>
                </span>
            </div>
            <div class="sheet-sub">Inspection <small>Observations visuelles et olfactives</small></div>
            <dl class="sheet">${parts(['visual', 'olfactory'])}</dl>
            <div class="sheet-sub">Fouille <small>Contenu de ce que détient votre personnage</small></div>
            <dl class="sheet">${parts(['upper', 'lower'])}</dl>
            <div class="sheet-sub">Détail notoire</div>
            <dl class="sheet"><dt>Détail notoire</dt><dd>${valueOrDefault(p.notable, 'notable')}</dd></dl>
            ${p.active ? '' : '<div class="note">Ce profil n\'est pas actif : la police découvre uniquement votre profil actif.</div>'}`;
    }

    const partForm = (d, part) => `
        <div class="form-part">
            <label class="check"><input type="checkbox" data-k="${part.key}Known" ${d[`${part.key}Known`] ? 'checked' : ''}> ${esc(part.label)}</label>
            <textarea data-k="${part.key}" rows="3" maxlength="1000" placeholder="${esc(part.ph)}" class="${d[`${part.key}Known`] ? '' : 'hidden'}">${esc(d[part.key])}</textarea>
            <div class="part-default ${d[`${part.key}Known`] ? 'hidden' : ''}">Non coché : « ${esc(DEFAULTS[part.defaults])} »</div>
        </div>`;

    function profileFormHtml(d) {
        return `
            <label class="lbl">Nom du profil *
                <input type="text" data-k="name" maxlength="40" value="${esc(d.name)}" placeholder="ex : Livreur nerveux, Sortie de bar…">
            </label>
            <div class="form-section">
                <span class="form-section-title">Inspection</span>
                <div class="form-section-desc">Observations visuelles et olfactives</div>
                ${partForm(d, PROFILE_PARTS[0])}
                ${partForm(d, PROFILE_PARTS[1])}
            </div>
            <div class="form-section">
                <span class="form-section-title">Fouille</span>
                <div class="form-section-desc">Contenu de ce que détient votre personnage</div>
                ${partForm(d, PROFILE_PARTS[2])}
                ${partForm(d, PROFILE_PARTS[3])}
            </div>
            <div class="form-section">
                <span class="form-section-title">Détail notoire</span>
                <div class="form-section-desc">Facultatif : éléments importants à prendre en compte</div>
                <textarea data-k="notable" rows="4" maxlength="1000" placeholder="ex : tatouage de gang sur la main, très agité, cherche à fuir…">${esc(d.notable)}</textarea>
            </div>
            <div class="form-actions">
                <button type="button" class="btn" data-act="cancel">Annuler</button>
                <button type="button" class="btn btn-default" data-act="save">Enregistrer</button>
            </div>`;
    }

    function renderProfilePanel() {
        const el = $('#profileDetail');
        const p = ed.profiles.find((x) => x.id === ed.selected);
        if (ed.mode === 'form' && ed.draft) {
            $('#profilePanelTitle').textContent = ed.draft.id ? 'Modifier le profil' : 'Nouveau profil';
            el.innerHTML = profileFormHtml(ed.draft);
        } else if (ed.mode === 'view' && p) {
            $('#profilePanelTitle').textContent = 'Profil';
            el.innerHTML = profileViewHtml(p);
        } else {
            $('#profilePanelTitle').textContent = 'Profil';
            el.innerHTML = '<div class="empty">Sélectionnez un profil, ou créez-en un.</div>';
        }
        el.scrollTop = 0;
    }

    // Saisie : texte et cases (les cases affichent / masquent leur zone de texte)
    function bindDraft(container, getDraft) {
        container.addEventListener('input', (e) => {
            const k = e.target.dataset && e.target.dataset.k;
            const d = getDraft();
            if (!k || !d) return;
            if (e.target.type === 'checkbox') {
                d[k] = e.target.checked;
                const part = e.target.closest('.form-part');
                if (part) {
                    part.querySelectorAll('textarea, .part-default, .part-fields').forEach((x) => {
                        const show = x.classList.contains('part-default') ? !e.target.checked : e.target.checked;
                        x.classList.toggle('hidden', !show);
                    });
                    if (e.target.checked) {
                        const first = part.querySelector('textarea');
                        if (first) first.focus();
                    }
                }
            } else {
                d[k] = e.target.value;
            }
        });
    }
    bindDraft($('#profileDetail'), () => ed.draft);

    $('#profileDetail').addEventListener('click', async (e) => {
        const btn = e.target.closest('[data-act]');
        if (!btn) return;
        const act = btn.dataset.act;
        const p = ed.profiles.find((x) => x.id === ed.selected);

        if (act === 'cancel') {
            ed.mode = ed.draft && ed.draft.id ? 'view' : 'empty';
            ed.draft = null;
            renderProfilePanel();
        } else if (act === 'save') {
            const d = ed.draft;
            if (!d.name.trim()) {
                toast('Donnez un nom au profil.', 'error');
                return;
            }
            btn.disabled = true;
            const res = await post('saveProfile', d);
            btn.disabled = false;
            if (!res || !res.ok) {
                toast(res?.error || 'Enregistrement impossible.', 'error');
                return;
            }
            toast(res.active && !d.id ? 'Profil enregistré et défini comme profil actif.' : 'Profil enregistré.', 'success');
            ed.selected = res.id;
            ed.mode = 'view';
            ed.draft = null;
            await refreshProfiles();
            renderProfilePanel();
        } else if (act === 'edit' && p) {
            openProfileForm({ ...emptyProfile(), ...p });
        } else if ((act === 'activate' || act === 'deactivate') && p) {
            const res = await post('setActive', act === 'activate' ? { id: p.id } : {});
            if (!res || !res.ok) {
                toast(res?.error || 'Modification impossible.', 'error');
                return;
            }
            toast(act === 'activate' ? `Profil actif : ${p.name}` : 'Plus aucun profil actif.', 'success');
            await refreshProfiles();
            renderProfilePanel();
        } else if (act === 'delete' && p) {
            if (!ed.confirmDelete) {
                ed.confirmDelete = true;
                renderProfilePanel();
                setTimeout(() => {
                    if (ed.confirmDelete) {
                        ed.confirmDelete = false;
                        if (ed.mode === 'view') renderProfilePanel();
                    }
                }, 3500);
                return;
            }
            ed.confirmDelete = false;
            const res = await post('deleteProfile', { id: p.id });
            if (!res || !res.ok) {
                toast(res?.error || 'Suppression impossible.', 'error');
                return;
            }
            toast('Profil supprimé.', 'success');
            ed.selected = null;
            ed.mode = 'empty';
            await refreshProfiles();
            renderProfilePanel();
        }
    });

    // ---- Véhicule ----
    async function findVehicle() {
        const res = await post('findVehicle');
        if (res && res.ok) {
            setVehicle(res.vehicle);
        } else {
            ed.vehicle = null;
            toast(res?.error || 'Aucun véhicule à proximité.', 'error');
        }
    }

    function setVehicle(vehicle) {
        ed.vehicle = vehicle || null;
        ed.vdraft = vehicle ? { ...emptyVehicle(), ...(vehicle.profile || {}) } : null;
        ed.vconfirm = false;
    }

    function vehicleFormHtml(v, d) {
        const area = (k, label, ph, rows = 3) => `
            <label class="lbl">${esc(label)}<textarea data-k="${k}" rows="${rows}" maxlength="1000" placeholder="${esc(ph)}">${esc(d[k])}</textarea></label>`;
        return `
            <div class="sheet-title">
                <span>${esc(v.label || 'Véhicule')} ${v.plate ? `— ${esc(v.plate)}` : ''} ${v.profile ? '<span class="flag c-green">Profil appliqué</span>' : ''}</span>
                <span class="sheet-actions"><button type="button" class="btn btn-small" data-act="vfind">Autre véhicule</button></span>
            </div>
            <div class="form-section">
                <span class="form-section-title">Inspection visuelle</span>
                <div class="form-part">
                    <label class="check"><input type="checkbox" data-k="visualKnown" ${d.visualKnown ? 'checked' : ''}> Éléments visibles</label>
                    <div class="two-cols part-fields ${d.visualKnown ? '' : 'hidden'}">
                        ${area('interior', 'Intérieur', 'ex : sièges tachés de sang, sachets vides au sol…')}
                        ${area('exterior', 'Extérieur', 'ex : pare-chocs enfoncé, impacts de balles…')}
                    </div>
                    <div class="part-default ${d.visualKnown ? 'hidden' : ''}">Non coché : « ${esc(DEFAULTS.vehicleVisual)} »</div>
                </div>
            </div>
            <div class="form-section">
                <span class="form-section-title">Inspection olfactive</span>
                <textarea data-k="olfactory" rows="2" maxlength="1000" placeholder="Vide : « ${esc(DEFAULTS.vehicleOlfactory)} »">${esc(d.olfactory)}</textarea>
            </div>
            <div class="form-section">
                <span class="form-section-title">Détail notoire</span>
                <div class="form-section-desc">Facultatif : éléments importants à prendre en compte</div>
                <textarea data-k="notable" rows="3" maxlength="1000" placeholder="Vide : « ${esc(DEFAULTS.notable)} »">${esc(d.notable)}</textarea>
            </div>
            <div class="form-section">
                <span class="form-section-title">Fouille du véhicule</span>
                <div class="form-section-desc">Facultatif. Vide : « ${esc(DEFAULTS.vehicleSearch)} »</div>
                ${area('cabin', 'Habitacle', 'Boîte à gants, vide-poches, sous les sièges avant…', 2)}
                ${area('rear', 'Banquette arrière', 'Sièges et plancher arrière…', 2)}
                ${area('trunk', 'Coffre', 'Contenu du coffre…', 2)}
            </div>
            <div class="note">Ce profil est lié à ce véhicule : il disparaît avec lui (ou au redémarrage du serveur)
                et n'est pas conservé dans vos profils.</div>
            <div class="form-actions">
                ${v.profile ? `<button type="button" class="btn btn-danger ${ed.vconfirm ? 'confirm' : ''}" data-act="vdelete">${ed.vconfirm ? 'Confirmer ?' : 'Supprimer le profil du véhicule'}</button>` : ''}
                <span class="grow"></span>
                <button type="button" class="btn btn-default" data-act="vsave">${v.profile ? 'Mettre à jour le véhicule' : 'Appliquer au véhicule'}</button>
            </div>`;
    }

    function renderVehicle() {
        const el = $('#vehicleDetail');
        const v = ed.vehicle;
        $('#vehicleTitle').textContent = v ? 'Profil du véhicule' : 'Véhicule';
        if (!v) {
            el.innerHTML = `<div class="empty">Aucun véhicule : montez dans le véhicule ou placez-vous juste à côté.
                <br><br><button type="button" class="btn" data-act="vfind">Rechercher le véhicule</button></div>`;
        } else if (v.taken) {
            el.innerHTML = `<div class="sheet-title"><span>${esc(v.label)} ${v.plate ? `— ${esc(v.plate)}` : ''}</span>
                <span class="sheet-actions"><button type="button" class="btn btn-small" data-act="vfind">Autre véhicule</button></span></div>
                <div class="empty">Ce véhicule a déjà un profil, créé par un autre joueur.</div>`;
        } else {
            el.innerHTML = vehicleFormHtml(v, ed.vdraft);
        }
    }

    bindDraft($('#vehicleDetail'), () => ed.vdraft);

    $('#vehicleDetail').addEventListener('click', async (e) => {
        const btn = e.target.closest('[data-act]');
        if (!btn) return;
        const act = btn.dataset.act;
        const v = ed.vehicle;
        if (act === 'vfind') {
            await findVehicle();
            renderVehicle();
        } else if (act === 'vsave' && v) {
            const d = ed.vdraft;
            if (d.visualKnown && !d.interior.trim() && !d.exterior.trim()) {
                toast('Inspection visuelle : remplissez l\'intérieur et / ou l\'extérieur (ou décochez la case).', 'error');
                return;
            }
            btn.disabled = true;
            const res = await post('saveVehicleProfile', { ...d, netId: v.netId, label: v.label, plate: v.plate });
            btn.disabled = false;
            if (!res || !res.ok) {
                toast(res?.error || 'Enregistrement impossible.', 'error');
                return;
            }
            toast(v.profile ? 'Profil du véhicule mis à jour.' : 'Profil appliqué au véhicule.', 'success');
            v.profile = { ...d };
            renderVehicle();
        } else if (act === 'vdelete' && v) {
            if (!ed.vconfirm) {
                ed.vconfirm = true;
                renderVehicle();
                setTimeout(() => {
                    if (ed.vconfirm) {
                        ed.vconfirm = false;
                        if (ed.tab === 'vehicle') renderVehicle();
                    }
                }, 3500);
                return;
            }
            ed.vconfirm = false;
            const res = await post('deleteVehicleProfile', { netId: v.netId });
            if (!res || !res.ok) {
                toast(res?.error || 'Suppression impossible.', 'error');
                return;
            }
            toast('Profil du véhicule supprimé.', 'success');
            v.profile = null;
            ed.vdraft = emptyVehicle();
            renderVehicle();
        }
    });

    // ---- Ouverture / fermeture ----
    function setEditor(data) {
        ed.open = !!data.open;
        $('#editor').classList.toggle('hidden', !ed.open);
        if (!ed.open) return;
        const profiles = data.profiles || {};
        ed.profiles = toArray(profiles.profiles);
        ed.max = profiles.max || ed.max;
        if (data.vehicle) setVehicle(data.vehicle);
        ed.selected = null;
        ed.mode = 'empty';
        ed.draft = null;
        centerEditor();
        renderProfileList();
        if (data.view === 'vehicle') {
            setTab('vehicle');
        } else {
            setTab('profiles');
            openProfileForm(emptyProfile()); // "Créer un profil" : formulaire vide prêt à remplir
        }
    }

    function centerEditor() {
        const win = $('#editor');
        const w = Math.min(980, innerWidth * 0.96);
        const h = Math.min(640, innerHeight * 0.94);
        win.style.left = `${Math.round((innerWidth - w) / 2)}px`;
        win.style.top = `${Math.round((innerHeight - h) / 2)}px`;
    }

    $('#editorClose').addEventListener('click', () => post('closeEditor'));

    // Déplacement de la fenêtre (barre de titre)
    let drag = null;
    $('#editorBar').addEventListener('mousedown', (e) => {
        if (e.target.closest('button')) return;
        const win = $('#editor');
        drag = { x: e.clientX - win.offsetLeft, y: e.clientY - win.offsetTop };
    });
    document.addEventListener('mousemove', (e) => {
        if (!drag) return;
        const win = $('#editor');
        win.style.left = `${Math.min(Math.max(e.clientX - drag.x, 0), innerWidth - 120)}px`;
        win.style.top = `${Math.min(Math.max(e.clientY - drag.y, 0), innerHeight - 40)}px`;
    });
    document.addEventListener('mouseup', () => { drag = null; });

    // Échap : liste de l'œil, puis fiche, puis menu
    document.addEventListener('keydown', (e) => {
        if (e.key !== 'Escape') return;
        if (eye.menu) {
            eye.menu = false;
            post('eyeCancel');
        } else if (ed.open) {
            post('closeEditor');
        } else if (menu.open) {
            if (menu.view !== 'home') {
                goBack();
            } else {
                post('closeMenu');
            }
        }
    });

    // =====================================================================
    // MENU DES TENUES /eup (au clavier : touches lues par client/eup.lua)
    // =====================================================================
    const EUP_SERVICES = [
        { code: 'APD', name: 'Atlanta Police Department', color: '#12357a' },
        { code: 'FCSO', name: 'Fayette County Sheriff Office', color: '#1e5631' },
        { code: 'GSP', name: 'Georgia State Patrol', color: '#ff6a00' },
    ];
    const EUP_COLORS = { root: '#23272e', police: '#1b2a44', civil: '#3b3f46', other: '#3a3350' };
    const EUP_VISIBLE = 10;
    const eup = { open: false, outfits: [], policeLocked: false, stack: [], worn: null };

    const plural = (n, word) => `${n} ${word}${n > 1 ? 's' : ''}`;

    function eupOutfitPage(title, list, color, banner) {
        return {
            title, color, banner,
            items: list.length ? list.map((o) => ({ kind: 'outfit', label: o.name, index: o.index,
                desc: 'Entrée : mettre cette tenue.' }))
                : [{ kind: 'empty', label: 'Aucune tenue', desc: 'Aucune tenue pour ce personnage dans data/outfits.json.' }],
        };
    }

    function eupPolicePage() {
        const police = eup.outfits.filter((o) => o.cate === 'police');
        const groups = EUP_SERVICES.map((s) => ({ ...s, list: police.filter((o) => o.group === s.code) }));
        const known = new Set(EUP_SERVICES.map((s) => s.code));
        [...new Set(police.map((o) => o.group || 'Autres').filter((g) => !known.has(g)))].sort()
            .forEach((g) => groups.push({ code: g, name: g, color: EUP_COLORS.other, list: police.filter((o) => (o.group || 'Autres') === g) }));
        return {
            title: 'Police', color: EUP_COLORS.police, banner: { title: 'Police', sub: 'APD · FCSO · GSP' },
            items: groups.map((g) => ({
                kind: 'menu', label: g.name, right: g.name !== g.code ? g.code : '', color: g.color,
                desc: `${plural(g.list.length, 'tenue')}${eup.policeLocked ? ' — réservées aux policiers en service (unité du MDC)' : ''}`,
                open: () => eupOutfitPage(g.code, g.list, g.color, { title: g.code, sub: g.name !== g.code ? g.name : 'Police' }),
            })),
        };
    }

    function eupCivilPage() {
        const civil = eup.outfits.filter((o) => o.cate !== 'police');
        const groupOf = (o) => (o.group && o.group.toLowerCase() !== 'civil' ? o.group : '');
        const groups = [...new Set(civil.map(groupOf).filter(Boolean))].sort();
        const banner = { title: 'Civil', sub: 'Tenues civiles' };
        if (!groups.length) return eupOutfitPage('Civil', civil, EUP_COLORS.civil, banner);
        const loose = civil.filter((o) => !groupOf(o));
        if (loose.length) groups.push('');
        return {
            title: 'Civil', color: EUP_COLORS.civil, banner,
            items: groups.map((g) => {
                const list = civil.filter((o) => groupOf(o) === g);
                return { kind: 'menu', label: g || 'Autres', desc: plural(list.length, 'tenue'),
                    open: () => eupOutfitPage(g || 'Autres', list, EUP_COLORS.civil, banner) };
            }),
        };
    }

    function eupRootPage() {
        const count = (cate) => eup.outfits.filter((o) => (cate === 'police' ? o.cate === 'police' : o.cate !== 'police')).length;
        return {
            title: 'Tenues', color: EUP_COLORS.root,
            items: [
                { kind: 'menu', label: 'Police', right: eup.policeLocked ? 'En service' : '', open: eupPolicePage,
                    desc: `APD, FCSO, GSP — ${plural(count('police'), 'tenue')}` },
                { kind: 'menu', label: 'Civil', open: eupCivilPage, desc: plural(count('civil'), 'tenue') },
            ],
        };
    }

    function renderEup() {
        const page = eup.stack[eup.stack.length - 1];
        if (!page) return;
        const sel = page.sel || 0;
        page.top = page.top || 0;
        if (sel < page.top) page.top = sel;
        if (sel >= page.top + EUP_VISIBLE) page.top = sel - EUP_VISIBLE + 1;
        const banner = page.banner || { title: 'Tenues', sub: 'EUP' };
        $('#eupBanner').style.setProperty('--eup-color', page.color || EUP_COLORS.root);
        $('#eupBanner .eup-title').textContent = banner.title;
        $('#eupBanner .eup-sub').textContent = banner.sub;
        $('#eupCrumb').textContent = eup.stack.map((p) => p.title).join(' › ');
        $('#eupCount').textContent = `${sel + 1}/${page.items.length}`;
        $('#eupList').innerHTML = page.items.slice(page.top, page.top + EUP_VISIBLE).map((it, i) => {
            const n = page.top + i;
            const worn = it.kind === 'outfit' && it.index === eup.worn;
            return `<div class="eup-item ${n === sel ? 'sel' : ''} ${it.kind === 'empty' ? 'empty' : ''}"
                ${it.color ? `style="--eup-tag:${esc(it.color)}"` : ''}>
                ${it.color ? '<span class="eup-tag"></span>' : ''}
                <span class="eup-label">${esc(it.label)}</span>
                ${it.right ? `<span class="eup-right">${esc(it.right)}</span>` : ''}
                ${worn ? '<span class="eup-worn">&#10003;</span>' : ''}
                ${it.kind === 'menu' ? '<span class="eup-arrow">&#8250;</span>' : ''}
            </div>`;
        }).join('');
        $('#eupDesc').textContent = (page.items[sel] && page.items[sel].desc) || '';
    }

    function setEup(data) {
        eup.open = !!data.open;
        $('#eup').classList.toggle('hidden', !eup.open);
        if (!eup.open) { eup.stack = []; return; }
        eup.outfits = toArray(data.outfits);
        eup.policeLocked = !!data.policeLocked;
        eup.stack = [{ ...eupRootPage(), sel: 0, top: 0 }];
        renderEup();
    }

    function eupKey(key) {
        if (!eup.open) return;
        const page = eup.stack[eup.stack.length - 1];
        const count = page.items.length;
        const item = page.items[page.sel || 0];
        if (key === 'up') page.sel = ((page.sel || 0) - 1 + count) % count;
        else if (key === 'down') page.sel = ((page.sel || 0) + 1) % count;
        else if (key === 'select' || key === 'right') {
            if (item && item.kind === 'menu') eup.stack.push({ ...item.open(), sel: 0, top: 0 });
            else if (item && item.kind === 'outfit' && key === 'select') {
                eup.worn = item.index;
                post('eupWear', { index: item.index });
            }
        } else if (key === 'back') {
            if (eup.stack.length > 1) eup.stack.pop(); else return post('eupClose');
        } else if (key === 'close') return post('eupClose');
        renderEup();
    }

    // =====================================================================
    // MESSAGES Lua -> NUI
    // =====================================================================
    window.addEventListener('message', ({ data }) => {
        if (!data || !data.action) return;
        switch (data.action) {
            case 'eye': setEye(data.data || {}); break;
            case 'eyeOptions': showEyeOptions(data.data || {}); break;
            case 'result': if (data.data) showResult(data.data); break;
            case 'menu': setMenu(data.data || {}); break;
            case 'menuLayout': setMenuLayout(data.data || {}); break;
            case 'menuPolice': // entrée / sortie d'une unité du MDC pendant que le menu est ouvert
                menu.data.police = data.data ? data.data.police : null;
                if (menu.open) renderMenu();
                break;
            case 'tips': setTips(data.data || {}); break;
            case 'menuActions': setMenuActions(data.data || {}); break;
            case 'progress': setProgress(data.data || {}); break;
            case 'editor': setEditor(data.data || {}); break;
            case 'notify': if (data.data) toast(data.data.text, data.data.type); break;
            case 'radio': radioUpdate(data.data); break;
            case 'radioStop': radioStop(data.data && data.data.id); break;
            case 'eup': setEup(data.data || {}); break;
            case 'eupKey': eupKey(data.data && data.data.key); break;
        }
    });
})();
