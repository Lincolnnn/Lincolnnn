// RP Equipment : menu "Équipement" d'un véhicule (client/client.lua envoie open / close / rack / held / message)
(() => {
    const $ = (id) => document.getElementById(id);
    const box = $('equip');
    const resource = typeof window.GetParentResourceName === 'function' ? window.GetParentResourceName() : 'rp_equipment';
    let state = { slots: [], rack: {}, held: false, stock: false, where: 'trunk', inv: { carrying: 0, maxCarry: 5, flares: 0, maxHeld: 25, jerrycan: false, radar: false }, coneQty: 1 };
    // Onglets ouverts (gardés pendant la session, d'un véhicule à l'autre) : Arme longue ouvert par défaut
    const openFolds = { rack: true };
    let messageTimer = null;

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

    function renderFolds() {
        box.querySelectorAll('.eq-fold').forEach((f) => f.classList.toggle('open', !!openFolds[f.dataset.fold]));
    }

    // Pièces EUP de la catégorie du véhicule : "Mettre" / "Retirer" selon ce que le joueur porte ; onglet seulement
    // s'il y en a
    function renderAssets(assets) {
        const list = $('eqItems');
        $('eqAssetsSection').classList.toggle('hidden', !state.freemode || !assets.length);
        const worn = assets.filter((a) => a.worn).length;
        $('eqAssetsSum').textContent = assets.length ? `${worn} / ${assets.length} porté${worn > 1 ? 's' : ''}` : '';
        if (!state.freemode) {
            list.innerHTML = '<div class="eq-empty">Équipement disponible uniquement avec un personnage multijoueur.</div>';
            return;
        }
        list.innerHTML = assets.length
            ? assets.map((a) => `
                <div class="eq-item${a.worn ? ' worn' : ''}">
                    <span class="eq-item-label">${a.worn ? '<span class="eq-check">✓</span>' : ''}${esc(a.name)}</span>
                    <button class="eq-btn${a.worn ? '' : ' eq-primary'}" data-wear="${esc(a.id)}">${a.item ? (a.worn ? 'Ranger' : 'Prendre') : (a.worn ? 'Retirer' : 'Mettre')}</button>
                </div>`).join('')
            : '<div class="eq-empty">Aucun équipement pour cette catégorie de véhicule.</div>';
    }

    function renderRack() {
        const section = $('eqRackSection');
        section.classList.toggle('hidden', state.slots.length === 0);
        $('eqSlots').innerHTML = state.slots.map((slot) => {
            const w = state.rack[slot.id];
            const target = state.held && state.held.slot === slot.id;
            if (!w) {
                return `
                <div class="eq-slot empty${target ? ' target' : ''}">
                    <div class="eq-slot-name">${esc(slot.label)}</div>
                    <div class="eq-slot-weapon">Vide</div>
                </div>`;
            }
            const info = w.components ? `${w.components} accessoire${w.components > 1 ? 's' : ''}` : 'Sans accessoire';
            return `
                <div class="eq-slot full">
                    <div class="eq-slot-name">${esc(slot.label)}</div>
                    <div class="eq-slot-weapon">${esc(w.label)}</div>
                    <div class="eq-slot-info">${esc(info)}</div>
                    <button class="eq-btn eq-primary" data-retrieve="${esc(slot.id)}">Sortir l'arme</button>
                </div>`;
        }).join('');
        const full = state.slots.filter((slot) => state.rack[slot.id]);
        $('eqRackSum').textContent = !state.slots.length ? '' : full.length ? full.map((slot) => state.rack[slot.id].label).join(', ') : 'Vide';
        const held = state.held;
        const free = held && !state.rack[held.slot];
        $('eqStore').disabled = !free;
        $('eqHeld').textContent = !held
            ? 'Tenez l\'arme longue dans les mains pour la ranger.'
            : free ? `En main : ${held.label}` : `En main : ${held.label} (emplacement déjà occupé)`;
    }

    // Avant : fusées de l'avant ; coffre : Affaires (Matériel : plots, fusées, pistolet radar, herse ; Jerrycan)
    function renderStock() {
        const st = state.stock;
        const inv = state.inv;
        const front = state.where !== 'trunk';
        $('eqStockSection').classList.toggle('hidden', !st || front);
        $('eqFrontFlaresSection').classList.toggle('hidden', !st || !front || !(st.maxFrontFlares > 0));
        box.querySelectorAll('[data-flares-held]').forEach((el) => { el.textContent = `Sur vous : ${inv.flares}`; });
        if (!st) return;
        if (front) {
            const n = Number(st.frontFlares) || 0, max = Number(st.maxFrontFlares) || 0;
            $('eqFrontFlares').textContent = `${n} / ${max} à l'avant`;
            $('eqFrontFlaresSum').textContent = `${n} / ${max}`;
            $('eqFrontFlaresSection').querySelectorAll('[data-flares="take"]').forEach((b) => { b.disabled = n <= 0 || inv.flares >= inv.maxHeld; });
            $('eqFrontFlaresSection').querySelectorAll('[data-flares="store"]').forEach((b) => { b.disabled = inv.flares <= 0 || n >= max; });
            return;
        }
        $('eqCones').textContent = `${st.cones} / ${st.maxCones} dans le coffre`;
        $('eqConesBar').style.width = `${st.maxCones ? Math.round(st.cones / st.maxCones * 100) : 0}%`;
        // Prendre : le nombre choisi (1 → ce que le coffre a et ce que le policier peut encore porter)
        const carrying = Number(inv.carrying) || 0;
        const canTake = Math.max(0, Math.min(st.cones, (inv.maxCarry || 5) - carrying));
        state.coneQty = Math.max(1, Math.min(state.coneQty || 1, canTake || 1));
        $('eqConeQty').textContent = state.coneQty;
        box.querySelector('[data-qty="-1"]').disabled = canTake <= 0 || state.coneQty <= 1;
        box.querySelector('[data-qty="1"]').disabled = canTake <= 0 || state.coneQty >= canTake;
        $('eqConeTake').disabled = canTake <= 0;
        $('eqConeTake').textContent = `Prendre ${state.coneQty} plot${state.coneQty > 1 ? 's' : ''}`;
        // Ranger : tous les plots portés d'un coup (un seul : « Ranger le plot »)
        $('eqConeStore').disabled = carrying <= 0 || st.cones >= st.maxCones;
        $('eqConeStore').textContent = carrying > 1 ? `Ranger les ${carrying} plots` : 'Ranger le plot';
        // Jerrican : un par coffre (plein d'origine), rangé avec l'essence qui lui reste
        const cans = Number(st.jerrycans) || 0;
        const held = inv.jerrycan !== false && inv.jerrycan != null;
        $('eqCans').textContent = cans
            ? `${cans} / ${st.maxJerrycans || 1} dans le coffre${st.jerrycanFill >= 100 ? ' (plein)' : ` (${st.jerrycanFill} %)`}`
            : `0 / ${st.maxJerrycans || 1} dans le coffre`;
        $('eqCanHeld').textContent = held ? `Sur vous : 1 (${inv.jerrycan} %)` : 'Sur vous : aucun';
        $('eqCanTake').disabled = cans <= 0 || held;
        $('eqCanStore').disabled = !held || cans >= (st.maxJerrycans || 1);
        // Pistolet radar : un par coffre
        const radars = Number(st.radars) || 0;
        $('eqRadars').textContent = `${radars} / ${st.maxRadars || 1} dans le coffre`;
        $('eqRadarHeld').textContent = inv.radar ? 'Sur vous : 1' : 'Sur vous : aucun';
        $('eqRadarTake').disabled = radars <= 0 || !!inv.radar;
        $('eqRadarStore').disabled = !inv.radar || radars >= (st.maxRadars || 1);
        // Herse (riven_spikes) : seulement si le script est là, dans le coffre ; en main ou non
        $('eqSpikeRow').classList.toggle('hidden', !inv.spikes);
        if (inv.spikes) {
            $('eqSpikeHeld').textContent = inv.spikeHeld ? 'En main : une herse' : 'En main : aucune';
            $('eqSpikeTake').disabled = !!inv.spikeHeld;
            $('eqSpikeStore').disabled = !inv.spikeHeld;
        }
        $('eqFlares').textContent = `${st.flares} / ${st.maxFlares} dans le coffre`;
        $('eqStockSection').querySelectorAll('[data-flares="take"]').forEach((b) => { b.disabled = st.flares <= 0 || inv.flares >= inv.maxHeld; });
        $('eqStockSection').querySelectorAll('[data-flares="store"]').forEach((b) => { b.disabled = inv.flares <= 0 || st.flares >= st.maxFlares; });
        $('eqGearSum').textContent = `${st.cones} plots · ${st.flares} fusées`;
        $('eqCansSum').textContent = cans ? (st.jerrycanFill >= 100 ? 'Plein' : `${st.jerrycanFill} %`) : 'Vide';
        $('eqCarry').textContent = carrying
            ? `Vous portez ${carrying > 1 ? `${carrying} plots` : 'un plot'} : G pour en poser un au sol, ou les ranger ici.`
            : 'Plots posés : les reprendre avec le target (« Ramasser le plot » ou « Ramasser les plots autour »). Un plot pris et pas remis n\'est plus dans le coffre.';
    }

    function message(text, error) {
        const el = $('eqMessage');
        el.textContent = text || '';
        el.classList.toggle('error', !!error);
        clearTimeout(messageTimer);
        if (text) messageTimer = setTimeout(() => { el.textContent = ''; }, 4000);
    }

    function open(data) {
        const t = data.type || {};
        $('eqTag').textContent = t.short || '';
        $('eqTag').style.background = t.color || '';
        box.style.setProperty('--head-color', t.color || '#2d63b3'); // bannière : couleur de la police du véhicule
        $('eqTag').title = t.label || '';
        $('eqSub').textContent = `${data.where === 'trunk' ? 'Coffre' : 'Portières avant'}${data.plate ? ` · ${data.plate}` : ''}`;
        // une arme longue à l'avant, une dans le coffre : chacune ne se prend que là où elle est rangée
        $('eqRackLegend').textContent = data.where === 'trunk' ? 'Arme longue · coffre' : 'Arme longue · avant';
        $('eqFoot').textContent = `Se ferme à plus de ${data.closeDistance || 4} m du véhicule · Échap pour fermer`;
        state = { slots: Array.isArray(data.slots) ? data.slots : [], rack: data.rack || {}, held: false, freemode: data.freemode !== false,
            stock: data.stock || false, where: data.where === 'trunk' ? 'trunk' : 'front', inv: state.inv, coneQty: 1 };
        renderFolds();
        renderAssets(Array.isArray(data.assets) ? data.assets : []);
        renderRack();
        renderStock();
        message('');
        box.classList.remove('hidden');
    }

    function close() {
        box.classList.add('hidden');
    }

    box.addEventListener('click', (e) => {
        const head = e.target.closest('.eq-fold-head');
        if (head) {
            const name = head.parentElement.dataset.fold;
            openFolds[name] = !openFolds[name];
            renderFolds();
            return null;
        }
        const wear = e.target.closest('[data-wear]');
        if (wear) return post('wear', { id: wear.dataset.wear });
        const retrieve = e.target.closest('[data-retrieve]');
        if (retrieve) return post('retrieve', { slot: retrieve.dataset.retrieve });
        if (e.target.closest('#eqStore')) return post('store');
        const qty = e.target.closest('[data-qty]');
        if (qty) { state.coneQty = (state.coneQty || 1) + Number(qty.dataset.qty); renderStock(); return null; }
        if (e.target.closest('#eqConeTake')) return post('coneTake', { count: state.coneQty || 1 });
        if (e.target.closest('#eqConeStore')) return post('coneStore');
        if (e.target.closest('#eqCanTake')) return post('jerrycan', { mode: 'take' });
        if (e.target.closest('#eqCanStore')) return post('jerrycan', { mode: 'store' });
        if (e.target.closest('#eqRadarTake')) return post('radarGun', { mode: 'take' });
        if (e.target.closest('#eqRadarStore')) return post('radarGun', { mode: 'store' });
        if (e.target.closest('#eqSpikeTake')) return post('spikes', { mode: 'take' });
        if (e.target.closest('#eqSpikeStore')) return post('spikes', { mode: 'store' });
        const flares = e.target.closest('[data-flares]');
        if (flares) return post('flares', { mode: flares.dataset.flares, all: !!flares.dataset.all });
        if (e.target.closest('#eqClose')) return post('close');
        return null;
    });

    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && !box.classList.contains('hidden')) post('close');
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
        const data = msg.data;
        if (msg.action === 'open') open(data || {});
        else if (msg.action === 'close') close();
        else if (msg.action === 'rack') { state.rack = data || {}; renderRack(); }
        else if (msg.action === 'assets') renderAssets(Array.isArray(data) ? data : []);
        else if (msg.action === 'held') { state.held = data || false; renderRack(); }
        else if (msg.action === 'message') message(data && data.text, data && data.error);
        else if (msg.action === 'stock') { state.stock = data || false; renderStock(); }
        else if (msg.action === 'inventory') { state.inv = Object.assign(state.inv, data || {}); renderStock(); }
    });
})();
