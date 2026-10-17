// RP RoleplayZone : menu des créations, message de zone, flèche de l'œil d'aigle, fouilles, sons (générés ici)
(() => {
    const $ = (id) => document.getElementById(id);
    const box = $('rz');
    const resource = typeof window.GetParentResourceName === 'function' ? window.GetParentResourceName() : 'rp_RoleplayZone';
    const KIND = { zone: 'Zone de recherche', perimeter: 'Périmètre à fouiller', object: 'Objet à fouiller' };
    const TEXT_LABEL = {
        zone: 'Message affiché aux policiers dans la zone',
        perimeter: 'Ce que le policier trouvera en fouillant',
        object: 'Ce que le policier trouvera en fouillant l\'objet',
    };
    const PLACEHOLDER = {
        zone: 'ex. Des traces de pneus partent vers la ruelle. Une odeur d\'essence flotte dans l\'air…',
        perimeter: 'ex. Sous les cartons : un sachet de poudre blanche et une douille de 9 mm.',
        object: 'ex. Dans la poubelle : un sweat noir taché de sang, roulé en boule.',
    };

    let state = {
        scenes: [], admin: false, durations: [30, 60, 120, 240, 0], duration: 120,
        zone: {}, perimeter: {}, titleLength: 40, textLength: 500, view: 'home', draft: null, editId: null,
    };
    let messageTimer = null;
    let tick = null;

    function post(name, data) {
        return fetch(`https://${resource}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        }).catch(() => {});
    }

    function esc(text) {
        return String(text == null ? '' : text).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    }

    const toArray = (v) => (Array.isArray(v) ? v : (v && typeof v === 'object' ? Object.values(v) : []));
    const durationLabel = (m) => (m === 0 ? 'Illimitée' : m >= 60 && m % 60 === 0 ? `${m / 60} h` : `${m} min`);
    const meters = (m) => (m >= 10 ? `${Math.round(m)} m` : `${String(Math.round(m * 100) / 100).replace('.', ',')} m`);

    function timeLeft(s) {
        if (s.permanent) return 'jusqu\'à suppression';
        const left = Math.max(0, Math.round((s.endsAt - Date.now()) / 1000));
        if (left >= 3600) return `${Math.floor(left / 3600)} h ${String(Math.floor((left % 3600) / 60)).padStart(2, '0')}`;
        if (left >= 60) return `${Math.ceil(left / 60)} min`;
        return `${left} s`;
    }

    // =====================================================================
    // MENU
    // =====================================================================
    function show(view) {
        state.view = view;
        $('rzHome').classList.toggle('hidden', view !== 'home');
        $('rzDescribe').classList.toggle('hidden', view !== 'describe');
    }

    function renderHome() {
        const Z = state.zone || {}; const P = state.perimeter || {};
        if (Z.MinRadius) $('rzZoneHint').textContent = `Grand cercle de ${meters(Z.MinRadius)} à ${meters(Z.MaxRadius)} : message affiché aux policiers qui y entrent`;
        if (P.MinRadius) $('rzPerimeterHint').textContent = `Petit lieu (sol, recoin…), de ${meters(P.MinRadius)} à ${meters(P.MaxRadius)} : ce que le policier y trouvera`;
        $('rzClearAll').classList.toggle('hidden', !state.admin);
        renderList();
    }

    function renderList() {
        const list = state.scenes;
        const mine = list.filter((s) => s.mine).length;
        $('rzCount').textContent = list.length ? `(${list.length})` : '';
        $('rzSub').textContent = `${mine} scène${mine > 1 ? 's' : ''} préparée${mine > 1 ? 's' : ''}${state.admin ? ' · administration' : ''}`;
        $('rzList').innerHTML = list.length ? list.map((s) => {
            const radius = s.kind === 'object' ? 'objet du décor' : `rayon ${meters(s.radius)}`;
            const searches = s.kind === 'zone' ? '' : ` · ${s.searches ? `fouillé ${s.searches} fois${s.lastBy ? ` (${esc(s.lastBy)})` : ''}` : 'pas encore fouillé'}`;
            return `
            <div class="rz-item ${esc(s.kind)}">
                <div class="rz-item-info">
                    <div class="rz-item-title"><span class="rz-badge">${KIND[s.kind] || ''}</span>${esc(s.title || s.label || `Scène n°${s.id}`)}</div>
                    <div class="rz-item-text">${esc(s.text)}</div>
                    <div class="rz-item-meta">${esc(s.label || '')} · ${radius} · <span data-left="${s.id}">${timeLeft(s)}</span>${searches}${s.mine ? '' : ` · <span class="rz-other">${esc(s.by || '?')}</span>`}</div>
                </div>
                <div class="rz-item-actions">
                    <button class="rz-btn rz-small" data-locate="${s.id}" title="Point GPS sur la scène">Repérer</button>
                    <button class="rz-btn rz-small" data-edit="${s.id}">Modifier</button>
                    <button class="rz-btn rz-small rz-danger" data-remove="${s.id}">Supprimer</button>
                </div>
            </div>`;
        }).join('') : '<div class="rz-empty">Aucune scène : choisissez un type ci-dessus pour commencer.</div>';
        $('rzClearMine').disabled = mine === 0;
        $('rzClearAll').disabled = list.length === 0;
    }

    function setScenes(list) {
        const now = Date.now();
        state.scenes = toArray(list).map((s) => ({ ...s, endsAt: now + (Number(s.remaining) || 0) * 1000 }));
        renderList();
    }

    function renderDurations() {
        $('rzDurations').innerHTML = state.durations.map((d) => `
            <button class="rz-chip${d === state.duration ? ' active' : ''}" data-duration="${d}">${durationLabel(d)}</button>`).join('');
    }

    function updateCounter() {
        const n = $('rzText').value.length;
        $('rzCounter').textContent = `${n} / ${state.textLength}`;
    }

    /** Étape 3 : décrire une sélection (draft) ou modifier une scène (scene) */
    function openDescribe(draft, scene) {
        const kind = scene ? scene.kind : draft.kind;
        state.draft = scene ? null : draft;
        state.editId = scene ? scene.id : null;
        const where = scene ? scene.label : draft.label;
        const radius = scene ? scene.radius : draft.radius;
        $('rzDescTitle').textContent = scene ? 'Modifier la scène' : 'Description';
        $('rzSummary').className = `rz-summary ${kind}`;
        $('rzSummary').innerHTML = `<div><b>${KIND[kind]}</b><small>${esc(where || 'Lieu inconnu')} · ${kind === 'object' ? 'objet du décor' : `rayon ${meters(Number(radius) || 0)}`}</small></div>`;
        $('rzTextLabel').textContent = TEXT_LABEL[kind];
        $('rzTitle').maxLength = state.titleLength;
        $('rzText').maxLength = state.textLength;
        $('rzText').placeholder = PLACEHOLDER[kind];
        $('rzTitle').value = scene ? (scene.title || '') : '';
        $('rzText').value = scene ? (scene.text || '') : '';
        if (scene) state.duration = scene.permanent ? 0 : (Number(scene.duration) || state.duration);
        $('rzReselect').classList.toggle('hidden', !!scene);
        $('rzSubmit').textContent = scene ? 'Enregistrer' : 'Créer';
        renderDurations();
        updateCounter();
        show('describe');
        setTimeout(() => $('rzText').focus(), 30);
    }

    function message(text, error) {
        const el = $('rzMessage');
        el.textContent = text || '';
        el.classList.toggle('error', !!error);
        clearTimeout(messageTimer);
        if (text) messageTimer = setTimeout(() => { el.textContent = ''; }, 4500);
    }

    function open(data) {
        state.durations = toArray(data.durations).map(Number);
        if (!state.durations.length) state.durations = [30, 60, 120, 240, 0];
        if (!state.opened) { state.duration = Number(data.defaultDuration) || 120; state.opened = true; }
        state.zone = data.zone || {}; state.perimeter = data.perimeter || {};
        state.titleLength = Number(data.titleLength) || 40; state.textLength = Number(data.textLength) || 500;
        state.admin = !!data.admin;
        setScenes(data.scenes);
        renderHome();
        message('');
        if (data.draft) openDescribe(data.draft); else show('home');
        box.classList.remove('hidden');
        clearInterval(tick);
        tick = setInterval(() => {
            state.scenes.forEach((s) => {
                const el = box.querySelector(`[data-left="${s.id}"]`);
                if (el) el.textContent = timeLeft(s);
            });
        }, 1000);
    }

    function close() {
        box.classList.add('hidden');
        clearInterval(tick);
    }

    function submit() {
        const title = $('rzTitle').value.trim();
        const text = $('rzText').value.trim();
        if (!text) { message('Écrivez une description.', true); $('rzText').focus(); return; }
        if (state.editId) post('update', { id: state.editId, title, text, duration: state.duration });
        else if (state.draft) post('create', { draft: state.draft, title, text, duration: state.duration });
    }

    box.addEventListener('click', (e) => {
        const kind = e.target.closest('[data-kind]');
        if (kind) {
            const k = kind.dataset.kind;
            const limits = k === 'zone' ? state.zone : state.perimeter;
            return post('pick', { kind: k, radius: limits && limits.DefaultRadius });
        }
        const d = e.target.closest('[data-duration]');
        if (d) { state.duration = Number(d.dataset.duration); return renderDurations(); }
        const rm = e.target.closest('[data-remove]');
        if (rm) return post('remove', { id: Number(rm.dataset.remove) });
        const loc = e.target.closest('[data-locate]');
        if (loc) return post('locate', { id: Number(loc.dataset.locate) });
        const ed = e.target.closest('[data-edit]');
        if (ed) {
            const scene = state.scenes.find((s) => s.id === Number(ed.dataset.edit));
            if (scene) openDescribe(null, scene);
            return null;
        }
        if (e.target.closest('#rzSubmit')) return submit();
        if (e.target.closest('#rzBack')) { show('home'); return null; }
        if (e.target.closest('#rzReselect') && state.draft) return post('pick', { kind: state.draft.kind, radius: state.draft.radius });
        if (e.target.closest('#rzClearMine')) return post('clear', { mine: true });
        if (e.target.closest('#rzClearAll')) return post('clear', { mine: false });
        if (e.target.closest('#rzClose')) return post('close');
        return null;
    });

    $('rzText').addEventListener('input', updateCounter);

    document.addEventListener('keydown', (e) => {
        if (box.classList.contains('hidden')) return;
        if (e.key === 'Escape') post('close');
        else if (e.key === 'Enter' && (e.ctrlKey || e.target.id === 'rzTitle') && state.view === 'describe') { e.preventDefault(); submit(); }
    });

    // =====================================================================
    // ZONE DE RECHERCHE (en haut au milieu)
    // =====================================================================
    const zone = $('zone');
    let zoneHideTimer = null;
    function setZone(data) {
        clearTimeout(zoneHideTimer);
        if (data.show) {
            $('zoneTitle').textContent = data.title || '';
            $('zoneText').textContent = data.text || '';
            $('zoneLabel').textContent = data.label || '';
            zone.classList.remove('out', 'hidden');
        } else if (!zone.classList.contains('hidden')) {
            zone.classList.add('out');
            zoneHideTimer = setTimeout(() => zone.classList.add('hidden'), 360);
        }
    }

    // =====================================================================
    // ŒIL D'AIGLE : flèche
    // =====================================================================
    function setArrow(data) {
        const el = $('arrow');
        if (!data.show) { el.classList.add('hidden'); return; }
        $('arrowRot').style.transform = `rotate(${Number(data.angle) || 0}deg)`;
        $('arrowLabel').textContent = data.label || '';
        $('arrowDist').textContent = data.distance != null ? `${data.distance} m` : '';
        el.classList.remove('hidden');
    }

    // =====================================================================
    // FOUILLE : barre de chargement, contenu trouvé
    // =====================================================================
    let progressFrame = null;
    function setProgress(data) {
        const el = $('progress');
        cancelAnimationFrame(progressFrame);
        if (!data.show) { el.classList.add('hidden'); return; }
        const duration = Number(data.duration) || 5000;
        const start = performance.now();
        $('progressLabel').textContent = data.label || '';
        el.classList.remove('hidden');
        const step = (now) => {
            const t = Math.min(1, (now - start) / duration);
            $('progressBar').style.width = `${t * 100}%`;
            $('progressTime').textContent = `${Math.max(0, (duration - (now - start)) / 1000).toFixed(1)} s`;
            if (t < 1) progressFrame = requestAnimationFrame(step);
        };
        progressFrame = requestAnimationFrame(step);
    }

    function addResult(data) {
        const list = $('results');
        const card = document.createElement('div');
        card.className = 'result';
        card.innerHTML = `
            <div class="result-head"><span>${data.kind === 'object' ? 'Fouille de l\'objet' : 'Fouille des lieux'}</span><span>${esc(data.label || '')}</span></div>
            <div class="result-title">${esc(data.title || '')}</div>
            <div class="result-text">${esc(data.text || '')}</div>`;
        list.prepend(card);
        while (list.children.length > 3) list.lastElementChild.remove();
        setTimeout(() => { card.classList.add('fade'); setTimeout(() => card.remove(), 450); }, Number(data.duration) || 25000);
    }

    // =====================================================================
    // SONS (Web Audio : aucun fichier)
    // =====================================================================
    let ctx = null;
    function audio() {
        if (!ctx) {
            const AC = window.AudioContext || window.webkitAudioContext;
            if (!AC) return null;
            ctx = new AC();
        }
        if (ctx.state === 'suspended') ctx.resume();
        return ctx;
    }

    /** Sortie commune : volume, filtre doux, écho (un peu d'espace, d'air de mystère) */
    function chain(ac, volume, echo) {
        const master = ac.createGain();
        master.gain.value = volume;
        const lp = ac.createBiquadFilter();
        lp.type = 'lowpass'; lp.frequency.value = 3800;
        master.connect(lp); lp.connect(ac.destination);
        if (echo) {
            const delay = ac.createDelay(1.0); delay.delayTime.value = echo.time;
            const fb = ac.createGain(); fb.gain.value = echo.feedback;
            const wet = ac.createGain(); wet.gain.value = echo.wet;
            master.connect(delay); delay.connect(fb); fb.connect(delay); delay.connect(wet); wet.connect(lp);
        }
        return master;
    }

    function note(ac, out, freq, at, length, peak, type, attack) {
        const o = ac.createOscillator(); const g = ac.createGain();
        o.type = type || 'triangle'; o.frequency.setValueAtTime(freq, at);
        g.gain.setValueAtTime(0.0001, at);
        g.gain.exponentialRampToValueAtTime(peak, at + (attack || 0.012));
        g.gain.exponentialRampToValueAtTime(0.0001, at + length);
        o.connect(g); g.connect(out);
        o.start(at); o.stop(at + length + 0.05);
    }

    /** Nappe grave qui gonfle puis s'éteint (tension) */
    function drone(ac, out, freq, at, length, peak) {
        [freq, freq * 1.006].forEach((f) => {
            const o = ac.createOscillator(); const g = ac.createGain(); const f1 = ac.createBiquadFilter();
            o.type = 'sawtooth'; o.frequency.value = f;
            f1.type = 'lowpass'; f1.frequency.setValueAtTime(180, at); f1.frequency.linearRampToValueAtTime(520, at + length * 0.5);
            g.gain.setValueAtTime(0.0001, at);
            g.gain.exponentialRampToValueAtTime(peak, at + length * 0.35);
            g.gain.exponentialRampToValueAtTime(0.0001, at + length);
            o.connect(f1); f1.connect(g); g.connect(out);
            o.start(at); o.stop(at + length + 0.05);
        });
    }

    const SOUNDS = {
        // Entrée dans une zone : court motif d'intrigue (accord diminué qui reste en suspens)
        enter(ac, v) {
            const out = chain(ac, v, { time: 0.24, feedback: 0.38, wet: 0.45 });
            const t = ac.currentTime + 0.02;
            drone(ac, out, 73.42, t, 1.9, 0.10);                 // ré grave
            note(ac, out, 293.66, t, 0.9, 0.22);                 // ré
            note(ac, out, 349.23, t + 0.17, 0.9, 0.2);           // fa
            note(ac, out, 415.30, t + 0.34, 1.2, 0.2);           // sol dièse : la tension reste
            note(ac, out, 830.61, t + 0.34, 1.0, 0.035, 'sine'); // reflet aigu
        },
        // Sortie : le même motif redescend et se résout sur un accord majeur (l'intrigue est levée)
        exit(ac, v) {
            const out = chain(ac, v, { time: 0.22, feedback: 0.3, wet: 0.4 });
            const t = ac.currentTime + 0.02;
            note(ac, out, 415.30, t, 0.45, 0.17);
            note(ac, out, 349.23, t + 0.14, 0.45, 0.17);
            note(ac, out, 293.66, t + 0.28, 1.2, 0.18);           // ré
            note(ac, out, 369.99, t + 0.42, 1.1, 0.13);           // fa dièse
            note(ac, out, 440.00, t + 0.42, 1.1, 0.12);           // la : ré majeur, apaisé
            note(ac, out, 146.83, t + 0.42, 1.2, 0.08, 'sine');
        },
        // Œil d'aigle : « ping » de sonar très court, avec un souffle qui monte
        eagle(ac, v) {
            const out = chain(ac, v, { time: 0.13, feedback: 0.32, wet: 0.5 });
            const t = ac.currentTime + 0.01;
            const o = ac.createOscillator(); const g = ac.createGain();
            o.type = 'sine';
            o.frequency.setValueAtTime(880, t); o.frequency.exponentialRampToValueAtTime(1980, t + 0.11);
            g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.32, t + 0.02);
            g.gain.exponentialRampToValueAtTime(0.0001, t + 0.16);
            o.connect(g); g.connect(out); o.start(t); o.stop(t + 0.2);
            note(ac, out, 1975.5, t + 0.1, 0.5, 0.2, 'sine', 0.004);
            const len = Math.floor(ac.sampleRate * 0.3);
            const buf = ac.createBuffer(1, len, ac.sampleRate);
            const ch = buf.getChannelData(0);
            for (let i = 0; i < len; i += 1) ch[i] = (Math.random() * 2 - 1) * (1 - i / len);
            const n = ac.createBufferSource(); const bp = ac.createBiquadFilter(); const ng = ac.createGain();
            n.buffer = buf; bp.type = 'bandpass'; bp.Q.value = 2.5;
            bp.frequency.setValueAtTime(600, t); bp.frequency.exponentialRampToValueAtTime(4200, t + 0.28);
            ng.gain.value = 0.12;
            n.connect(bp); bp.connect(ng); ng.connect(out); n.start(t);
        },
    };

    function play(data) {
        const fn = SOUNDS[data.name];
        const ac = fn && audio();
        if (!ac) return;
        try { fn(ac, Math.max(0, Math.min(1, Number(data.volume) || 0.45))); } catch (err) { /* son indisponible */ }
    }

    // =====================================================================
    // MESSAGES DU CLIENT
    // =====================================================================
    window.addEventListener('message', (event) => {
        const msg = event.data || {};
        const data = msg.data || {};
        switch (msg.action) {
        case 'open': open(data); break;
        case 'close': close(); break;
        case 'list': state.admin = !!data.admin; setScenes(data.scenes); break;
        case 'created': setScenes(data.scenes); state.draft = null; state.editId = null; show('home'); break;
        case 'message': message(data.text, data.error); break;
        case 'zone': setZone(data); break;
        case 'arrow': setArrow(data); break;
        case 'progress': setProgress(data); break;
        case 'result': addResult(data); break;
        case 'sound': play(data); break;
        default: break;
        }
    });
})();
