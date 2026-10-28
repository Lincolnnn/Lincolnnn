// RP Revive : écran de mort (client/client.lua envoie death ; le choix revient par le callback revive)
(() => {
    'use strict';

    const RESOURCE = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'rp_revive';
    const $ = (id) => document.getElementById(id);
    const box = $('death');
    const state = { open: false, readyAt: 0, timer: null, keys: { here: 'E', hospital: 'H', corpse: 'C' }, sent: false };

    function post(name, data) {
        return fetch(`https://${RESOURCE}/${name}`, {
            method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data || {}),
        }).catch(() => {});
    }

    function ready() { return Date.now() >= state.readyAt; }

    function tick() {
        const left = Math.ceil((state.readyAt - Date.now()) / 1000);
        const can = left <= 0;
        $('reviveHere').disabled = !can || state.sent;
        $('reviveHospital').disabled = !can || state.sent;
        $('deathWait').textContent = state.sent ? 'Réanimation…' : (can ? '' : `Choix possible dans ${left} s`);
        if (can) { clearInterval(state.timer); state.timer = null; }
    }

    function open(d) {
        state.open = true; state.sent = false;
        state.keys = Object.assign(state.keys, d.keys || {});
        state.readyAt = Date.now() + (Number(d.delay) || 0) * 1000;
        $('keyHere').textContent = state.keys.here; $('keyHospital').textContent = state.keys.hospital; $('keyCorpse').textContent = state.keys.corpse;
        const list = Array.isArray(d.hospitals) ? d.hospitals : Object.values(d.hospitals || {});
        $('hospitalList').textContent = list.length ? `Au hasard : ${list.join(' ou ')}` : 'Un hôpital au hasard';
        $('corpseRow').classList.toggle('hidden', d.corpse === false);
        $('corpse').checked = false;
        box.classList.remove('hidden');
        clearInterval(state.timer);
        state.timer = setInterval(tick, 250);
        tick();
    }

    function close() {
        state.open = false;
        clearInterval(state.timer); state.timer = null;
        box.classList.add('hidden');
    }

    function choose(where) {
        if (!state.open || state.sent || !ready()) return;
        state.sent = true;
        tick();
        post('revive', { where, corpse: $('corpse').checked });
    }

    box.addEventListener('click', (e) => {
        const btn = e.target.closest('[data-where]');
        if (btn && !btn.disabled) choose(btn.dataset.where);
    });

    document.addEventListener('keydown', (e) => {
        if (!state.open) return;
        const k = e.key.toUpperCase();
        if (k === String(state.keys.here).toUpperCase()) choose('here');
        else if (k === String(state.keys.hospital).toUpperCase()) choose('hospital');
        else if (k === String(state.keys.corpse).toUpperCase() && !$('corpseRow').classList.contains('hidden')) $('corpse').checked = !$('corpse').checked;
    });

    // Mode nuit des menus (MDC : Paramètres > MDC > Apparence), envoyé par client/theme.lua
    window.addEventListener('message', ({ data }) => {
        if (!data || data.action !== 'uiTheme') return;
        const t = data.data || {};
        document.documentElement.dataset.theme = 'night'; // toujours sombre : de jour, couleurs du logo du serveur
        document.documentElement.dataset.nightColor = t.theme === 'night' && ['green', 'yellow', 'red', 'blue'].includes(t.color) ? t.color : 'logo';
    });

    window.addEventListener('message', ({ data }) => {
        if (!data || data.action !== 'death') return;
        const d = data.data || {};
        if (d.show) open(d); else close();
    });
})();
