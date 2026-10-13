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
        home: 'Menu Interaction', civil: 'Civil', police: 'Police', equipment: 'Équipements',
        car: 'Voiture', spawn: 'Spawn', 'spawn-police': 'Véhicules de police', 'spawn-other': 'Autres véhicules', radio: 'Radio',
    };
    // Page précédente (bouton retour / Échap)
    const MENU_PARENT = { civil: 'home', police: 'home', equipment: 'home', car: 'home', spawn: 'car', radio: 'car', 'spawn-police': 'spawn', 'spawn-other': 'spawn' };
    // Catégories réservées (config.lua : Permissions) : page -> catégorie
    const SECTION_OF = { equipment: 'equipment', car: 'car', spawn: 'car', 'spawn-police': 'car', 'spawn-other': 'car', radio: 'car' };
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
            if (menu.view === 'equipment') loadEquipment();
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

    // ---- Équipements : tenues EUP et armes (data/equipment.lua) ----
    const listButtons = (items, kind, empty) => (items.length ? items.map((x) => `
        <button type="button" class="menu-item" data-kind="${kind}" data-index="${x.index}">${esc(x.name)}
            ${x.service ? `<small>${esc(x.service)}</small>` : ''}</button>`).join('') : `<div class="menu-empty">${esc(empty)}</div>`);

    async function loadEquipment() {
        const res = await post('equipmentList');
        if (!res || !res.ok) return;
        const locked = res.policeOnly && !res.police;
        const notice = $('#equipNotice');
        notice.classList.toggle('hidden', !locked && res.freemode);
        notice.textContent = locked ? 'Réservé à la police : rejoignez une unité dans le MDC.'
            : 'Tenues disponibles uniquement avec un personnage multijoueur (homme / femme).';
        $('#outfitList').innerHTML = listButtons(toArray(res.outfits), 'outfit', 'Aucune tenue pour ce personnage.');
        $('#loadoutList').innerHTML = listButtons(toArray(res.loadouts), 'loadout', 'Aucune arme configurée.');
        $$('#outfitList .menu-item, #loadoutList .menu-item').forEach((b) => { b.disabled = locked; });
    }

    document.addEventListener('click', async (e) => {
        const item = e.target.closest('#outfitList .menu-item, #loadoutList .menu-item');
        if (!item || item.disabled) return;
        post('useEquipment', { kind: item.dataset.kind, index: Number(item.dataset.index) });
    });
    $('#weaponsRemove').addEventListener('click', () => post('useEquipment', { kind: 'removeWeapons' }));

    // ---- Voiture > Spawn (data/vehicles.txt) ----
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
        fill('#spawnApd', apd, 'Aucun véhicule APD (data/vehicles.txt).');
        fill('#spawnGsp', gsp, 'Aucun véhicule GSP (data/vehicles.txt).');
        fill('#spawnFcso', fcso, 'Aucun véhicule FCSO (data/vehicles.txt).');
        fill('#spawnOther', other, 'Aucun véhicule (data/vehicles.txt).');
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
    function renderRadio(info) {
        const status = $('#radioStatus');
        const controls = $('#radioControls');
        info = info || {};
        if (!info.available) {
            status.className = 'menu-active none';
            status.textContent = info.error || 'Montez dans un véhicule (ou visez l\'intérieur avant avec l\'œil, portière ouverte).';
            controls.classList.add('disabled');
            controls.querySelectorAll('input, button').forEach((el) => { el.disabled = true; });
            return;
        }
        const radio = info.radio || null;
        status.className = `menu-active ${radio ? 'on-air' : 'none'}`;
        status.innerHTML = `${info.vehicle ? `<b>${esc(info.vehicle)}</b> — ` : ''}${radio ? 'radio allumée' : 'radio éteinte'}`
            + (radio ? `<br><small>${esc(radioEffects(info.id))}</small>` : '')
            + (info.canControl ? '' : '<br><small>Seules les places avant peuvent la régler.</small>');
        controls.classList.toggle('disabled', !info.canControl);
        controls.querySelectorAll('input, button').forEach((el) => { el.disabled = !info.canControl; });
        $('#radioStop').disabled = !info.canControl || !radio;
        if (radio && document.activeElement !== $('#radioUrl')) $('#radioUrl').value = radio.url || '';
        const volume = radio ? radio.volume : Number($('#radioVolume').value);
        $('#radioVolume').value = volume;
        $('#radioVolumeValue').textContent = `${volume} %`;
    }

    /** Effets du son (étouffé dehors, position) : actifs ou non pour la radio de ce véhicule */
    function radioEffects(id) {
        const r = radios[id];
        if (!r || r.kind === 'wait') return 'Préparation du son…';
        if (r.kind === 'audio' && r.gain) return 'Son du véhicule actif : étouffé dehors portières fermées, venant du véhicule.';
        return r.kind === 'yt'
            ? 'Lecteur YouTube classique (flux audio introuvable) : volume seulement, sans son étouffé.'
            : 'Ce site ne permet pas les effets : volume seulement, sans son étouffé.';
    }

    async function loadRadio() {
        renderRadio(await post('radioInfo'));
    }

    async function radioAction(action, extra = {}) {
        const res = await post('radioAction', { action, ...extra });
        if (!res || !res.ok) return toast(res?.error || 'Action impossible.', 'error');
        renderRadio(res);
    }
    $('#radioPlay').addEventListener('click', () => radioAction('play', { url: $('#radioUrl').value.trim(), volume: Number($('#radioVolume').value) }));
    $('#radioStop').addEventListener('click', () => radioAction('stop'));
    $('#radioVolume').addEventListener('input', () => { $('#radioVolumeValue').textContent = `${$('#radioVolume').value} %`; });
    $('#radioVolume').addEventListener('change', () => {
        if (!$('#radioStop').disabled) radioAction('volume', { volume: Number($('#radioVolume').value) });
    });

    // ---- Lecteurs de la radio des véhicules (client/radio.lua) ----
    // Chaîne audio : source -> filtre passe-bas ("étouffé" dehors, portières et vitres fermées)
    //                       -> son 3D (HRTF : le son vient du véhicule, devant / derrière / côtés) -> volume.
    // Le volume selon la distance est calculé par client/radio.lua (le son 3D ne donne que la direction).
    // YouTube : lu en flux audio (adresse cherchée par le serveur : "stream") pour pouvoir le filtrer et
    // le placer ; sans flux, lecteur YouTube classique (volume seulement).
    const radios = {};
    let ytReady = null;
    let audioCtx = null;
    const MUFFLED_HZ = 420;   // étouffé : on n'entend plus que les basses, comme à travers la carrosserie
    const CLEAR_HZ = 20000;

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
        if (r.kind === 'yt') {
            // Lecteur YouTube classique : ni filtre ni position, seulement le volume
            if (r.player && r.player.setVolume) r.player.setVolume(Math.round(v * 100));
        } else if (r.gain) {
            const t = audioCtx.currentTime;
            r.gain.gain.setTargetAtTime(v, t, 0.12);
            r.filter.frequency.setTargetAtTime(r.muffled ? MUFFLED_HZ : CLEAR_HZ, t, 0.15);
            if (r.panner) placeRadio(r, t);
        } else if (r.audio) {
            r.audio.volume = v;
        }
    }

    /** Son 3D (HRTF) : direction seulement, pas d'atténuation (déjà dans le volume) ; sinon gauche / droite */
    function createPanner() {
        try {
            const p = audioCtx.createPanner();
            p.panningModel = 'HRTF';
            p.distanceModel = 'linear';
            p.rolloffFactor = 0;
            p.refDistance = 1;
            return p;
        } catch (err) {
            return audioCtx.createStereoPanner ? audioCtx.createStereoPanner() : null;
        }
    }

    /** Position du véhicule vue de la caméra (x droite, y devant, z haut) -> repère Web Audio (devant = -Z) */
    function placeRadio(r, t) {
        const p = r.pos || { x: 0, y: 1, z: 0 }; // à bord : juste devant
        const len = Math.hypot(p.x, p.y, p.z) || 1;
        // Direction seule, ramenée à 1 m (le volume selon la distance vient de client/radio.lua)
        const x = p.x / len, y = p.z / len, z = -p.y / len;
        if (r.panner.pan) { r.panner.pan.setTargetAtTime(Math.max(-1, Math.min(1, x)) * 0.85, t, 0.1); return; }
        if (r.panner.positionX) {
            r.panner.positionX.setTargetAtTime(x, t, 0.1);
            r.panner.positionY.setTargetAtTime(y, t, 0.1);
            r.panner.positionZ.setTargetAtTime(z, t, 0.1);
        } else {
            r.panner.setPosition(x, y, z);
        }
    }

    function playIframe(r, id, offset) {
        r.kind = 'yt';
        const slot = document.createElement('div');
        r.holder.appendChild(slot);
        loadYouTube().then((YT) => {
            if (r.dead) return;
            r.player = new YT.Player(slot, {
                width: 200, height: 200, videoId: id,
                playerVars: { autoplay: 1, controls: 0, start: Math.floor(offset || 0), playsinline: 1 },
                events: { onReady: (e) => { applyRadio(r); e.target.seekTo(Math.floor(r.offset || offset || 0), true); e.target.playVideo(); } },
            });
        });
    }

    /** Lecture par <audio> + Web Audio (filtre, position) ; onFail : site sans CORS / flux illisible */
    function playAudio(r, src, offset, onFail) {
        r.kind = 'audio';
        const audio = new Audio();
        audio.crossOrigin = 'anonymous';
        audio.src = src;
        audio.addEventListener('loadedmetadata', () => {
            const now = r.offset ?? offset;
            if (Number.isFinite(audio.duration) && now < audio.duration) audio.currentTime = now;
        }, { once: true });
        audio.addEventListener('error', () => { if (!r.dead) onFail(); }, { once: true });
        r.audio = audio;
        try {
            audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)();
            if (audioCtx.state === 'suspended') audioCtx.resume().catch(() => {});
            const source = audioCtx.createMediaElementSource(audio);
            r.filter = audioCtx.createBiquadFilter();
            r.filter.type = 'lowpass';
            r.filter.Q.value = 0.9;
            r.panner = createPanner();
            r.gain = audioCtx.createGain();
            r.gain.gain.value = 0;
            let node = source.connect(r.filter);
            if (r.panner) node = node.connect(r.panner);
            node.connect(r.gain).connect(audioCtx.destination);
        } catch (err) {
            r.gain = null;
        }
        applyRadio(r);
        audio.play().then(() => {
            if (audioCtx && audioCtx.state === 'suspended') audioCtx.resume().catch(() => {});
        }).catch(() => {});
    }

    function stopMedia(r) {
        try { if (r.player && r.player.destroy) r.player.destroy(); } catch (err) { /* déjà fermé */ }
        r.player = null;
        if (r.audio) { r.audio.pause(); r.audio.removeAttribute('src'); r.audio.load(); }
        r.audio = null; r.gain = null; r.filter = null; r.panner = null;
        r.holder.innerHTML = '';
    }

    /** Lecteur selon le lien : flux audio (effets), YouTube classique ou lien direct sans effets */
    function startMedia(r, d) {
        const id = youtubeId(d.url);
        r.stream = d.stream;
        if (id) {
            if (d.stream === undefined || d.stream === null) { r.kind = 'wait'; return; } // flux cherché par le serveur
            if (!d.stream) return playIframe(r, id, d.offset);
            playAudio(r, d.stream, d.offset, () => { stopMedia(r); playIframe(r, id, r.offset); refreshRadioStatus(); });
            return;
        }
        // Lien direct : sans autorisation du site (CORS), lu quand même (sans filtre ni position)
        playAudio(r, d.url, d.offset, () => {
            stopMedia(r);
            refreshRadioStatus();
            r.kind = 'plain';
            const audio = new Audio(d.url);
            audio.addEventListener('loadedmetadata', () => {
                if (Number.isFinite(audio.duration) && r.offset < audio.duration) audio.currentTime = r.offset;
            }, { once: true });
            r.audio = audio;
            applyRadio(r);
            audio.play().catch(() => {});
        });
    }

    // Menu ouvert sur la page Radio : état des effets mis à jour (flux trouvé, lecteur de secours…)
    let radioStatusTimer = null;
    function refreshRadioStatus() {
        clearTimeout(radioStatusTimer);
        radioStatusTimer = setTimeout(() => { if (menu.open && menu.view === 'radio') loadRadio(); }, 400);
    }

    function createRadio(d) {
        const r = { url: d.url, volume: d.volume, muffled: d.muffled, pos: d.pos || null, offset: d.offset };
        r.holder = document.createElement('div');
        r.holder.className = 'radio-player';
        $('#radioPlayers').appendChild(r.holder);
        startMedia(r, d);
        return r;
    }

    function radioStop(id) {
        const r = radios[id];
        if (!r) return;
        r.dead = true;
        stopMedia(r);
        r.holder.remove();
        delete radios[id];
    }

    function radioUpdate(d) {
        if (!d || !d.id) return;
        let r = radios[d.id];
        if (r && r.url !== d.url) { radioStop(d.id); r = null; }
        if (!r) radios[d.id] = r = createRadio(d);
        else if ((r.stream ?? null) !== (d.stream ?? null)) {
            // Flux YouTube trouvé (ou introuvable) par le serveur : lecteur remplacé, au bon moment
            r.offset = d.offset;
            stopMedia(r);
            startMedia(r, d);
            refreshRadioStatus();
        }
        r.volume = Number(d.volume) || 0;
        r.muffled = !!d.muffled;
        r.pos = d.pos && typeof d.pos === 'object' ? { x: Number(d.pos.x) || 0, y: Number(d.pos.y) || 0, z: Number(d.pos.z) || 0 } : null;
        r.offset = d.offset;
        applyRadio(r);
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
        }
    });
})();
