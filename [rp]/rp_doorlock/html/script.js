// RP Doorlock : barre de réussite (client/client.lua envoie breach / breachKey ; ESPACE et RETOUR sont lus par le jeu)
(() => {
    'use strict';

    const RESOURCE = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'rp_doorlock';
    const $ = (id) => document.getElementById(id);
    const box = $('breach');
    const CURSOR_TOLERANCE = 0.006; // demi-largeur du curseur (part de la barre)

    const game = { running: false, frozen: true, pos: 0, dir: 1, speed: 1, zone: [0.4, 0.6], last: 0, steps: 3, step: 0 };

    function post(name, data) {
        return fetch(`https://${RESOURCE}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        }).catch(() => {});
    }

    function renderSteps() {
        $('breachSteps').innerHTML = Array.from({ length: game.steps }, (_, i) => {
            const cls = i < game.step ? 'done' : (i === game.step ? 'current' : '');
            return `<span class="breach-step ${cls}"></span>`;
        }).join('');
        $('breachCount').textContent = `${Math.min(game.step, game.steps)} / ${game.steps} réussis`;
    }

    // Curseur : va et vient d'un bout à l'autre, `speed` allers par seconde
    function frame(t) {
        if (!game.running) return;
        const dt = game.last ? Math.min((t - game.last) / 1000, 0.05) : 0;
        game.last = t;
        if (!game.frozen) {
            game.pos += game.dir * game.speed * dt;
            if (game.pos >= 1) { game.pos = 2 - game.pos; game.dir = -1; }
            if (game.pos <= 0) { game.pos = -game.pos; game.dir = 1; }
            $('breachCursor').style.left = `${game.pos * 100}%`;
        }
        requestAnimationFrame(frame);
    }

    function startStep(d) {
        game.steps = Number(d.steps) || 3;
        game.step = Number(d.step) || 0;
        game.speed = Number(d.speed) || 1;
        const width = Math.min(Math.max(Number(d.zone) || 0.2, 0.04), 0.6);
        const start = 0.12 + Math.random() * (0.76 - width); // jamais collée à un bord
        game.zone = [start, start + width];
        $('breachZone').style.left = `${start * 100}%`;
        $('breachZone').style.width = `${width * 100}%`;
        // le curseur repart d'un bord, du côté le plus loin de la zone
        game.dir = start + width / 2 > 0.5 ? 1 : -1;
        game.pos = game.dir === 1 ? 0 : 1;
        box.classList.remove('hit', 'miss');
        renderSteps();
        game.frozen = false;
        if (!game.running) {
            game.running = true;
            game.last = 0;
            requestAnimationFrame(frame);
        }
        box.classList.remove('hidden');
    }

    function stop() {
        game.running = false;
        game.frozen = true;
        box.classList.add('hidden');
        box.classList.remove('hit', 'miss');
    }

    // ESPACE : le curseur s'arrête ; dans la zone verte = réussi
    function press() {
        if (!game.running || game.frozen) return;
        game.frozen = true;
        const hit = game.pos >= game.zone[0] - CURSOR_TOLERANCE && game.pos <= game.zone[1] + CURSOR_TOLERANCE;
        box.classList.add(hit ? 'hit' : 'miss');
        if (hit) { game.step += 1; renderSteps(); }
        post('breachResult', { hit, pos: game.pos });
    }

    // Mode nuit des menus (MDC : Paramètres > MDC > Apparence), envoyé par client/theme.lua
    window.addEventListener('message', ({ data }) => {
        if (!data || data.action !== 'uiTheme') return;
        const t = data.data || {};
        document.documentElement.dataset.theme = 'night'; // toujours sombre : de jour, couleurs du logo du serveur
        document.documentElement.dataset.nightColor = t.theme === 'night' && ['green', 'yellow', 'red', 'blue'].includes(t.color) ? t.color : 'logo';
    });

    window.addEventListener('message', ({ data }) => {
        if (!data || !data.action) return;
        if (data.action === 'breach') {
            const d = data.data || {};
            if (d.show) startStep(d); else stop();
        } else if (data.action === 'breachKey') {
            press();
        }
    });
})();
