// RP Notepad - interface : pages (texte manuscrit + dessin), le texte qui dépasse passe à la page suivante,
// enregistrement pendant la frappe (client.lua : KVP du joueur), déplacement / taille gardés dans le navigateur.
(() => {
    const RESOURCE = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'rp_notepad';
    const post = (name, data = {}) => fetch(`https://${RESOURCE}/${name}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data),
    }).then((r) => r.json()).catch(() => null);
    const $ = (s) => document.querySelector(s);

    const pad = $('#pad');
    const text = $('#text');
    const canvas = $('#draw');
    const ctx = canvas.getContext('2d');

    const st = { pages: [{ text: '', drawing: '' }], page: 0, max: 30, lines: 13, mode: 'text', ink: '#1d3a8a', dirty: new Set(), timer: null };
    const toArray = (v) => (Array.isArray(v) ? v : Object.values(v || {}));

    // ---- Enregistrement (regroupé : 400 ms après la dernière frappe / le dernier trait) ----
    function saveSoon() {
        clearTimeout(st.timer);
        st.timer = setTimeout(saveNow, 400);
    }
    function saveNow() {
        clearTimeout(st.timer);
        const drawings = {};
        st.dirty.forEach((i) => { drawings[i + 1] = st.pages[i] ? st.pages[i].drawing || false : false; });
        st.dirty.clear();
        post('save', { page: st.page + 1, texts: st.pages.map((p) => p.text || ''), drawings });
    }

    // ---- Pages ----
    function ensurePage(i) { while (st.pages.length <= i) st.pages.push({ text: '', drawing: '' }); }
    function renderPage(caretEnd) {
        const p = st.pages[st.page];
        text.value = p.text || '';
        $('#pageNo').textContent = `${st.page + 1} / ${st.pages.length}`;
        $('#pageTag').textContent = `Page ${st.page + 1}`;
        $('#prev').disabled = st.page === 0;
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        if (p.drawing) {
            const img = new Image();
            img.onload = () => ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
            img.src = p.drawing;
        }
        if (st.mode === 'text') {
            text.focus();
            if (caretEnd) text.selectionStart = text.selectionEnd = text.value.length;
        }
    }
    function goTo(i, caretEnd = true) {
        if (i < 0 || i >= st.max) return;
        ensurePage(i);
        st.page = i;
        renderPage(caretEnd);
        saveSoon();
    }
    $('#prev').addEventListener('click', () => goTo(st.page - 1));
    $('#next').addEventListener('click', () => goTo(st.page + 1));

    // ---- Texte : limité aux lignes de la page ; ce qui dépasse passe au début de la page suivante ----
    const limit = () => parseFloat(getComputedStyle(text).height);
    function fits(value) {
        const keep = text.value;
        text.value = value;
        const ok = text.scrollHeight <= limit() + 1;
        text.value = keep;
        return ok;
    }
    text.addEventListener('input', () => {
        const value = text.value;
        if (!fits(value) && st.page + 1 < st.max) {
            let lo = 0; let hi = value.length; let cut = 0;
            while (lo <= hi) { // plus long début qui tient sur la page
                const mid = (lo + hi) >> 1;
                if (fits(value.slice(0, mid))) { cut = mid; lo = mid + 1; } else hi = mid - 1;
            }
            // coupe au dernier espace / retour à la ligne (pas au milieu d'un mot)
            const space = Math.max(value.lastIndexOf(' ', cut), value.lastIndexOf('\n', cut));
            if (space > cut - 25 && space > 0) cut = space + 1;
            const rest = value.slice(cut);
            st.pages[st.page].text = value.slice(0, cut);
            ensurePage(st.page + 1);
            st.pages[st.page + 1].text = rest + (st.pages[st.page + 1].text || '');
            st.page += 1;
            renderPage(false);
            text.selectionStart = text.selectionEnd = rest.length;
        } else if (!fits(value)) {
            text.value = st.pages[st.page].text || ''; // dernière page pleine
        } else {
            st.pages[st.page].text = value;
        }
        saveSoon();
    });
    // Retour arrière au tout début d'une page : on revient à la fin de la page précédente
    text.addEventListener('keydown', (e) => {
        if (e.key === 'Backspace' && st.page > 0 && text.selectionStart === 0 && text.selectionEnd === 0) {
            e.preventDefault();
            goTo(st.page - 1, true);
        }
    });

    // ---- Dessin ----
    function sizeCanvas() {
        const r = canvas.getBoundingClientRect();
        const scale = currentScale();
        canvas.width = Math.round(r.width / scale);
        canvas.height = Math.round(r.height / scale);
    }
    let stroke = null;
    const pointAt = (e) => {
        const r = canvas.getBoundingClientRect();
        return { x: (e.clientX - r.left) * (canvas.width / r.width), y: (e.clientY - r.top) * (canvas.height / r.height) };
    };
    canvas.addEventListener('mousedown', (e) => {
        if (st.mode !== 'draw' || e.button !== 0) return;
        stroke = pointAt(e);
        ctx.globalCompositeOperation = st.ink === 'eraser' ? 'destination-out' : 'source-over';
        ctx.strokeStyle = st.ink === 'eraser' ? '#000' : st.ink;
        ctx.lineWidth = st.ink === 'eraser' ? 14 : 2.2;
        ctx.lineCap = 'round'; ctx.lineJoin = 'round';
        ctx.beginPath(); ctx.moveTo(stroke.x, stroke.y); ctx.lineTo(stroke.x + 0.01, stroke.y); ctx.stroke();
    });
    window.addEventListener('mousemove', (e) => {
        if (!stroke) return;
        const p = pointAt(e);
        ctx.lineTo(p.x, p.y); ctx.stroke();
        stroke = p;
    });
    window.addEventListener('mouseup', () => {
        if (!stroke) return;
        stroke = null;
        ctx.globalCompositeOperation = 'source-over';
        const blank = !ctx.getImageData(0, 0, canvas.width, canvas.height).data.some((v, i) => i % 4 === 3 && v > 0);
        st.pages[st.page].drawing = blank ? '' : canvas.toDataURL('image/png');
        st.dirty.add(st.page);
        saveSoon();
    });

    function setMode(mode) {
        st.mode = mode;
        $('#modeText').classList.toggle('on', mode === 'text');
        $('#modeDraw').classList.toggle('on', mode === 'draw');
        $('#inks').classList.toggle('hidden', mode !== 'draw');
        document.body.classList.toggle('drawing', mode === 'draw');
        $('#hint').textContent = mode === 'draw' ? 'Dessinez à la souris ; la gomme efface les traits.'
            : 'Le texte passe à la page suivante quand la page est pleine.';
        if (mode === 'text') text.focus();
    }
    $('#modeText').addEventListener('click', () => setMode('text'));
    $('#modeDraw').addEventListener('click', () => setMode('draw'));
    document.querySelectorAll('.ink').forEach((b) => b.addEventListener('click', () => {
        document.querySelectorAll('.ink').forEach((x) => x.classList.toggle('on', x === b));
        st.ink = b.dataset.ink;
    }));

    // Effacer la page : deux clics (le second confirme)
    let clearArmed = null;
    $('#btnClear').addEventListener('click', () => {
        const b = $('#btnClear');
        if (!clearArmed) {
            b.classList.add('confirm'); b.title = 'Cliquer à nouveau pour effacer la page';
            clearArmed = setTimeout(() => { b.classList.remove('confirm'); b.title = 'Effacer la page'; clearArmed = null; }, 2500);
            return;
        }
        clearTimeout(clearArmed); clearArmed = null; b.classList.remove('confirm'); b.title = 'Effacer la page';
        st.pages[st.page] = { text: '', drawing: '' };
        st.dirty.add(st.page);
        renderPage(true);
        saveSoon();
    });

    // ---- Fenêtre : déplacer (barre), taille (coin), gardées pour la prochaine ouverture ----
    const PREF = 'rp_notepad_layout';
    const prefs = (() => { try { return JSON.parse(localStorage.getItem(PREF)) || {}; } catch (e) { return {}; } })();
    const savePrefs = () => { try { localStorage.setItem(PREF, JSON.stringify(prefs)); } catch (e) { /* stockage indisponible */ } };
    const currentScale = () => Number(prefs.scale) || 1;
    function applyLayout() {
        pad.style.transform = `scale(${currentScale()})`;
        if (prefs.left != null) { pad.style.left = `${prefs.left}px`; pad.style.top = `${prefs.top}px`; }
    }
    let drag = null; let resize = null;
    $('#padHead').addEventListener('mousedown', (e) => {
        if (e.target.closest('button, select')) return;
        const r = pad.getBoundingClientRect();
        drag = { dx: e.clientX - r.left, dy: e.clientY - r.top };
    });
    $('#grip').addEventListener('mousedown', (e) => {
        e.preventDefault();
        const r = pad.getBoundingClientRect();
        resize = { left: r.left, width: r.width / currentScale() };
    });
    window.addEventListener('mousemove', (e) => {
        if (drag) {
            prefs.left = Math.max(-200, Math.min(window.innerWidth - 80, e.clientX - drag.dx));
            prefs.top = Math.max(0, Math.min(window.innerHeight - 60, e.clientY - drag.dy));
            applyLayout();
        } else if (resize) {
            prefs.scale = Math.max(0.65, Math.min(1.8, (e.clientX - resize.left) / resize.width));
            applyLayout();
        }
    });
    window.addEventListener('mouseup', () => { if (drag || resize) { drag = resize = null; savePrefs(); } });

    // ---- Barre ----
    $('#btnClose').addEventListener('click', () => { saveNow(); post('close'); });
    $('#btnVisual').addEventListener('click', () => { saveNow(); post('visual'); });
    $('#animSelect').addEventListener('change', (e) => post('anim', { id: e.target.value }));
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && !pad.classList.contains('hidden') && !document.body.classList.contains('visual')) {
            saveNow(); post('close');
        }
    });

    // ---- Messages du jeu ----
    let tipTimer = null;
    window.addEventListener('message', ({ data }) => {
        if (!data || !data.action) return;
        const d = data.data || {};
        if (data.action === 'uiTheme') {
            document.documentElement.dataset.theme = d.theme === 'night' ? 'night' : 'day';
            document.documentElement.dataset.nightColor = ['green', 'yellow', 'red', 'blue'].includes(d.color) ? d.color : 'green';
        } else if (data.action === 'open') {
            st.max = Number(d.maxPages) || 30;
            st.lines = Number(d.lines) || 13;
            document.documentElement.style.setProperty('--lines', st.lines);
            st.pages = toArray(d.pages).map((p) => ({ text: (p && p.text) || '', drawing: (p && p.drawing) || '' }));
            st.page = Math.max(0, Math.min(st.max - 1, (Number(d.page) || 1) - 1));
            ensurePage(st.page);
            $('#animSelect').innerHTML = toArray(d.anims).map((a) => `<option value="${String(a.id).replace(/"/g, '')}">${String(a.label).replace(/[<>&]/g, '')}</option>`).join('');
            $('#animSelect').value = d.anim || '';
            pad.classList.remove('hidden');
            applyLayout();
            document.body.classList.remove('visual');
            requestAnimationFrame(() => { sizeCanvas(); setMode('text'); renderPage(true); }); // dernière page utilisée, curseur à la fin
        } else if (data.action === 'mode') {
            document.body.classList.toggle('visual', d.visual === true);
            clearTimeout(tipTimer);
            $('#visualTip').classList.toggle('show', d.visual === true);
            if (d.visual) tipTimer = setTimeout(() => $('#visualTip').classList.remove('show'), 3500);
            else if (st.mode === 'text') text.focus();
        } else if (data.action === 'close') {
            saveNow();
            pad.classList.add('hidden');
            document.body.classList.remove('visual');
        }
    });
})();
