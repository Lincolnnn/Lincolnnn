// RP Weapons Control : acouphène (sifflement généré ici, aucun fichier son). Chaque tir proche le fait monter ; il
// redescend tout seul. Plusieurs tirs : on garde le plus fort, la durée repart.
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

    window.addEventListener('message', ({ data }) => {
        if (data && data.action === 'tinnitus') ring(data.data || {});
    });
})();
