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
        { name: 'me', usage: '/me [action]', desc: 'Action de votre personnage (rayon de 100 m)' },
        { name: 'info', usage: '/info [texte]', desc: 'Information pour tous (sans nom RP)' },
        { name: 'qst', usage: '/qst [question]', desc: 'Question pour tous' },
        { name: 'rep', usage: '/rep [réponse]', desc: 'Réponse pour tous' },
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
        const shade = Math.round((s.shade / 100) * 120); // 0 = noir … 100 = gris
        root.setProperty('--chat-bg', `rgba(${shade}, ${shade}, ${shade}, ${s.opacity / 100})`);
        root.setProperty('--chat-border', s.border ? `${s.borderWidth}px solid ${s.borderColor}` : 'none');
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
        scrollToBottom();
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
        scrollToBottom();
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
            case 'me': // "<nom RP> jette l'arme au sol"
                el.append(span('name', m.name || ''), ` ${m.text}`);
                break;
            case 'info': // sans nom RP
                el.textContent = m.text;
                break;
            case 'qst':
                el.append(span('name', m.name || ''), ` Question : ${m.text}`);
                break;
            case 'rep':
                el.append(span('name', m.name || ''), ` Réponse : ${m.text}`);
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

    function scrollToBottom() {
        list.scrollTop = list.scrollHeight;
    }

    function addMessage(m, quiet) {
        if (!m || typeof m.text !== 'string' || m.text === '') return;
        const stick = !state.open || nearBottom(); // ne fait pas sauter la lecture des anciens messages
        list.appendChild(buildMessage(m));
        while (list.children.length > MAX_MESSAGES) list.firstElementChild.remove();
        if (stick) scrollToBottom();
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
            li.className = i === state.suggestIndex ? 'active' : '';
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
                list.scrollTop -= list.clientHeight * 0.8;
                break;
            case 'PageDown':
                e.preventDefault();
                list.scrollTop += list.clientHeight * 0.8;
                break;
        }
    });

    input.addEventListener('input', () => {
        state.suggestIndex = 0;
        renderSuggest();
    });

    // ---------------------------------------------------------------------
    // Messages Lua -> NUI
    // ---------------------------------------------------------------------
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
            case 'history': // derniers /info, /qst, /rep (connexion)
                (Array.isArray(data.data) ? data.data : Object.values(data.data || {})).forEach((m) => addMessage(m, true));
                break;
            case 'clear':
                list.replaceChildren();
                break;
            case 'settings':
                if (data.data) applySettings(data.data);
                if (data.preview) showFeed('preview'); // réglage depuis le MDC : aperçu du chat
                break;
        }
    });

    post('ready');
})();
