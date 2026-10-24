// RP TrafficControl : menu "Gestion du trafic" (client/menu.lua envoie open / close / list / message)
(() => {
    const $ = (id) => document.getElementById(id);
    const box = $('tc');
    const resource = typeof window.GetParentResourceName === 'function' ? window.GetParentResourceName() : 'rp_TrafficControl';
    const KIND = { close: 'Fermeture', slow: 'Ralentissement', stop: 'Trafic arrêté' };
    const CLOSE_HINT = {
        lane: 'Les PNJ se rabattent sur une voie du même sens',
        direction: 'Ce sens est fermé : les PNJ font demi-tour / une déviation',
        road: 'Route fermée : les PNJ prennent une déviation',
    };
    let state = { measures: [], durations: [15, 30, 60, 120, 0], duration: 30, speed: 25, scope: 'lane', limits: { min: 5, max: 80, step: 5 }, unit: '' };
    let messageTimer = null;
    let tick = null;

    function post(name, data) {
        return fetch(`https://${resource}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        }).catch(() => {});
    }

    function esc(text) {
        return String(text == null ? '' : text).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    }

    const toArray = (v) => (Array.isArray(v) ? v : (v && typeof v === 'object' ? Object.values(v) : []));
    const durationLabel = (m) => (m === 0 ? 'Illimitée' : m >= 60 && m % 60 === 0 ? `${m / 60} h` : `${m} min`);

    function timeLeft(m) {
        if (m.permanent) return 'jusqu\'à levée';
        const s = Math.max(0, Math.round((m.endsAt - Date.now()) / 1000));
        if (s >= 3600) return `${Math.floor(s / 3600)} h ${String(Math.floor((s % 3600) / 60)).padStart(2, '0')}`;
        if (s >= 60) return `${Math.ceil(s / 60)} min`;
        return `${s} s`;
    }

    function laneName(i, n) {
        if (!n || n <= 1) return 'voie unique';
        if (i === 1) return 'voie de gauche';
        if (i === n) return 'voie de droite';
        return n === 3 ? 'voie centrale' : `voie ${i}`;
    }

    function detail(m) {
        const dx = m.b.x - m.a.x; const dy = m.b.y - m.a.y;
        const length = `${Math.round(Math.sqrt(dx * dx + dy * dy))} m`;
        let scope = 'route entière';
        if (m.scope === 'lane') scope = `${laneName(m.laneIndex, m.laneCount)} (${m.laneIndex}/${m.laneCount}), sens ${m.compass || ''}`;
        else if (m.scope === 'direction') scope = `sens ${m.compass || ''}`;
        return `${m.kind === 'slow' ? `${m.speed} MPH · ` : ''}${scope} · ${length}`;
    }

    function renderSettings() {
        $('tcSpeed').textContent = `${state.speed} MPH`;
        $('tcSpeedIco').textContent = state.speed;
        box.querySelector('[data-speed="-1"]').disabled = state.speed <= state.limits.min;
        box.querySelector('[data-speed="1"]').disabled = state.speed >= state.limits.max;
        box.querySelectorAll('[data-scope]').forEach((b) => b.classList.toggle('active', b.dataset.scope === state.scope));
        $('tcCloseHint').textContent = CLOSE_HINT[state.scope] || '';
        $('tcDurations').innerHTML = state.durations.map((d) => `
            <button class="tc-chip${d === state.duration ? ' active' : ''}" data-duration="${d}">${durationLabel(d)}</button>`).join('');
    }

    function renderList() {
        const list = state.measures;
        const mine = list.filter((m) => m.mine).length;
        $('tcCount').textContent = list.length ? `(${list.length})` : '';
        $('tcSub').textContent = `${state.unit ? `${state.unit} · ` : ''}${list.length} mesure${list.length > 1 ? 's' : ''} active${list.length > 1 ? 's' : ''}`;
        $('tcList').innerHTML = list.length ? list.map((m) => `
            <div class="tc-item ${esc(m.kind)}">
                <div class="tc-item-info">
                    <div class="tc-item-title"><span class="tc-badge">${KIND[m.kind] || ''}</span>${esc(m.label || `Mesure n°${m.id}`)}</div>
                    <div class="tc-item-meta">${esc(detail(m))} · ${m.mine ? '<span class="tc-mine">vous</span>' : esc(m.by || '?')} · <span data-left="${m.id}">${timeLeft(m)}</span></div>
                </div>
                <div class="tc-item-actions">
                    <button class="tc-btn tc-small" data-locate="${m.id}" title="Point GPS sur la mesure">Repérer</button>
                    <button class="tc-btn tc-small tc-danger" data-remove="${m.id}">Lever</button>
                </div>
            </div>`).join('') : '<div class="tc-empty">Aucune mesure : le trafic circule normalement.</div>';
        $('tcClearMine').disabled = mine === 0;
        $('tcClearAll').disabled = list.length === 0;
    }

    function setMeasures(list) {
        const now = Date.now();
        state.measures = toArray(list).map((m) => ({ ...m, endsAt: now + (Number(m.remaining) || 0) * 1000 }));
        renderList();
    }

    function message(text, error) {
        const el = $('tcMessage');
        el.textContent = text || '';
        el.classList.toggle('error', !!error);
        clearTimeout(messageTimer);
        if (text) messageTimer = setTimeout(() => { el.textContent = ''; }, 4000);
    }

    function open(data) {
        const sp = data.speed || {};
        state.limits = { min: Number(sp.MinLimit) || 5, max: Number(sp.MaxLimit) || 80, step: Number(sp.Step) || 5 };
        state.durations = toArray(data.durations).map(Number);
        if (!state.durations.length) state.durations = [15, 30, 60, 120, 0];
        if (!state.opened) { // premier affichage : valeurs par défaut ; ensuite les choix du joueur sont gardés
            state.duration = Number(data.defaultDuration) || 30;
            state.speed = Number(sp.DefaultLimit) || 25;
            state.opened = true;
        }
        state.unit = data.unit || '';
        renderSettings();
        setMeasures(data.measures);
        message('');
        box.classList.remove('hidden');
        clearInterval(tick);
        tick = setInterval(() => {
            state.measures.forEach((m) => {
                const el = box.querySelector(`[data-left="${m.id}"]`);
                if (el) el.textContent = timeLeft(m);
            });
        }, 1000);
    }

    function close() {
        box.classList.add('hidden');
        clearInterval(tick);
    }

    box.addEventListener('click', (e) => {
        const kind = e.target.closest('[data-kind]');
        if (kind) return post('pick', { kind: kind.dataset.kind, scope: state.scope, duration: state.duration, speed: state.speed });
        const scope = e.target.closest('[data-scope]');
        if (scope) { state.scope = scope.dataset.scope; return renderSettings(); }
        const sp = e.target.closest('[data-speed]');
        if (sp && !sp.disabled) {
            state.speed = Math.max(state.limits.min, Math.min(state.limits.max, state.speed + Number(sp.dataset.speed) * state.limits.step));
            return renderSettings();
        }
        const d = e.target.closest('[data-duration]');
        if (d) { state.duration = Number(d.dataset.duration); return renderSettings(); }
        const rm = e.target.closest('[data-remove]');
        if (rm) return post('remove', { id: Number(rm.dataset.remove) });
        const loc = e.target.closest('[data-locate]');
        if (loc) return post('locate', { id: Number(loc.dataset.locate) });
        if (e.target.closest('#tcClearMine')) return post('clear', { mine: true });
        if (e.target.closest('#tcClearAll')) return post('clear', { mine: false });
        if (e.target.closest('#tcClose')) return post('close');
        return null;
    });

    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && !box.classList.contains('hidden')) post('close');
    });

    // Mode nuit des menus (MDC : Paramètres > MDC > Apparence), envoyé par client/theme.lua
    window.addEventListener('message', ({ data }) => {
        if (!data || data.action !== 'uiTheme') return;
        const t = data.data || {};
        document.documentElement.dataset.theme = t.theme === 'night' ? 'night' : 'day';
        document.documentElement.dataset.nightColor = ['green', 'yellow', 'red', 'blue'].includes(t.color) ? t.color : 'green';
    });

    window.addEventListener('message', (event) => {
        const msg = event.data || {};
        const data = msg.data || {};
        if (msg.action === 'open') open(data);
        else if (msg.action === 'close') close();
        else if (msg.action === 'list') setMeasures(data.measures);
        else if (msg.action === 'message') message(data.text, data.error);
    });
})();
