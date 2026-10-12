// Vehicle Control : message "pousser le véhicule" (client/push.lua) et sons du véhicule (sounds/*.ogg)
(() => {
    const box = document.getElementById('push');
    const TEXTS = { prompt: 'Pousser le véhicule', pushing: 'Arrêter de pousser' };

    // ---- Sons : fichiers réels, remplaçables (mêmes noms) dans html/sounds/ ----
    const SOUND_FILES = ['belt_on', 'belt_off', 'belt_chime', 'indicator_tick', 'indicator_tock'];
    const cache = {};
    SOUND_FILES.forEach((name) => {
        const audio = new Audio(`sounds/${name}.ogg`);
        audio.preload = 'auto';
        cache[name] = audio;
    });

    function play(name, volume) {
        const base = cache[name];
        if (!base || !(volume > 0)) return;
        const audio = base.cloneNode(); // plusieurs sons en même temps (ex. tic + carillon)
        audio.volume = Math.min(Math.max(volume, 0), 1);
        audio.play().catch(() => {});
    }

    // Sons répétés (clignotant, alarme de ceinture) : un par identifiant, volume 0 = arrêt
    const loops = {};
    function soundLoop({ id, names, interval, volume }) {
        const current = loops[id];
        if (!(volume > 0) || !Array.isArray(names) || names.length === 0) {
            if (current) { clearInterval(current.timer); delete loops[id]; }
            return;
        }
        if (current) { current.volume = volume; current.names = names; return; } // déjà en cours : volume mis à jour
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
