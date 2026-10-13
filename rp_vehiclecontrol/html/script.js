// Vehicle Control : message "pousser le véhicule" (client/push.lua) et sons du véhicule (sounds/*.ogg)
(() => {
    const box = document.getElementById('push');
    const TEXTS = { prompt: 'Pousser le véhicule', pushing: 'Arrêter de pousser' };

    // ---- Sons : fichiers réels, remplaçables (mêmes noms) dans html/sounds/ ----
    // Chaque son : fichier -> filtre passe-bas ("étouffé" : entendu de l'extérieur, portières fermées)
    // -> volume (au-delà de 100 % possible). Un son arrêté est coupé net.
    const SOUND_FILES = ['belt_on', 'belt_off', 'belt_chime', 'indicators_sound'];
    const MUFFLED_HZ = 650;
    const CLEAR_HZ = 20000;
    const cache = {};
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

    /** Lecteur d'un son : { audio, gain, filter } (sans Web Audio : volume de l'élément seulement) */
    function voice(name, loop) {
        const base = cache[name];
        if (!base) return null;
        const v = { audio: base.cloneNode() }; // plusieurs sons en même temps (ex. clignotant + carillon)
        v.audio.loop = loop;
        const ac = audioContext();
        if (ac) {
            try {
                v.filter = ac.createBiquadFilter();
                v.filter.type = 'lowpass';
                v.filter.Q.value = 0.8;
                v.gain = ac.createGain();
                ac.createMediaElementSource(v.audio).connect(v.filter).connect(v.gain).connect(ac.destination);
            } catch (err) {
                v.filter = null; v.gain = null;
            }
        }
        return v;
    }

    function setVoice(v, volume, muffled) {
        volume = Math.max(Number(volume) || 0, 0);
        if (v.gain) {
            v.audio.volume = 1;
            v.gain.gain.value = Math.min(volume, 6); // amplification jusqu'à x6 (clignotants renforcés)
            v.filter.frequency.value = muffled ? MUFFLED_HZ : CLEAR_HZ;
        } else {
            v.audio.volume = Math.min(volume, 1);
        }
    }

    function stopVoice(v) {
        if (!v) return;
        v.audio.pause();
        v.audio.currentTime = 0;
    }

    function play(name, volume, muffled, loop = false) {
        if (!(volume > 0)) return null;
        const v = voice(name, loop);
        if (!v) return null;
        setVoice(v, volume, muffled);
        v.audio.play().catch(() => {});
        return v;
    }

    // Sons répétés (clignotants, carillon de la ceinture) : un par identifiant, volume 0 = arrêt (coupé net).
    //   loop : un seul fichier joué en boucle sans interruption ; sinon, rejoué toutes les `interval` ms.
    const loops = {};
    function stopLoop(id) {
        const current = loops[id];
        if (!current) return;
        clearInterval(current.timer);
        current.voices.forEach(stopVoice);
        delete loops[id];
    }

    function soundLoop({ id, names, interval, volume, loop: continuous, muffled }) {
        if (!(volume > 0) || !Array.isArray(names) || names.length === 0) return stopLoop(id);
        const current = loops[id];
        if (current) { // déjà en cours : volume / étouffement mis à jour
            current.volume = volume; current.muffled = !!muffled; current.names = names;
            current.voices.forEach((v) => setVoice(v, volume, muffled));
            return;
        }
        const entry = { names, volume, muffled: !!muffled, index: 0, voices: [] };
        loops[id] = entry;
        if (continuous) {
            const v = play(names[0], volume, muffled, true);
            if (v) entry.voices.push(v);
            return;
        }
        const tick = () => {
            const v = play(entry.names[entry.index % entry.names.length], entry.volume, entry.muffled);
            entry.index += 1;
            if (!v) return;
            entry.voices.push(v);
            v.audio.addEventListener('ended', () => { entry.voices = entry.voices.filter((x) => x !== v); }, { once: true });
        };
        tick();
        entry.timer = setInterval(tick, Math.max(100, Number(interval) || 1000));
    }

    window.addEventListener('message', (event) => {
        const msg = event.data || {};
        const data = msg.data || {};
        if (msg.action === 'sound') {
            play(data.name, data.volume, data.muffled);
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
