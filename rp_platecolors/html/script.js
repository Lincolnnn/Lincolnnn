// RP PlateColors : éditeur des plaques (client/editor.lua envoie open / refresh / close / looking / message)
(() => {
    const $ = (id) => document.getElementById(id);
    const box = $('pc');
    const resource = typeof window.GetParentResourceName === 'function' ? window.GetParentResourceName() : 'rp_platecolors';
    // Réglages de position : pas des boutons −/+ (Maj : x5)
    const FIELDS = [
        { key: 'x', label: 'Gauche / droite', unit: 'm', step: 0.005, digits: 3 },
        { key: 'y', label: 'Avant / arrière', unit: 'm', step: 0.005, digits: 3 },
        { key: 'z', label: 'Hauteur', unit: 'm', step: 0.005, digits: 3 },
        { key: 'pitch', label: 'Inclinaison', unit: '°', step: 0.5, digits: 1 },
        { key: 'yaw', label: 'Rotation', unit: '°', step: 0.5, digits: 1 },
        { key: 'scale', label: 'Taille', unit: '×', step: 0.01, digits: 2 },
    ];
    // Raccourcis clavier : touche -> [réglage, sens]
    const KEYS = {
        ArrowLeft: ['x', -1], ArrowRight: ['x', 1], ArrowUp: ['z', 1], ArrowDown: ['z', -1],
        PageUp: ['y', 1], PageDown: ['y', -1], r: ['pitch', 1], f: ['pitch', -1],
        q: ['yaw', -1], e: ['yaw', 1], '+': ['scale', 1], '=': ['scale', 1], '-': ['scale', -1],
    };
    // Fond approximatif de chaque type de plaque pour l'aperçu (gris neutre si inconnu : noir et blanc restent lisibles)
    const SAMPLE_BG = { 0: '#f1f1ec', 1: '#151515', 2: '#1d3f8f', 3: '#f4f4f4', 4: '#efefef', 5: '#e9e6dc', 7: '#ece7da', 8: '#ecebe6' };
    let state = null;
    let colors = [];
    let msgTimer = null;

    function post(name, data) {
        return fetch(`https://${resource}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        }).then((r) => r.json()).catch(() => ({}));
    }

    function esc(text) {
        return String(text == null ? '' : text).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    }

    function message(text, error) {
        const el = $('pcMsg');
        el.textContent = text || '';
        el.classList.toggle('error', !!error);
        clearTimeout(msgTimer);
        msgTimer = setTimeout(() => { el.textContent = ''; }, 3500);
    }

    // ---------------------------------------------------------------- Position
    function buildRows() {
        $('pcRows').innerHTML = FIELDS.map((f) => `
            <div class="pc-row">
                <span class="pc-label">${f.label}</span>
                <span style="display:flex;align-items:center;gap:6px">
                    <span class="pc-qty">
                        <button class="pc-qty-btn" data-key="${f.key}" data-dir="-1">−</button>
                        <input type="number" step="${f.step}" data-key="${f.key}">
                        <button class="pc-qty-btn" data-key="${f.key}" data-dir="1">+</button>
                    </span>
                    <span class="pc-unit">${f.unit}</span>
                </span>
            </div>`).join('');
    }

    function renderState() {
        if (!state || !state.data) return;
        const side = state.data[state.side];
        $('pcName').textContent = state.label || 'Véhicule';
        $('pcSub').textContent = `Plaque « ${String(state.plateText || '').trim()} » · type ${state.plateIndex}`
            + (state.saved ? ' · réglage enregistré' : ' · placement automatique');
        document.querySelectorAll('#pcSides .pc-seg-btn').forEach((b) => b.classList.toggle('active', b.dataset.side === state.side));
        $('pcOn').checked = !!side.on;
        $('pcRows').classList.toggle('off', !side.on);
        FIELDS.forEach((f) => {
            const input = document.querySelector(`#pcRows input[data-key="${f.key}"]`);
            if (input !== document.activeElement) input.value = Number(side[f.key]).toFixed(f.digits);
        });
        $('pcReset').classList.toggle('hidden', !state.saved);
        document.querySelectorAll('.pc-color').forEach((row) => row.classList.toggle('current', Number(row.dataset.index) === state.plateIndex));
    }

    function apply(res) { if (res && res.data) { state = res; renderState(); } }

    function setValue(key, value) {
        if (!state) return;
        const f = FIELDS.find((x) => x.key === key);
        const v = Number(Number(value).toFixed(f.digits + 1));
        if (!Number.isFinite(v)) return;
        state.data[state.side][key] = v;
        renderState();
        post('set', { side: state.side, key, value: v }).then(apply);
    }

    function nudge(key, dir, big) {
        const f = FIELDS.find((x) => x.key === key);
        const cur = Number(state.data[state.side][key]) || 0;
        setValue(key, cur + dir * f.step * (big ? 5 : 1));
    }

    $('pcRows').addEventListener('click', (e) => {
        const b = e.target.closest('.pc-qty-btn');
        if (b) nudge(b.dataset.key, Number(b.dataset.dir), e.shiftKey);
    });
    $('pcRows').addEventListener('change', (e) => {
        if (e.target.dataset.key) setValue(e.target.dataset.key, e.target.value);
    });
    $('pcSides').addEventListener('click', (e) => {
        const b = e.target.closest('[data-side]');
        if (b) post('side', { side: b.dataset.side }).then(apply);
    });
    $('pcOn').addEventListener('change', (e) => post('set', { side: state.side, key: 'on', value: e.target.checked }).then(apply));
    $('pcAuto').addEventListener('click', () => post('auto').then((res) => { apply(res); message('Estimation automatique (pas encore enregistrée).'); }));
    $('pcSave').addEventListener('click', () => post('save'));
    $('pcReset').addEventListener('click', () => post('reset'));

    // ---------------------------------------------------------------- Couleurs
    function renderColors() {
        $('pcColors').innerHTML = colors.map((c) => `
            <div class="pc-color" data-index="${c.index}">
                <div class="pc-sample" title="Mettre ce type de plaque sur le véhicule" data-try="${c.index}"
                     style="background:${SAMPLE_BG[c.index] || '#8a8f96'};color:${c.text};${c.outline ? `-webkit-text-stroke:1px ${c.outline}` : ''}">12AB</div>
                <div class="pc-color-info"><b>${esc(c.label)}</b><small>type ${c.index}</small></div>
                <div class="pc-color-tools">
                    <input type="color" data-k="text" value="${c.text}" title="Couleur du texte">
                    <label title="Contour"><input type="checkbox" data-k="outlineOn" ${c.outline ? 'checked' : ''}>contour</label>
                    <input type="color" data-k="outline" value="${c.outline || '#ffffff'}" ${c.outline ? '' : 'disabled'} title="Couleur du contour">
                </div>
            </div>`).join('');
        renderState();
    }

    function colorChanged(row) {
        const c = colors.find((x) => x.index === Number(row.dataset.index));
        const on = row.querySelector('[data-k="outlineOn"]').checked;
        const outlineInput = row.querySelector('[data-k="outline"]');
        outlineInput.disabled = !on;
        c.text = row.querySelector('[data-k="text"]').value;
        c.outline = on ? outlineInput.value : false;
        const sample = row.querySelector('.pc-sample');
        sample.style.color = c.text;
        sample.style.webkitTextStroke = c.outline ? `1px ${c.outline}` : '0';
        post('color', { index: c.index, text: c.text, outline: c.outline });
    }

    $('pcColors').addEventListener('input', (e) => { const row = e.target.closest('.pc-color'); if (row) colorChanged(row); });
    $('pcColors').addEventListener('click', (e) => {
        const t = e.target.closest('[data-try]');
        if (t) post('plateIndex', { index: Number(t.dataset.try) }).then(apply);
    });
    $('pcColorsSave').addEventListener('click', () => post('saveColors'));
    $('pcColorsReset').addEventListener('click', () => post('resetColors'));

    // ---------------------------------------------------------------- Général
    $('pcTabs').addEventListener('click', (e) => {
        const b = e.target.closest('[data-tab]');
        if (!b) return;
        document.querySelectorAll('#pcTabs .pc-seg-btn').forEach((x) => x.classList.toggle('active', x === b));
        document.querySelectorAll('[data-panel]').forEach((p) => p.classList.toggle('hidden', p.dataset.panel !== b.dataset.tab));
    });
    $('pcClose').addEventListener('click', () => post('close'));

    document.addEventListener('keydown', (e) => {
        if (box.classList.contains('hidden')) return;
        if (e.key === 'Escape') { e.preventDefault(); post('close'); return; }
        if (e.key === 'Tab') {
            e.preventDefault();
            box.classList.add('looking');
            message('Souris libérée : Tab pour reprendre le panneau.');
            post('look');
            return;
        }
        const typing = e.target.tagName === 'INPUT' && e.target.type === 'number';
        const map = KEYS[e.key.length === 1 ? e.key.toLowerCase() : e.key];
        if (!typing && map && state && state.data[state.side].on && !document.querySelector('[data-panel="pos"]').classList.contains('hidden')) {
            e.preventDefault();
            nudge(map[0], map[1], e.shiftKey);
        }
    });

    window.addEventListener('message', (event) => {
        const { action, data } = event.data || {};
        if (action === 'open' || action === 'refresh') {
            if (action === 'open') {
                box.classList.remove('hidden', 'looking');
                $('pcMsg').textContent = '';
            }
            colors = data.colors || [];
            state = data.state;
            renderColors();
        } else if (action === 'close') {
            box.classList.add('hidden');
            state = null;
        } else if (action === 'looking') {
            box.classList.toggle('looking', !!data);
        } else if (action === 'message') {
            message(data.text, data.error);
        }
    });

    buildRows();
})();
