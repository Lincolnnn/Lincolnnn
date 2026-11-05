// RP Ganghunt : lecteur de musique de la traque (fichiers de html/music/)
// Fondu d'entrée au lancement, morceaux à la suite et en boucle (fondu enchaîné), fondu de sortie à la fin de la
// traque, volume réglé par le joueur (appliqué tout de suite, même pendant la lecture). Un fichier absent ou
// illisible est sauté ; si aucun ne l'est, onError est appelé. Boucle de 50 ms seulement pendant la lecture.
window.GHMusic = (() => {
    const TICK = 50;
    let volume = 0.5;       // réglage du joueur (0..1)
    let master = 0;         // fondu d'entrée / de sortie (0..1)
    let masterRamp = null;  // { from, to, start, dur, done }
    let decks = [];         // morceaux en cours : { audio, gain, ramp, leaving } (2 pendant un fondu enchaîné)
    let list = [];
    let pos = 0;
    let crossfade = 3000;
    let playing = false;
    let failures = 0;
    let session = 0;
    let timer = null;
    let mode = null;        // 'hunt' (traque) | 'preview' (bouton Écouter du menu)
    const api = { onError: null };

    const now = () => performance.now();
    const ramp = (from, to, dur, done) => ({ from, to, start: now(), dur: Math.max(1, dur), done });
    const rampValue = (r) => r.from + (r.to - r.from) * Math.min(1, (now() - r.start) / r.dur);
    const rampDone = (r) => now() - r.start >= r.dur;
    const src = (i) => `music/${encodeURIComponent(list[i])}`;

    function apply() {
        decks.forEach((d) => { d.audio.volume = Math.max(0, Math.min(1, volume * master * d.gain)); });
    }

    function drop(d) {
        d.audio.pause();
        d.audio.removeAttribute('src');
        try { d.audio.load(); } catch (e) { /* déjà libéré */ }
        decks = decks.filter((x) => x !== d);
    }

    function deck(index, fadeMs) {
        const id = session;
        const audio = new Audio(src(index));
        const d = { audio, gain: fadeMs > 0 ? 0 : 1, ramp: fadeMs > 0 ? ramp(0, 1, fadeMs) : null, leaving: false };
        audio.preload = 'auto';
        audio.volume = 0;
        audio.addEventListener('playing', () => { if (id === session) failures = 0; });
        audio.addEventListener('error', () => {
            if (id !== session) return;
            drop(d);
            failures += 1;
            if (failures >= list.length) {
                playing = false;
                if (api.onError) api.onError();
            } else if (playing) {
                pos = (pos + 1) % list.length;
                deck(pos, 0);
            }
        });
        audio.addEventListener('ended', () => {
            if (id !== session) return;
            if (!d.leaving && playing) next();
            drop(d);
        });
        decks.push(d);
        apply();
        const p = audio.play();
        if (p && p.catch) p.catch(() => { /* fichier illisible : événement 'error' */ });
        return d;
    }

    // Morceau suivant (en boucle sur la liste) en fondu enchaîné
    function next() {
        const cur = decks[decks.length - 1];
        if (cur && !cur.leaving) {
            cur.leaving = true;
            cur.ramp = ramp(cur.gain, 0, crossfade, () => drop(cur));
        }
        pos = (pos + 1) % list.length;
        deck(pos, crossfade);
    }

    function loop() {
        if (masterRamp) {
            master = rampValue(masterRamp);
            if (rampDone(masterRamp)) {
                const r = masterRamp;
                master = r.to;
                masterRamp = null;
                if (r.done) r.done();
            }
        }
        decks.slice().forEach((d) => {
            if (!d.ramp) return;
            d.gain = rampValue(d.ramp);
            if (rampDone(d.ramp)) {
                const r = d.ramp;
                d.gain = r.to;
                d.ramp = null;
                if (r.done) r.done();
            }
        });
        // fin du morceau en cours qui approche : fondu enchaîné vers le suivant
        const cur = decks[decks.length - 1];
        const a = cur && cur.audio;
        if (playing && cur && !cur.leaving && a.duration && isFinite(a.duration) && a.duration - a.currentTime <= crossfade / 1000) next();
        apply();
        if (!playing && !masterRamp && decks.length === 0) {
            clearInterval(timer);
            timer = null;
        }
    }

    function ensureLoop() { if (!timer) timer = setInterval(loop, TICK); }

    function shuffled(arr) {
        const out = arr.slice();
        for (let i = out.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [out[i], out[j]] = [out[j], out[i]];
        }
        return out;
    }

    /** Lecture depuis le début : { tracks, shuffle, fadeIn, crossfade }, mode 'hunt' ou 'preview' */
    api.play = (opts, playMode) => {
        session += 1;
        decks.slice().forEach(drop);
        list = (opts.shuffle ? shuffled : (x) => x.slice())((opts.tracks || []).filter(Boolean));
        if (list.length === 0) return false;
        pos = 0;
        crossfade = Math.max(0, Number(opts.crossfade) || 0);
        playing = true;
        failures = 0;
        mode = playMode || 'hunt';
        master = 0;
        masterRamp = ramp(0, 1, Number(opts.fadeIn) || 0);
        deck(0, 0);
        ensureLoop();
        return true;
    };

    /** Fondu de sortie puis arrêt */
    api.stop = (fadeOut) => {
        if (!playing && decks.length === 0) return;
        playing = false;
        const id = session;
        masterRamp = ramp(master, 0, Number(fadeOut) || 0, () => {
            if (id === session) decks.slice().forEach(drop);
        });
        ensureLoop();
    };

    api.setVolume = (v) => {
        volume = Math.max(0, Math.min(1, Number(v) || 0));
        apply();
    };

    api.playing = () => playing;
    api.mode = () => (playing ? mode : null);
    return api;
})();
