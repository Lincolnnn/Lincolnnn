// RP Equipment : menu "Équipement" d'un véhicule (client/client.lua envoie open / close / rack / held / message)
(() => {
    const $ = (id) => document.getElementById(id);
    const box = $('equip');
    const resource = typeof window.GetParentResourceName === 'function' ? window.GetParentResourceName() : 'rp_equipment';
    let state = { slots: [], rack: {}, held: false };
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
        $('eqTag').title = t.label || '';
        $('eqSub').textContent = `${data.where === 'trunk' ? 'Coffre' : 'Portières avant'}${data.plate ? ` · ${data.plate}` : ''}`;
        $('eqFoot').textContent = `Se ferme à plus de ${data.closeDistance || 4} m du véhicule · Échap pour fermer`;
        state = { slots: Array.isArray(data.slots) ? data.slots : [], rack: data.rack || {}, held: false, freemode: data.freemode !== false };
        renderAssets(Array.isArray(data.assets) ? data.assets : []);
        renderRack();
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
    });
})();
