// RP VehicleProps - NUI : liste des objets (ajouter / déplacer / retirer) et éditeur (position, rotation)
(() => {
    const $ = (s) => document.querySelector(s);
    const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'rp_vehicleprops';
    const post = (name, data = {}) => fetch(`https://${RES}/${name}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data),
    }).catch(() => {});

    const root = $('#vp');
    const TITLES = { add: 'Ajouter un objet', edit: 'Déplacer un objet', remove: 'Retirer un objet' };
    const POS = [{ key: 'x', label: 'Gauche / droite' }, { key: 'y', label: 'Arrière / avant' }, { key: 'z', label: 'Bas / haut' }];
    const ROT = [{ key: 'rx', label: 'Tangage' }, { key: 'ry', label: 'Roulis' }, { key: 'rz', label: 'Lacet' }];
    const ed = { offsets: {}, range: 3, step: 0.01, rotStep: 1, sens: 1, sensCfg: { min: 0.05, max: 3, step: 0.05 } };

    const el = (tag, cls, text) => {
        const e = document.createElement(tag);
        if (cls) e.className = cls;
        if (text !== undefined) e.textContent = text;
        return e;
    };
    const clamp = (v, min, max) => { const n = Number(v); return Number.isNaN(n) ? 0 : Math.min(max, Math.max(min, n)); };

    function show(view, title, vehicle) {
        $('#vpTitle').textContent = title;
        $('#vpSub').textContent = vehicle ? [vehicle.name && vehicle.name !== 'NULL' ? vehicle.name : 'Véhicule', vehicle.plate].filter(Boolean).join(' · ') : '';
        $('#vpList').classList.toggle('hidden', view !== 'list');
        $('#vpEditor').classList.toggle('hidden', view !== 'editor');
        $('#vpKeyText').textContent = view === 'editor' ? 'Annuler sans enregistrer · molette sur une ligne : un pas' : 'Fermer';
        root.classList.remove('hidden');
    }

    // ---- Liste
    function showList(d) {
        const list = $('#vpList');
        list.replaceChildren();
        const items = d.mode === 'add' ? (d.props || []) : (d.placed || []);
        if (!items.length) list.append(el('div', 'vp-empty', 'Aucun objet sur ce véhicule.'));
        let category = null;
        items.forEach((it) => {
            if (it.category !== category) {
                category = it.category;
                list.append(el('div', 'vp-cat', category || 'Objets'));
            }
            const b = el('button', 'vp-item' + (d.mode === 'remove' ? ' danger' : ''));
            b.type = 'button';
            b.append(el('span', 'vp-item-label', it.label), el('span', 'vp-item-go', d.mode === 'remove' ? 'Retirer' : '›'));
            b.addEventListener('click', () => post('choose', { mode: d.mode, id: it.id }));
            list.append(b);
        });
        show('list', TITLES[d.mode] || 'Objets du véhicule', d.vehicle);
    }

    // ---- Éditeur
    function pushOffsets() { post('offsets', ed.offsets); }

    function sliderRow(def, isRot) {
        const row = el('div', 'vp-row');
        const min = isRot ? -180 : -ed.range;
        const max = isRot ? 180 : ed.range;
        const step = (isRot ? ed.rotStep : ed.step) * ed.sens;
        const range = el('input'); range.type = 'range'; range.min = min; range.max = max; range.step = step;
        const num = el('input', 'vp-num'); num.type = 'number'; num.min = min; num.max = max; num.step = step;
        const set = (v) => {
            const n = clamp(v, min, max);
            ed.offsets[def.key] = n;
            range.value = n;
            num.value = n.toFixed(isRot ? 1 : 2);
            pushOffsets();
        };
        range.value = ed.offsets[def.key] || 0;
        num.value = Number(ed.offsets[def.key] || 0).toFixed(isRot ? 1 : 2);
        range.addEventListener('input', () => set(range.value));
        num.addEventListener('change', () => set(num.value));
        // Molette sur la ligne : un pas de plus / de moins
        row.addEventListener('wheel', (e) => { e.preventDefault(); set((ed.offsets[def.key] || 0) + (e.deltaY < 0 ? step : -step)); }, { passive: false });
        row.append(el('span', 'vp-label', def.label), range, num);
        return row;
    }

    function buildSliders() {
        $('#vpPos').replaceChildren(...POS.map((d) => sliderRow(d, false)));
        $('#vpRot').replaceChildren(...ROT.map((d) => sliderRow(d, true)));
    }

    function setSens(v) {
        const c = ed.sensCfg;
        ed.sens = clamp(v, c.min, c.max);
        const s = $('#vpSens');
        s.min = c.min; s.max = c.max; s.step = c.step; s.value = ed.sens;
        $('#vpSensVal').textContent = `x${ed.sens.toFixed(2)}`;
        buildSliders();
    }

    function showEditor(d) {
        ed.offsets = { x: 0, y: 0, z: 0, rx: 0, ry: 0, rz: 0, ...(d.offsets || {}) };
        ed.range = Number(d.range) || 3;
        ed.step = Number(d.step) || 0.01;
        ed.rotStep = Number(d.rotStep) || 1;
        ed.sensCfg = { min: 0.05, max: 3, step: 0.05, ...(d.sensitivity || {}) };
        setSens((d.sensitivity && d.sensitivity.default) || 1);
        $('#vpHint').textContent = d.mode === 'edit'
            ? 'Réglez la position puis enregistrez. L\'aperçu n\'est visible que par vous.'
            : 'L\'objet apparaît là où vous regardiez. Réglez-le puis enregistrez : il sera visible par tous.';
        show('editor', d.title || 'Objet', d.vehicle);
    }

    $('#vpSens').addEventListener('input', (e) => setSens(e.target.value));
    $('#vpReset').addEventListener('click', () => { ed.offsets.rx = 0; ed.offsets.ry = 0; ed.offsets.rz = 0; buildSliders(); pushOffsets(); });
    $('#vpSave').addEventListener('click', () => post('save'));
    $('#vpCancel').addEventListener('click', () => post('close'));
    $('#vpClose').addEventListener('click', () => post('close'));
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !root.classList.contains('hidden')) post('close'); });

    // Mode nuit des menus (MDC : Paramètres > MDC > Apparence), envoyé par client/theme.lua
    window.addEventListener('message', ({ data }) => {
        if (!data || !data.action) return;
        const d = data.data || {};
        if (data.action === 'uiTheme') {
            document.documentElement.dataset.theme = 'night'; // toujours sombre : de jour, couleurs du logo du serveur
            document.documentElement.dataset.nightColor = d.theme === 'night' && ['green', 'yellow', 'red', 'blue'].includes(d.color) ? d.color : 'logo';
        } else if (data.action === 'list') {
            showList(d);
        } else if (data.action === 'editor') {
            showEditor(d);
        } else if (data.action === 'close') {
            root.classList.add('hidden');
        }
    });
})();
