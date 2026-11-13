// /blocs (admins) : éditeur des blocs du PLD (client/blockeditor.lua). Point (coordonnée + rayon) ou carré (centre,
// largeur, hauteur, rotation -> 4 coins) ; « Ajouter » : la ligne rejoint la liste à copier dans config/blocs.json.
(() => {
    'use strict';
    const $ = (id) => document.getElementById(id);
    const res = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'rp_mdc';
    const post = (name, body) => fetch(`https://${res}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body || {}) }).catch(() => {});
    const box = $('blockEditor');
    let st = null;

    function render(d) {
        st = d;
        box.classList.toggle('hidden', !d.open);
        if (!d.open) return;
        box.querySelectorAll('input[name="beType"]').forEach((r) => { r.checked = r.value === d.type; });
        box.querySelectorAll('.be-point').forEach((e) => { e.style.display = d.type === 'point' ? '' : 'none'; });
        box.querySelectorAll('.be-square').forEach((e) => { e.style.display = d.type === 'square' ? '' : 'none'; });
        if (document.activeElement !== $('beName')) $('beName').value = d.name || '';
        [['beRadius', 'radius', ' m'], ['beWidth', 'width', ' m'], ['beHeight', 'height', ' m'], ['beRotation', 'rotation', '°']].forEach(([id, k, u]) => {
            $(id).value = d[k]; $(`${id}V`).textContent = `${Math.round(d[k])}${u}`;
        });
        $('beFollow').checked = !!d.follow;
        $('bePos').textContent = `x ${d.x}  y ${d.y}`;
        $('bePreview').textContent = d.preview || '';
        $('beFocusHint').textContent = d.focus ? '' : 'souris rendue : /blocs pour la reprendre';
        const list = Array.isArray(d.list) ? d.list : Object.values(d.list || {});
        $('beCount').textContent = list.length;
        $('beList').replaceChildren(...list.map((b, i) => {
            const row = document.createElement('div');
            row.className = 'be-item';
            const code = document.createElement('code');
            code.textContent = b.line;
            const del = document.createElement('button');
            del.type = 'button'; del.textContent = '✕'; del.dataset.index = String(i + 1);
            row.append(code, del);
            return row;
        }));
        $('beAll').value = list.map((b) => b.line).join(',\n');
    }

    const send = (extra) => post('blockSet', {
        type: (box.querySelector('input[name="beType"]:checked') || {}).value, name: $('beName').value,
        radius: $('beRadius').value, width: $('beWidth').value, height: $('beHeight').value, rotation: $('beRotation').value,
        follow: $('beFollow').checked, ...extra,
    });
    box.addEventListener('input', (e) => {
        if (e.target.type === 'range') {
            const u = e.target.id === 'beRotation' ? '°' : ' m';
            $(`${e.target.id}V`).textContent = `${e.target.value}${u}`;
        }
        if (e.target.id !== 'beAll') send();
    });
    box.addEventListener('change', (e) => { if (e.target.name === 'beType' || e.target.id === 'beFollow') send(); });
    $('beHere').addEventListener('click', () => post('blockHere'));
    $('beMove').addEventListener('click', () => post('blockMove'));
    $('beAdd').addEventListener('click', () => post('blockAdd'));
    $('beClose').addEventListener('click', () => post('blockClose'));
    $('beList').addEventListener('click', (e) => {
        const b = e.target.closest('button[data-index]');
        if (b) post('blockRemove', { index: Number(b.dataset.index) });
    });
    $('beCopy').addEventListener('click', () => { $('beAll').select(); try { document.execCommand('copy'); } catch (err) { /* copie manuelle */ } });
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && st && st.open && st.focus) post('blockMove'); });
    window.addEventListener('message', ({ data }) => { if (data && data.action === 'blockEditor') render(data.data || {}); });
})();
