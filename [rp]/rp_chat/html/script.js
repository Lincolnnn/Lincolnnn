/* =========================================================================
   RP Chat - NUI (Vanilla JS)
   - NUI -> Lua : fetch(`https://<ressource>/<callback>`)
   - Lua -> NUI : window 'message' (SendNUIMessage)
   ========================================================================= */
(() => {
    'use strict';

    const RESOURCE = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'rp_chat';
    const MAX_MESSAGES = 150;     // messages gardés à l'écran
    const MAX_HISTORY = 30;       // lignes déjà tapées (flèches haut / bas)
    const FEED_DURATION = 8000;   // chat fermé : durée d'affichage d'un nouveau message (ms)
    const KEY_GUARD = 250;        // ms : la touche d'ouverture n'est pas tapée dans la saisie

    // Commandes proposées en tapant "/" (doivent correspondre à server/server.lua)
    const COMMANDS = [
        { name: 'nomrp', usage: '/nomrp [nom RP]', desc: 'Définit votre nom RP (aussi celui du MDC)' },
        { name: 'me', usage: '/me [action]', desc: 'Action de votre personnage (rayon de 50 m)' },
        { name: 'info', usage: '/info [texte]', desc: 'Information pour tous (sans nom RP)' },
        { name: 'qst', usage: '/qst [question]', desc: 'Question pour tous' },
        { name: 'rep', usage: '/rep [réponse]', desc: 'Réponse pour tous' },
        { name: 'dv', usage: '/dv', desc: 'Supprime votre véhicule, ou celui regardé / le plus proche (5 m)' },
        { name: 'eup', usage: '/eup', desc: 'Menu des tenues (Police, Civil), au clavier' },
        { name: 'tuto', usage: '/tuto', desc: 'Affiche / retire la page des touches et fonctionnalités' },
        { name: 'fichecivil', usage: '/fichecivil', desc: 'Fiche civile : créer / gérer vos profils' },
        { name: 'repair', usage: '/repair', desc: 'Répare le moteur du véhicule (pas la carrosserie)' },
        // grisée : existe, mais n'est pas mise en avant
        { name: 'hrp', usage: '/hrp [message]', desc: 'Message hors RP (à limiter)', muted: true },
    ];

    const $ = (sel) => document.querySelector(sel);
    const chat = $('#chat');
    const list = $('#messages');
    const input = $('#input');
    const suggest = $('#suggest');

    const state = {
        open: false,
        key: null,          // touche d'ouverture (pour refermer avec la même touche)
        openedAt: 0,
        settings: null,
        typed: [],          // lignes déjà envoyées
        typedIndex: -1,
        draft: '',
        feedTimer: null,
        previewTimer: null,
        suggestIndex: 0,
    };

    function post(name, data = {}) {
        return fetch(`https://${RESOURCE}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data),
        }).then((res) => res.json()).catch(() => null);
    }

    // ---------------------------------------------------------------------
    // Réglages du joueur (fond, opacité, texte, taille, contour)
    // ---------------------------------------------------------------------
    function applySettings(s) {
        state.settings = s;
        const root = document.documentElement.style;
        // 0 = noir … 100 = gris, légèrement teinté de bleu nuit (thème du MDC)
        const shade = (s.shade / 100) * 120;
        const tint = (k) => Math.min(255, Math.round(shade * k));
        root.setProperty('--chat-bg', `rgba(${tint(0.78)}, ${tint(0.93)}, ${tint(1.25)}, ${s.opacity / 100})`);
        // Contour : blanc le jour ; couleur du mode nuit la nuit (style.css, [data-theme="night"] .chat)
        root.setProperty('--chat-border', s.border ? `${s.borderWidth}px solid #ffffff` : 'none');
        root.setProperty('--chat-font', `${s.fontSize}px`);
        root.setProperty('--chat-w', `${s.width}vw`);
        root.setProperty('--chat-h', `${s.height}vh`);
        if (s.feed === 'always' && !state.open) showFeed(true);
        if (s.feed === 'never' && !state.open) hideChat();
        scrollToBottom();
    }

    // ---------------------------------------------------------------------
    // Affichage : ouvert (saisie), "feed" (chat fermé, nouveaux messages), masqué
    // ---------------------------------------------------------------------
    function hideChat() {
        clearTimeout(state.feedTimer);
        chat.classList.add('hidden');
        chat.classList.remove('feed', 'fading');
    }

    function showFeed(persistent) {
        if (state.open) return;
        const mode = state.settings ? state.settings.feed : 'fade';
        if (mode === 'never' && !persistent) return;
        clearTimeout(state.feedTimer);
        chat.classList.remove('hidden', 'fading');
        chat.classList.add('feed');
        if (!state.browsing || nearBottom()) { state.browsing = false; scrollToBottom(); } else updateHint();
        if (mode === 'always') return;
        state.feedTimer = setTimeout(() => {
            chat.classList.add('fading');
            state.feedTimer = setTimeout(() => { if (!state.open) hideChat(); }, 600);
        }, persistent === 'preview' ? 6000 : FEED_DURATION);
    }

    function openChat(data) {
        state.open = true;
        state.key = data && data.key ? String(data.key).toUpperCase() : null;
        state.openedAt = Date.now();
        clearTimeout(state.feedTimer);
        chat.classList.remove('hidden', 'feed', 'fading');
        input.value = '';
        input.classList.toggle('no-name', !(data && data.hasName));
        input.placeholder = data && data.hasName
            ? '/me, /info, /qst, /rep — Entrée pour envoyer'
            : 'Définissez votre nom RP : /nomrp [nom RP]';
        state.typedIndex = -1;
        renderSuggest();
        if (!state.browsing) scrollToBottom(); else updateHint(); // garde la position s'il lisait l'historique
        state.browsing = false;
        setTimeout(() => input.focus(), 0);
    }

    function closeChat(notify = true) {
        if (!state.open) return;
        state.open = false;
        input.value = '';
        input.blur();
        renderSuggest();
        if (state.settings && state.settings.feed === 'always') showFeed(true);
        else hideChat();
        if (notify) post('close');
    }

    // ---------------------------------------------------------------------
    // Messages
    // ---------------------------------------------------------------------
    const span = (cls, text) => {
        const el = document.createElement('span');
        el.className = cls;
        el.textContent = text;
        return el;
    };

    // Construit une ligne (textContent uniquement : aucun HTML venant des joueurs n'est interprété)
    function buildMessage(m) {
        const el = document.createElement('div');
        el.className = `msg msg-${m.type}`;
        switch (m.type) {
            case 'me': // "<nom RP> jette l'arme au sol" : nom en gras (non souligné)
                el.append(span('name', m.name || ''), ` ${m.text}`);
                break;
            case 'info': // sans nom RP
                el.textContent = m.text;
                break;
            case 'qst': // nom RP en gras souligné, "Question :" en gras
                el.append(span('name name-underline', m.name || ''), ' ', span('label', 'Question :'), ` ${m.text}`);
                break;
            case 'rep': // nom RP en gras souligné, "Réponse :" en gras
                el.append(span('name name-underline', m.name || ''), ' ', span('label', 'Réponse :'), ` ${m.text}`);
                break;
            case 'hrp': // hors RP : gris discret
                el.append(span('hrp-tag', 'HRP'), ' ', span('name', m.name || ''), ` : ${m.text}`);
                break;
            case 'private': // résultat visible uniquement par ce joueur (rp_interact)
                el.append(span('private-tag', 'PRIVÉ'), ' ', span('label', m.title || ''),
                    m.name ? span('private-subject', ` (${m.name})`) : '', ` : ${m.text}`);
                break;
            case 'tuto': // rappel à la connexion (« Faites /tuto… ») : visible uniquement par ce joueur
                el.append(span('private-tag tuto-tag', 'TUTO'), ' ', span('label', m.title || ''), `\n${m.text}`);
                break;
            case 'external': { // chat:addMessage d'autres ressources
                if (m.name) el.append(span('name', `${m.name} : `));
                el.append(m.text);
                const c = Array.isArray(m.color) ? m.color : null;
                if (c && c.length >= 3) el.style.color = `rgb(${c.slice(0, 3).map((v) => Math.min(Math.max(Number(v) || 0, 0), 255)).join(',')})`;
                break;
            }
            default: // system / error / success
                el.textContent = m.text;
        }
        return el;
    }

    function nearBottom() {
        return list.scrollHeight - list.scrollTop - list.clientHeight < 40;
    }

    // Repère "plus récents en bas" quand on a remonté dans la conversation
    function updateHint() {
        $('#browseHint').classList.toggle('hidden', nearBottom());
    }

    function scrollToBottom() {
        list.scrollTop = list.scrollHeight;
        updateHint();
    }

    // Remonter (-1) / redescendre (1) d'une page (80 % de la hauteur visible)
    function scrollPage(dir) {
        list.scrollTop += dir * list.clientHeight * 0.8;
        updateHint();
    }

    // Chat fermé : touche de navigation -> le chat s'affiche (sans saisie) le temps de lire, à la position voulue
    function browse(dir) {
        if (state.open) return scrollPage(dir);
        const wasShown = !chat.classList.contains('hidden') && !chat.classList.contains('fading');
        state.browsing = true;
        clearTimeout(state.feedTimer);
        chat.classList.remove('hidden', 'fading');
        chat.classList.add('feed');
        if (wasShown || dir < 0) scrollPage(dir);
        if (state.settings && state.settings.feed === 'always') return;
        state.feedTimer = setTimeout(() => {
            chat.classList.add('fading');
            state.feedTimer = setTimeout(() => { if (!state.open) { hideChat(); state.browsing = false; } }, 600);
        }, FEED_DURATION);
    }

    function addMessage(m, quiet) {
        if (!m || typeof m.text !== 'string' || m.text === '') return;
        // ne fait pas sauter la lecture des anciens messages (chat ouvert, ou fermé en train de remonter)
        const stick = (!state.open && !state.browsing) || nearBottom();
        list.appendChild(buildMessage(m));
        while (list.children.length > MAX_MESSAGES) list.firstElementChild.remove();
        if (stick) scrollToBottom(); else updateHint();
        if (!state.open && !quiet) showFeed();
    }

    // ---------------------------------------------------------------------
    // Saisie : Entrée, Échap / touche d'ouverture, historique, suggestions
    // ---------------------------------------------------------------------
    function matchingCommands() {
        const m = /^\/(\S*)$/.exec(input.value);
        if (!state.open || !m) return [];
        const typed = m[1].toLowerCase();
        return COMMANDS.filter((c) => c.name.startsWith(typed));
    }

    function renderSuggest() {
        const matches = matchingCommands();
        suggest.classList.toggle('hidden', matches.length === 0);
        state.suggestIndex = Math.min(state.suggestIndex, Math.max(matches.length - 1, 0));
        suggest.replaceChildren(...matches.map((c, i) => {
            const li = document.createElement('li');
            li.className = [i === state.suggestIndex ? 'active' : '', c.muted ? 'muted' : ''].filter(Boolean).join(' ');
            li.append(span('usage', c.usage), span('desc', c.desc));
            return li;
        }));
    }

    function submit() {
        const text = input.value.trim();
        if (text) {
            state.typed = [text, ...state.typed.filter((t) => t !== text)].slice(0, MAX_HISTORY);
        }
        state.typedIndex = -1;
        state.open = false; // le Lua referme le chat
        input.value = '';
        renderSuggest();
        if (state.settings && state.settings.feed === 'always') showFeed(true);
        else hideChat();
        post('submit', { text });
    }

    function browseTyped(step) {
        if (!state.typed.length) return;
        if (state.typedIndex === -1) state.draft = input.value;
        state.typedIndex = Math.min(Math.max(state.typedIndex + step, -1), state.typed.length - 1);
        input.value = state.typedIndex === -1 ? state.draft : state.typed[state.typedIndex];
        renderSuggest();
        setTimeout(() => input.setSelectionRange(input.value.length, input.value.length), 0);
    }

    const keyMatches = (e) => !!state.key && e.key.toUpperCase() === state.key;

    document.addEventListener('keydown', (e) => {
        if (!state.open) return;

        // La touche d'ouverture ne doit pas s'écrire dans la saisie juste après l'ouverture
        if (keyMatches(e) && Date.now() - state.openedAt < KEY_GUARD) {
            e.preventDefault();
            return;
        }
        if (e.key === 'Escape' || (keyMatches(e) && input.value === '')) {
            e.preventDefault();
            closeChat();
            return;
        }

        const matches = matchingCommands();
        switch (e.key) {
            case 'Enter':
                e.preventDefault();
                submit();
                break;
            case 'Tab':
                e.preventDefault();
                if (matches.length) {
                    input.value = `/${matches[state.suggestIndex].name} `;
                    state.suggestIndex = 0;
                    renderSuggest();
                }
                break;
            case 'ArrowUp':
                e.preventDefault();
                if (matches.length > 1) { state.suggestIndex = (state.suggestIndex - 1 + matches.length) % matches.length; renderSuggest(); }
                else browseTyped(1);
                break;
            case 'ArrowDown':
                e.preventDefault();
                if (matches.length > 1) { state.suggestIndex = (state.suggestIndex + 1) % matches.length; renderSuggest(); }
                else browseTyped(-1);
                break;
            case 'PageUp':
                e.preventDefault();
                scrollPage(-1);
                break;
            case 'PageDown':
                e.preventDefault();
                scrollPage(1);
                break;
        }
    });

    // Chat ouvert : molette de la souris (même sans curseur visible)
    document.addEventListener('wheel', (e) => {
        if (!state.open) return;
        list.scrollTop += e.deltaY;
        updateHint();
    }, { passive: true });
    list.addEventListener('scroll', updateHint, { passive: true });

    input.addEventListener('input', () => {
        state.suggestIndex = 0;
        renderSuggest();
    });

    // ---------------------------------------------------------------------
    // Messages Lua -> NUI
    // ---------------------------------------------------------------------
    // Mode nuit des menus (MDC : Paramètres > MDC > Apparence), envoyé par client/theme.lua
    window.addEventListener('message', ({ data }) => {
        if (!data || data.action !== 'uiTheme') return;
        const t = data.data || {};
        document.documentElement.dataset.theme = 'night'; // toujours sombre : de jour, couleurs du logo du serveur
        document.documentElement.dataset.nightColor = t.theme === 'night' && ['green', 'yellow', 'red', 'blue'].includes(t.color) ? t.color : 'logo';
    });

    window.addEventListener('message', ({ data }) => {
        if (!data || !data.action) return;
        switch (data.action) {
            case 'open':
                openChat(data.data);
                break;
            case 'close':
                closeChat(false);
                break;
            case 'message':
                addMessage(data.data);
                break;
            case 'scroll': // touche de navigation, chat fermé
                browse(data.data && data.data.dir < 0 ? -1 : 1);
                break;
            case 'history': // derniers /info, /qst, /rep (connexion)
                (Array.isArray(data.data) ? data.data : Object.values(data.data || {})).forEach((m) => addMessage(m, true));
                break;
            case 'clear':
                list.replaceChildren();
                break;
            case 'tuto':
                setTuto(data.data || {});
                break;
            case 'settings':
                if (data.data) applySettings(data.data);
                if (data.preview) showFeed('preview'); // réglage depuis le MDC : aperçu du chat
                break;
        }
    });

    post('ready');

    // ---------------------------------------------------------------------
    // /tuto : affiche des touches (textContent uniquement), non interactive
    // ---------------------------------------------------------------------
    function setTuto(d) {
        const box = $('#tuto');
        box.classList.toggle('hidden', !d.show);
        if (!d.show) { box.replaceChildren(); return; }
        const el = (tag, cls, text) => {
            const e = document.createElement(tag);
            if (cls) e.className = cls;
            if (text != null) e.textContent = text;
            return e;
        };
        const head = el('div', 'tuto-head');
        const close = el('div', 'tuto-close');
        close.append('Tapez ', el('kbd', 'tuto-cmd', d.command || '/tuto'), ' pour fermer cette page');
        head.append(el('div', 'tuto-title', d.title || 'Tutoriel'), close);
        const grid = el('div', 'tuto-grid');
        const list = (v) => (Array.isArray(v) ? v : Object.values(v || {}));
        list(d.sections).forEach((section) => {
            const col = el('div', 'tuto-col');
            col.append(el('div', 'tuto-section', section.title || ''));
            list(section.items).forEach((item) => {
                const [key, text] = list(item);
                const line = el('div', 'tuto-line');
                line.append(el('span', 'tuto-key', key || ''), el('span', 'tuto-text', text || ''));
                col.append(line);
            });
            grid.append(col);
        });
        box.replaceChildren(head, grid);
        if (d.footer) box.append(el('div', 'tuto-foot', d.footer));
    }
})();
