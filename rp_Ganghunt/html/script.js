// RP Ganghunt : menu de la chasse (faction, vagues, armes en pourcentages ou aléatoire, renforts) et HUD
(() => {
    const $ = (id) => document.getElementById(id);
    const box = $('gh');
    const resource = typeof window.GetParentResourceName === 'function' ? window.GetParentResourceName() : 'rp_Ganghunt';
    const STORE = 'rp_ganghunt_last';

    let config = { categories: [], weapons: [], maxWaves: 10, waveSize: 10, maxWeapons: 10, sidearm: 'WEAPON_COMBATPISTOL' };
    let state = { category: null, faction: null, waves: 1, mode: 'random', weapons: [], vehicles: false, heli: false };
    let messageTimer = null;
    let busy = false;

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

    const toArray = (v) => (Array.isArray(v) ? v : (v && typeof v === 'object' ? Object.values(v) : []));
    const weaponInfo = (name) => config.weapons.find((w) => w.name === name);
    const allFactions = () => config.categories.flatMap((c) => c.factions);
    const factionOf = (key) => allFactions().find((f) => f.key === key);
    const categoryOf = (key) => config.categories.find((c) => c.factions.some((f) => f.key === key));
    const total = () => state.weapons.reduce((sum, w) => sum + (Number(w.pct) || 0), 0);

    // Derniers choix gardés chez le joueur (confort : rien d'important)
    function save() {
        try { localStorage.setItem(STORE, JSON.stringify(state)); } catch (e) { /* stockage indisponible */ }
    }
    function restore() {
        try {
            const saved = JSON.parse(localStorage.getItem(STORE) || 'null');
            if (saved && typeof saved === 'object') state = Object.assign(state, saved);
        } catch (e) { /* stockage indisponible */ }
    }

    function message(text, isError) {
        const el = $('ghMessage');
        el.textContent = text || '';
        el.classList.toggle('error', isError === true);
        clearTimeout(messageTimer);
        if (text) messageTimer = setTimeout(() => { el.textContent = ''; }, 5000);
    }

    // =====================================================================
    // RENDU
    // =====================================================================
    function renderCategories() {
        $('ghCats').innerHTML = config.categories.map((c) =>
            `<button class="gh-seg-btn${c.key === state.category ? ' active' : ''}" data-cat="${esc(c.key)}">${esc(c.label)}</button>`).join('');
        const category = config.categories.find((c) => c.key === state.category) || config.categories[0];
        $('ghFactions').innerHTML = (category ? category.factions : []).map((f) => `
            <button class="gh-faction${f.key === state.faction ? ' active' : ''}" data-faction="${esc(f.key)}" title="${esc(f.label)}">
                <b>${esc(f.label)}</b>
                <small>${f.armour > 0 ? `Gilet ${f.armour}` : 'Sans gilet'} · ${toArray(f.vehicles).length} véhicules</small>
            </button>`).join('');
    }

    function renderWaves() {
        $('ghWaves').textContent = state.waves;
        $('ghWavesMinus').disabled = state.waves <= 1;
        $('ghWavesPlus').disabled = state.waves >= config.maxWaves;
        const n = state.waves * config.waveSize;
        $('ghWavesText').textContent = `${n} ennemis (${config.waveSize} par vague)`;
    }

    function renderWeapons() {
        document.querySelectorAll('[data-mode]').forEach((b) => b.classList.toggle('active', b.dataset.mode === state.mode));
        const random = state.mode === 'random';
        $('ghChoose').classList.toggle('hidden', random);
        const sidearm = weaponInfo(config.sidearm);
        const sidearmLabel = sidearm ? sidearm.label.toLowerCase() : 'pistolet de combat';
        $('ghWeaponHint').innerHTML = random
            ? `Chaque ennemi reçoit une arme au hasard parmi celles de sa faction, et un <b>${esc(sidearmLabel)}</b> en plus d'une arme longue.`
            : `Arme de poing : l'ennemi n'a <b>qu'elle</b>. Arme longue : il a aussi un <b>${esc(sidearmLabel)}</b>. `
              + `Jusqu'à ${config.maxWeapons} armes, réparties sur <b>100 %</b>.`;
        if (random) return;

        const used = new Set(state.weapons.map((w) => w.name));
        const option = (w) => `<option value="${esc(w.name)}">${esc(w.label)}</option>`;
        const free = config.weapons.filter((w) => !used.has(w.name));
        const hand = free.filter((w) => w.handgun);
        const long = free.filter((w) => !w.handgun);
        $('ghWeaponSelect').innerHTML = (hand.length ? `<optgroup label="Armes de poing (seules)">${hand.map(option).join('')}</optgroup>` : '')
            + (long.length ? `<optgroup label="Armes longues (+ ${esc(sidearmLabel)})">${long.map(option).join('')}</optgroup>` : '');
        const full = state.weapons.length >= config.maxWeapons || free.length === 0;
        $('ghWeaponSelect').disabled = full;
        $('ghWeaponAdd').disabled = full;

        $('ghWeapons').innerHTML = state.weapons.length === 0
            ? '<div class="gh-empty">Aucune arme : ajoutez-en une, ou choisissez « Aléatoire ».</div>'
            : state.weapons.map((w, i) => {
                const info = weaponInfo(w.name) || { label: w.name };
                return `<div class="gh-weapon" data-index="${i}">
                    <div class="gh-weapon-name"><b>${esc(info.label)}</b><small>${info.handgun ? 'seule' : `+ ${esc(sidearmLabel)}`}</small></div>
                    <input class="gh-range" type="range" min="0" max="100" step="1" value="${w.pct}" data-range="${i}">
                    <span class="gh-pct"><input class="gh-input" type="number" min="0" max="100" value="${w.pct}" data-pct="${i}">%</span>
                    <button class="gh-remove" data-remove="${i}" title="Retirer">✕</button>
                </div>`;
            }).join('');
        $('ghSpread').disabled = state.weapons.length < 2;
        renderTotal();
    }

    function renderTotal() {
        const t = total();
        const el = $('ghTotal');
        el.textContent = state.weapons.length ? `Total : ${t} % / 100 %` : '';
        el.classList.toggle('bad', state.weapons.length > 0 && t !== 100);
    }

    function renderReinforcements() {
        const f = factionOf(state.faction);
        $('ghVehicles').checked = state.vehicles;
        $('ghHeli').checked = state.heli;
        $('ghVehiclesText').textContent = f
            ? `Jusqu'à 4 par véhicule : ${toArray(f.vehicles).map((v) => v.label || v).join(', ')}. Ceux à pied en reprennent un s'ils vous perdent.`
            : '';
        $('ghHeliText').textContent = f && f.heli ? `${f.heliLabel || f.heli} : un pilote et deux tireurs dans chaque vague.` : '';
    }

    function render() {
        renderCategories();
        renderWaves();
        renderWeapons();
        renderReinforcements();
    }

    function renderActive(active, current) {
        $('ghActive').classList.toggle('hidden', !active);
        $('ghStart').disabled = active === true;
        if (active && current) $('ghActiveText').textContent = `${current.faction} · vague ${current.wave} / ${current.waves}`;
    }

    // =====================================================================
    // ACTIONS
    // =====================================================================
    function spread() {
        const n = state.weapons.length;
        if (!n) return;
        const base = Math.floor(100 / n);
        let rest = 100 - base * n;
        state.weapons.forEach((w) => { w.pct = base + (rest > 0 ? 1 : 0); rest -= 1; });
    }

    function setPct(i, value, rerender) {
        const w = state.weapons[i];
        if (!w) return;
        w.pct = Math.max(0, Math.min(100, Math.round(Number(value) || 0)));
        const row = document.querySelector(`.gh-weapon[data-index="${i}"]`);
        if (row && !rerender) {
            row.querySelector('[data-range]').value = w.pct;
            const input = row.querySelector('[data-pct]');
            if (document.activeElement !== input) input.value = w.pct;
        }
        if (rerender) renderWeapons(); else renderTotal();
        save();
    }

    function start() {
        if (busy) return;
        if (!factionOf(state.faction)) return message('Choisissez les ennemis.', true);
        if (state.mode === 'choose') {
            if (state.weapons.length === 0) return message('Ajoutez au moins une arme, ou choisissez « Aléatoire ».', true);
            if (state.weapons.some((w) => !(w.pct > 0))) return message('Chaque arme doit avoir au moins 1 %.', true);
            if (total() !== 100) return message(`Les pourcentages font ${total()} % : il faut 100 %.`, true);
        }
        busy = true;
        post('start', {
            faction: state.faction, waves: state.waves, random: state.mode === 'random',
            weapons: state.mode === 'random' ? [] : state.weapons.map((w) => ({ name: w.name, pct: w.pct })),
            vehicles: state.vehicles, heli: state.heli,
        }).then((res) => {
            busy = false;
            if (res && res.ok === false) message(res.error || 'Impossible de lancer la chasse.', true);
        });
    }

    $('ghCats').addEventListener('click', (e) => {
        const b = e.target.closest('[data-cat]');
        if (!b) return;
        state.category = b.dataset.cat;
        const category = config.categories.find((c) => c.key === state.category);
        if (category && !category.factions.some((f) => f.key === state.faction)) state.faction = category.factions[0] && category.factions[0].key;
        render();
        save();
    });
    $('ghFactions').addEventListener('click', (e) => {
        const b = e.target.closest('[data-faction]');
        if (!b) return;
        state.faction = b.dataset.faction;
        renderCategories();
        renderReinforcements();
        save();
    });
    $('ghWavesMinus').addEventListener('click', () => { state.waves = Math.max(1, state.waves - 1); renderWaves(); save(); });
    $('ghWavesPlus').addEventListener('click', () => { state.waves = Math.min(config.maxWaves, state.waves + 1); renderWaves(); save(); });
    document.querySelectorAll('[data-mode]').forEach((b) => b.addEventListener('click', () => {
        state.mode = b.dataset.mode;
        renderWeapons();
        save();
    }));
    $('ghWeaponAdd').addEventListener('click', () => {
        const name = $('ghWeaponSelect').value;
        if (!name || state.weapons.length >= config.maxWeapons || state.weapons.some((w) => w.name === name)) return;
        const left = 100 - total();
        state.weapons.push({ name, pct: Math.max(0, left) });
        if (left <= 0) spread(); // déjà 100 % : tout est réparti à parts égales
        renderWeapons();
        save();
    });
    $('ghWeapons').addEventListener('input', (e) => {
        if (e.target.dataset.range !== undefined) setPct(Number(e.target.dataset.range), e.target.value);
        else if (e.target.dataset.pct !== undefined) setPct(Number(e.target.dataset.pct), e.target.value);
    });
    $('ghWeapons').addEventListener('change', (e) => {
        if (e.target.dataset.pct !== undefined) setPct(Number(e.target.dataset.pct), e.target.value, true);
    });
    $('ghWeapons').addEventListener('click', (e) => {
        const b = e.target.closest('[data-remove]');
        if (!b) return;
        state.weapons.splice(Number(b.dataset.remove), 1);
        renderWeapons();
        save();
    });
    $('ghSpread').addEventListener('click', () => { spread(); renderWeapons(); save(); });
    $('ghVehicles').addEventListener('change', (e) => { state.vehicles = e.target.checked; save(); });
    $('ghHeli').addEventListener('change', (e) => { state.heli = e.target.checked; save(); });
    $('ghStart').addEventListener('click', start);
    $('ghStop').addEventListener('click', () => post('stop'));
    $('ghClose').addEventListener('click', () => post('close'));

    document.addEventListener('keydown', (e) => {
        if (box.classList.contains('hidden')) return;
        if (e.key === 'Escape') post('close');
    });

    // =====================================================================
    // MESSAGES DU JEU
    // =====================================================================
    function open(data) {
        const c = data.config || {};
        config = {
            categories: toArray(c.categories).map((cat) => ({ ...cat, factions: toArray(cat.factions) })),
            weapons: toArray(c.weapons), maxWaves: c.maxWaves || 10, waveSize: c.waveSize || 10,
            maxWeapons: c.maxWeapons || 10, sidearm: c.sidearm || 'WEAPON_COMBATPISTOL',
        };
        restore();
        // choix gardés mais plus valables (config changée) : corrigés
        state.weapons = toArray(state.weapons).filter((w) => weaponInfo(w.name)).slice(0, config.maxWeapons);
        if (!factionOf(state.faction)) state.faction = config.categories[0] && config.categories[0].factions[0] && config.categories[0].factions[0].key;
        const cat = categoryOf(state.faction);
        state.category = cat ? cat.key : (config.categories[0] && config.categories[0].key);
        state.waves = Math.max(1, Math.min(config.maxWaves, Number(state.waves) || 1));
        if (state.mode !== 'choose') state.mode = 'random';
        message('');
        render();
        renderActive(data.active === true, data.current);
        box.classList.remove('hidden');
        document.body.classList.add('menu-open');
    }

    function hud(data) {
        const el = $('ghHud');
        if (!data || !data.show) return el.classList.add('hidden');
        $('hudFaction').textContent = data.faction || '';
        $('hudWave').textContent = `Vague ${Math.max(1, data.wave || 1)} / ${data.waves || 1}`;
        const alive = $('hudAlive');
        alive.classList.toggle('waiting', data.waiting === true);
        alive.textContent = data.waiting ? 'Vague suivante dans quelques secondes…'
            : `${data.alive || 0} ennemi${data.alive > 1 ? 's' : ''} restant${data.alive > 1 ? 's' : ''}`;
        el.classList.remove('hidden');
    }

    window.addEventListener('message', (e) => {
        const msg = e.data || {};
        if (msg.action === 'open') open(msg.data || {});
        else if (msg.action === 'close') {
            box.classList.add('hidden');
            document.body.classList.remove('menu-open');
        }
        else if (msg.action === 'hud') hud(msg.data);
    });
})();
