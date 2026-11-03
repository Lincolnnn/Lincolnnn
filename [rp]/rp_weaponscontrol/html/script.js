// RP Weapons Control (aucun acouphène : son retiré).
// Sélecteur de tir : logo en bas au milieu de l'écran (coup par coup / automatique) et petit clic mécanique.
// Effet de tir sur les bords de l'écran (Suppression) : voile style « motion blur », s'étend à chaque tir, disparaît
// fadeOut ms après le dernier ; touché : bords légèrement rouges.
(() => {
    'use strict';

    let ctx = null;

    /** Contexte audio (clic du sélecteur de tir). Plus d'acouphène : aucun sifflement n'est généré. */
    function setup() {
        if (ctx) return ctx;
        try {
            ctx = new (window.AudioContext || window.webkitAudioContext)();
        } catch (err) { return null; }
        return ctx;
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
        // Logo non permanent : seulement `seconds` s après un appui sur la touche, ou quand une arme longue est prise
        // en main (drawn : coup par coup, sans clic) ; autre arme sortie ou changée : rien
        if (!d.show || (d.persistent !== true && !d.changed && !d.drawn)) { badge.classList.remove('show', 'flash'); return; }
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
        if (d.persistent !== true) hideTimer = setTimeout(() => badge.classList.remove('show'), (Number(d.seconds) || 3) * 1000);
    }

    // ---- Effet de tir sur les bords de l'écran ----
    const spEl = document.getElementById('suppress');
    const spHit = document.getElementById('suppressHit');
    const spStreaks = document.getElementById('spStreaks');
    const sp = { peak: 0, last: 0, hitPeak: 0, hitLast: 0, cfg: null, running: false };
    const clamp01 = (v) => Math.max(0, Math.min(1, Number(v) || 0));

    /** Intensité restante (0-1) : décroît jusqu'à 0 en `fade` ms après le dernier tir */
    const levelAt = (peak, last, fade, now) => peak * Math.max(0, 1 - (now - last) / Math.max(1, fade));

    /** Masque : transparent au centre, dense vers les bords ; `coverage` = part couverte depuis chaque bord */
    function edgeMask(coverage) {
        const edge = 70.71; // milieu des bords dans une ellipse qui passe par les coins
        const inner = Math.max(0, (1 - 2 * coverage) * edge);
        const mid = inner + (edge - inner) * 0.55;
        return `radial-gradient(ellipse at 50% 50%, transparent ${inner.toFixed(2)}%, rgba(0,0,0,.6) ${mid.toFixed(2)}%, #000 ${edge}%, #000 100%)`;
    }

    function spFrame() {
        const c = sp.cfg;
        const now = performance.now();
        const level = levelAt(sp.peak, sp.last, c.fadeOut, now);
        const hit = levelAt(sp.hitPeak, sp.hitLast, c.hitFade, now);
        const lo = clamp01(c.minCoverage); const hi = Math.max(lo, clamp01(c.maxCoverage));
        if (level > 0) {
            // densité : vite visible (curve < 1) ; taille : grandit tir après tir (proportionnelle)
            const k = Math.pow(level, Number(c.curve) > 0 ? Number(c.curve) : 0.5);
            spEl.style.setProperty('--mask', edgeMask(lo + (hi - lo) * level));
            spEl.style.opacity = (clamp01(c.opacity) * k).toFixed(3);
        } else spEl.style.opacity = 0;
        if (hit > 0) {
            spHit.style.setProperty('--mask', edgeMask(lo + (hi - lo) * Math.max(0.35, hit) * 0.85));
            spHit.style.opacity = (clamp01(c.hitOpacity) * hit).toFixed(3);
        } else spHit.style.opacity = 0;
        // touché : le voile lui-même vire à la couleur HitColor (dosée par HitOpacity), puis redevient Tint
        const mix = clamp01(c.hitOpacity) * hit;
        if (mix > 0 || sp.tinted) {
            const t = rgbArr(c.tint, [26, 28, 32]); const h = rgbArr(c.hitColor, [150, 8, 12]);
            spEl.style.setProperty('--tint', t.map((v, i) => Math.round(v + (h[i] - v) * mix)).join(', '));
            sp.tinted = mix > 0;
        }
        if (level > 0 || hit > 0) { requestAnimationFrame(spFrame); return; }
        sp.running = false;
        spEl.style.display = 'none'; spHit.style.display = 'none';
    }

    const rgbArr = (a, def) => (Array.isArray(a) && a.length >= 3 ? a.slice(0, 3).map((v) => Math.max(0, Math.min(255, Number(v) || 0))) : def);

    function suppress(d) {
        const c = d.cfg || sp.cfg;
        if (!c) return;
        sp.cfg = c;
        const now = performance.now();
        const rgb = (a, def) => (Array.isArray(a) && a.length >= 3 ? a.slice(0, 3).map((v) => Math.round(Number(v) || 0)) : def).join(', ');
        spEl.style.setProperty('--tint', rgb(c.tint, [26, 28, 32]));
        spEl.style.setProperty('--blur', `${Math.max(0, Number(c.blur) || 0)}px`);
        spEl.style.setProperty('--streaks', clamp01(c.streaks));
        spEl.style.setProperty('--grain', clamp01(c.grain));
        spHit.style.setProperty('--hit', rgb(c.hitColor, [150, 8, 12]));
        const add = clamp01(d.add);
        if (add > 0) {
            sp.peak = Math.min(1, levelAt(sp.peak, sp.last, c.fadeOut, now) + add);
            sp.last = now;
            // à-coup de chaque tir : les traînées « zooment » puis reviennent
            if (spStreaks.animate) spStreaks.animate([{ transform: 'scale(1.06) rotate(.8deg)' }, { transform: 'scale(1) rotate(0deg)' }], { duration: 280, easing: 'ease-out' });
        }
        if (d.hit) {
            sp.hitPeak = Math.min(1, levelAt(sp.hitPeak, sp.hitLast, c.hitFade, now) + 0.6);
            sp.hitLast = now;
        }
        spEl.style.display = 'block'; spHit.style.display = 'block';
        if (!sp.running) { sp.running = true; requestAnimationFrame(spFrame); }
    }

    // ---- Aide d'une autre ressource (exports showHint : CartoonFlashlight…) ----
    const hintEl = document.getElementById('hint');
    const esc = (t) => String(t == null ? '' : t).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
    function hint(d) {
        if (!d || !d.show) { hintEl.classList.remove('show'); return; }
        document.getElementById('hintTitle').textContent = d.title || '';
        document.getElementById('hintRows').innerHTML = (Array.isArray(d.lines) ? d.lines : []).map((l) => (Array.isArray(l)
            ? `<div class="hint-row"><kbd>${esc(l[0])}</kbd><span>${esc(l[1])}</span></div>`
            : `<div class="hint-sub">${esc(l)}</div>`)).join('');
        hintEl.classList.add('show');
    }

    window.addEventListener('message', ({ data }) => {
        if (data && data.action === 'firemode') fireMode(data.data || {});
        if (data && data.action === 'suppress') suppress(data.data || {});
        if (data && data.action === 'hint') hint(data.data || {});
    });
})();
