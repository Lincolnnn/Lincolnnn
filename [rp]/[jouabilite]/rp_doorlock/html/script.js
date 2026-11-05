// RP Doorlock : barre de réussite (client/client.lua envoie breach / breachKey ; ESPACE et RETOUR sont lus par le jeu)
// et bruits des coups de pied / de la porte qui cède (sound)
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

    // =====================================================================
    // BRUITS (générés ici, aucun fichier) : coup de pied réussi / raté, porte qui cède
    // =====================================================================
    let ac = null;
    function audio() {
        try { ac = ac || new (window.AudioContext || window.webkitAudioContext)(); } catch (err) { ac = null; }
        if (ac && ac.state === 'suspended') ac.resume();
        return ac;
    }
    function noise(ctx, length) {
        const len = Math.floor(ctx.sampleRate * length);
        const buf = ctx.createBuffer(1, len, ctx.sampleRate);
        const ch = buf.getChannelData(0);
        for (let i = 0; i < len; i += 1) ch[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, 2);
        const src = ctx.createBufferSource(); src.buffer = buf;
        return src;
    }
    /** Choc sourd sur du bois : bruit filtré grave + note basse qui retombe */
    function thud(ctx, out, at, { gain, cutoff, freq, length }) {
        const n = noise(ctx, length); const f = ctx.createBiquadFilter(); const g = ctx.createGain();
        f.type = 'lowpass'; f.frequency.value = cutoff;
        g.gain.setValueAtTime(gain, at); g.gain.exponentialRampToValueAtTime(0.0001, at + length);
        n.connect(f); f.connect(g); g.connect(out); n.start(at);
        const o = ctx.createOscillator(); const og = ctx.createGain();
        o.type = 'sine'; o.frequency.setValueAtTime(freq, at); o.frequency.exponentialRampToValueAtTime(freq * 0.55, at + length);
        og.gain.setValueAtTime(gain * 0.9, at); og.gain.exponentialRampToValueAtTime(0.0001, at + length);
        o.connect(og); og.connect(out); o.start(at); o.stop(at + length + 0.05);
    }
    /** Craquement (bois qui éclate) : bruit aigu haché */
    function crack(ctx, out, at, gain) {
        for (let i = 0; i < 5; i += 1) {
            const t = at + i * 0.018 + Math.random() * 0.01;
            const n = noise(ctx, 0.06); const f = ctx.createBiquadFilter(); const g = ctx.createGain();
            f.type = 'bandpass'; f.frequency.value = 1400 + Math.random() * 2200; f.Q.value = 1.2;
            g.gain.setValueAtTime(gain * (1 - i * 0.15), t); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.06);
            n.connect(f); f.connect(g); g.connect(out); n.start(t);
        }
    }
    const SOUNDS = {
        hit(ctx, out, t) { thud(ctx, out, t, { gain: 1.0, cutoff: 520, freq: 78, length: 0.32 }); crack(ctx, out, t + 0.005, 0.12); },
        miss(ctx, out, t) { thud(ctx, out, t, { gain: 0.55, cutoff: 380, freq: 95, length: 0.2 }); },
        break(ctx, out, t) {
            thud(ctx, out, t, { gain: 1.0, cutoff: 700, freq: 70, length: 0.45 });
            crack(ctx, out, t, 0.5);
            crack(ctx, out, t + 0.09, 0.3);
            thud(ctx, out, t + 0.32, { gain: 0.7, cutoff: 900, freq: 120, length: 0.35 }); // le battant tape le mur
        },
    };
    function playSound(d) {
        const fn = SOUNDS[d.kind]; const ctx = fn && audio();
        if (!ctx) return;
        const out = ctx.createGain();
        out.gain.value = Math.max(0, Math.min(1, Number(d.volume) || 0));
        out.connect(ctx.destination);
        try { fn(ctx, out, ctx.currentTime + 0.01); } catch (err) { /* son indisponible */ }
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
        } else if (data.action === 'sound') {
            playSound(data.data || {});
        }
    });
})();
