// RP Equipment : menu "Équipement" d'un véhicule (client/client.lua envoie open / close / rack / held / message)
(() => {
    const $ = (id) => document.getElementById(id);
    const box = $('equip');
    const resource = typeof window.GetParentResourceName === 'function' ? window.GetParentResourceName() : 'rp_equipment';
    let state = { slots: [], rack: {}, held: false, stock: false, inv: { carrying: 0, maxCarry: 5, flares: 0, maxHeld: 25, jerrycan: false }, coneQty: 1 };
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

    // Pièces EUP de la catégorie du véhicule : "Mettre" / "Retirer" selon ce que le joueur porte
    function renderAssets(assets) {
        const list = $('eqItems');
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
        const held = state.held;
        const free = held && !state.rack[held.slot];
        $('eqStore').disabled = !free;
        $('eqHeld').textContent = !held
            ? 'Tenez l\'arme longue dans les mains pour la ranger.'
            : free ? `En main : ${held.label}` : `En main : ${held.label} (emplacement déjà occupé)`;
    }

    // Coffre : plots (portés / rangés) et fusées (sur soi / dans le coffre)
    function renderStock() {
        const st = state.stock;
        const inv = state.inv;
        $('eqStockSection').classList.toggle('hidden', !st);
        if (!st) return;
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
        $('eqFlares').textContent = `${st.flares} / ${st.maxFlares} dans le coffre`;
        $('eqFlaresHeld').textContent = `Sur vous : ${inv.flares}`;
        box.querySelectorAll('[data-flares="take"]').forEach((b) => { b.disabled = st.flares <= 0 || inv.flares >= inv.maxHeld; });
        box.querySelectorAll('[data-flares="store"]').forEach((b) => { b.disabled = inv.flares <= 0 || st.flares >= st.maxFlares; });
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
        $('eqFoot').textContent = `Se ferme à plus de ${data.closeDistance || 4} m du véhicule · Échap pour fermer`;
        state = { slots: Array.isArray(data.slots) ? data.slots : [], rack: data.rack || {}, held: false, freemode: data.freemode !== false,
            stock: data.stock || false, inv: state.inv, coneQty: 1 };
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
        const flares = e.target.closest('[data-flares]');
        if (flares) return post('flares', { mode: flares.dataset.flares, all: !!flares.dataset.all });
        if (e.target.closest('#eqClose')) return post('close');
        return null;
    });

    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && !box.classList.contains('hidden')) post('close');
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
