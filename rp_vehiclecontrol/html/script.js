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
    const buffers = {}; // [nom] = AudioBuffer décodé
    SOUND_FILES.forEach((name) => {
        const audio = new Audio(`sounds/${name}.ogg`);
        audio.preload = 'auto';
        cache[name] = audio;
    });

    let ctx = null;
    function audioContext() {
        try {
            ctx = ctx || new (window.AudioContext || window.webkitAudioContext)();
            if (ctx.state === 'suspended') ctx.resume().catch(() => {});
            return ctx;
        } catch (err) {
            return null;
        }
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
                .then((buffer) => { buffers[name] = buffer; })
                .catch(() => {}); // fichier absent / illisible : secours <audio>
        });
    })();

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
        const ac = audioContext();
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

    function play(name, volume, muffled, loop = false) {
        if (!(volume > 0)) return null;
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
    }

    function holdLoop(id, current) {
        if (current.holdTimer) return;
        current.voices.forEach((v) => setVoice(v, 0, current.muffled));
        current.holdTimer = setTimeout(() => { if (loops[id] === current) stopLoop(id); }, HOLD_MS);
    }

    function soundLoop({ id, names, interval, volume, loop: continuous, muffled }) {
        let current = loops[id];
        if (!(volume > 0) || !Array.isArray(names) || names.length === 0) {
            if (current && current.continuous && current.voices.length > 0) return holdLoop(id, current);
            return stopLoop(id);
        }
        // Autre fichier en boucle (ex. belt_chime -> fast_belt_chime) : l'ancien est coupé net ;
        // boucle gardée muette dont le lecteur s'est arrêté entre-temps : relancée du début
        if (current && continuous && (current.names[0] !== names[0] || current.voices.length === 0)) { stopLoop(id); current = null; }
        if (current) { // déjà en cours (ou gardé muet) : reprend, volume / étouffement mis à jour
            clearTimeout(current.holdTimer);
            current.holdTimer = null;
            current.volume = volume; current.muffled = !!muffled; current.names = names;
            current.voices.forEach((v) => setVoice(v, volume, muffled));
            return;
        }
        const entry = { names, volume, muffled: !!muffled, index: 0, voices: [], continuous: !!continuous };
        loops[id] = entry;
        if (continuous) {
            // Boucle sans limite tant qu'elle est demandée ; si le son s'arrête quand même (lecteur perdu),
            // il est relancé aussitôt : seul un volume 0 (ou un autre fichier) l'arrête
            const start = () => {
                if (loops[id] !== entry) return;
                const v = play(entry.names[0], entry.volume, entry.muffled, true);
                if (!v) return;
                entry.voices = [v];
                v.onEnded(() => {
                    if (loops[id] !== entry || v.stopped) return;
                    if (entry.holdTimer) { entry.voices = []; return; } // gardé muet : relancé s'il est redemandé
                    start();
                });
            };
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
