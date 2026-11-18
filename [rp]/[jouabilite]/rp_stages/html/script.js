// RP Stages - indicateur à l'écran (client/client.lua envoie l'état seulement quand il change)
(() => {
    'use strict';
    const root = document.getElementById('stages');
    const main = document.getElementById('stMain');
    const sec = document.getElementById('stSec');
    const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
    const SHORT = { taLeft: '◀ TA', taRight: 'TA ▶', steadyBurn: 'SB' };
    const CLS = { taLeft: 'ta', taRight: 'ta', steadyBurn: 'sb' };
    const SIREN = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 10v4h4l5 4V6L7 10H3zm13.5 2A4.5 4.5 0 0 0 14 8v8a4.5 4.5 0 0 0 2.5-4zM14 3.2v2.1a7 7 0 0 1 0 13.4v2.1a9 9 0 0 0 0-17.6z"/></svg>';
    let hiddenByFreecam = false;
    let visible = false;

    function render(d) {
        main.innerHTML = d.stages.map((n) => `<span class="st-chip ${d.stage === n ? 'on' : ''} ${n === 3 ? 'response' : ''}" title="Stage ${n}">${n}${n === 3 && d.stage === 3 && d.auto ? ' <small>AUTO</small>' : ''}</span>`).join('')
            + `<span class="st-chip siren ${d.siren ? 'on' : ''}" title="${d.sirenNeeds3 ? 'Sirène (stage 3)' : 'Sirène'}">${SIREN}</span>`;
        sec.innerHTML = d.secondary.map((s) => `<span class="st-chip ${CLS[s.key] || ''} ${s.on ? 'on' : ''}" title="${esc(s.label)}">${esc(SHORT[s.key] || s.label)}</span>`).join('');
        root.setAttribute('aria-label', `${d.label} : ${d.stage ? `stage ${d.stage}` : 'aucun stage'}${d.siren ? ', sirène' : ''}`);
    }
    function show() { root.classList.toggle('hidden', !visible || hiddenByFreecam); }

    window.addEventListener('message', (e) => {
        const m = e.data || {};
        if (m.action === 'state' && m.data) { render(m.data); visible = true; show(); }
        else if (m.action === 'hide') { visible = false; show(); }
        else if (m.action === 'config' && m.data) {
            if (m.data.right) root.style.right = m.data.right;
            if (m.data.bottom) root.style.bottom = m.data.bottom;
        } else if (m.action === 'rpHideUi') { hiddenByFreecam = !!(m.data && m.data.hidden); show(); }
    });
})();
