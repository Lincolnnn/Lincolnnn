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

    function renderItems(items) {
        const list = $('eqItems');
        list.innerHTML = items.length
            ? items.map((it) => `
                <div class="eq-item">
                    <span class="eq-item-label">${esc(it.label)}</span>
                    <button class="eq-btn eq-primary" data-take="${esc(it.id)}">Prendre</button>
                </div>`).join('')
            : '<div class="eq-empty">Rien ici : essayez l\'autre côté du véhicule.</div>';
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
            const parts = [];
            if (w.components) parts.push(`${w.components} accessoire${w.components > 1 ? 's' : ''}`);
            parts.push(`${w.ammo || 0} munition${(w.ammo || 0) > 1 ? 's' : ''}`);
            return `
                <div class="eq-slot full">
                    <div class="eq-slot-name">${esc(slot.label)}</div>
                    <div class="eq-slot-weapon">${esc(w.label)}</div>
                    <div class="eq-slot-info">${esc(parts.join(' · '))}</div>
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
        state = { slots: data.slots || [], rack: data.rack || {}, held: false };
        renderItems(data.items || []);
        renderRack();
        message('');
        box.classList.remove('hidden');
    }

    function close() {
        box.classList.add('hidden');
    }

    box.addEventListener('click', (e) => {
        const take = e.target.closest('[data-take]');
        if (take) return post('take', { id: take.dataset.take });
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
        else if (msg.action === 'held') { state.held = data || false; renderRack(); }
        else if (msg.action === 'message') message(data && data.text, data && data.error);
    });
})();
