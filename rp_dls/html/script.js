// RP DLS : panneau de commande (client/ui.lua). Boutons cliquables en mode souris (/dls), sinon affichage seul.
(() => {
    const $ = (id) => document.getElementById(id);
    const panel = $('panel');
    const stagesBox = $('stages');
    const tonesBox = $('tones');
    const lightbar = $('lightbar');
    const taBar = $('ta-bar');
    const resource = typeof window.GetParentResourceName === 'function' ? window.GetParentResourceName() : 'rp_dls';

    // Vitesse de la barre de gyrophares de l'en-tête selon le stage (purement visuel)
    const SPEED = { 1: '1.1s', 2: '.7s', 3: '.42s', 4: '.55s', 5: '.55s' };
    // Segments allumés du Traffic Advisor, image par image (1 gauche, 2 diverge, 3 droite, 4 warn)
    const TA_COUNT = { three: 3, four: 4, five: 5, six: 6 };

    let data = null;
    let lastStageKey = '';
    let lastToneKey = '';

    function post(name, body) {
        fetch(`https://${resource}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(body || {}),
        }).catch(() => {});
    }

    function button(cls, label, action, arg, key, extra) {
        const b = document.createElement('button');
        b.className = `btn ${cls}`;
        b.dataset.action = action;
        if (arg !== undefined) b.dataset.arg = arg;
        b.textContent = label;
        if (key) {
            const k = document.createElement('span');
            k.className = 'key';
            k.textContent = key;
            b.appendChild(k);
        }
        if (extra) b.appendChild(extra);
        return b;
    }

    // ---- Construction des boutons propres au véhicule (stages, tons) ----
    function buildStages(d) {
        const key = JSON.stringify(d.stages) + JSON.stringify(d.keys);
        if (key === lastStageKey) return;
        lastStageKey = key;
        stagesBox.innerHTML = '';
        d.stages.forEach((s) => {
            let dot = null;
            if (s.native) {
                dot = document.createElement('span');
                dot.className = 'native';
                dot.title = 'Gyrophares d\'origine du véhicule';
            }
            const b = button('stage', s.label, 'stage', s.n, d.keys[`stage${s.n}`], dot);
            b.dataset.stage = s.n;
            stagesBox.appendChild(b);
        });
    }

    function buildTones(d) {
        const key = JSON.stringify(d.tones) + JSON.stringify(d.keys);
        if (key === lastToneKey) return;
        lastToneKey = key;
        tonesBox.innerHTML = '';
        d.tones.forEach((t) => {
            const b = button('tone', t.label, 'tone', t.n, d.keys[`tone${t.n}`]);
            b.dataset.tone = t.n;
            tonesBox.appendChild(b);
        });
        if (!d.tones.length) {
            const none = document.createElement('span');
            none.className = 'hint';
            none.textContent = 'Aucun ton';
            tonesBox.appendChild(none);
        }
    }

    // ---- Mise à jour ----
    function render(d) {
        data = d;
        const s = d.state;
        panel.classList.toggle('show', !!d.show);
        panel.classList.toggle('focus', !!d.focus);
        panel.classList.toggle('locked', !!d.locked);
        panel.setAttribute('aria-hidden', d.show ? 'false' : 'true');
        $('vehicle').textContent = d.name || '';
        $('lock').classList.toggle('active', !!d.locked);

        buildStages(d);
        buildTones(d);

        // Allumage / extinction : touche du jeu de base seulement ; les stages se choisissent gyrophares allumés
        const lightsOn = s.s > 0 && !s.bo;
        const lightsKey = d.keys.lights || 'touche du jeu';
        $('lights-hint').textContent = lightsOn ? `allumés · ${lightsKey} : éteindre` : `éteints · ${lightsKey} : allumer`;
        $('lights-hint').classList.toggle('on', lightsOn);
        stagesBox.querySelectorAll('.btn.stage').forEach((b) => {
            const n = Number(b.dataset.arg);
            b.classList.toggle('on', n === s.s);
            b.disabled = !lightsOn;
        });
        // Cruise : DLS v2 -> n° du mode (CRUISE 1, CRUISE 2…), DLS v1 -> Steady Burn
        const cruiseOn = d.v2 ? s.cr > 0 : !!s.sb;
        $('steady').classList.toggle('on', cruiseOn);
        $('steady').disabled = !d.steady;
        $('steady').textContent = d.v2 && d.cruise > 1 && s.cr > 0 ? `CRUISE ${s.cr}` : 'CRUISE';
        // Scène : takedown (n° du mode s'il y en a plusieurs), alley gauche / droite, stationnement
        $('td').classList.toggle('on', s.td > 0);
        $('td').disabled = !d.takedown;
        $('td').textContent = d.takedown > 1 && s.td > 0 ? `TAKEDOWN ${s.td}` : 'TAKEDOWN';
        $('al-left').classList.toggle('on', (s.al & 1) !== 0);
        $('al-left').disabled = !(d.alley && d.alley.left);
        $('al-right').classList.toggle('on', (s.al & 2) !== 0);
        $('al-right').disabled = !(d.alley && d.alley.right);
        $('park').classList.toggle('on', !!d.park);
        $('int').classList.toggle('on', !!s.int);
        $('bo').classList.toggle('on', !!s.bo);

        const ta = d.ta;
        $('row-ta').classList.toggle('hidden', !ta);
        if (ta) {
            document.querySelectorAll('.btn.ta').forEach((b) => {
                const n = Number(b.dataset.arg);
                b.classList.toggle('on', n === s.ta);
                b.disabled = ta.divergeOnly && n !== 2;
            });
            $('ta-pattern').textContent = ta.count > 1 ? `${ta.pattern} (${ta.index}/${ta.count})` : '';
            $('ta-next').style.display = ta.count > 1 ? '' : 'none';
            const n = TA_COUNT[ta.type] || 6;
            if (taBar.children.length !== n) {
                taBar.innerHTML = '';
                taBar.style.setProperty('--n', n);
                for (let i = 0; i < n; i += 1) taBar.appendChild(document.createElement('span'));
            }
        }

        tonesBox.querySelectorAll('.btn.tone').forEach((b) => {
            b.classList.toggle('on', Number(b.dataset.tone) === s.tone);
        });
        $('aux').classList.toggle('on', !!s.aux);
        $('scan').classList.toggle('on', !!d.scan);
        $('horn').classList.toggle('on', !!s.horn || s.tone === 5);
        $('man').classList.toggle('on', !!d.manual);

        // Barre de l'en-tête
        const lit = s.s > 0 && !s.bo;
        lightbar.classList.toggle('on', lit);
        lightbar.classList.toggle('steady', !lit && !!s.sb && !s.bo);
        lightbar.classList.toggle('native', lit && d.stages.some((st) => st.n === s.s && st.native));
        lightbar.style.setProperty('--speed', SPEED[s.s] || '.8s');

        let foot = '';
        if (d.locked) foot = 'Touches DLS verrouillées.';
        else if (s.bo) foot = 'Blackout : tous les feux sont éteints.';
        if (d.v2 && d.modes && d.modes.length) foot = (foot ? `${foot} ` : '') + `Modes : ${d.modes.join(', ')}.`;
        if (d.focus) foot = (foot ? `${foot} ` : '') + 'Glisser le titre pour déplacer · Échap pour fermer.';
        $('foot').textContent = foot;
    }

    // ---- Chenillard du Traffic Advisor (visuel) ----
    let frame = 0;
    setInterval(() => {
        if (!data || !data.ta || !panel.classList.contains('show')) return;
        frame += 1;
        const cells = taBar.children;
        const n = cells.length;
        const dir = data.state.bo ? 0 : data.state.ta;
        for (let i = 0; i < n; i += 1) {
            let on = false;
            const step = frame % (n + 2);
            if (dir === 1) on = i === n - 1 - step || i === n - step;          // vers la gauche
            else if (dir === 3) on = i === step || i === step - 1;              // vers la droite
            else if (dir === 2) {                                               // du centre vers les bords
                const half = Math.ceil(n / 2);
                const k = frame % (half + 1);
                on = i === half - 1 - k || i === n - half + k;
            } else if (dir === 4) on = (i % 2 === 0) === (frame % 2 === 0);     // warn : alterné
            cells[i].classList.toggle('lit', on);
        }
    }, 140);

    // ---- Clics (mode souris) ----
    panel.addEventListener('click', (e) => {
        const b = e.target.closest('[data-action]');
        if (!b || b.disabled || !panel.classList.contains('focus')) return;
        const arg = b.dataset.arg !== undefined ? Number(b.dataset.arg) : undefined;
        post('action', { name: b.dataset.action, arg });
    });
    $('close').addEventListener('click', () => post('close'));
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && panel.classList.contains('focus')) post('close');
    });

    // ---- Déplacement (titre glissé en mode souris) et position gardée ----
    const POS_KEY = 'rp_dls_panel_pos';
    function clampPos(x, y) {
        const w = panel.offsetWidth;
        const h = panel.offsetHeight;
        return [Math.max(0, Math.min(window.innerWidth - w, x)), Math.max(0, Math.min(window.innerHeight - h, y))];
    }
    function place(x, y) {
        const [cx, cy] = clampPos(x, y);
        panel.style.left = `${cx}px`;
        panel.style.top = `${cy}px`;
        panel.style.right = 'auto';
        panel.style.bottom = 'auto';
    }
    try {
        const saved = JSON.parse(localStorage.getItem(POS_KEY) || 'null');
        if (saved && typeof saved.x === 'number') requestAnimationFrame(() => place(saved.x, saved.y));
    } catch (err) { /* stockage indisponible */ }

    let drag = null;
    $('head').addEventListener('mousedown', (e) => {
        if (!panel.classList.contains('focus') || e.target.closest('button')) return;
        const r = panel.getBoundingClientRect();
        drag = { dx: e.clientX - r.left, dy: e.clientY - r.top };
        e.preventDefault();
    });
    window.addEventListener('mousemove', (e) => {
        if (drag) place(e.clientX - drag.dx, e.clientY - drag.dy);
    });
    window.addEventListener('mouseup', () => {
        if (!drag) return;
        drag = null;
        const r = panel.getBoundingClientRect();
        try { localStorage.setItem(POS_KEY, JSON.stringify({ x: r.left, y: r.top })); } catch (err) { /* stockage indisponible */ }
    });
    $('head').addEventListener('dblclick', () => {
        if (!panel.classList.contains('focus')) return;
        panel.style.left = panel.style.top = panel.style.right = panel.style.bottom = '';
        try { localStorage.removeItem(POS_KEY); } catch (err) { /* stockage indisponible */ }
    });

    window.addEventListener('message', (e) => {
        const d = e.data;
        if (!d || !d.action) return;
        if (d.action === 'update') render(d);
        else if (d.action === 'hide') {
            data = null;
            panel.classList.remove('show', 'focus');
            panel.setAttribute('aria-hidden', 'true');
        }
    });
})();
