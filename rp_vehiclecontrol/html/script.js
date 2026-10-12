// Vehicle Control : message "pousser le véhicule" (client/push.lua)
(() => {
    const box = document.getElementById('push');
    const TEXTS = { prompt: 'Pousser le véhicule', pushing: 'Arrêter de pousser' };

    window.addEventListener('message', (event) => {
        const msg = event.data || {};
        if (msg.action !== 'push') return;
        const data = msg.data || {};
        if (TEXTS[data.mode]) {
            document.getElementById('pushKey').textContent = data.key || 'K';
            document.getElementById('pushText').textContent = TEXTS[data.mode];
            box.dataset.mode = data.mode;
            box.classList.add('show');
        } else {
            box.classList.remove('show');
        }
    });
})();
