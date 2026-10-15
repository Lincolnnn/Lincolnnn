// Vehicle Control : message "pousser le véhicule" (client/push.lua) et sons du véhicule (sounds/*.ogg)
(() => {
    const box = document.getElementById('push');
    const TEXTS = { prompt: 'Pousser le véhicule', pushing: 'Arrêter de pousser' };

    // ---- Sons : fichiers réels, remplaçables (mêmes noms) dans html/sounds/ ----
    // Chaque son : fichier -> filtre passe-bas ("étouffé" : entendu de l'extérieur, portières fermées)
    // -> volume (au-delà de 100 % possible). Un son arrêté est coupé net.
    // Lecture : fichier décodé une fois en mémoire (Web Audio) ; une boucle tourne alors SANS LIMITE, sans
    // dépendre du serveur de fichiers du NUI. Secours (fichier pas encore décodé, Web Audio indisponible) :
    // élément <audio>, rejoué du début à chaque fin tant que la boucle est demandée (soundLoop).
    const SOUND_FILES = ['belt_on', 'belt_off', 'belt_chime', 'fast_belt_chime', 'door_chime', 'indicators_sound'];
    const MUFFLED_HZ = 650;
    const CLEAR_HZ = 20000;
    const cache = {};
    const buffers = {}; // [nom] = AudioBuffer joué (décodé, silence de début / fin éventuellement raccourci)
    const rawBuffers = {}; // [nom] = AudioBuffer décodé tel quel
    const fileInfo = {};   // [nom] = analyse du fichier (durée, silences) : affichée par le diagnostic
    const maxGap = {};     // [nom] = silence maximal (s) entre deux passages en boucle (réglé par le Lua)
    SOUND_FILES.forEach((name) => {
        const audio = new Audio(`sounds/${name}.ogg`);
        audio.preload = 'auto';
        cache[name] = audio;
    });

    // ---- Diagnostic (en jeu : setr vc_debug_sound 1, console F8) : envoyé au script Lua qui l'affiche ----
    function debug(text) {
        try {
            const resource = typeof window.GetParentResourceName === 'function' ? window.GetParentResourceName() : 'rp_vehiclecontrol';
            fetch(`https://${resource}/soundDebug`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify({ text }),
            }).catch(() => {});
        } catch (err) { /* hors du jeu */ }
    }

    // Lecteur Web Audio. S'il est suspendu par le navigateur du jeu, TOUS ses sons se taisent : il est relancé
    // aussitôt (et vérifié chaque seconde, voir watchdog) ; s'il reste suspendu, les sons passent par de simples
    // éléments <audio> (sans étouffement) pour ne jamais rester muets.
    let ctx = null;
    let webAudioOff = false; // lecteur Web Audio inutilisable : simples éléments <audio>
    function audioContext() {
        try {
            if (!ctx) {
                ctx = new (window.AudioContext || window.webkitAudioContext)();
                ctx.onstatechange = () => {
                    debug(`lecteur audio : ${ctx.state}`);
                    if (ctx.state === 'running') webAudioOff = false;
                    else if (ctx.state !== 'closed') ctx.resume().catch(() => {});
                };
            }
            if (ctx.state !== 'running' && ctx.state !== 'closed') ctx.resume().catch(() => {});
            return ctx;
        } catch (err) {
            return null;
        }
    }

    /** Lecteur Web Audio utilisable maintenant (en marche) ? */
    function liveContext() {
        const ac = audioContext();
        return ac && ac.state === 'running' && !webAudioOff ? ac : null;
    }

    // Décodage des fichiers au démarrage (une seule fois)
    (() => {
        const ac = audioContext();
        if (!ac || typeof fetch !== 'function') return;
        SOUND_FILES.forEach((name) => {
            fetch(`sounds/${name}.ogg`)
                .then((res) => (res.ok ? res.arrayBuffer() : Promise.reject(new Error('absent'))))
                .then((data) => new Promise((resolve, reject) => {
                    const p = ac.decodeAudioData(data, resolve, reject);
                    if (p && typeof p.then === 'function') p.then(resolve, reject);
                }))
                .then((buffer) => { rawBuffers[name] = buffer; prepare(name); })
                .catch(() => {}); // fichier absent / illisible : secours <audio>
        });
    })();

    // ---- Analyse d'un fichier : durée, silence au début, à la fin, plus long silence au milieu ----
    const SILENT = 0.008; // amplitude sous laquelle un échantillon est considéré silencieux (~ -42 dB)
    function analyse(buffer) {
        const len = buffer.length;
        const rate = buffer.sampleRate;
        const data = [];
        for (let c = 0; c < buffer.numberOfChannels; c += 1) data.push(buffer.getChannelData(c));
        const loud = (i) => data.some((d) => Math.abs(d[i]) > SILENT);
        let first = 0;
        while (first < len && !loud(first)) first += 1;
        if (first >= len) return { duration: len / rate, silent: true };
        let last = len - 1;
        while (last > first && !loud(last)) last -= 1;
        let gap = 0;
        let run = 0;
        for (let i = first; i <= last; i += 1) {
            if (loud(i)) { if (run > gap) gap = run; run = 0; } else run += 1;
        }
        return { duration: len / rate, lead: first / rate, trail: (len - 1 - last) / rate, gap: gap / rate, first, last };
    }

    /** Fichier joué : silence de début + fin ramené à maxGap secondes (d'abord la fin gardée, puis le début) */
    function prepare(name) {
        const raw = rawBuffers[name];
        if (!raw) return;
        const info = fileInfo[name] || (fileInfo[name] = analyse(raw));
        const limit = Number(maxGap[name]) || 0;
        info.trimmed = false;
        buffers[name] = raw;
        if (info.silent || !(limit > 0) || info.lead + info.trail <= limit || !ctx) return;
        const rate = raw.sampleRate;
        const keepTrail = Math.min(info.trail, limit);
        const keepLead = Math.min(info.lead, Math.max(limit - keepTrail, 0));
        const start = Math.max(info.first - Math.round(keepLead * rate), 0);
        const end = Math.min(info.last + 1 + Math.round(keepTrail * rate), raw.length);
        try {
            const out = ctx.createBuffer(raw.numberOfChannels, end - start, rate);
            for (let c = 0; c < raw.numberOfChannels; c += 1) out.copyToChannel(raw.getChannelData(c).subarray(start, end), c);
            buffers[name] = out;
            info.trimmed = true;
            info.played = out.length / rate;
        } catch (err) { /* fichier gardé tel quel */ }
    }

    function describe(name) {
        const i = fileInfo[name];
        if (!i) return buffers[name] ? '' : ', fichier pas encore chargé : lecteur <audio>';
        if (i.silent) return `, fichier ${i.duration.toFixed(1)} s entièrement silencieux !`;
        const f = (x) => x.toFixed(1);
        return `, fichier ${f(i.duration)} s (silence : début ${f(i.lead)} s, fin ${f(i.trail)} s, plus long au milieu ${f(i.gap)} s)`
            + (i.trimmed ? `, joué en ${f(i.played)} s (silence de début / fin raccourci)` : '');
    }

    function chain(ac, input) {
        const filter = ac.createBiquadFilter();
        filter.type = 'lowpass';
        filter.Q.value = 0.8;
        const gain = ac.createGain();
        input.connect(filter).connect(gain).connect(ac.destination);
        return { filter, gain };
    }

    /** Lecteur d'un son : { start, stop, onEnded, gain, filter } ; loop : rejoué sans fin jusqu'à l'arrêt */
    function voice(name, loop) {
        const ac = liveContext(); // lecteur suspendu : élément <audio> simple (un son relié à lui serait muet)
        if (ac && buffers[name]) {
            try {
                const source = ac.createBufferSource();
                source.buffer = buffers[name];
                source.loop = loop; // boucle sans coupure ni limite
                const v = chain(ac, source);
                v.start = () => source.start();
                v.stop = () => {
                    v.stopped = true;
                    try { source.stop(); } catch (err) { /* déjà arrêté */ }
                    source.disconnect();
                };
                v.onEnded = (fn) => source.addEventListener('ended', fn, { once: true });
                return v;
            } catch (err) { /* secours ci-dessous */ }
        }
        const base = cache[name];
        if (!base) return null;
        const audio = base.cloneNode(); // plusieurs sons en même temps (ex. clignotant + carillon)
        const v = { audio, filter: null, gain: null, stopped: false };
        if (ac) {
            try { Object.assign(v, chain(ac, ac.createMediaElementSource(audio))); } catch (err) { v.filter = null; v.gain = null; }
        }
        // Pas de audio.loop : le serveur du NUI ne permet pas toujours de revenir au début du fichier (la boucle
        // s'arrêtait à la fin du premier passage) ; une boucle est relancée à chaque fin par soundLoop()
        v.start = () => audio.play().catch(() => {});
        v.stop = () => {
            v.stopped = true;
            audio.pause();
            try { audio.currentTime = 0; } catch (err) { /* pas de retour au début possible */ }
        };
        v.onEnded = (fn) => audio.addEventListener('ended', fn, { once: true });
        return v;
    }

    function setVoice(v, volume, muffled) {
        volume = Math.max(Number(volume) || 0, 0);
        if (v.gain) {
            if (v.audio) v.audio.volume = 1;
            v.gain.gain.value = Math.min(volume, 6); // amplification jusqu'à x6 (clignotants renforcés)
            v.filter.frequency.value = muffled ? MUFFLED_HZ : CLEAR_HZ;
        } else if (v.audio) {
            v.audio.volume = Math.min(volume, 1);
        }
    }

    function stopVoice(v) {
        if (v) v.stop();
    }

    function play(name, volume, muffled, loop = false, silent = false) {
        if (!(volume > 0) && !silent) return null; // silent : boucle démarrée muette (hors de portée)
        const v = voice(name, loop);
        if (!v) return null;
        setVoice(v, volume, muffled);
        v.start();
        return v;
    }

    // Sons répétés (clignotants, carillons de ceinture et de portière) : un par identifiant, volume 0 = arrêt (coupé net).
    //   loop : un seul fichier joué en boucle sans interruption ; sinon, rejoué toutes les `interval` ms.
    //   Boucle continue coupée (volume 0) : muette TOUT DE SUITE, mais gardée HOLD_MS ; redemandée entre-temps
    //   (portière qui bouge, pas hors de portée, lecture isolée), elle reprend là où elle en était, sans
    //   repartir du début. Au-delà : arrêtée, et relancée du début la fois suivante.
    const HOLD_MS = 1500;
    const loops = {};
    const oneShots = {}; // [nom] = dernier son ponctuel joué
    function stopLoop(id) {
        const current = loops[id];
        if (!current) return;
        clearInterval(current.timer);
        clearTimeout(current.holdTimer);
        current.voices.forEach(stopVoice);
        delete loops[id];
        debug(`${id} : arrêté`);
    }

    function holdLoop(id, current) {
        if (current.holdTimer) return;
        current.voices.forEach((v) => setVoice(v, 0, current.muffled));
        current.holdTimer = setTimeout(() => { if (loops[id] === current) stopLoop(id); }, HOLD_MS);
    }

    // Surveillance (chaque seconde, seulement pendant un son en boucle) : lecteur audio suspendu -> relancé, puis
    // remplacé par des éléments <audio> s'il le reste ; boucle demandée sans lecteur -> relancée.
    let suspendedSince = 0;
    function watchdog() {
        const ids = Object.keys(loops).filter((id) => loops[id].continuous);
        if (ids.length === 0) return;
        if (ctx && ctx.state !== 'running' && ctx.state !== 'closed') {
            ctx.resume().catch(() => {});
            if (!suspendedSince) {
                suspendedSince = Date.now();
                debug(`lecteur audio ${ctx.state} : relance`);
            } else if (!webAudioOff && Date.now() - suspendedSince > 2000) {
                webAudioOff = true;
                debug('lecteur audio toujours suspendu : sons rejoués par des éléments <audio>');
                ids.forEach((id) => {
                    const e = loops[id];
                    e.voices.forEach(stopVoice);
                    e.voices = [];
                    if (!e.holdTimer && e.start) e.start();
                });
            }
        } else if (suspendedSince) {
            suspendedSince = 0;
            debug('lecteur audio de nouveau en marche');
        }
        ids.forEach((id) => {
            const e = loops[id];
            if (!e.holdTimer && e.voices.length === 0 && e.start) {
                debug(`${id} : lecteur perdu, relancé`);
                e.start();
            }
        });
    }
    setInterval(watchdog, 1000);

    //   keep : boucle continue toujours en cours même à volume 0 (hors de portée) : muette, SANS limite de temps,
    //   réentendue là où elle en est ; seul un message sans keep (volume 0) l'arrête.
    function soundLoop({ id, names, interval, volume, loop: continuous, muffled, keep }) {
        let current = loops[id];
        if (!Array.isArray(names) || names.length === 0) return stopLoop(id);
        const kept = continuous && keep === true;
        if (!(volume > 0) && !kept) {
            if (current && current.continuous && current.voices.length > 0) return holdLoop(id, current);
            return stopLoop(id);
        }
        volume = volume > 0 ? volume : 0;
        // Autre fichier en boucle (ex. belt_chime -> fast_belt_chime) : l'ancien est coupé net ;
        // boucle gardée muette dont le lecteur s'est arrêté entre-temps : relancée du début
        if (current && continuous && (current.names[0] !== names[0] || current.voices.length === 0)) { stopLoop(id); current = null; }
        if (current) { // déjà en cours (ou gardé muet) : reprend, volume / étouffement mis à jour
            clearTimeout(current.holdTimer);
            current.holdTimer = null;
            current.keep = kept;
            current.volume = volume; current.muffled = !!muffled; current.names = names;
            current.voices.forEach((v) => setVoice(v, volume, muffled));
            return;
        }
        const entry = { names, volume, muffled: !!muffled, index: 0, voices: [], continuous: !!continuous, keep: kept };
        loops[id] = entry;
        if (continuous) {
            // Boucle sans limite tant qu'elle est demandée ; si le son s'arrête quand même (lecteur perdu),
            // il est relancé aussitôt : seul un volume 0 (ou un autre fichier) l'arrête
            const start = () => {
                if (loops[id] !== entry) return;
                const v = play(entry.names[0], entry.volume, entry.muffled, true, entry.keep);
                if (!v) return;
                entry.voices = [v];
                v.onEnded(() => {
                    if (loops[id] !== entry || v.stopped) return;
                    entry.voices = [];
                    if (entry.holdTimer) return; // gardé muet : relancé s'il est redemandé
                    start();
                });
            };
            entry.start = start;
            debug(`${id} : démarré (${names[0]}, volume ${Number(volume).toFixed(2)}${kept ? ', gardé' : ''}${describe(names[0])})`);
            start();
            return;
        }
        const tick = () => {
            // Jamais deux fois en même temps : le précédent est coupé avant de rejouer
            entry.voices.forEach(stopVoice);
            entry.voices = [];
            const v = play(entry.names[entry.index % entry.names.length], entry.volume, entry.muffled);
            entry.index += 1;
            if (!v) return;
            entry.voices.push(v);
            v.onEnded(() => { entry.voices = entry.voices.filter((x) => x !== v); });
        };
        tick();
        entry.timer = setInterval(tick, Math.max(100, Number(interval) || 1000));
    }

    window.addEventListener('message', (event) => {
        const msg = event.data || {};
        const data = msg.data || {};
        if (msg.action === 'sound') {
            // Son ponctuel (attache / retrait de la ceinture) : un seul à la fois, le précédent est coupé
            stopVoice(oneShots[data.name]);
            oneShots[data.name] = play(data.name, data.volume, data.muffled);
        } else if (msg.action === 'soundConfig') {
            // Silence maximal entre deux passages des carillons en boucle (config.lua : Seatbelt.ChimeMaxGap)
            Object.entries((data && data.maxGap) || {}).forEach(([name, gap]) => {
                maxGap[name] = Number(gap) || 0;
                prepare(name);
            });
        } else if (msg.action === 'soundLoop') {
            soundLoop(data);
        } else if (msg.action === 'push') {
            if (TEXTS[data.mode]) {
                document.getElementById('pushKey').textContent = data.key || 'K';
                document.getElementById('pushText').textContent = TEXTS[data.mode];
                box.dataset.mode = data.mode;
                box.classList.add('show');
            } else {
                box.classList.remove('show');
            }
        }
    });
})();
