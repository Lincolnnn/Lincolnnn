// Vehicle Control : message "pousser le véhicule" (client/push.lua) et sons du véhicule (sounds/*.ogg)
(() => {
    const box = document.getElementById('push');
    const TEXTS = { prompt: 'Pousser le véhicule', pushing: 'Arrêter de pousser' };

    // ---- Sons : fichiers réels, remplaçables (mêmes noms) dans html/sounds/ ----
    const SOUND_FILES = ['belt_on', 'belt_off', 'belt_chime', 'indicators_sound'];
    const cache = {};
    SOUND_FILES.forEach((name) => {
        const audio = new Audio(`sounds/${name}.ogg`);
        audio.preload = 'auto';
        cache[name] = audio;
    });

    // Volume au-delà de 100 % (ex. clignotants +25 %) : amplifié par Web Audio
    let ctx = null;
    function setVolume(audio, volume) {
        volume = Math.max(volume, 0);
        if (volume <= 1 && !audio.gainNode) { audio.volume = volume; return; }
        try {
            if (!audio.gainNode) {
                ctx = ctx || new (window.AudioContext || window.webkitAudioContext)();
                audio.gainNode = ctx.createGain();
                ctx.createMediaElementSource(audio).connect(audio.gainNode).connect(ctx.destination);
            }
            if (ctx.state === 'suspended') ctx.resume().catch(() => {});
            audio.volume = 1;
            audio.gainNode.gain.value = Math.min(volume, 2);
        } catch (err) {
            audio.volume = Math.min(volume, 1);
        }
    }

    function play(name, volume, loop = false) {
        const base = cache[name];
        if (!base || !(volume > 0)) return null;
        const audio = base.cloneNode(); // plusieurs sons en même temps (ex. clignotant + carillon)
        audio.loop = loop;
        setVolume(audio, volume);
        audio.play().catch(() => {});
        return audio;
    }

    // Sons répétés (clignotant, alarme de ceinture) : un par identifiant, volume 0 = arrêt.
    // loop : un seul fichier joué en boucle sans interruption (son des clignotants)
    const loops = {};
    function soundLoop({ id, names, interval, volume, loop: continuous }) {
        const current = loops[id];
        if (!(volume > 0) || !Array.isArray(names) || names.length === 0) {
            if (current) {
                clearInterval(current.timer);
                if (current.audio) { current.audio.pause(); current.audio.currentTime = 0; }
                delete loops[id];
            }
            return;
        }
        if (current) { // déjà en cours : volume mis à jour
            current.volume = volume; current.names = names;
            if (current.audio) setVolume(current.audio, volume);
            return;
        }
        if (continuous) {
            loops[id] = { names, volume, audio: play(names[0], volume, true) };
            return;
        }
        const loop = { names, volume, index: 0 };
        const tick = () => {
            play(loop.names[loop.index % loop.names.length], loop.volume);
            loop.index += 1;
        };
        tick();
        loop.timer = setInterval(tick, Math.max(100, Number(interval) || 1000));
        loops[id] = loop;
    }

    window.addEventListener('message', (event) => {
        const msg = event.data || {};
        const data = msg.data || {};
        if (msg.action === 'sound') {
            play(data.name, data.volume);
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
