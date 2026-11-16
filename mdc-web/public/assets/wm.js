// =====================================================================================================================
// GESTIONNAIRE DE FENÊTRES du MDC Web : fenêtres flottantes (déplacer, redimensionner, réduire, agrandir, épingler,
// fermer), dock, espaces de travail (Dispatch, Enquête, Supervision) gardés par dispatcher, palette de commandes,
// menus contextuels, confirmations. Aucune dépendance. API : window.WM.
// =====================================================================================================================
(() => {
    'use strict';
    const $ = (s, root = document) => root.querySelector(s);
    const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
    const icon = (name) => `<svg class="i" aria-hidden="true"><use href="#i-${name}"/></svg>`;
    const desk = $('#desk');
    const apps = new Map();      // id -> définition
    const wins = new Map();      // id -> élément
    let z = 10;
    let saveTimer = null;
    let onSave = () => {};

    // Espaces de travail : position / taille en fraction du bureau (s'adaptent à l'écran)
    const DEFAULTS = {
        dispatch: {
            kpi: { x: 0, y: 0, w: 0.62, h: 0.15 }, queue: { x: 0, y: 0.165, w: 0.62, h: 0.37 },
            units: { x: 0.628, y: 0, w: 0.372, h: 0.535 }, calls: { x: 0, y: 0.55, w: 0.62, h: 0.45 },
        },
        enquete: { search: { x: 0, y: 0, w: 0.48, h: 1 }, registries: { x: 0.49, y: 0, w: 0.51, h: 1 } },
        supervision: { live: { x: 0, y: 0, w: 0.66, h: 1 }, audit: { x: 0.67, y: 0, w: 0.33, h: 0.5 }, trash: { x: 0.67, y: 0.51, w: 0.33, h: 0.49 } },
    };
    const state = { ws: 'dispatch', layouts: {} }; // layouts[ws][id] = { x, y, w, h (px), min, max, pinned }

    const deskRect = () => desk.getBoundingClientRect();
    const narrow = () => window.matchMedia('(max-width: 1100px)').matches;

    function layoutOf(ws = state.ws) {
        if (!state.layouts[ws]) state.layouts[ws] = {};
        return state.layouts[ws];
    }
    function save() {
        clearTimeout(saveTimer);
        saveTimer = setTimeout(() => onSave({ ws: state.ws, layouts: state.layouts }), 700);
    }
    function defaultRect(id) {
        const r = deskRect();
        const d = (DEFAULTS[state.ws] || {})[id] || apps.get(id).rect || { x: 0.2, y: 0.08, w: 0.5, h: 0.75 };
        return { x: Math.round(d.x * r.width), y: Math.round(d.y * r.height), w: Math.round(d.w * r.width) - (d.x + d.w < 1 ? 10 : 0),
            h: Math.round(d.h * r.height) - (d.y + d.h < 1 ? 10 : 0) };
    }
    function clamp(rect) {
        const r = deskRect();
        const w = Math.max(300, Math.min(rect.w, r.width));
        const h = Math.max(140, Math.min(rect.h, r.height));
        // fenêtre entière sur le bureau : coin de redimensionnement et boutons toujours atteignables
        return { x: Math.max(0, Math.min(rect.x, r.width - w)), y: Math.max(0, Math.min(rect.y, r.height - h)), w, h };
    }
    function apply(id) {
        const el = wins.get(id);
        const l = layoutOf()[id];
        if (!el || !l) return;
        const c = clamp(l);
        Object.assign(el.style, { left: `${c.x}px`, top: `${c.y}px`, width: `${c.w}px`, height: `${c.h}px` });
        el.classList.toggle('hidden', !!l.min);
        el.classList.toggle('max', !!l.max);
        el.classList.toggle('pinned', !!l.pinned);
        el.style.zIndex = (l.pinned ? 500 : 0) + (l.z || 1);
        const pin = el.querySelector('[data-wact="pin"]');
        if (pin) pin.setAttribute('aria-pressed', l.pinned ? 'true' : 'false');
    }

    function focus(id) {
        const el = wins.get(id);
        if (!el) return;
        const l = layoutOf()[id];
        l.z = ++z;
        for (const [wid, w] of wins) w.classList.toggle('active', wid === id);
        apply(id);
        renderDock();
    }

    function build(id) {
        const app = apps.get(id);
        const el = document.createElement('section');
        el.className = 'win glass opening';
        el.dataset.win = id;
        el.setAttribute('role', 'dialog');
        el.setAttribute('aria-label', app.title);
        el.innerHTML = `
            <div class="win-head">
                <span class="tag-dot"></span>
                <h2>${esc(app.title)}</h2><span class="meta" data-wmeta></span>
                ${app.headButtons || ''}
                <button type="button" class="win-ctl" data-wact="pin" title="Épingler au premier plan" aria-pressed="false">${icon('pin')}</button>
                <button type="button" class="win-ctl" data-wact="min" title="Réduire (Alt+M)">${icon('min')}</button>
                <button type="button" class="win-ctl maxbtn" data-wact="max" title="Agrandir / restaurer">${icon('max')}</button>
                <button type="button" class="win-ctl close" data-wact="close" title="Fermer">${icon('x')}</button>
            </div>
            <div class="win-body"></div>
            <span class="resize" aria-hidden="true"></span>`;
        el.querySelector('.tag-dot').style.background = app.color || 'var(--text-3)';
        const tpl = app.template && document.getElementById(app.template);
        if (tpl) el.querySelector('.win-body').appendChild(tpl.content.cloneNode(true));
        desk.appendChild(el);
        wins.set(id, el);
        requestAnimationFrame(() => el.classList.remove('opening'));

        el.addEventListener('pointerdown', () => focus(id), true);
        el.querySelector('.win-head').addEventListener('dblclick', (e) => { if (!e.target.closest('button')) toggle(id, 'max'); });
        el.querySelector('.win-head').addEventListener('click', (e) => {
            const b = e.target.closest('[data-wact]');
            if (!b) return;
            const act = b.dataset.wact;
            if (act === 'close') close(id);
            else toggle(id, act);
        });
        // déplacer
        el.querySelector('.win-head').addEventListener('pointerdown', (e) => {
            if (e.button !== 0 || e.target.closest('button, input, select') || narrow()) return;
            const l = layoutOf()[id];
            if (l.max) return;
            const startX = e.clientX; const startY = e.clientY; const ox = l.x; const oy = l.y;
            const move = (ev) => { l.x = ox + ev.clientX - startX; l.y = oy + ev.clientY - startY; apply(id); };
            const up = () => { removeEventListener('pointermove', move); removeEventListener('pointerup', up); Object.assign(l, clamp(l)); save(); };
            addEventListener('pointermove', move);
            addEventListener('pointerup', up);
        });
        // redimensionner
        el.querySelector('.resize').addEventListener('pointerdown', (e) => {
            e.stopPropagation();
            const l = layoutOf()[id];
            const sx = e.clientX; const sy = e.clientY; const ow = l.w; const oh = l.h;
            const move = (ev) => { l.w = ow + ev.clientX - sx; l.h = oh + ev.clientY - sy; l.max = false; apply(id); };
            const up = () => { removeEventListener('pointermove', move); removeEventListener('pointerup', up); Object.assign(l, clamp(l)); save(); };
            addEventListener('pointermove', move);
            addEventListener('pointerup', up);
        });
        if (app.onOpen) app.onOpen(el);
        return el;
    }

    function open(id, opts = {}) {
        if (!apps.has(id)) return null;
        const lay = layoutOf();
        if (!lay[id]) lay[id] = { ...defaultRect(id), min: false, max: false, pinned: false, z: ++z };
        lay[id].min = false;
        lay[id].closed = false;
        let el = wins.get(id);
        if (!el) el = build(id);
        apply(id);
        if (opts.focus !== false) focus(id);
        save();
        renderDock();
        if (apps.get(id).onShow) apps.get(id).onShow(el);
        return el;
    }
    function close(id) {
        const el = wins.get(id);
        if (!el) return;
        const app = apps.get(id);
        if (app.canClose && !app.canClose()) return;
        el.remove();
        wins.delete(id);
        const l = layoutOf()[id];
        if (l) l.closed = true;
        if (app.onClose) app.onClose();
        save();
        renderDock();
    }
    function toggle(id, what) {
        const l = layoutOf()[id];
        if (!l) return;
        if (what === 'min') { l.min = !l.min; if (!l.min) focus(id); }
        if (what === 'max') { l.max = !l.max; focus(id); }
        if (what === 'pin') { l.pinned = !l.pinned; focus(id); }
        apply(id);
        save();
        renderDock();
    }

    // ---- espaces de travail ----
    function switchWorkspace(ws) {
        if (!DEFAULTS[ws]) return;
        for (const id of [...wins.keys()]) { wins.get(id).remove(); wins.delete(id); if (apps.get(id).onClose) apps.get(id).onClose(); }
        state.ws = ws;
        const lay = layoutOf();
        const ids = Object.keys(lay).length ? Object.keys(lay).filter((id) => !lay[id].closed) : Object.keys(DEFAULTS[ws]);
        for (const id of ids) if (apps.has(id) && !apps.get(id).transient) open(id, { focus: false });
        for (const b of document.querySelectorAll('#wsSwitch [data-ws]')) b.setAttribute('aria-pressed', b.dataset.ws === ws ? 'true' : 'false');
        save();
        renderDock();
    }
    document.querySelectorAll('#wsSwitch [data-ws]').forEach((b) => b.addEventListener('click', () => switchWorkspace(b.dataset.ws)));

    // ---- dock ----
    const badges = {};
    function renderDock() {
        const front = [...wins.entries()].sort((a, b) => (layoutOf()[b[0]].z || 0) - (layoutOf()[a[0]].z || 0))[0];
        $('#dockApps').innerHTML = [...apps.values()].filter((a) => a.dock !== false).map((a) => {
            const isOpen = wins.has(a.id);
            const l = layoutOf()[a.id];
            const n = badges[a.id];
            return `<button type="button" class="task ${isOpen ? 'open' : ''} ${front && front[0] === a.id ? 'front' : ''} ${l && l.min ? 'min' : ''}" data-dock="${a.id}"
                title="${esc(a.title)}${a.key ? ` (${a.key})` : ''}" aria-label="${esc(a.title)}">${icon(a.icon)}<span class="lbl">${esc(a.short || a.title)}</span>${n ? `<span class="count">${n}</span>` : ''}</button>`;
        }).join('');
    }
    $('#dockApps').addEventListener('click', (e) => {
        const b = e.target.closest('[data-dock]');
        if (!b) return;
        const id = b.dataset.dock;
        const l = layoutOf()[id];
        if (wins.has(id) && l && !l.min && b.classList.contains('front')) toggle(id, 'min'); // clic sur la fenêtre de devant : réduire
        else open(id);
    });
    $('#dockApps').addEventListener('contextmenu', (e) => {
        const b = e.target.closest('[data-dock]');
        if (!b) return;
        e.preventDefault();
        const id = b.dataset.dock;
        menu(e.clientX, e.clientY - 120, [
            { label: wins.has(id) ? 'Mettre devant' : 'Ouvrir', icon: apps.get(id).icon, action: () => open(id) },
            ...(wins.has(id) ? [{ label: 'Réduire / restaurer', icon: 'min', action: () => toggle(id, 'min') }, { label: 'Fermer', icon: 'x', action: () => close(id) }] : []),
        ]);
    });

    // ---- menu contextuel ----
    const ctx = $('#ctxmenu');
    function menu(x, y, items) {
        ctx.innerHTML = items.map((it, i) => (it.sep ? '<hr>' : `<button type="button" role="menuitem" data-i="${i}" class="${it.danger ? 'danger' : ''}" ${it.disabled ? 'disabled' : ''}>${icon(it.icon || 'check')}${esc(it.label)}</button>`)).join('');
        ctx.classList.remove('hidden');
        const r = ctx.getBoundingClientRect();
        ctx.style.left = `${Math.min(x, innerWidth - r.width - 8)}px`;
        ctx.style.top = `${Math.max(8, Math.min(y, innerHeight - r.height - 8))}px`;
        ctx.onclick = (e) => {
            const b = e.target.closest('[data-i]');
            if (!b) return;
            hideMenu();
            const it = items[Number(b.dataset.i)];
            if (it && it.action) it.action();
        };
        const first = ctx.querySelector('button');
        if (first) first.focus();
    }
    function hideMenu() { ctx.classList.add('hidden'); }
    addEventListener('pointerdown', (e) => { if (!e.target.closest('#ctxmenu')) hideMenu(); }, true);
    addEventListener('blur', hideMenu);
    ctx.addEventListener('keydown', (e) => {
        const btns = [...ctx.querySelectorAll('button:not([disabled])')];
        const i = btns.indexOf(document.activeElement);
        if (e.key === 'ArrowDown') { e.preventDefault(); (btns[i + 1] || btns[0]).focus(); }
        if (e.key === 'ArrowUp') { e.preventDefault(); (btns[i - 1] || btns[btns.length - 1]).focus(); }
        if (e.key === 'Escape') hideMenu();
    });

    // ---- confirmation (toute action destructive) / saisie d'un motif ----
    function confirmBox({ title, text, ok = 'Confirmer', danger = true, input = false, placeholder = '', extra = '' }) {
        return new Promise((resolve) => {
            const m = $('#modal');
            $('#modalTitle').textContent = title;
            $('#modalText').innerHTML = text;
            $('#modalExtra').innerHTML = extra;
            $('#modalInput').classList.toggle('hidden', !input);
            $('#modalInput').value = '';
            $('#modalInput').placeholder = placeholder;
            $('#modalOk').textContent = ok;
            $('#modalOk').className = `btn ${danger ? 'stop' : 'primary'}`;
            m.classList.remove('hidden');
            (input ? $('#modalInput') : $('#modalCancel')).focus();
            const done = (v) => { m.classList.add('hidden'); $('#modalForm').onsubmit = null; $('#modalCancel').onclick = null; resolve(v); };
            $('#modalForm').onsubmit = (e) => {
                e.preventDefault();
                const extraVal = $('#modalExtra input') ? $('#modalExtra input').checked : undefined;
                done(input ? { value: $('#modalInput').value.trim(), extra: extraVal } : (extraVal === undefined ? true : { extra: extraVal }));
            };
            $('#modalCancel').onclick = () => done(null);
        });
    }

    // ---- palette de commandes (Ctrl+K) ----
    const pal = { providers: [], items: [], index: 0 };
    function openPalette(prefill = '') {
        $('#palette').classList.remove('hidden');
        $('#palInput').value = prefill;
        renderPalette();
        $('#palInput').focus();
    }
    function closePalette() { $('#palette').classList.add('hidden'); }
    function renderPalette() {
        const q = $('#palInput').value.trim();
        const groups = pal.providers.map((p) => p(q)).filter((g) => g && g.items.length);
        pal.items = groups.flatMap((g) => g.items);
        pal.index = Math.min(pal.index, Math.max(0, pal.items.length - 1));
        let i = 0;
        $('#palList').innerHTML = groups.map((g) => `<div class="pal-group">${esc(g.title)}</div>${g.items.slice(0, 8).map((it) => {
            const idx = pal.items.indexOf(it);
            i += 1;
            return `<div class="pal-item ${idx === pal.index ? 'active' : ''}" role="option" data-pi="${idx}">${icon(it.icon || 'search')}${esc(it.label)}${it.hint ? ` <span class="muted">${esc(it.hint)}</span>` : ''}${it.key ? `<span class="kbd">${esc(it.key)}</span>` : ''}</div>`;
        }).join('')}`).join('') || '<div class="empty"><b>Aucun résultat</b></div>';
    }
    $('#palInput').addEventListener('input', () => { pal.index = 0; renderPalette(); });
    $('#palInput').addEventListener('keydown', (e) => {
        const shown = [...document.querySelectorAll('#palList [data-pi]')].map((x) => Number(x.dataset.pi));
        const pos = shown.indexOf(pal.index);
        if (e.key === 'ArrowDown') { e.preventDefault(); pal.index = shown[Math.min(shown.length - 1, pos + 1)] ?? 0; renderPalette(); }
        if (e.key === 'ArrowUp') { e.preventDefault(); pal.index = shown[Math.max(0, pos - 1)] ?? 0; renderPalette(); }
        if (e.key === 'Enter') { e.preventDefault(); runPalette(pal.index); }
        if (e.key === 'Escape') closePalette();
    });
    function runPalette(idx) {
        const groups = pal.providers.map((p) => p($('#palInput').value.trim())).filter((g) => g && g.items.length);
        const all = groups.flatMap((g) => g.items);
        const it = all[idx];
        if (!it) return;
        closePalette();
        it.action();
    }
    $('#palList').addEventListener('click', (e) => { const it = e.target.closest('[data-pi]'); if (it) runPalette(Number(it.dataset.pi)); });
    $('#palette').addEventListener('mousedown', (e) => { if (e.target.id === 'palette') closePalette(); });
    $('#omnibox').addEventListener('click', () => openPalette());
    $('#omnibox').addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openPalette(); } });

    addEventListener('keydown', (e) => {
        if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); if ($('#palette').classList.contains('hidden')) openPalette(); else closePalette(); }
        if (e.altKey && e.key.toLowerCase() === 'm') {
            const active = [...wins.keys()].find((id) => wins.get(id).classList.contains('active'));
            if (active) { e.preventDefault(); toggle(active, 'min'); }
        }
    });
    addEventListener('resize', () => { for (const id of wins.keys()) apply(id); });

    window.WM = {
        register(app) { apps.set(app.id, app); },
        open, close, focus, toggle, isOpen: (id) => wins.has(id), el: (id) => wins.get(id),
        setMeta(id, text) { const el = wins.get(id); if (el) el.querySelector('[data-wmeta]').textContent = text || ''; },
        setTitle(id, text) { const el = wins.get(id); if (el) el.querySelector('.win-head h2').textContent = text; },
        setBadge(id, n) { if ((badges[id] || 0) !== (n || 0)) { badges[id] = n || 0; renderDock(); } },
        menu, hideMenu, confirm: confirmBox, palette: { add: (fn) => pal.providers.push(fn), open: openPalette, close: closePalette, isOpen: () => !$('#palette').classList.contains('hidden') },
        workspace: () => state.ws, switchWorkspace,
        restore(saved) {
            if (saved && saved.layouts && typeof saved.layouts === 'object') {
                state.layouts = saved.layouts;
                // ordre d'empilement repris au-dessus des valeurs enregistrées : une fenêtre ouverte passe devant
                for (const ws of Object.values(state.layouts)) for (const l of Object.values(ws || {})) if (l && Number(l.z) > z) z = Number(l.z);
            }
            switchWorkspace(saved && DEFAULTS[saved.ws] ? saved.ws : 'dispatch');
        },
        onSave(fn) { onSave = fn; },
        resetWorkspace() { state.layouts[state.ws] = {}; switchWorkspace(state.ws); },
    };
})();
