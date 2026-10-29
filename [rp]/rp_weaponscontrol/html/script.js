// RP Weapons Control : acouphène (sifflement généré ici, aucun fichier son). Chaque tir proche le fait monter ; il
// redescend tout seul. Plusieurs tirs : on garde le plus fort, la durée repart.
// Sélecteur de tir : logo en bas au milieu de l'écran (coup par coup / automatique) et petit clic mécanique.
(() => {
    'use strict';

    let ctx = null; let out = null; let level = 0; let fadeTimer = null;

    function setup() {
        if (ctx) return ctx;
        try {
            ctx = new (window.AudioContext || window.webkitAudioContext)();
        } catch (err) { return null; }
        out = ctx.createGain();
        out.gain.value = 0.0001;
        // deux sifflements très aigus légèrement décalés (battement), un souffle léger
        [4180, 4235].forEach((f) => {
            const o = ctx.createOscillator(); o.type = 'sine'; o.frequency.value = f; o.connect(out); o.start();
        });
        out.connect(ctx.destination);
        return ctx;
    }

    function ring(d) {
        const ac = setup();
        if (!ac) return;
        if (ac.state === 'suspended') ac.resume();
        const amount = Math.max(0, Math.min(1, Number(d.amount) || 0));
        const volume = Math.max(0, Math.min(1, Number(d.volume) || 0.16));
        const duration = Math.max(500, Number(d.duration) || 3000) / 1000;
        level = Math.max(level, amount);
        const peak = Math.max(0.0002, level * volume);
        const t = ac.currentTime;
        out.gain.cancelScheduledValues(t);
        out.gain.setValueAtTime(Math.max(out.gain.value, 0.0001), t);
        out.gain.linearRampToValueAtTime(peak, t + 0.08);                    // monte vite
        out.gain.setValueAtTime(peak, t + 0.08 + duration * 0.25);           // tient un peu
        out.gain.exponentialRampToValueAtTime(0.0001, t + 0.08 + duration);  // redescend
        clearTimeout(fadeTimer);
        fadeTimer = setTimeout(() => { level = 0; }, (0.08 + duration) * 1000);
    }

    // ---- Sélecteur de tir ----
    /** Petit clic du sélecteur : un claquement bref (bruit filtré) et un tic métallique */
    function click(volume) {
        const ac = setup();
        if (!ac) return;
        if (ac.state === 'suspended') ac.resume();
        const t = ac.currentTime;
        const v = Math.max(0, Math.min(1, Number(volume) || 0.35));
        const len = Math.floor(ac.sampleRate * 0.03);
        const buf = ac.createBuffer(1, len, ac.sampleRate);
        const ch = buf.getChannelData(0);
        for (let i = 0; i < len; i++) ch[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, 6);
        const noise = ac.createBufferSource(); noise.buffer = buf;
        const band = ac.createBiquadFilter(); band.type = 'bandpass'; band.frequency.value = 2600; band.Q.value = 1.2;
        const gn = ac.createGain(); gn.gain.value = v;
        noise.connect(band).connect(gn).connect(ac.destination);
        noise.start(t);
        const tick = ac.createOscillator(); tick.type = 'square'; tick.frequency.setValueAtTime(1800, t);
        tick.frequency.exponentialRampToValueAtTime(900, t + 0.025);
        const gt = ac.createGain(); gt.gain.setValueAtTime(v * 0.18, t); gt.gain.exponentialRampToValueAtTime(0.0001, t + 0.03);
        tick.connect(gt).connect(ac.destination);
        tick.start(t); tick.stop(t + 0.035);
    }

    const badge = document.getElementById('firemode');
    let hideTimer = null; let flashTimer = null;
    function fireMode(d) {
        clearTimeout(hideTimer);
        if (!d.show) { badge.classList.remove('show', 'flash'); return; }
        const auto = d.mode !== 'semi';
        badge.dataset.mode = auto ? 'auto' : 'semi';
        badge.querySelectorAll('.bullets i').forEach((b, i) => b.classList.toggle('off', !auto && i > 0));
        badge.querySelector('.label').textContent = auto ? 'Auto' : 'Coup par coup';
        badge.classList.add('show');
        if (d.changed) {
            click(d.volume);
            badge.classList.add('flash');
            clearTimeout(flashTimer);
            flashTimer = setTimeout(() => badge.classList.remove('flash'), 600);
        }
        // Logo non permanent : seulement quelques secondes après un changement
        if (d.persistent === false) hideTimer = setTimeout(() => badge.classList.remove('show'), d.changed ? 2500 : 0);
    }

    window.addEventListener('message', ({ data }) => {
        if (data && data.action === 'tinnitus') ring(data.data || {});
        if (data && data.action === 'firemode') fireMode(data.data || {});
    });
})();
