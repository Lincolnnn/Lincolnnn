// RP Ganghunt : menu de la chasse (faction, vagues, armes en pourcentages ou aléatoire, renforts) et HUD
(() => {
    const $ = (id) => document.getElementById(id);
    const box = $('gh');
    const resource = typeof window.GetParentResourceName === 'function' ? window.GetParentResourceName() : 'rp_Ganghunt';
    const STORE = 'rp_ganghunt_last';

    let config = {
        categories: [], weapons: [], maxWaves: 10, waveSize: 10, maxWaveSize: 30, maxWeapons: 10, sidearm: 'WEAPON_COMBATPISTOL',
        waveTimer: { Default: 60, Min: 15, Max: 600, Step: 15 }, musicVolume: 50, musicTracks: [],
    };
    const seconds = (n) => (n >= 60 ? `${Math.floor(n / 60)} min${n % 60 ? ` ${n % 60} s` : ''}` : `${n} s`);
    let state = {
        category: null, faction: null, waves: 1, size: 10, mode: 'random', weapons: [], vehicles: false, heli: false,
        silencer: false, grenades: false, music: false, passive: false, waveMode: 'clear', waveTimer: 60, volume: null,
    };
    const Music = window.GHMusic;
    Music.onError = () => { post('musicError'); renderListen(); };
    const PREVIEW_FADE = 800;
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
        $('ghSize').textContent = state.size;
        $('ghSizeMinus').disabled = state.size <= 1;
        $('ghSizePlus').disabled = state.size >= config.maxWaveSize;
        const n = state.waves * state.size;
        $('ghWavesText').innerHTML = `<b>${n}</b> ennemi${n > 1 ? 's' : ''} en tout, apparus à 70 m au plus autour de vous.`;
        document.querySelectorAll('[data-wavemode]').forEach((b) => b.classList.toggle('active', b.dataset.wavemode === state.waveMode));
        const T = config.waveTimer;
        $('ghTimerRow').classList.toggle('hidden', state.waveMode !== 'timer');
        $('ghTimer').textContent = seconds(state.waveTimer);
        $('ghTimerMinus').disabled = state.waveTimer <= T.Min;
        $('ghTimerPlus').disabled = state.waveTimer >= T.Max;
    }

    function renderWeapons() {
        document.querySelectorAll('[data-mode]').forEach((b) => b.classList.toggle('active', b.dataset.mode === state.mode));
        const random = state.mode === 'random';
        $('ghChoose').classList.toggle('hidden', random);
        const sidearm = weaponInfo(config.sidearm);
        const sidearmLabel = sidearm ? sidearm.label.toLowerCase() : 'pistolet de combat';
        $('ghWeaponHint').innerHTML = random
            ? `Chaque ennemi reçoit une arme au hasard parmi celles de sa faction, et un <b>${esc(sidearmLabel)}</b> en plus d'une arme longue.`
            : `Arme de poing : l'ennemi n'a <b>qu'elle</b>. Arme longue ou spéciale (lance-grenades, RPG…) : il a aussi un <b>${esc(sidearmLabel)}</b>. `
              + `Jusqu'à ${config.maxWeapons} armes, réparties sur <b>100 %</b>.`;
        if (random) return;

        const used = new Set(state.weapons.map((w) => w.name));
        const option = (w) => `<option value="${esc(w.name)}">${esc(w.label)}</option>`;
        const free = config.weapons.filter((w) => !used.has(w.name));
        const hand = free.filter((w) => w.handgun);
        const long = free.filter((w) => !w.handgun && !w.special);
        const special = free.filter((w) => w.special);
        $('ghWeaponSelect').innerHTML = (hand.length ? `<optgroup label="Armes de poing (seules)">${hand.map(option).join('')}</optgroup>` : '')
            + (long.length ? `<optgroup label="Armes longues (+ ${esc(sidearmLabel)})">${long.map(option).join('')}</optgroup>` : '')
            + (special.length ? `<optgroup label="Armes spéciales (+ ${esc(sidearmLabel)})">${special.map(option).join('')}</optgroup>` : '');
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
        $('ghSilencer').checked = state.silencer;
        $('ghGrenades').checked = state.grenades;
        $('ghMusic').checked = state.music;
        renderVolume();
        $('ghPassive').checked = state.passive;
        $('ghVehiclesText').textContent = f
            ? `En convoi, jusqu'à 4 par véhicule : ${toArray(f.vehicles).map((v) => v.label || v).join(', ')}. Ils descendent près de vous.`
            : '';
        $('ghHeliText').textContent = f && f.heli ? `${f.heliLabel || f.heli} : un pilote et deux tireurs, il vous suit et fouille la zone.` : '';
    }

    function renderListen() {
        const btn = $('ghListen');
        const hunt = Music.mode() === 'hunt';
        btn.classList.toggle('playing', Music.mode() === 'preview');
        btn.textContent = Music.mode() === 'preview' ? '■' : '▶';
        btn.disabled = hunt || config.musicTracks.length === 0;
        btn.title = hunt ? 'La musique de la traque joue' : 'Écouter';
    }

    function renderVolume() {
        $('ghVolumeRow').classList.toggle('hidden', !state.music);
        $('ghVolume').value = state.volume;
        $('ghVolumeText').textContent = `${state.volume} %`;
        renderListen();
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
            faction: state.faction, waves: state.waves, waveSize: state.size, random: state.mode === 'random',
            weapons: state.mode === 'random' ? [] : state.weapons.map((w) => ({ name: w.name, pct: w.pct })),
            vehicles: state.vehicles, heli: state.heli, silencer: state.silencer, grenades: state.grenades, music: state.music,
            passive: state.passive, waveMode: state.waveMode, waveTimer: state.waveTimer,
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
    $('ghSizeMinus').addEventListener('click', () => { state.size = Math.max(1, state.size - 1); renderWaves(); save(); });
    $('ghSizePlus').addEventListener('click', () => { state.size = Math.min(config.maxWaveSize, state.size + 1); renderWaves(); save(); });
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
    document.querySelectorAll('[data-wavemode]').forEach((b) => b.addEventListener('click', () => {
        state.waveMode = b.dataset.wavemode;
        renderWaves();
        save();
    }));
    const stepTimer = (dir) => {
        const T = config.waveTimer;
        state.waveTimer = Math.max(T.Min, Math.min(T.Max, state.waveTimer + dir * T.Step));
        renderWaves();
        save();
    };
    $('ghTimerMinus').addEventListener('click', () => stepTimer(-1));
    $('ghTimerPlus').addEventListener('click', () => stepTimer(1));
    ['silencer', 'grenades', 'music', 'passive'].forEach((key) => {
        const id = `gh${key[0].toUpperCase()}${key.slice(1)}`;
        $(id).addEventListener('change', (e) => { state[key] = e.target.checked; save(); });
    });
    // Musique : volume (appliqué tout de suite, même pendant la traque) et écoute d'essai depuis le menu
    $('ghVolume').addEventListener('input', (e) => {
        state.volume = Number(e.target.value);
        $('ghVolumeText').textContent = `${state.volume} %`;
        Music.setVolume(state.volume / 100);
        save();
    });
    $('ghListen').addEventListener('click', () => {
        if (Music.mode() === 'preview') Music.stop(PREVIEW_FADE);
        else if (!Music.playing()) Music.play({ tracks: config.musicTracks.slice(0, 1), fadeIn: PREVIEW_FADE }, 'preview');
        renderListen();
    });
    $('ghMusic').addEventListener('change', () => {
        renderVolume();
        if (!state.music && Music.mode() === 'preview') Music.stop(PREVIEW_FADE);
    });
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
            weapons: toArray(c.weapons), maxWaves: c.maxWaves || 10, waveSize: c.waveSize || 10, maxWaveSize: c.maxWaveSize || 30,
            waveTimer: Object.assign({ Default: 60, Min: 15, Max: 600, Step: 15 }, c.waveTimer || {}),
            maxWeapons: c.maxWeapons || 10, sidearm: c.sidearm || 'WEAPON_COMBATPISTOL',
            musicVolume: c.musicVolume != null ? c.musicVolume : 50, musicTracks: toArray(c.musicTracks),
        };
        restore();
        // choix gardés mais plus valables (config changée) : corrigés
        state.weapons = toArray(state.weapons).filter((w) => weaponInfo(w.name)).slice(0, config.maxWeapons);
        if (!factionOf(state.faction)) state.faction = config.categories[0] && config.categories[0].factions[0] && config.categories[0].factions[0].key;
        const cat = categoryOf(state.faction);
        state.category = cat ? cat.key : (config.categories[0] && config.categories[0].key);
        state.waves = Math.max(1, Math.min(config.maxWaves, Number(state.waves) || 1));
        state.size = Math.max(1, Math.min(config.maxWaveSize, Number(state.size) || config.waveSize));
        if (state.waveMode !== 'timer') state.waveMode = 'clear';
        state.waveTimer = Math.max(config.waveTimer.Min, Math.min(config.waveTimer.Max, Number(state.waveTimer) || config.waveTimer.Default));
        if (state.mode !== 'choose') state.mode = 'random';
        if (state.volume == null) state.volume = config.musicVolume;
        state.volume = Math.max(0, Math.min(100, Number(state.volume) || 0));
        Music.setVolume(state.volume / 100);
        message('');
        render();
        renderActive(data.active === true, data.current);
        box.classList.remove('hidden');
        document.body.classList.add('menu-open');
    }

    const STATE_TEXT = { engaged: 'REPÉRÉ', search: 'ILS VOUS CHERCHENT', waiting: 'VAGUE SUIVANTE', calm: 'NEUTRES' };
    function bar(fill, count, done, total) {
        const t = Math.max(1, total || 0);
        $(fill).style.width = `${Math.min(100, Math.round((done || 0) * 100 / t))}%`;
        $(count).textContent = `${done || 0} / ${total || 0}`;
    }
    function hud(data) {
        const el = $('ghHud');
        if (!data || !data.show) return el.classList.add('hidden');
        const st = STATE_TEXT[data.state] ? data.state : 'engaged';
        el.classList.remove('engaged', 'search', 'waiting', 'calm');
        el.classList.add(st);
        $('hudStateText').textContent = STATE_TEXT[st];
        $('hudFaction').textContent = data.faction || '';
        $('hudWave').textContent = `Vague ${Math.max(1, data.wave || 1)} / ${data.waves || 1}`;
        bar('hudWaveBar', 'hudWaveCount', data.waveKilled, data.waveTotal);
        bar('hudHuntBar', 'hudHuntCount', data.huntKilled, data.huntTotal);
        const alive = data.alive || 0;
        const left = `${alive} ennemi${alive > 1 ? 's' : ''} restant${alive > 1 ? 's' : ''}`;
        const next = data.next != null && st !== 'waiting' ? ` · suivante dans ${seconds(data.next)}` : '';
        $('hudSub').textContent = st === 'waiting' ? `Vague suivante dans ${seconds(data.next || 0)}`
            : st === 'search' ? `Hors de vue depuis ${data.lost || 0} s · ${left}${next}`
            : st === 'calm' ? `N'attaquent que si vous attaquez · ${alive} restant${alive > 1 ? 's' : ''}${next}` : `${left}${next}`;
        el.classList.remove('hidden');
    }

    // Volume gardé chez le joueur, appliqué dès le chargement (avant même l'ouverture du menu)
    restore();
    if (state.volume != null) Music.setVolume(Math.max(0, Math.min(100, Number(state.volume) || 0)) / 100);

    // Mode nuit des menus (MDC : Paramètres > MDC > Apparence), envoyé par client/theme.lua
    window.addEventListener('message', ({ data }) => {
        if (data && data.action === 'uiTheme') document.documentElement.dataset.theme = data.data && data.data.theme === 'night' ? 'night' : 'day';
    });

    window.addEventListener('message', (e) => {
        const msg = e.data || {};
        if (msg.action === 'open') open(msg.data || {});
        else if (msg.action === 'close') {
            box.classList.add('hidden');
            document.body.classList.remove('menu-open');
            if (Music.mode() === 'preview') Music.stop(PREVIEW_FADE);
        } else if (msg.action === 'music') {
            const m = msg.data || {};
            if (m.play) Music.play({ tracks: toArray(m.tracks), shuffle: m.shuffle, fadeIn: m.fadeIn, crossfade: m.crossfade }, 'hunt');
            else if (m.stop && Music.mode() !== 'preview') Music.stop(m.fadeOut);
            renderListen();
        }
        else if (msg.action === 'hud') hud(msg.data);
    });
})();
