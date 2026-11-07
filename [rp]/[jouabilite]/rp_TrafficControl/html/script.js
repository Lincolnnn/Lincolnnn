// RP TrafficControl : menu "Gestion du trafic" (client/menu.lua envoie open / zone / close / list / message)
//   Accueil : 1. « Choisir la zone du trafic » (portée) ; mesures actives.
//   Zone choisie : 2. l'action sur ce trafic (fermeture de voie, ralentissement, arrêt), vitesse, durée -> Appliquer.
(() => {
    const $ = (id) => document.getElementById(id);
    const box = $('tc');
    const resource = typeof window.GetParentResourceName === 'function' ? window.GetParentResourceName() : 'rp_TrafficControl';
    const KIND = { close: 'Fermeture', slow: 'Ralentissement', stop: 'Trafic arrêté' };
    let state = {
        measures: [], durations: [15, 30, 60, 120, 0], duration: 30, speed: 25, scope: 'lane',
        limits: { min: 5, max: 80, step: 5 }, unit: '', view: 'home', zone: null, kind: null, camera: 'player',
    };
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
    const plural = (n, word) => `${n} ${word}${n > 1 ? 's' : ''}`;

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

    // ------------------------------------------------------------------ vues
    function showView(view) {
        state.view = view;
        $('tcHome').classList.toggle('hidden', view !== 'home');
        $('tcZoneView').classList.toggle('hidden', view !== 'zone');
        $('tcSub').textContent = view === 'zone'
            ? `${state.unit ? `${state.unit} · ` : ''}Choisissez l'action sur ce trafic`
            : `${state.unit ? `${state.unit} · ` : ''}${plural(state.measures.length, 'mesure')} active${state.measures.length > 1 ? 's' : ''}`;
    }

    function renderHome() {
        box.querySelectorAll('[data-scope]').forEach((b) => b.classList.toggle('active', b.dataset.scope === state.scope));
        box.querySelectorAll('[data-view]').forEach((b) => b.classList.toggle('active', b.dataset.view === state.camera));
    }

    // Texte de la fermeture selon la zone : une voie (vers quelle voie le trafic se réoriente), un sens, la route
    function closeTexts(z) {
        if (z.scope === 'lane') {
            return {
                title: 'Fermeture de voie',
                hint: z.redirect ? `Le trafic se réoriente vers la ${z.redirect}${z.sideSlow > 0 ? ` ; les autres voies du sens ralentissent à ${z.sideSlow} MPH` : ''}`
                    : 'Aucune autre voie dans ce sens : le trafic fait demi-tour',
            };
        }
        if (z.scope === 'direction') return { title: 'Fermeture du sens', hint: 'Le trafic de ce sens est dévié (autre route / demi-tour)' };
        return { title: 'Fermeture de la route', hint: 'Le trafic prend une déviation' };
    }

    function renderZone() {
        const z = state.zone || {};
        $('tcZoneLabel').textContent = z.label || 'Zone sans nom';
        const parts = [];
        if (z.scope === 'lane') parts.push(`${laneName(z.laneIndex, z.laneCount)} (${z.laneIndex}/${z.laneCount}), sens ${z.compass || ''}`);
        else if (z.scope === 'direction') parts.push(`sens ${z.compass || ''} (${plural(z.laneCount || 1, 'voie')})`);
        else parts.push('route entière (les deux sens)');
        parts.push(`${z.length || 0} m`);
        if (z.nodes > 0) parts.push(`${plural(z.nodes, 'nœud')} du trafic`);
        else parts.push(z.scope === 'lane' ? 'trafic de cette voie (nœuds communs à toutes les voies)' : 'nœuds partagés avec l\'autre sens : trafic dirigé');
        $('tcZoneMeta').textContent = parts.join(' · ');
        const ct = closeTexts(z);
        $('tcCloseTitle').textContent = ct.title;
        $('tcCloseHint').textContent = ct.hint;
        $('tcSlowHint').textContent = `Le trafic de la zone roule à ${state.speed} MPH`;
        box.querySelectorAll('[data-kind]').forEach((b) => b.classList.toggle('active', b.dataset.kind === state.kind));
        $('tcSpeedField').classList.toggle('hidden', state.kind !== 'slow');
        $('tcSpeed').textContent = `${state.speed} MPH`;
        $('tcSpeedIco').textContent = state.speed;
        box.querySelector('[data-speed="-1"]').disabled = state.speed <= state.limits.min;
        box.querySelector('[data-speed="1"]').disabled = state.speed >= state.limits.max;
        $('tcDurations').innerHTML = state.durations.map((d) => `
            <button class="tc-chip${d === state.duration ? ' active' : ''}" data-duration="${d}">${durationLabel(d)}</button>`).join('');
        $('tcApply').disabled = !state.kind;
        $('tcApply').textContent = state.kind ? `Appliquer : ${(KIND[state.kind] || '').toLowerCase()}` : 'Appliquer';
    }

    function renderList() {
        const list = state.measures;
        const mine = list.filter((m) => m.mine).length;
        $('tcCount').textContent = list.length ? `(${list.length})` : '';
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
        if (state.view === 'home') showView('home');
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

    function settings(data) {
        const sp = data.speed || {};
        state.limits = { min: Number(sp.MinLimit) || 5, max: Number(sp.MaxLimit) || 80, step: Number(sp.Step) || 5 };
        state.durations = toArray(data.durations).map(Number);
        if (!state.durations.length) state.durations = [15, 30, 60, 120, 0];
        if (!state.opened) { // premier affichage : valeurs par défaut ; ensuite les choix du joueur sont gardés
            state.duration = Number(data.defaultDuration) || 30;
            state.speed = Number(sp.DefaultLimit) || 25;
            state.opened = true;
        }
        if (!state.durations.includes(state.duration)) state.duration = state.durations[0];
        state.unit = data.unit || '';
    }

    function show() {
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

    function open(data) {
        settings(data);
        renderHome();
        setMeasures(data.measures);
        showView('home');
        show();
    }

    // Zone du trafic choisie (editor.lua) : choix de l'action
    function openZone(data) {
        settings(data);
        state.zone = data.zone || {};
        state.kind = null;
        renderZone();
        showView('zone');
        show();
    }

    function close() {
        box.classList.add('hidden');
        clearInterval(tick);
    }

    function pickKind(kind) {
        state.kind = kind;
        renderZone();
        post('zoneKind', { kind });
    }

    box.addEventListener('click', (e) => {
        if (e.target.closest('#tcClose')) return post('close');
        if (state.view === 'zone') {
            const kind = e.target.closest('[data-kind]');
            if (kind) return pickKind(kind.dataset.kind);
            const sp = e.target.closest('[data-speed]');
            if (sp && !sp.disabled) {
                state.speed = Math.max(state.limits.min, Math.min(state.limits.max, state.speed + Number(sp.dataset.speed) * state.limits.step));
                return renderZone();
            }
            const d = e.target.closest('[data-duration]');
            if (d) { state.duration = Number(d.dataset.duration); return renderZone(); }
            if (e.target.closest('#tcApply') && state.kind) return post('apply', { kind: state.kind, speed: state.speed, duration: state.duration });
            if (e.target.closest('#tcReselect')) return post('reselect');
            if (e.target.closest('#tcCancelZone')) return post('close');
            return null;
        }
        if (e.target.closest('#tcPickZone')) return post('pickZone', { scope: state.scope, view: state.camera });
        const scope = e.target.closest('[data-scope]');
        if (scope) { state.scope = scope.dataset.scope; return renderHome(); }
        const cam = e.target.closest('[data-view]');
        if (cam) { state.camera = cam.dataset.view; return renderHome(); }
        const rm = e.target.closest('[data-remove]');
        if (rm) return post('remove', { id: Number(rm.dataset.remove) });
        const loc = e.target.closest('[data-locate]');
        if (loc) return post('locate', { id: Number(loc.dataset.locate) });
        if (e.target.closest('#tcClearMine')) return post('clear', { mine: true });
        if (e.target.closest('#tcClearAll')) return post('clear', { mine: false });
        return null;
    });

    document.addEventListener('keydown', (e) => {
        if (box.classList.contains('hidden')) return;
        if (e.key === 'Escape') post('close');
        // Zone choisie : 1 / 2 / 3 choisissent l'action, Entrée applique
        if (state.view === 'zone') {
            const keys = { 1: 'close', 2: 'slow', 3: 'stop' };
            if (keys[e.key]) pickKind(keys[e.key]);
            else if (e.key === 'Enter' && state.kind) post('apply', { kind: state.kind, speed: state.speed, duration: state.duration });
        }
    });

    // Mode nuit des menus (MDC : Paramètres > MDC > Apparence), envoyé par client/theme.lua
    window.addEventListener('message', ({ data }) => {
        if (!data || data.action !== 'uiTheme') return;
        const t = data.data || {};
        document.documentElement.dataset.theme = 'night'; // toujours sombre : de jour, couleurs du logo du serveur
        document.documentElement.dataset.nightColor = t.theme === 'night' && ['green', 'yellow', 'red', 'blue'].includes(t.color) ? t.color : 'logo';
    });

    window.addEventListener('message', (event) => {
        const msg = event.data || {};
        const data = msg.data || {};
        if (msg.action === 'open') open(data);
        else if (msg.action === 'zone') openZone(data);
        else if (msg.action === 'close') close();
        else if (msg.action === 'list') setMeasures(data.measures);
        else if (msg.action === 'message') message(data.text, data.error);
    });
})();
