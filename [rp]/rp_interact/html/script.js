/* =========================================================================
   RP Interact - NUI (Vanilla JS)
   Œil (Eye Target), menu d'interactions, fiche civile, résultats d'inspection
   ========================================================================= */
(() => {
    'use strict';

    const RESOURCE = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'rp_interact';
    const $ = (sel, root = document) => root.querySelector(sel);
    const $$ = (sel, root = document) => root.querySelectorAll(sel);

    const esc = (value) => String(value ?? '').replace(/[&<>"']/g, (c) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c]));
    const toArray = (value) => (Array.isArray(value) ? value : Object.values(value || {}));
    const pad = (n) => String(n).padStart(2, '0');
    const formatDate = (unix) => {
        if (!unix) return '-';
        const d = new Date(unix * 1000);
        return `${pad(d.getDate())}/${pad(d.getMonth() + 1)} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
    };

    async function post(name, data = {}) {
        try {
            const res = await fetch(`https://${RESOURCE}/${name}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(data),
            });
            return await res.json();
        } catch (err) {
            return { ok: false, error: 'Callback indisponible.' };
        }
    }

    function toast(text, type = 'info') {
        const el = document.createElement('div');
        el.className = `toast ${type}`;
        el.textContent = text;
        const box = $('#toasts');
        while (box.children.length >= 3) box.firstElementChild.remove();
        box.appendChild(el);
        setTimeout(() => el.remove(), 4000);
    }

    // Réponses par défaut affichées dans la fiche (identiques à config.lua)
    const DEFAULTS = {
        visual: 'Rien à signaler / Rien d\'anormal / Tout est correct',
        olfactory: 'Rien à signaler / Rien d\'anormal / Tout est correct',
        search: 'Rien à signaler / Aucun élément / Rien d\'illégal',
        notable: 'Aucun détail notoire',
        vehicleVisual: 'Rien d\'anormal / Tout semble normal / Rien de suspect / Rien à signaler',
        vehicleOlfactory: 'Rien d\'anormal / Rien de suspect',
        vehicleSearch: 'Rien à signaler / Aucun élément / Rien d\'illégal',
    };

    // =====================================================================
    // ŒIL
    // =====================================================================
    const ICONS = {
        eye: '<path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7S1 12 1 12Z" fill="none" stroke="currentColor" stroke-width="1.8"/><circle cx="12" cy="12" r="3.2" fill="currentColor"/>',
        nose: '<path d="M4 9c3-2 5 2 8 0s5-2 8 0M4 14c3-2 5 2 8 0s5-2 8 0" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
        search: '<circle cx="10" cy="10" r="6" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="m15 15 6 6" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',
        note: '<path d="M6 3h9l4 4v14H6Z M14 3v5h5 M9 12h7 M9 16h7" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/>',
        door: '<path d="M5 3h11v18H5Z M16 5l3 1v13l-3 2" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/><circle cx="13" cy="12" r="1" fill="currentColor"/>',
        seat: '<path d="M7 3v9h10 M7 12l-1 8 M17 12v8 M7 16h10" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
        trash: '<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v6M14 11v6" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round" stroke-linecap="round"/>',
        move: '<path d="M12 3v18M3 12h18M12 3l-3 3M12 3l3 3M12 21l-3-3M12 21l3-3M3 12l3-3M3 12l3 3M21 12l-3-3M21 12l-3 3" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round" stroke-linecap="round"/>',
        cuffs: '<circle cx="7" cy="14" r="4.2" fill="none" stroke="currentColor" stroke-width="1.8"/><circle cx="17" cy="14" r="4.2" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M9.5 10.5 12 8l2.5 2.5" fill="none" stroke="currentColor" stroke-width="1.6"/>',
        car: '<path d="M3 15v-3l2-5h14l2 5v3Z M3 15v3h3v-3 M18 15v3h3v-3 M5 12h14" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/>',
        wave: '<path d="M8 13V6a1.5 1.5 0 0 1 3 0v5V4a1.5 1.5 0 0 1 3 0v7V5.5a1.5 1.5 0 0 1 3 0V15c0 3.5-2.5 6-6 6-2.5 0-4-1.2-5.5-3.5L3.5 14a1.6 1.6 0 0 1 2.6-1.8Z" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>',
        music: '<path d="M9 18V5l11-2v13M9 18a3 3 0 1 1-3-3 3 3 0 0 1 3 3Zm11-2a3 3 0 1 1-3-3 3 3 0 0 1 3 3Z" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/>',
        hand: '<path d="M8 13V6a1.5 1.5 0 0 1 3 0v5V4a1.5 1.5 0 0 1 3 0v7V5.5a1.5 1.5 0 0 1 3 0V15c0 3.5-2.5 6-6 6-2.5 0-4-1.2-5.5-3.5L3.5 14a1.6 1.6 0 0 1 2.6-1.8Z" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>',
        lock: '<rect x="5" y="11" width="14" height="10" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M8 11V7a4 4 0 0 1 8 0v4" fill="none" stroke="currentColor" stroke-width="1.8"/>',
        unlock: '<rect x="5" y="11" width="14" height="10" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M8 11V7a4 4 0 0 1 7.6-1.7" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
        barrier: '<path d="M3 9h18v5H3Z M6 14v6M18 14v6M6 9V5M18 9V5M7 9l5 5M12 9l5 5" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round" stroke-linecap="round"/>',
        box: '<path d="M3 4h18v4H3Z M5 8v12h14V8 M10 12h4" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round" stroke-linecap="round"/>',
    };
    const icon = (name) => `<svg viewBox="0 0 24 24">${ICONS[name] || ICONS.eye}</svg>`;

    const eye = { active: false, menu: false };

    function setEye(data) {
        eye.active = !!data.active;
        $('#eye').classList.toggle('hidden', !eye.active);
        if (!eye.active) {
            eye.menu = false;
            $('#eyeOptions').classList.add('hidden');
            return;
        }
        $('#eye').classList.toggle('has-options', !!data.hasOptions);
        $('#eyeLabel').textContent = data.label || '';
        $('#eyeLabel').classList.toggle('hidden', !data.hasOptions || !data.label || eye.menu);
    }

    function showEyeOptions(data) {
        eye.menu = true;
        // Options par groupes (inspections, fouilles, police, portière, le reste, en bas), un trait entre deux groupes ;
        // les principales (inspections, ce qui est visé précisément, police) sont mises en avant
        const all = toArray(data.options);
        const grouped = all.some((o) => o.group);
        const row = (o) => `
                <li class="opt ${o.primary ? 'primary' : ''} ${o.disabled ? 'disabled' : ''}" data-index="${esc(o.index)}">
                    ${icon(o.icon)}
                    <span class="opt-label">${esc(o.label)}</span>
                    ${o.police ? '<span class="opt-police">POLICE</span>' : ''}
                </li>`;
        $('#eyeLabel').classList.add('hidden');
        $('#eyeOptions').innerHTML = `
            ${data.label ? `<li class="opt-title">${esc(data.label)}</li>` : ''}
            ${grouped
                ? all.map((o, i) => (i > 0 && o.group !== all[i - 1].group ? '<li class="opt-sep" aria-hidden="true"></li>' : '') + row(o)).join('')
                : all.map(row).join('')}`;
        $('#eyeOptions').classList.remove('hidden');
    }

    $('#eyeOptions').addEventListener('click', (e) => {
        const li = e.target.closest('li.opt');
        if (!li || li.classList.contains('disabled')) return;
        eye.menu = false;
        post('eyeSelect', { index: Number(li.dataset.index) });
    });

    // Clic droit ou clic hors de la liste : fermer
    document.addEventListener('mousedown', (e) => {
        if (!eye.menu) return;
        if (e.button === 2 || !e.target.closest('#eyeOptions')) {
            eye.menu = false;
            post('eyeCancel');
        }
    });
    document.addEventListener('contextmenu', (e) => e.preventDefault());

    // =====================================================================
    // RÉSULTATS D'INSPECTION
    // =====================================================================
    function showResult(r) {
        const el = document.createElement('div');
        el.className = 'result';
        el.innerHTML = `
            <div class="result-head"><span>Résultat</span><span>${esc(r.subject || '')}</span></div>
            <div class="result-title">${esc(r.title)}</div>
            <div class="result-text">${esc(r.text)}</div>`;
        const box = $('#results');
        while (box.children.length >= 4) box.firstElementChild.remove();
        box.appendChild(el);
        const duration = (Number(r.duration) || 20000) + String(r.text || '').length * 40;
        setTimeout(() => {
            el.classList.add('fade');
            setTimeout(() => el.remove(), 450);
        }, duration);
    }

    // =====================================================================
    // MENUS AU CLAVIER (Menu Interaction, /eup) : touches lues par client/kbmenu.lua (le NUI n'a pas le focus)
    //   ↑ ↓ choisir · Entrée valider · → ouvrir / valeur suivante · ← valeur précédente (sinon retour)
    //   Retour arrière : revenir · Échap : fermer
    // Une page = { id, title, banner: { title, sub, color }, items: () => [...], onEnter }
    // Éléments : menu (ouvre une page), button, check (case), list (valeurs ← →), input (texte), info, section
    // =====================================================================
    const KB_VISIBLE = 10;
    const KB_SELECTABLE = new Set(['menu', 'button', 'check', 'list', 'input']);
    const KB_ICONS = {
        menu: '<svg viewBox="0 0 24 24"><path d="M4 6h16M4 12h16M4 18h10" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
        eup: '<svg viewBox="0 0 24 24"><path d="M12 6a2 2 0 1 1 2-2M12 6v2L3 15a1 1 0 0 0 .6 1.8h16.8A1 1 0 0 0 21 15l-9-7" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    };
    const kbMenus = {};

    class KbMenu {
        /** opts = { icon, close(), onPage(page) } */
        constructor(el, name, opts) {
            this.el = el;
            this.name = name;
            this.opts = opts;
            this.stack = [];
            this.open = false;
            this.editing = null;
            el.innerHTML = `
                <div class="kb-banner">
                    <span class="kb-icon">${opts.icon || ''}</span>
                    <span class="kb-head"><span class="kb-title"></span><span class="kb-sub"></span></span>
                </div>
                <div class="kb-crumb"><span class="kb-path"></span><span class="kb-count"></span></div>
                <div class="kb-list"></div>
                <div class="kb-desc"></div>
                <div class="kb-keys">
                    <span><kbd>&#8593;</kbd><kbd>&#8595;</kbd> Choisir</span>
                    <span><kbd>Entrée</kbd> Valider</span>
                    <span><kbd>&#8592;</kbd><kbd>&#8594;</kbd> Régler</span>
                    <span><kbd>&#9003;</kbd> Retour</span>
                    <span><kbd>Échap</kbd> Fermer</span>
                </div>`;
            // Saisie de texte : Entrée valide, Échap annule (le clavier est rendu au jeu ensuite)
            el.addEventListener('keydown', (e) => {
                if (!e.target.classList.contains('kb-input')) return;
                if (e.key === 'Enter') { e.preventDefault(); this.stopEditing(true); }
                if (e.key === 'Escape') { e.preventDefault(); this.stopEditing(false); }
                e.stopPropagation();
            });
            el.addEventListener('focusout', (e) => {
                if (e.target.classList.contains('kb-input') && this.editing) this.stopEditing(true);
            });
            kbMenus[name] = this;
        }

        get page() { return this.stack[this.stack.length - 1]; }

        items() {
            const p = this.page;
            if (!p) return [];
            return toArray(typeof p.items === 'function' ? p.items() : p.items).filter(Boolean);
        }

        start(pages) {
            this.stopEditing(false);
            this.open = true;
            this.stack = [];
            toArray(pages).forEach((p, i, all) => this.push(p, i < all.length - 1));
            this.el.classList.remove('hidden');
        }

        stop() {
            this.stopEditing(false);
            this.open = false;
            this.stack = [];
            this.el.classList.add('hidden');
        }

        /** Ouvre une page ; `quiet` : sans la charger (pages traversées pour arriver à la dernière) */
        push(page, quiet) {
            if (!page) return;
            this.stack.push({ sel: null, top: 0, ...page });
            if (!quiet) this.enter();
        }

        pop() {
            if (this.stack.length <= 1) return false;
            this.stack.pop();
            this.enter();
            return true;
        }

        enter() {
            const p = this.page;
            if (p.onEnter) p.onEnter(p);
            if (this.opts.onPage) this.opts.onPage(p);
            this.render();
        }

        selectable(items) {
            return items.map((it, i) => (KB_SELECTABLE.has(it.kind) ? i : -1)).filter((i) => i >= 0);
        }

        /** Sélection valide (la liste peut avoir changé : rechargée, élément retiré) */
        fixSel(items) {
            const p = this.page;
            const ids = this.selectable(items);
            if (!ids.length) { p.sel = -1; return ids; }
            if (p.sel == null || p.sel < 0) p.sel = ids[0];
            if (!ids.includes(p.sel)) p.sel = ids.find((i) => i > p.sel) ?? ids[ids.length - 1];
            return ids;
        }

        render(force) {
            if (!this.open || !this.page || (this.editing && !force)) return;
            const p = this.page;
            const items = this.items();
            const ids = this.fixSel(items);
            const banner = (typeof p.banner === 'function' ? p.banner() : p.banner) || {};
            this.el.style.setProperty('--kb-color', banner.color || MENU_COLORS.home);
            const icon = $('.kb-icon', this.el);
            const logo = banner.logo || '';
            if (icon.dataset.logo !== logo) {
                icon.dataset.logo = logo;
                icon.innerHTML = logo ? `<img src="${esc(logo)}" alt="">` : (this.opts.icon || '');
                icon.classList.toggle('has-logo', !!logo);
            }
            $('.kb-title', this.el).textContent = banner.title || p.title || '';
            $('.kb-sub', this.el).textContent = banner.sub || '';
            $('.kb-path', this.el).textContent = this.stack.map((x) => x.title).join(' › ');
            $('.kb-count', this.el).textContent = ids.length ? `${ids.indexOf(p.sel) + 1}/${ids.length}` : '';
            if (p.sel >= 0) {
                if (p.sel < p.top) p.top = p.sel;
                if (p.sel >= p.top + KB_VISIBLE) p.top = p.sel - KB_VISIBLE + 1;
                // Titre de section juste au-dessus de la sélection : gardé visible en remontant
                if (p.top === p.sel && p.sel > 0 && items[p.sel - 1].kind === 'section') p.top -= 1;
            }
            p.top = Math.max(0, Math.min(p.top, items.length - KB_VISIBLE));
            $('.kb-list', this.el).innerHTML = items.slice(p.top, p.top + KB_VISIBLE)
                .map((it, i) => this.rowHtml(it, p.top + i === p.sel)).join('')
                || '<div class="kb-info">Chargement…</div>';
            this.el.classList.toggle('more-up', p.top > 0);
            this.el.classList.toggle('more-down', p.top + KB_VISIBLE < items.length);
            const current = items[p.sel];
            const desc = (current && current.desc) || p.desc || '';
            $('.kb-desc', this.el).innerHTML = desc ? esc(desc).replace(/\n/g, '<br>') : '';
            $('.kb-desc', this.el).classList.toggle('hidden', !desc);
        }

        rowHtml(it, sel) {
            if (it.kind === 'section') return `<div class="kb-section">${esc(it.label)}</div>`;
            if (it.kind === 'info') return `<div class="kb-info${it.tone ? ` tone-${it.tone}` : ''}">${esc(it.label)}</div>`;
            let right = '';
            if (it.kind === 'check') {
                right = `<span class="kb-check${it.checked ? ' on' : ''}" aria-hidden="true"></span>`;
            } else if (it.kind === 'list') {
                const option = toArray(it.options)[Number(it.index) || 0];
                const label = option && typeof option === 'object' ? option.label : option;
                right = `<span class="kb-choice"><i>&#8249;</i><span>${esc(label ?? '')}</span><i>&#8250;</i></span>`;
            } else if (it.kind === 'input') {
                right = this.editing && this.editing.item.key === it.key
                    ? `<input class="kb-input" type="text" maxlength="${Number(it.max) || 80}" value="${esc(this.editing.value)}" placeholder="${esc(it.placeholder || '')}" spellcheck="false" autocomplete="off">`
                    : `<span class="kb-value${it.value ? '' : ' is-empty'}">${esc(it.value || it.placeholder || 'Vide')}</span>`;
            } else if (it.right) {
                right = `<span class="kb-right">${esc(it.right)}</span>`;
            }
            if (it.mark) right += '<span class="kb-mark" aria-hidden="true">&#10003;</span>';
            if (it.kind === 'menu') right += '<span class="kb-arrow" aria-hidden="true">&#8250;</span>';
            const cls = ['kb-item', sel && 'sel', it.disabled && 'disabled', it.danger && 'danger', it.kind === 'input' && 'is-input'].filter(Boolean).join(' ');
            return `<div class="${cls}"${it.color ? ` style="--kb-tag:${esc(it.color)}"` : ''}>
                ${it.color ? '<span class="kb-tag"></span>' : ''}<span class="kb-label">${esc(it.label)}</span>${right}</div>`;
        }

        key(key) {
            if (!this.open || this.editing || !this.page) return;
            const p = this.page;
            const items = this.items();
            const ids = this.fixSel(items);
            const it = items[p.sel];
            const move = (d) => {
                if (!ids.length) return;
                const pos = ids.indexOf(p.sel);
                p.sel = ids[(pos + d + ids.length) % ids.length];
            };
            switch (key) {
                case 'up': move(-1); break;
                case 'down': move(1); break;
                case 'left':
                    if (it && it.kind === 'list') { if (!it.disabled) this.cycle(it, -1); break; }
                    if (!this.pop()) return this.opts.close();
                    return;
                case 'right':
                    if (!it || it.disabled) break;
                    if (it.kind === 'list') this.cycle(it, 1);
                    else if (it.kind === 'menu') return this.activate(it);
                    else if (it.onRight) it.onRight();
                    break;
                case 'select': if (it) return this.activate(it); break;
                case 'back': if (!this.pop()) return this.opts.close(); return;
                case 'close': return this.opts.close();
                default: return;
            }
            this.render();
        }

        activate(it) {
            if (it.disabled) {
                if (it.why) toast(it.why, 'error');
                return;
            }
            if (it.kind === 'menu') {
                const page = typeof it.open === 'function' ? it.open() : it.open;
                if (page) this.push(page);
                return;
            }
            if (it.kind === 'check') { if (it.onChange) it.onChange(!it.checked); }
            else if (it.kind === 'list') this.cycle(it, 1);
            else if (it.kind === 'input') return this.startEditing(it);
            else if (it.action) it.action();
            this.render();
        }

        cycle(it, d) {
            const n = toArray(it.options).length;
            if (!n) return;
            const current = Number(it.index) || 0;
            const next = it.clamp ? Math.min(Math.max(current + d, 0), n - 1) : (current + d + n) % n;
            if (next !== current && it.onChange) it.onChange(next, toArray(it.options)[next]);
        }

        // ---- Saisie de texte : le NUI prend le clavier (sans curseur) le temps de la saisie ----
        async startEditing(it) {
            this.editing = { item: it, value: it.value || '' };
            this.render(true);
            await post('kbTyping', { active: true });
            const input = $('.kb-input', this.el);
            if (!input || !this.editing) return;
            input.focus();
            input.setSelectionRange(input.value.length, input.value.length);
        }

        stopEditing(commit) {
            const edit = this.editing;
            if (!edit) return;
            const input = $('.kb-input', this.el);
            const value = (input ? input.value : edit.value).trim();
            this.editing = null;
            post('kbTyping', { active: false });
            if (commit && edit.item.onChange) edit.item.onChange(value);
            this.render();
        }
    }

    // =====================================================================
    // MENU D'INTERACTIONS (touche F1 par défaut)
    // =====================================================================
    const menu = { data: {} };
    const LOCKED_TEXT = 'Accès réservé : vous n\'avez pas la permission.';
    // Couleur de la bannière : une par partie du menu ; WSP / KCSO : couleur de la police (comme le MDC)
    const AGENCY_COLORS = { wsp: '#2d63b3', kcso: '#2f7a55' };
    const MENU_COLORS = { home: '#2f5ea8', police: '#28509a', civil: '#6a4fa0', equipment: '#a0662a', car: '#23827a', weather: '#3a6f8f' };
    const agencyCode = (text) => {
        const t = String(text || '').toLowerCase();
        if (t === 'wsp' || t.startsWith('washington')) return 'wsp';
        if (t === 'kcso' || t.startsWith('king county')) return 'kcso';
        return '';
    };
    const agencyColor = (text) => AGENCY_COLORS[agencyCode(text)] || '';
    // Logos des polices (html/img), dans les bannières
    const AGENCY_LOGOS = { wsp: 'img/wsp.png', kcso: 'img/kcso.png' };
    const agencyLogo = (text) => AGENCY_LOGOS[agencyCode(text)] || '';
    const isLocked = (section) => !!(menu.data.locked && menu.data.locked[section]);
    const menuOn = (id) => interact.open && interact.page && interact.page.id === id;
    const plural = (n, word) => `${n} ${word}${n > 1 ? 's' : ''}`;

    const interact = new KbMenu($('#menu'), 'menu', {
        icon: KB_ICONS.menu,
        close: () => post('closeMenu'),
        onPage: (page) => post('menuView', { view: page.id }), // la page Police reçoit l'état des actions en direct
    });
    const rerender = () => interact.render();

    // ---- Accueil ----
    function homePage() {
        return {
            id: 'home', title: 'Menu Interaction',
            banner: () => ({ title: 'Interactions', sub: menu.data.activeName ? `Profil actif : ${menu.data.activeName}` : 'Menu Interaction', color: MENU_COLORS.home,
                logo: menu.data.police ? agencyLogo(menu.data.agency) : '' }),
            items: () => {
                const d = menu.data;
                const locked = (section) => (isLocked(section) ? { disabled: true, why: LOCKED_TEXT, right: 'Réservé' } : {});
                return [
                    { kind: 'section', label: 'Usage' },
                    { kind: 'menu', label: 'Police', right: d.police ? `${d.agency ? `${d.agency} · ` : ''}${d.police}` : 'Hors service', open: policePage,
                        color: agencyColor(d.agency) || undefined,
                        desc: d.police ? 'Menottes, prendre par le bras, placer dans un véhicule ; secteur affiché sur le MDC.'
                            : 'Hors service : rejoignez une unité dans le MDC (WSP ou KCSO).' },
                    { kind: 'menu', label: 'Civil', right: d.activeName || 'Aucun profil', open: civilPage,
                        desc: 'Mode civil, profils, véhicule et tips d\'arrestation.' },
                    { kind: 'section', label: 'Configuration' },
                    { kind: 'menu', label: 'Équipements', open: equipmentPage, desc: 'Tenues (/eup) et armes.', ...locked('equipment') },
                    { kind: 'menu', label: 'Voiture', open: carPage, desc: 'Faire apparaître un véhicule, radio du véhicule.', ...locked('car') },
                    { kind: 'menu', label: 'Météo', open: weatherPage, desc: 'Météo et heure du serveur (pour tout le monde), et leur défilement.', ...locked('weather') },
                ];
            },
        };
    }

    // ---- Police : actions toujours affichées, grisées si personne n'est assez proche ; secteur (display MDC) ----
    const actions = {};
    function setMenuActions(a) {
        Object.assign(actions, a || {});
        if (menuOn('police')) rerender();
    }

    function policePage() {
        return {
            id: 'police', title: 'Police',
            banner: () => ({ title: 'Police', sub: menu.data.police ? `${menu.data.agencyLabel || 'En service'} — unité ${menu.data.police}` : 'Hors service',
                color: agencyColor(menu.data.agency) || MENU_COLORS.police, logo: agencyLogo(menu.data.agency) }),
            items: () => {
                const d = menu.data;
                const action = (key, fallback, why) => {
                    const state = actions[key] || {};
                    return { kind: 'button', label: state.label || fallback, disabled: !state.enabled,
                        why: d.police ? why : 'Réservé à la police : rejoignez une unité dans le MDC.',
                        desc: d.police ? (state.enabled ? 'Entrée : faire l\'action (le menu se ferme).' : why) : 'Rejoignez une unité dans le MDC.',
                        action: () => post('policeAction', { action: key }) };
                };
                const targetKey = d.targetKey || 'Alt';
                return [
                    { kind: 'info', label: d.police ? `En service — unité ${d.police}` : 'Hors service', tone: d.police ? 'ok' : 'muted' },
                    action('cuff', 'Menotter', 'Personne à moins de 2 m.'),
                    action('drag', 'Prendre par le bras', 'Personne à moins de 2 m.'),
                    action('place', 'Placer l\'individu à l\'arrière du véhicule', 'Lâchez le bras : un civil à moins de 4 m d\'une portière arrière libre.'),
                    action('seat', 'Faire s\'asseoir l\'individu', 'Individu menotté à moins de 2 m (pas tenu par le bras).'),
                    { kind: 'section', label: 'Display MDC' },
                    { kind: 'input', key: 'sector', label: 'Secteur', value: (d.policeProfile || {}).sector || '', max: 40,
                        placeholder: 'ex : Downtown, I-5 Nord…',
                        desc: 'Entrée : écrire le secteur (zone de jeu), affiché sur le display du MDC. Entrée pour valider, Échap pour annuler.',
                        onChange: async (value) => {
                            const res = await post('setPoliceProfile', { sector: value });
                            if (res && res.ok) menu.data.policeProfile = res.profile;
                            rerender();
                        } },
                    { kind: 'info', label: d.police ? `Œil (${targetKey}) : inspections, fouilles, détails notoires.`
                        : `Œil (${targetKey}) : inspections visuelles et olfactives seulement.`, tone: 'muted' },
                ];
            },
        };
    }

    // ---- Civil ----
    async function openEditorView(view) {
        const res = await post('openEditor', { view });
        if (!res || !res.ok) toast(res?.error || 'Ouverture impossible.', 'error');
    }

    function civilPage() {
        return {
            id: 'civil', title: 'Civil',
            banner: () => ({ title: 'Civil', sub: menu.data.activeName ? `Profil actif : ${menu.data.activeName}` : 'Aucun profil actif', color: MENU_COLORS.civil }),
            items: () => {
                const d = menu.data;
                return [
                    { kind: 'info', label: d.activeName ? `Profil actif : ${d.activeName}` : 'Aucun profil actif : créez-en un.', tone: d.activeName ? '' : 'muted' },
                    { kind: 'check', label: 'Mode civil', checked: !!d.civilMode,
                        desc: 'Options visuelles propres au rôle de civil (tips d\'arrestation). Gardé d\'une connexion à l\'autre.',
                        onChange: async (on) => {
                            const res = await post('setCivilMode', { enabled: on });
                            d.civilMode = !!(res && res.ok ? res.civilMode : on);
                            if (!d.civilMode) d.tipsManual = false;
                            rerender();
                        } },
                    { kind: 'button', label: 'Créer un profil', desc: 'Ouvre la fiche civile (profils permanents).', action: () => openEditorView('profiles') },
                    { kind: 'button', label: 'Créer un véhicule', desc: 'Profil du véhicule dans lequel vous êtes (ou le plus proche).', action: () => openEditorView('vehicle') },
                    d.civilMode && { kind: 'button', label: d.tipsManual ? 'Masquer les tips arrestation' : 'Tips arrestation', mark: !!d.tipsManual,
                        desc: 'Touches des emotes de reddition (le menu se ferme pour les utiliser).',
                        action: async () => {
                            const res = await post('toggleTips');
                            if (!res || !res.ok) return toast(res?.error || 'Action impossible.', 'error');
                            d.tipsManual = !!res.visible;
                            rerender();
                        } },
                ];
            },
        };
    }

    // ---- Équipements : équipements de police (Équipement WSP / KCSO), modifiés, autres lots ; tenues : menu /eup ----
    // Équipement sélectionné : de base ({ key }) ou modifié ({ id }) ; c'est lui que "Customiser équipement" modifie.
    const equip = { loaded: false, services: [], customs: [], loadouts: [], max: 10, selected: null, locked: false, custom: null };
    const selectedKit = () => {
        const sel = equip.selected;
        if (!sel) return null;
        if (sel.id) {
            const c = equip.customs.find((x) => x.id === sel.id);
            return c ? { ...c, custom: true } : null;
        }
        return equip.services.find((x) => x.key === sel.key) || null;
    };
    const LOCKED_WEAPONS = 'Armes réservées à la police : rejoignez une unité dans le MDC.';

    async function loadEquipment() {
        const res = await post('equipmentList');
        if (!res || !res.ok) return;
        equip.loaded = true;
        equip.locked = !!(res.policeOnly && !res.police);
        equip.services = toArray(res.services);
        equip.customs = toArray(res.customs);
        equip.loadouts = toArray(res.loadouts);
        equip.max = Number(res.maxCustom) || 10;
        if (!selectedKit()) equip.selected = null; // rien d'imposé : le joueur choisit son équipement
        rerender();
    }

    const kitColor = (kit) => agencyColor(kit.code) || agencyColor(kit.service) || undefined;

    function equipmentPage() {
        return {
            id: 'equipment', title: 'Équipements',
            banner: { title: 'Équipements', sub: 'Tenues et armes', color: MENU_COLORS.equipment },
            onEnter: loadEquipment,
            items: () => {
                const lock = equip.locked ? { disabled: true, why: LOCKED_WEAPONS } : {};
                const sel = equip.selected || {};
                const kit = selectedKit();
                const n = equip.customs.length;
                return [
                    { kind: 'section', label: 'Tenues' },
                    { kind: 'button', label: 'Accéder aux tenues', right: '/eup', desc: 'Menu des tenues (WSP, KCSO, Civil).', action: () => post('openEup') },
                    { kind: 'section', label: 'Armes' },
                    equip.locked && { kind: 'info', label: LOCKED_WEAPONS, tone: 'warn' },
                    ...(equip.loaded && !equip.services.length ? [{ kind: 'info', label: 'Aucun équipement de police (equipment_services.json).', tone: 'muted' }] : []),
                    ...equip.services.map((x) => ({
                        kind: 'button', label: x.name, right: 'Base', color: kitColor(x), mark: !sel.id && sel.key === x.key, ...lock,
                        desc: 'Entrée : prendre tout l\'équipement de départ (toujours la version de base). Il devient l\'équipement à customiser.',
                        action: () => {
                            equip.selected = { key: x.key };
                            post('useEquipment', { kind: 'service', key: x.key });
                        },
                    })),
                    { kind: 'menu', label: 'Équipements modifiés', right: n ? `${n}` : 'Aucun', open: savedPage, ...lock,
                        desc: n ? `${plural(n, 'équipement')} enregistré${n > 1 ? 's' : ''} (${equip.max} max).` : 'Aucun : choisissez un équipement, « Customiser équipement », puis « Enregistrer ».' },
                    { kind: 'menu', label: 'Customiser équipement', right: kit ? kit.name : '', open: customPage, ...lock,
                        ...(kit ? {} : { disabled: true, why: 'Choisissez d\'abord un équipement.' }),
                        desc: kit ? `Armes, accessoires et teintes de « ${kit.name} ».` : 'Choisissez d\'abord un équipement (de base ou modifié).' },
                    ...(equip.loadouts.length ? [{ kind: 'section', label: 'Autres armes' }] : []),
                    ...equip.loadouts.map((x) => ({ kind: 'button', label: x.name, ...lock,
                        action: () => post('useEquipment', { kind: 'loadout', index: Number(x.index) }) })),
                    { kind: 'button', label: 'Retirer mes armes', danger: true, action: () => post('useEquipment', { kind: 'removeWeapons' }) },
                ];
            },
        };
    }

    function savedPage() {
        return {
            id: 'equipment-saved', title: 'Équipements modifiés',
            banner: { title: 'Équipements modifiés', sub: 'Les vôtres, enregistrés sur le serveur', color: MENU_COLORS.equipment },
            onEnter: loadEquipment,
            items: () => {
                const sel = equip.selected || {};
                if (!equip.customs.length) return [{ kind: 'info', label: 'Aucun équipement modifié.', tone: 'muted' }];
                return equip.customs.map((x) => ({
                    kind: 'button', label: x.name, right: x.service, color: kitColor(x), mark: sel.id === x.id,
                    desc: 'Entrée : équiper · → : modifier.',
                    action: () => {
                        equip.selected = { id: x.id };
                        post('useEquipment', { kind: 'custom', id: x.id });
                    },
                    onRight: () => {
                        equip.selected = { id: x.id };
                        interact.push(customPage());
                    },
                }));
            },
        };
    }

    // ---- Customiser équipement : armes de la police, accessoires, teintes ; nom ; enregistré = équipement modifié ----
    const TINTS = ['Noir (d\'origine)', 'Vert', 'Or', 'Rose', 'Kaki', 'Bleu police', 'Orange', 'Platine'];

    async function loadCustom() {
        const kit = selectedKit();
        equip.custom = null;
        rerender();
        if (!kit) return;
        const res = await post('equipmentCustom', kit.custom ? { id: kit.id } : { key: kit.key });
        if (!res || !res.ok) {
            toast(res?.error || 'Action impossible.', 'error');
            return;
        }
        // Choix en cours (modifiés dans le menu, envoyés à "Équiper" / "Enregistrer")
        res.weapons = toArray(res.weapons).map((w) => {
            const choice = w.choice || {};
            return { ...w, groups: toArray(w.groups), on: !!(w.required || choice.on),
                components: toArray(choice.components), tint: Number(choice.tint) || 0 };
        });
        res.draftName = res.name || '';
        equip.custom = res;
        rerender();
    }

    function customItems() {
        const c = equip.custom;
        if (!c) return [{ kind: 'info', label: 'Chargement…', tone: 'muted' }];
        const items = [
            { kind: 'info', label: c.id ? `Modifié depuis ${c.service}` : `Équipement de base : ${c.service}`, tone: 'muted' },
            { kind: 'input', key: 'name', label: 'Nom', value: c.draftName, placeholder: c.suggested || 'Nom de l\'équipement', max: 40,
                desc: 'Nom de l\'équipement modifié (Entrée pour écrire).', onChange: (v) => { c.draftName = v; rerender(); } },
        ];
        c.weapons.forEach((w) => {
            items.push({ kind: 'section', label: w.label });
            items.push({ kind: 'check', label: 'Prendre cette arme', checked: w.on, disabled: !!w.required,
                right: w.required ? 'Obligatoire' : '', why: 'Arme obligatoire.',
                onChange: (on) => { w.on = on; } });
            w.groups.forEach((g) => {
                const choices = toArray(g.choices);
                const has = (comp) => w.components.includes(comp);
                const without = () => { w.components = w.components.filter((x) => !choices.some((ch) => ch.component === x)); };
                if (choices.length === 1) {
                    const ch = choices[0];
                    items.push({ kind: 'check', label: ch.label || g.label, checked: has(ch.component), disabled: !w.on, why: 'Prenez d\'abord l\'arme.',
                        onChange: (on) => { without(); if (on) w.components.push(ch.component); } });
                    return;
                }
                const options = [{ label: 'Aucun' }, ...choices];
                const index = Math.max(0, options.findIndex((o) => o.component && has(o.component)));
                items.push({ kind: 'list', label: g.label, options, index, disabled: !w.on, why: 'Prenez d\'abord l\'arme.',
                    onChange: (i) => { without(); if (options[i].component) w.components.push(options[i].component); } });
            });
            if (w.tints) {
                items.push({ kind: 'list', label: 'Teinte', options: TINTS, index: w.tint, disabled: !w.on, why: 'Prenez d\'abord l\'arme.',
                    onChange: (i) => { w.tint = i; } });
            }
        });
        items.push({ kind: 'section', label: 'Enregistrer' });
        items.push({ kind: 'button', label: 'Équiper', desc: 'Prendre ces armes sans enregistrer.', action: () => customAction('apply') });
        items.push({ kind: 'button', label: c.id ? 'Enregistrer (mettre à jour)' : 'Enregistrer', desc: c.id
            ? 'Met à jour cet équipement modifié.'
            : 'Ajoute un équipement modifié à votre liste (l\'équipement de base ne change pas).', action: () => customAction('save') });
        if (c.id) {
            items.push({ kind: 'button', label: c.confirmDelete ? 'Confirmer la suppression' : 'Supprimer cet équipement modifié', danger: true,
                desc: c.confirmDelete ? 'Entrée à nouveau : supprimer définitivement.' : 'Supprime cet équipement modifié.',
                action: () => {
                    if (!c.confirmDelete) { c.confirmDelete = true; return; }
                    customAction('delete');
                } });
        }
        return items;
    }

    function customPage() {
        return {
            id: 'equipment-custom', title: 'Customiser',
            banner: () => {
                const c = equip.custom;
                return { title: 'Customiser équipement', sub: c ? (c.id ? c.name : c.service) : '', color: (c && kitColor(c)) || MENU_COLORS.equipment };
            },
            onEnter: (page) => { if (!page.loaded) { page.loaded = true; loadCustom(); } },
            items: customItems,
        };
    }

    function customChoices() {
        const weapons = {};
        equip.custom.weapons.forEach((w) => {
            weapons[w.weapon] = { on: w.on, components: w.components.slice(), tint: w.tint };
        });
        return { weapons };
    }

    async function customAction(action) {
        const c = equip.custom;
        if (!c) return;
        const payload = { key: c.key, id: c.id || null, action, name: c.draftName.trim() };
        if (action !== 'delete') payload.choices = customChoices();
        const res = await post('equipmentCustomSave', payload);
        if (!res || !res.ok) return;
        if (res.customs) equip.customs = toArray(res.customs);
        if (action === 'delete') {
            equip.custom = null;
            equip.selected = { key: c.key };
            interact.pop();
            return;
        }
        if (action === 'save' && res.id) {
            // Enregistré : c'est désormais cet équipement modifié qui est sélectionné (un nouvel enregistrement le met à jour)
            c.id = res.id;
            c.name = res.name || c.name;
            c.draftName = c.name;
            equip.selected = { id: res.id };
        }
        rerender();
    }

    // ---- Voiture ----
    function carPage() {
        return {
            id: 'car', title: 'Voiture',
            banner: { title: 'Voiture', sub: 'Spawn et radio', color: MENU_COLORS.car },
            items: [
                { kind: 'menu', label: 'Spawn', open: spawnPage, desc: 'Faire apparaître un véhicule (data/vehicle.json).' },
                { kind: 'menu', label: 'Radio', open: radioPage, desc: 'Musique, vidéo, podcast dans le véhicule, pour tout le monde.' },
            ],
        };
    }

    // ---- Configuration > Météo : météo et heure du serveur (server/weather.lua) ----
    const WEATHER_MODES = [{ id: 'fixed', label: 'Fixe' }, { id: 'fair', label: 'Beau temps' }, { id: 'rainy', label: 'Pluvieux' }];
    const TIME_MODES = [{ id: 'fixed', label: 'Fixe (ne bouge plus)' }, { id: 'base', label: 'De base (rapide)' }, { id: 'realistic', label: 'Réaliste' }];
    const wx = { loaded: false, allowed: false, types: [], current: null, draft: null };
    const two = (n) => String(n).padStart(2, '0');
    const labelOf = (list, id) => (list.find((x) => x.id === id) || {}).label || id;

    async function loadWeather() {
        const res = await post('weatherGet');
        if (!res || !res.ok) return;
        wx.loaded = true;
        wx.allowed = !!res.allowed;
        wx.types = toArray(res.types);
        wx.current = res;
        wx.draft = { weather: res.weather, weatherMode: res.weatherMode, timeMode: res.timeMode, hour: res.hour, minute: res.minute };
        rerender();
    }

    function weatherPage() {
        return {
            id: 'weather', title: 'Météo',
            banner: { title: 'Météo', sub: 'Météo et heure du serveur', color: MENU_COLORS.weather },
            onEnter: loadWeather,
            items: () => {
                const c = wx.current; const d = wx.draft;
                if (!wx.loaded || !d) return [{ kind: 'info', label: 'Chargement…', tone: 'muted' }];
                const lock = wx.allowed ? {} : { disabled: true, why: LOCKED_TEXT };
                const index = (list, id) => Math.max(0, list.findIndex((x) => x.id === id));
                return [
                    { kind: 'info', label: `Actuellement : ${labelOf(wx.types, c.weather)} · ${two(c.hour)}:${two(c.minute)}`
                        + ` · météo ${labelOf(WEATHER_MODES, c.weatherMode).toLowerCase()} · heure ${labelOf(TIME_MODES, c.timeMode).toLowerCase()}`, tone: 'muted' },
                    !wx.allowed && { kind: 'info', label: 'Réservé : vous ne pouvez pas régler la météo.', tone: 'warn' },
                    { kind: 'section', label: 'Météo' },
                    { kind: 'list', label: 'Temps', options: wx.types.map((t) => t.label), index: index(wx.types, d.weather), ...lock,
                        desc: 'Le temps qu\'il fait maintenant (changement en douceur pour tout le monde).',
                        onChange: (i) => { d.weather = wx.types[i].id; rerender(); } },
                    { kind: 'list', label: 'Défilement de la météo', options: WEATHER_MODES.map((m) => m.label), index: index(WEATHER_MODES, d.weatherMode), ...lock,
                        desc: 'Fixe : le temps ne change plus. Beau temps : passe d\'un temps clair à un autre. Pluvieux : pluie, orage, brumeux, brouillard.',
                        onChange: (i) => { d.weatherMode = WEATHER_MODES[i].id; rerender(); } },
                    { kind: 'section', label: 'Heure' },
                    { kind: 'input', key: 'time', label: 'Heure', value: `${two(d.hour)}:${two(d.minute)}`, max: 5, placeholder: 'HH:MM', ...lock,
                        desc: 'Entrée : écrire l\'heure à la minute près (ex : 21:45), Entrée pour valider.',
                        onChange: (value) => {
                            const m = /^\s*(\d{1,2})\s*[:h.]\s*(\d{1,2})\s*$/.exec(value || '');
                            if (!m || Number(m[1]) > 23 || Number(m[2]) > 59) { toast('Heure invalide : 00:00 à 23:59.', 'error'); rerender(); return; }
                            d.hour = Number(m[1]); d.minute = Number(m[2]); rerender();
                        } },
                    { kind: 'list', label: 'Défilement du temps', options: TIME_MODES.map((m) => m.label), index: index(TIME_MODES, d.timeMode), ...lock,
                        desc: 'Fixe : l\'heure ne bouge plus. De base : 2 s par minute du jeu (GTA). Réaliste : 40 s par minute du jeu.',
                        onChange: (i) => { d.timeMode = TIME_MODES[i].id; rerender(); } },
                    { kind: 'section', label: 'Appliquer' },
                    { kind: 'button', label: 'Appliquer à tout le serveur', ...lock,
                        action: async () => {
                            const res = await post('weatherSet', d);
                            if (!res || !res.ok) { toast(res?.error || 'Réglage impossible.', 'error'); return; }
                            wx.current = res;
                            toast(`Météo : ${labelOf(wx.types, res.weather)}, ${two(res.hour)}:${two(res.minute)}.`, 'success');
                            rerender();
                        } },
                ].filter(Boolean);
            },
        };
    }

    // ---- Voiture > Spawn (data/vehicle.json) : catégorie principale ("Principale") > sous-catégorie ----
    const spawn = { loaded: false, vehicles: [], options: {}, locked: false };
    /** Groupes dans l'ordre du fichier : [{ name, items }] */
    function groupBy(list, key) {
        const out = [];
        list.forEach((v) => {
            const name = v[key] || '';
            let g = out.find((x) => x.name === name);
            if (!g) { g = { name, items: [] }; out.push(g); }
            g.items.push(v);
        });
        return out;
    }

    async function loadVehicles() {
        const res = await post('vehicleList');
        if (!res || !res.ok) return;
        spawn.loaded = true;
        spawn.options = res.options || {};
        spawn.vehicles = toArray(res.vehicles);
        spawn.locked = !!(res.policeOnly && !res.police);
        rerender();
    }

    const saveSpawnOptions = () => post('spawnOptions', { deleteOld: spawn.options.deleteOld !== false, warpInto: spawn.options.warpInto !== false });

    function spawnPage() {
        return {
            id: 'spawn', title: 'Spawn',
            banner: { title: 'Spawn', sub: 'Faire apparaître un véhicule', color: MENU_COLORS.car },
            onEnter: loadVehicles,
            items: () => {
                const o = spawn.options;
                const categories = groupBy(spawn.vehicles, 'category');
                return [
                    { kind: 'check', label: 'Supprimer l\'ancien véhicule', checked: o.deleteOld !== false,
                        desc: 'Le dernier véhicule que vous avez fait apparaître (s\'il n\'y a pas d\'autre joueur dedans).',
                        onChange: (on) => { o.deleteOld = on; saveSpawnOptions(); } },
                    { kind: 'check', label: 'Apparaître dans le véhicule', checked: o.warpInto !== false,
                        desc: 'Sinon, il apparaît devant vous.', onChange: (on) => { o.warpInto = on; saveSpawnOptions(); } },
                    { kind: 'section', label: 'Catégories' },
                    ...(spawn.loaded && !categories.length ? [{ kind: 'info', label: 'Aucun véhicule (data/vehicle.json).', tone: 'muted' }] : []),
                    ...categories.map((c) => {
                        const police = c.name.toLowerCase() === 'police';
                        const subs = groupBy(c.items, 'sub').filter((g) => g.name);
                        return { kind: 'menu', label: c.name, right: `${c.items.length}`, open: () => spawnListPage(c.name),
                            desc: `${plural(c.items.length, 'véhicule')}${subs.length ? ` · ${subs.map((g) => g.name).join(', ')}` : ''}${police && spawn.locked ? ' — réservés à la police' : ''}` };
                    }),
                ];
            },
        };
    }

    function spawnListPage(category) {
        return {
            id: 'spawn-list', title: category,
            banner: { title: category, sub: 'Véhicules', color: MENU_COLORS.car },
            items: () => {
                const current = groupBy(spawn.vehicles, 'category').find((c) => c.name === category);
                if (!current) return [{ kind: 'info', label: 'Aucun véhicule dans cette catégorie.', tone: 'muted' }];
                const police = current.name.toLowerCase() === 'police';
                const out = police && spawn.locked ? [{ kind: 'info', label: 'Réservé à la police : rejoignez une unité dans le MDC.', tone: 'warn' }] : [];
                groupBy(current.items, 'sub').forEach((g) => {
                    if (g.name) out.push({ kind: 'section', label: g.name });
                    g.items.forEach((v) => out.push({
                        kind: 'button', label: v.label, right: v.code, color: agencyColor(g.name) || undefined,
                        disabled: !!(v.police && spawn.locked), why: 'Réservé à la police : rejoignez une unité dans le MDC.',
                        action: () => {
                            post('spawnVehicle', { id: Number(v.id) });
                            post('closeMenu');
                        },
                    }));
                });
                return out;
            },
        };
    }

    // ---- Voiture > Radio : réglages du véhicule (le son est joué plus bas) ----
    const RADIO_QUEUE_MAX = 5;
    const RADIO_VOLUMES = Array.from({ length: 21 }, (_, i) => `${i * 5} %`);
    const radioUi = { info: null, url: '', volume: 60, volumeTimer: null };

    async function loadRadio() {
        radioUi.info = await post('radioInfo');
        const radio = radioUi.info && radioUi.info.radio;
        if (radio) radioUi.volume = Number(radio.volume) || 0;
        rerender();
    }

    async function radioAction(action, extra = {}) {
        const res = await post('radioAction', { action, ...extra });
        if (!res || !res.ok) {
            toast(res?.error || 'Action impossible.', 'error');
            return null;
        }
        radioUi.info = res;
        if (res.radio) radioUi.volume = Number(res.radio.volume) || 0;
        rerender();
        return res;
    }

    // Début du morceau ; deux appuis rapprochés (moins de 2,5 s) : morceau précédent
    const RADIO_DOUBLE_MS = 2500;
    let radioRestartAt = 0;

    function radioItems() {
        const info = radioUi.info;
        if (!info) return [{ kind: 'info', label: 'Chargement…', tone: 'muted' }];
        if (!info.available) {
            return [{ kind: 'info', label: info.error || 'Montez dans un véhicule (ou visez l\'intérieur avant avec l\'œil, portière ouverte).', tone: 'muted' }];
        }
        const radio = info.radio || null;
        const queue = radio ? toArray(radio.queue) : [];
        const can = !!info.canControl;
        const off = (cond, why) => (cond ? {} : { disabled: true, why });
        const front = 'Seules les places avant peuvent régler la radio.';
        const ctl = (extra) => (can ? (extra || {}) : { disabled: true, why: front });
        const items = [
            { kind: 'info', label: `${info.vehicle ? `${info.vehicle} — ` : ''}${radio ? (radio.paused ? 'radio en pause' : 'radio allumée') : 'radio éteinte'}`, tone: radio ? 'ok' : 'muted' },
            radio && { kind: 'info', label: radio.url, tone: 'muted' },
            !can && { kind: 'info', label: front, tone: 'warn' },
            { kind: 'input', key: 'url', label: 'Lien', value: radioUi.url, placeholder: 'YouTube, musique, podcast, radio…', max: 400, ...ctl(),
                desc: 'Entrée : coller / écrire le lien (Ctrl+V), puis Entrée.', onChange: (v) => { radioUi.url = v; rerender(); } },
            { kind: 'button', label: 'Lancer ce lien', ...ctl(radioUi.url ? {} : { disabled: true, why: 'Écrivez d\'abord un lien.' }),
                desc: 'Tout le monde l\'entend au même moment : à bord, et dehors selon la distance (plus bas vitres et portières fermées).',
                action: () => radioAction('play', { url: radioUi.url, volume: radioUi.volume }) },
            { kind: 'button', label: 'Ajouter à « Écouter ensuite »', right: `${queue.length} / ${RADIO_QUEUE_MAX}`,
                ...ctl(!radioUi.url ? { disabled: true, why: 'Écrivez d\'abord un lien.' } : (queue.length >= RADIO_QUEUE_MAX ? { disabled: true, why: 'File pleine (5 max).' } : {})),
                desc: 'Lu à la suite du morceau en cours.',
                action: async () => { if (await radioAction('queue', { url: radioUi.url, volume: radioUi.volume })) { radioUi.url = ''; rerender(); } } },
            { kind: 'section', label: 'Morceau en cours' },
            { kind: 'button', label: radio && radio.paused ? 'Reprendre' : 'Pause', ...ctl(off(radio, 'Radio éteinte.')), action: () => radioAction('pause') },
            { kind: 'button', label: 'Début du morceau', ...ctl(off(radio, 'Radio éteinte.')),
                desc: 'Appuyez deux fois : morceau précédent.',
                action: () => {
                    const now = Date.now();
                    const double = now - radioRestartAt < RADIO_DOUBLE_MS;
                    radioRestartAt = double ? 0 : now;
                    radioAction(double ? 'previous' : 'restart');
                } },
            { kind: 'button', label: 'Morceau suivant', ...ctl(off(radio, 'Radio éteinte.')), action: () => radioAction('next') },
            { kind: 'button', label: 'Arrêter la radio', danger: true, ...ctl(off(radio, 'Radio éteinte.')), desc: 'Vide aussi la file « Écouter ensuite ».', action: () => radioAction('stop') },
            { kind: 'list', label: 'Volume du véhicule', options: RADIO_VOLUMES, index: Math.round(radioUi.volume / 5), clamp: true, ...ctl(),
                desc: '← → : régler (pour tout le monde).',
                onChange: (i) => {
                    radioUi.volume = i * 5;
                    clearTimeout(radioUi.volumeTimer);
                    if (radio) radioUi.volumeTimer = setTimeout(() => radioAction('volume', { volume: radioUi.volume }), 350);
                } },
            { kind: 'section', label: `Écouter ensuite (${queue.length} / ${RADIO_QUEUE_MAX})` },
        ];
        if (!queue.length) items.push({ kind: 'info', label: 'Aucun morceau en attente.', tone: 'muted' });
        queue.forEach((url, i) => items.push({ kind: 'button', label: url, right: `${i + 1}`, ...ctl(),
            desc: 'Entrée : retirer de la file.', action: () => radioAction('unqueue', { index: i + 1 }) }));
        return items;
    }

    function radioPage() {
        return {
            id: 'radio', title: 'Radio',
            banner: () => ({ title: 'Radio', sub: (radioUi.info && radioUi.info.vehicle) || 'Radio du véhicule', color: MENU_COLORS.car }),
            onEnter: () => { radioUi.info = null; loadRadio(); },
            items: radioItems,
        };
    }

    // Pages ouvertes directement (ex. 'radio' depuis l'œil) : le chemin, pour que Retour arrière remonte
    const MENU_PATHS = { radio: [carPage, radioPage], spawn: [carPage, spawnPage], police: [policePage], civil: [civilPage], equipment: [equipmentPage] };
    const SECTION_OF = { radio: 'car', spawn: 'car', equipment: 'equipment' };

    function menuPages(view) {
        const pages = [homePage()];
        if (!MENU_PATHS[view]) return pages;
        if (isLocked(SECTION_OF[view])) {
            toast(LOCKED_TEXT, 'error');
            return pages;
        }
        return pages.concat(MENU_PATHS[view].map((fn) => fn()));
    }

    function setMenu(data) {
        if (!data.open) {
            interact.stop();
            return;
        }
        menu.data = data;
        Object.keys(actions).forEach((k) => delete actions[k]);
        interact.start(menuPages(data.view));
    }

    // Déjà ouvert : l'œil (Radio) l'amène sur une page
    function menuGo(view) {
        if (!interact.open || menuOn(view)) return;
        interact.start(menuPages(view));
    }

    // ---- Lecteurs de la radio des véhicules (client/radio.lua) ----
    // Lecture telle quelle, sans effet : lecteur YouTube (lien YouTube) ou lecteur audio (lien direct).
    // Le volume (distance, vitres / portières) est calculé par client/radio.lua. À la fin d'un morceau,
    // le serveur est prévenu ("radioEnded") et lance le suivant de la file pour tout le monde.
    const radios = {};
    let ytReady = null;

    function youtubeId(url) {
        const m = String(url).match(/(?:youtube\.com\/(?:watch\?(?:.*&)?v=|shorts\/|live\/|embed\/)|youtu\.be\/|music\.youtube\.com\/watch\?(?:.*&)?v=)([\w-]{11})/);
        return m ? m[1] : null;
    }

    function loadYouTube() {
        if (!ytReady) {
            ytReady = new Promise((resolve) => {
                window.onYouTubeIframeAPIReady = () => resolve(window.YT);
                const tag = document.createElement('script');
                tag.src = 'https://www.youtube.com/iframe_api';
                document.head.appendChild(tag);
            });
        }
        return ytReady;
    }

    function applyRadio(r) {
        const v = Math.min(Math.max(r.volume, 0), 1);
        if (r.player && r.player.setVolume) r.player.setVolume(Math.round(v * 100));
        if (r.audio) r.audio.volume = v;
    }

    /** Fin du morceau : une seule fois par morceau (même "start") */
    function radioEnded(r) {
        if (r.dead || r.endedSent) return;
        r.endedSent = true;
        post('radioEnded', { id: r.id, seq: r.seq });
    }

    function playYouTube(r, id) {
        const slot = document.createElement('div');
        r.holder.appendChild(slot);
        loadYouTube().then((YT) => {
            if (r.dead) return;
            r.player = new YT.Player(slot, {
                width: 200, height: 200, videoId: id,
                playerVars: { autoplay: 1, controls: 0, start: Math.floor(r.offset || 0), playsinline: 1 },
                events: {
                    onReady: (e) => {
                        applyRadio(r);
                        e.target.seekTo(Math.floor(r.offset || 0), true);
                        if (r.paused) e.target.pauseVideo(); else e.target.playVideo();
                    },
                    onStateChange: (e) => { if (e.data === 0) radioEnded(r); }, // 0 : vidéo terminée
                    onError: () => radioEnded(r), // vidéo indisponible : morceau suivant
                },
            });
        });
    }

    function playAudio(r, url) {
        const audio = new Audio(url);
        audio.addEventListener('loadedmetadata', () => {
            if (Number.isFinite(audio.duration) && r.offset < audio.duration) audio.currentTime = r.offset;
            else if (Number.isFinite(audio.duration) && r.offset >= audio.duration) radioEnded(r); // déjà fini
        }, { once: true });
        audio.addEventListener('ended', () => radioEnded(r));
        r.audio = audio;
        applyRadio(r);
        if (!r.paused) audio.play().catch(() => {});
    }

    function createRadio(d) {
        const r = { id: d.id, url: d.url, seq: d.seq, volume: d.volume, offset: d.offset, paused: !!d.paused };
        r.holder = document.createElement('div');
        r.holder.className = 'radio-player';
        $('#radioPlayers').appendChild(r.holder);
        const id = youtubeId(d.url);
        if (id) playYouTube(r, id); else playAudio(r, d.url);
        return r;
    }

    /** Pause / reprise : à la reprise, même position pour tout le monde (calculée par client/radio.lua) */
    function setRadioPaused(r, paused, offset) {
        r.paused = paused;
        if (r.player && r.player.pauseVideo) {
            if (paused) r.player.pauseVideo();
            else { r.player.seekTo(Math.floor(offset || 0), true); r.player.playVideo(); }
        }
        if (r.audio) {
            if (paused) r.audio.pause();
            else {
                if (Number.isFinite(r.audio.duration) && offset < r.audio.duration) r.audio.currentTime = offset;
                r.audio.play().catch(() => {});
            }
        }
    }

    function radioStop(id) {
        const r = radios[id];
        if (!r) return;
        r.dead = true;
        try { if (r.player && r.player.destroy) r.player.destroy(); } catch (err) { /* déjà fermé */ }
        if (r.audio) { r.audio.pause(); r.audio.removeAttribute('src'); r.audio.load(); }
        r.holder.remove();
        delete radios[id];
    }

    function radioUpdate(d) {
        if (!d || !d.id) return;
        let r = radios[d.id];
        if (r && (r.url !== d.url || r.seq !== d.seq)) { radioStop(d.id); r = null; }
        const created = !r;
        if (!r) radios[d.id] = r = createRadio(d);
        r.volume = Number(d.volume) || 0;
        r.offset = d.offset;
        applyRadio(r);
        if (!created && r.paused !== !!d.paused) setRadioPaused(r, !!d.paused, d.offset);
        if (!created && menuOn('radio') && r.pausedShown !== r.paused) loadRadio();
        r.pausedShown = r.paused;
        if (created && menuOn('radio')) loadRadio(); // morceau suivant : page Radio à jour
    }

    // ---- Barre de chargement (fouilles, menottes) ----
    const progress = { timer: null };

    // Se débattre : jauge du civil (value 0..100) ; policier : « L'individu se débat ! » quelques instants
    const struggleState = { timer: null };
    function setStruggle(data) {
        const box = $('#struggle');
        clearTimeout(struggleState.timer);
        if (!data.show) {
            box.classList.add('hidden');
            return;
        }
        const police = data.role === 'police';
        box.classList.toggle('police', police);
        $('#struggleLabel').textContent = police ? 'L\'individu se débat !' : 'Se débattre';
        $('#struggleHint').classList.toggle('hidden', police);
        if (!police) {
            $('#struggleKey').textContent = data.key || 'ESPACE';
            $('#struggleBar').style.width = `${Math.max(0, Math.min(100, Number(data.value) || 0))}%`;
        } else {
            $('#struggleBar').style.width = '';
            struggleState.timer = setTimeout(() => box.classList.add('hidden'), Number(data.until_) || 1200);
        }
        box.classList.remove('hidden');
    }

    function setProgress(data) {
        const box = $('#progress');
        const bar = $('#progressBar');
        clearInterval(progress.timer);
        if (!data.show) {
            box.classList.add('hidden');
            return;
        }
        const duration = Math.max(Number(data.duration) || 0, 1);
        const endsAt = Date.now() + duration;
        $('#progressLabel').textContent = data.label || '';
        bar.style.transition = 'none';
        bar.style.width = '0%';
        box.classList.remove('hidden');
        void bar.offsetWidth; // relance la transition depuis 0
        bar.style.transition = `width ${duration}ms linear`;
        bar.style.width = '100%';
        const tick = () => { $('#progressTime').textContent = `${Math.max(0, Math.ceil((endsAt - Date.now()) / 1000))} s`; };
        tick();
        progress.timer = setInterval(tick, 250);
    }

    // ---- Odeur détectée (policier en service, à côté d'un civil / d'un véhicule) ----
    let smellTimer = null; let smellHide = null; let smellAudio = null;
    /** Court son discret (deux notes douces qui montent), généré ici : comme l'entrée dans une zone de recherche */
    function smellSound(volume) {
        try {
            smellAudio = smellAudio || new (window.AudioContext || window.webkitAudioContext)();
            const ac = smellAudio; const t = ac.currentTime + 0.02;
            const v = Math.max(0, Math.min(1, Number(volume) || 0.4));
            [[392.0, 0], [523.25, 0.16]].forEach(([f, at]) => {
                const o = ac.createOscillator(); const g = ac.createGain();
                o.type = 'triangle'; o.frequency.value = f;
                g.gain.setValueAtTime(0.0001, t + at);
                g.gain.exponentialRampToValueAtTime(0.18 * v, t + at + 0.03);
                g.gain.exponentialRampToValueAtTime(0.0001, t + at + 0.7);
                o.connect(g); g.connect(ac.destination); o.start(t + at); o.stop(t + at + 0.75);
            });
        } catch (err) { /* son indisponible */ }
    }
    function setSmell(data) {
        const box = $('#smell');
        clearTimeout(smellTimer); clearTimeout(smellHide);
        if (!data.show) {
            if (!box.classList.contains('hidden')) {
                box.classList.add('out');
                smellHide = setTimeout(() => box.classList.add('hidden'), 360);
            }
            return;
        }
        $('#smellLabel').textContent = data.label || '';
        $('#smellText').innerHTML = toArray(data.lines).map((l) => `<div>${esc(l)}</div>`).join('');
        box.classList.remove('out', 'hidden');
        void box.offsetWidth;
        smellSound(data.volume);
        smellTimer = setTimeout(() => setSmell({ show: false }), Math.max(2000, Number(data.duration) || 9000));
    }

    // ---- Tips d'arrestation (mode civil) ----
    function setTips(data) {
        const box = $('#tips');
        box.classList.toggle('hidden', !data.show);
        if (!data.show) return;
        box.classList.toggle('aimed', !!data.aimed);
        $('#tipsTitle').textContent = data.aimed ? 'Un policier vous tient en joue' : 'Tips arrestation';
        $('#tipsKeys').innerHTML = toArray(data.keys).map((k) => `
            <span class="tips-key ${k.stop ? 'stop' : ''}"><kbd>${esc(k.key)}</kbd>${esc(k.label)}</span>`).join('');
    }

    // =====================================================================
    // FICHE CIVILE
    // =====================================================================
    const ed = {
        open: false,
        tab: 'profiles',
        profiles: [],
        max: 20,
        selected: null,      // id du profil affiché
        mode: 'empty',       // empty | view | form
        draft: null,
        confirmDelete: false,
        vehicle: null,       // { netId, label, plate, profile, taken }
        vdraft: null,
        vconfirm: false,
        smells: [],          // odeurs détectées automatiquement (config.lua : Smells)
        smellMax: 2,
        smellsEnabled: true,
    };

    const PROFILE_PARTS = [
        { key: 'visual', label: 'Visuel', defaults: 'visual', ph: 'Ce que l\'on voit : vêtements tachés, blessure, comportement…' },
        { key: 'olfactory', label: 'Olfactif', defaults: 'olfactory', ph: 'Ce que l\'on sent : alcool, cannabis, essence…' },
        { key: 'upper', label: 'Partie supérieure du corps', defaults: 'search', ph: 'Poches de veste, ceinture, sous les bras…' },
        { key: 'lower', label: 'Partie inférieure du corps', defaults: 'search', ph: 'Poches de pantalon, chaussettes, chevilles…' },
    ];

    const emptyProfile = () => ({
        id: null, name: '', notable: '',
        visualKnown: false, visual: '', olfactoryKnown: false, olfactory: '',
        upperKnown: false, upper: '', lowerKnown: false, lower: '', smells: [],
    });
    const emptyVehicle = () => ({
        visualKnown: false, interior: '', exterior: '', olfactory: '', notable: '', cabin: '', rear: '', trunk: '', smells: [],
    });

    // ---- Odeurs détectées automatiquement (2 au plus) ----
    const smellLabel = (id) => (ed.smells.find((x) => x.id === id) || {}).label || id;
    const smellText = (list) => toArray(list).map(smellLabel).join(' + ');

    function smellsHtml(d, who) {
        if (!ed.smellsEnabled || !ed.smells.length) return '';
        const chosen = toArray(d.smells);
        const full = chosen.length >= ed.smellMax;
        const groups = [];
        ed.smells.forEach((s) => {
            let g = groups.find((x) => x.name === s.group);
            if (!g) { g = { name: s.group || 'Autres', list: [] }; groups.push(g); }
            g.list.push(s);
        });
        return `
            <div class="form-part">
                <span class="form-section-title">Odeur détectée automatiquement <span class="smell-count">${chosen.length}/${ed.smellMax}</span></span>
                <div class="form-section-desc">Facultatif. Un policier en service qui passe à moins de 6 m ${who} la sent tout de suite (notification) ; elle s'ajoute aussi à l'inspection olfactive. ${ed.smellMax} odeurs au plus, combinables.</div>
                <div class="smell-groups">${groups.map((g) => `
                    <div><div class="smell-group-title">${esc(g.name)}</div><div class="smell-chips">${g.list.map((s) => {
                        const on = chosen.includes(s.id);
                        return `<button type="button" class="smell-chip ${on ? 'on' : ''}" data-smell="${esc(s.id)}" ${!on && full ? 'disabled' : ''}>${esc(s.label)}</button>`;
                    }).join('')}</div></div>`).join('')}
                </div>
            </div>`;
    }

    /** Clic sur une odeur : ajoutée / retirée (2 au plus), formulaire redessiné sans perdre la saisie */
    function bindSmells(container, getDraft, rerender) {
        container.addEventListener('click', (e) => {
            const chip = e.target.closest('[data-smell]');
            const d = getDraft();
            if (!chip || !d) return;
            const id = chip.dataset.smell;
            const list = toArray(d.smells).slice();
            const i = list.indexOf(id);
            if (i >= 0) list.splice(i, 1);
            else if (list.length < ed.smellMax) list.push(id);
            d.smells = list;
            const scroll = container.scrollTop;
            rerender();
            container.scrollTop = scroll;
        });
    }

    const valueOrDefault = (text, defaults) => (text
        ? esc(text)
        : `<span class="default-text">${esc(DEFAULTS[defaults])}</span>`);

    // ---- Onglets ----
    function setTab(tab) {
        ed.tab = tab;
        $$('#editor .tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === tab));
        $$('#editor .page').forEach((p) => p.classList.toggle('hidden', p.dataset.page !== tab));
        $('#editorStatus').textContent = tab === 'profiles'
            ? 'Profils enregistrés de façon permanente (vous seul les voyez). Le profil actif est celui que la police découvre.'
            : 'Profil de véhicule temporaire : lié au véhicule, supprimé avec lui ou au redémarrage du serveur.';
        if (tab === 'vehicle') renderVehicle();
    }

    $$('#editor .tab').forEach((t) => t.addEventListener('click', async () => {
        if (t.dataset.tab === 'vehicle' && !ed.vehicle) await findVehicle();
        setTab(t.dataset.tab);
    }));

    // ---- Liste des profils ----
    function renderProfileList() {
        const list = ed.profiles;
        $('#profileCount').textContent = `(${list.length}/${ed.max})`;
        $('#profileEmpty').classList.toggle('hidden', list.length > 0);
        $('#profileBody').innerHTML = list.map((p) => `
            <tr data-id="${esc(p.id)}" class="${p.id === ed.selected ? 'selected' : ''}">
                <td class="name"><b>${esc(p.name)}</b></td>
                <td>${p.active ? '<span class="flag c-green">Actif</span>' : '<span class="flag c-gray">—</span>'}</td>
                <td>${esc(formatDate(p.updatedAt || p.createdAt))}</td>
            </tr>`).join('');
        $('#newProfile').disabled = list.length >= ed.max;
    }

    async function refreshProfiles() {
        const res = await post('getProfiles');
        if (res && res.ok) {
            ed.profiles = toArray(res.profiles);
            ed.max = res.max || ed.max;
        }
        renderProfileList();
    }

    $('#profileBody').addEventListener('click', (e) => {
        const tr = e.target.closest('tr[data-id]');
        if (!tr) return;
        ed.selected = Number(tr.dataset.id);
        ed.mode = 'view';
        ed.confirmDelete = false;
        renderProfileList();
        renderProfilePanel();
    });

    $('#newProfile').addEventListener('click', () => openProfileForm(emptyProfile()));

    function openProfileForm(draft) {
        ed.draft = draft;
        ed.mode = 'form';
        if (!draft.id) ed.selected = null;
        renderProfileList();
        renderProfilePanel();
        const name = $('#profileDetail [data-k="name"]');
        if (name) name.focus();
    }

    // ---- Détail / formulaire d'un profil ----
    function profileViewHtml(p) {
        const parts = (keys) => keys.map((k) => {
            const part = PROFILE_PARTS.find((x) => x.key === k);
            return `<dt>${esc(part.label)}</dt><dd>${valueOrDefault(p[`${k}Known`] ? p[k] : '', part.defaults)}</dd>`;
        }).join('');
        return `
            <div class="sheet-title">
                <span>${esc(p.name)} ${p.active ? '<span class="flag c-green">Actif</span>' : ''}</span>
                <span class="sheet-actions">
                    ${p.active
                        ? '<button type="button" class="btn btn-small" data-act="deactivate">Désactiver</button>'
                        : '<button type="button" class="btn btn-small btn-default" data-act="activate">Définir comme profil actif</button>'}
                    <button type="button" class="btn btn-small" data-act="edit">Modifier</button>
                    <button type="button" class="btn btn-small btn-danger ${ed.confirmDelete ? 'confirm' : ''}" data-act="delete">${ed.confirmDelete ? 'Confirmer ?' : 'Supprimer'}</button>
                </span>
            </div>
            <div class="sheet-sub">Inspection <small>Observations visuelles et olfactives</small></div>
            <dl class="sheet">${parts(['visual', 'olfactory'])}${ed.smellsEnabled ? `<dt>Odeur détectée automatiquement</dt><dd>${toArray(p.smells).length ? esc(smellText(p.smells)) : '<span class="default-text">Aucune</span>'}</dd>` : ''}</dl>
            <div class="sheet-sub">Fouille <small>Contenu de ce que détient votre personnage</small></div>
            <dl class="sheet">${parts(['upper', 'lower'])}</dl>
            <div class="sheet-sub">Détail notoire</div>
            <dl class="sheet"><dt>Détail notoire</dt><dd>${valueOrDefault(p.notable, 'notable')}</dd></dl>
            ${p.active ? '' : '<div class="note">Ce profil n\'est pas actif : la police découvre uniquement votre profil actif.</div>'}`;
    }

    const partForm = (d, part) => `
        <div class="form-part">
            <label class="check"><input type="checkbox" data-k="${part.key}Known" ${d[`${part.key}Known`] ? 'checked' : ''}> ${esc(part.label)}</label>
            <textarea data-k="${part.key}" rows="3" maxlength="1000" placeholder="${esc(part.ph)}" class="${d[`${part.key}Known`] ? '' : 'hidden'}">${esc(d[part.key])}</textarea>
            <div class="part-default ${d[`${part.key}Known`] ? 'hidden' : ''}">Non coché : « ${esc(DEFAULTS[part.defaults])} »</div>
        </div>`;

    function profileFormHtml(d) {
        return `
            <label class="lbl">Nom du profil *
                <input type="text" data-k="name" maxlength="40" value="${esc(d.name)}" placeholder="ex : Livreur nerveux, Sortie de bar…">
            </label>
            <div class="form-section">
                <span class="form-section-title">Inspection</span>
                <div class="form-section-desc">Observations visuelles et olfactives</div>
                ${partForm(d, PROFILE_PARTS[0])}
                ${partForm(d, PROFILE_PARTS[1])}
                ${smellsHtml(d, 'de vous')}
            </div>
            <div class="form-section">
                <span class="form-section-title">Fouille</span>
                <div class="form-section-desc">Contenu de ce que détient votre personnage</div>
                ${partForm(d, PROFILE_PARTS[2])}
                ${partForm(d, PROFILE_PARTS[3])}
            </div>
            <div class="form-section">
                <span class="form-section-title">Détail notoire</span>
                <div class="form-section-desc">Facultatif : éléments importants à prendre en compte</div>
                <textarea data-k="notable" rows="4" maxlength="1000" placeholder="ex : tatouage de gang sur la main, très agité, cherche à fuir…">${esc(d.notable)}</textarea>
            </div>
            <div class="form-actions">
                <button type="button" class="btn" data-act="cancel">Annuler</button>
                <button type="button" class="btn btn-default" data-act="save">Enregistrer</button>
            </div>`;
    }

    function renderProfilePanel() {
        const el = $('#profileDetail');
        const p = ed.profiles.find((x) => x.id === ed.selected);
        if (ed.mode === 'form' && ed.draft) {
            $('#profilePanelTitle').textContent = ed.draft.id ? 'Modifier le profil' : 'Nouveau profil';
            el.innerHTML = profileFormHtml(ed.draft);
        } else if (ed.mode === 'view' && p) {
            $('#profilePanelTitle').textContent = 'Profil';
            el.innerHTML = profileViewHtml(p);
        } else {
            $('#profilePanelTitle').textContent = 'Profil';
            el.innerHTML = '<div class="empty">Sélectionnez un profil, ou créez-en un.</div>';
        }
        el.scrollTop = 0;
    }

    // Saisie : texte et cases (les cases affichent / masquent leur zone de texte)
    function bindDraft(container, getDraft) {
        container.addEventListener('input', (e) => {
            const k = e.target.dataset && e.target.dataset.k;
            const d = getDraft();
            if (!k || !d) return;
            if (e.target.type === 'checkbox') {
                d[k] = e.target.checked;
                const part = e.target.closest('.form-part');
                if (part) {
                    part.querySelectorAll('textarea, .part-default, .part-fields').forEach((x) => {
                        const show = x.classList.contains('part-default') ? !e.target.checked : e.target.checked;
                        x.classList.toggle('hidden', !show);
                    });
                    if (e.target.checked) {
                        const first = part.querySelector('textarea');
                        if (first) first.focus();
                    }
                }
            } else {
                d[k] = e.target.value;
            }
        });
    }
    bindDraft($('#profileDetail'), () => ed.draft);
    bindSmells($('#profileDetail'), () => (ed.mode === 'form' ? ed.draft : null), () => renderProfilePanel());

    $('#profileDetail').addEventListener('click', async (e) => {
        const btn = e.target.closest('[data-act]');
        if (!btn) return;
        const act = btn.dataset.act;
        const p = ed.profiles.find((x) => x.id === ed.selected);

        if (act === 'cancel') {
            ed.mode = ed.draft && ed.draft.id ? 'view' : 'empty';
            ed.draft = null;
            renderProfilePanel();
        } else if (act === 'save') {
            const d = ed.draft;
            if (!d.name.trim()) {
                toast('Donnez un nom au profil.', 'error');
                return;
            }
            btn.disabled = true;
            const res = await post('saveProfile', d);
            btn.disabled = false;
            if (!res || !res.ok) {
                toast(res?.error || 'Enregistrement impossible.', 'error');
                return;
            }
            toast(res.active && !d.id ? 'Profil enregistré et défini comme profil actif.' : 'Profil enregistré.', 'success');
            ed.selected = res.id;
            ed.mode = 'view';
            ed.draft = null;
            await refreshProfiles();
            renderProfilePanel();
        } else if (act === 'edit' && p) {
            openProfileForm({ ...emptyProfile(), ...p });
        } else if ((act === 'activate' || act === 'deactivate') && p) {
            const res = await post('setActive', act === 'activate' ? { id: p.id } : {});
            if (!res || !res.ok) {
                toast(res?.error || 'Modification impossible.', 'error');
                return;
            }
            toast(act === 'activate' ? `Profil actif : ${p.name}` : 'Plus aucun profil actif.', 'success');
            await refreshProfiles();
            renderProfilePanel();
        } else if (act === 'delete' && p) {
            if (!ed.confirmDelete) {
                ed.confirmDelete = true;
                renderProfilePanel();
                setTimeout(() => {
                    if (ed.confirmDelete) {
                        ed.confirmDelete = false;
                        if (ed.mode === 'view') renderProfilePanel();
                    }
                }, 3500);
                return;
            }
            ed.confirmDelete = false;
            const res = await post('deleteProfile', { id: p.id });
            if (!res || !res.ok) {
                toast(res?.error || 'Suppression impossible.', 'error');
                return;
            }
            toast('Profil supprimé.', 'success');
            ed.selected = null;
            ed.mode = 'empty';
            await refreshProfiles();
            renderProfilePanel();
        }
    });

    // ---- Véhicule ----
    async function findVehicle() {
        const res = await post('findVehicle');
        if (res && res.ok) {
            setVehicle(res.vehicle);
        } else {
            ed.vehicle = null;
            toast(res?.error || 'Aucun véhicule à proximité.', 'error');
        }
    }

    function setVehicle(vehicle) {
        ed.vehicle = vehicle || null;
        ed.vdraft = vehicle ? { ...emptyVehicle(), ...(vehicle.profile || {}) } : null;
        ed.vconfirm = false;
    }

    function vehicleFormHtml(v, d) {
        const area = (k, label, ph, rows = 3) => `
            <label class="lbl">${esc(label)}<textarea data-k="${k}" rows="${rows}" maxlength="1000" placeholder="${esc(ph)}">${esc(d[k])}</textarea></label>`;
        return `
            <div class="sheet-title">
                <span>${esc(v.label || 'Véhicule')} ${v.plate ? `— ${esc(v.plate)}` : ''} ${v.profile ? '<span class="flag c-green">Profil appliqué</span>' : ''}</span>
                <span class="sheet-actions"><button type="button" class="btn btn-small" data-act="vfind">Autre véhicule</button></span>
            </div>
            <div class="form-section">
                <span class="form-section-title">Inspection visuelle</span>
                <div class="form-part">
                    <label class="check"><input type="checkbox" data-k="visualKnown" ${d.visualKnown ? 'checked' : ''}> Éléments visibles</label>
                    <div class="two-cols part-fields ${d.visualKnown ? '' : 'hidden'}">
                        ${area('interior', 'Intérieur', 'ex : sièges tachés de sang, sachets vides au sol…')}
                        ${area('exterior', 'Extérieur', 'ex : pare-chocs enfoncé, impacts de balles…')}
                    </div>
                    <div class="part-default ${d.visualKnown ? 'hidden' : ''}">Non coché : « ${esc(DEFAULTS.vehicleVisual)} »</div>
                </div>
            </div>
            <div class="form-section">
                <span class="form-section-title">Inspection olfactive</span>
                <textarea data-k="olfactory" rows="2" maxlength="1000" placeholder="Vide : « ${esc(DEFAULTS.vehicleOlfactory)} »">${esc(d.olfactory)}</textarea>
                ${smellsHtml(d, 'du véhicule')}
            </div>
            <div class="form-section">
                <span class="form-section-title">Détail notoire</span>
                <div class="form-section-desc">Facultatif : éléments importants à prendre en compte</div>
                <textarea data-k="notable" rows="3" maxlength="1000" placeholder="Vide : « ${esc(DEFAULTS.notable)} »">${esc(d.notable)}</textarea>
            </div>
            <div class="form-section">
                <span class="form-section-title">Fouille du véhicule</span>
                <div class="form-section-desc">Facultatif. Vide : « ${esc(DEFAULTS.vehicleSearch)} »</div>
                ${area('cabin', 'Habitacle', 'Boîte à gants, vide-poches, sous les sièges avant…', 2)}
                ${area('rear', 'Banquette arrière', 'Sièges et plancher arrière…', 2)}
                ${area('trunk', 'Coffre', 'Contenu du coffre…', 2)}
            </div>
            <div class="note">Ce profil est lié à ce véhicule : il disparaît avec lui (ou au redémarrage du serveur)
                et n'est pas conservé dans vos profils.</div>
            <div class="form-actions">
                ${v.profile ? `<button type="button" class="btn btn-danger ${ed.vconfirm ? 'confirm' : ''}" data-act="vdelete">${ed.vconfirm ? 'Confirmer ?' : 'Supprimer le profil du véhicule'}</button>` : ''}
                <span class="grow"></span>
                <button type="button" class="btn btn-default" data-act="vsave">${v.profile ? 'Mettre à jour le véhicule' : 'Appliquer au véhicule'}</button>
            </div>`;
    }

    function renderVehicle() {
        const el = $('#vehicleDetail');
        const v = ed.vehicle;
        $('#vehicleTitle').textContent = v ? 'Profil du véhicule' : 'Véhicule';
        if (!v) {
            el.innerHTML = `<div class="empty">Aucun véhicule : montez dans le véhicule ou placez-vous juste à côté.
                <br><br><button type="button" class="btn" data-act="vfind">Rechercher le véhicule</button></div>`;
        } else if (v.taken) {
            el.innerHTML = `<div class="sheet-title"><span>${esc(v.label)} ${v.plate ? `— ${esc(v.plate)}` : ''}</span>
                <span class="sheet-actions"><button type="button" class="btn btn-small" data-act="vfind">Autre véhicule</button></span></div>
                <div class="empty">Ce véhicule a déjà un profil, créé par un autre joueur.</div>`;
        } else {
            el.innerHTML = vehicleFormHtml(v, ed.vdraft);
        }
    }

    bindDraft($('#vehicleDetail'), () => ed.vdraft);
    bindSmells($('#vehicleDetail'), () => ed.vdraft, () => renderVehicle());

    $('#vehicleDetail').addEventListener('click', async (e) => {
        const btn = e.target.closest('[data-act]');
        if (!btn) return;
        const act = btn.dataset.act;
        const v = ed.vehicle;
        if (act === 'vfind') {
            await findVehicle();
            renderVehicle();
        } else if (act === 'vsave' && v) {
            const d = ed.vdraft;
            if (d.visualKnown && !d.interior.trim() && !d.exterior.trim()) {
                toast('Inspection visuelle : remplissez l\'intérieur et / ou l\'extérieur (ou décochez la case).', 'error');
                return;
            }
            btn.disabled = true;
            const res = await post('saveVehicleProfile', { ...d, netId: v.netId, label: v.label, plate: v.plate });
            btn.disabled = false;
            if (!res || !res.ok) {
                toast(res?.error || 'Enregistrement impossible.', 'error');
                return;
            }
            toast(v.profile ? 'Profil du véhicule mis à jour.' : 'Profil appliqué au véhicule.', 'success');
            v.profile = { ...d };
            renderVehicle();
        } else if (act === 'vdelete' && v) {
            if (!ed.vconfirm) {
                ed.vconfirm = true;
                renderVehicle();
                setTimeout(() => {
                    if (ed.vconfirm) {
                        ed.vconfirm = false;
                        if (ed.tab === 'vehicle') renderVehicle();
                    }
                }, 3500);
                return;
            }
            ed.vconfirm = false;
            const res = await post('deleteVehicleProfile', { netId: v.netId });
            if (!res || !res.ok) {
                toast(res?.error || 'Suppression impossible.', 'error');
                return;
            }
            toast('Profil du véhicule supprimé.', 'success');
            v.profile = null;
            ed.vdraft = emptyVehicle();
            renderVehicle();
        }
    });

    // ---- Ouverture / fermeture ----
    function setEditor(data) {
        ed.open = !!data.open;
        $('#editor').classList.toggle('hidden', !ed.open);
        if (!ed.open) return;
        const profiles = data.profiles || {};
        ed.profiles = toArray(profiles.profiles);
        ed.max = profiles.max || ed.max;
        ed.smells = toArray(data.smells);
        ed.smellMax = Number(data.smellMax) || 2;
        ed.smellsEnabled = data.smellsEnabled !== false;
        if (data.vehicle) setVehicle(data.vehicle);
        ed.selected = null;
        ed.mode = 'empty';
        ed.draft = null;
        centerEditor();
        renderProfileList();
        if (data.view === 'vehicle') {
            setTab('vehicle');
        } else {
            setTab('profiles');
            openProfileForm(emptyProfile()); // "Créer un profil" : formulaire vide prêt à remplir
        }
    }

    function centerEditor() {
        const win = $('#editor');
        const w = Math.min(980, innerWidth * 0.96);
        const h = Math.min(640, innerHeight * 0.94);
        win.style.left = `${Math.round((innerWidth - w) / 2)}px`;
        win.style.top = `${Math.round((innerHeight - h) / 2)}px`;
    }

    $('#editorClose').addEventListener('click', () => post('closeEditor'));

    // Déplacement de la fenêtre (barre de titre)
    let drag = null;
    $('#editorBar').addEventListener('mousedown', (e) => {
        if (e.target.closest('button')) return;
        const win = $('#editor');
        drag = { x: e.clientX - win.offsetLeft, y: e.clientY - win.offsetTop };
    });
    document.addEventListener('mousemove', (e) => {
        if (!drag) return;
        const win = $('#editor');
        win.style.left = `${Math.min(Math.max(e.clientX - drag.x, 0), innerWidth - 120)}px`;
        win.style.top = `${Math.min(Math.max(e.clientY - drag.y, 0), innerHeight - 40)}px`;
    });
    document.addEventListener('mouseup', () => { drag = null; });

    // Échap : liste de l'œil, puis fiche (les menus au clavier reçoivent Échap par client/kbmenu.lua)
    document.addEventListener('keydown', (e) => {
        if (e.key !== 'Escape') return;
        if (eye.menu) {
            eye.menu = false;
            post('eyeCancel');
        } else if (ed.open) {
            post('closeEditor');
        }
    });

    // =====================================================================
    // MENU DES TENUES /eup (au clavier, même menu que le Menu Interaction : touches lues par client/kbmenu.lua)
    // Polices du MDC : Washington State Patrol (WSP), King County Sheriff Office (KCSO), puis les autres
    // polices trouvées dans data/outfits.json ; Civil.
    // =====================================================================
    const EUP_POLICES = [
        { code: 'WSP', name: 'Washington State Patrol', color: AGENCY_COLORS.wsp },
        { code: 'KCSO', name: 'King County Sheriff Office', color: AGENCY_COLORS.kcso },
    ];
    const EUP_COLORS = { root: '#2f5ea8', civil: '#6a4fa0', other: '#4d5d80' };
    const eup = { outfits: [], policeLocked: false, worn: null, mods: [], service: 'Civil', wornName: null, modService: null, modWorn: new Set() };

    const eupMenu = new KbMenu($('#eup'), 'eup', { icon: KB_ICONS.eup, close: () => post('eupClose') });

    function eupOutfitPage(title, list, banner) {
        return {
            id: 'outfits', title, banner,
            items: () => (list.length ? list.map((o) => ({
                kind: 'button', label: o.name, mark: o.index === eup.worn, desc: 'Entrée : mettre cette tenue.',
                action: () => {
                    eup.worn = o.index;
                    post('eupWear', { index: o.index });
                },
            })) : [{ kind: 'info', label: 'Aucune tenue pour ce personnage (data/outfits.json).', tone: 'muted' }]),
        };
    }

    function eupPoliceGroups() {
        const police = eup.outfits.filter((o) => o.cate === 'police');
        const groups = EUP_POLICES.map((s) => ({ ...s, list: police.filter((o) => o.group === s.code) }));
        const known = new Set(EUP_POLICES.map((s) => s.code));
        [...new Set(police.map((o) => o.group || 'Autres').filter((g) => !known.has(g)))].sort()
            .forEach((g) => groups.push({ code: g, name: g, color: EUP_COLORS.other, list: police.filter((o) => (o.group || 'Autres') === g) }));
        return groups.filter((g) => g.list.length || known.has(g.code));
    }

    function eupCivilPage() {
        const civil = eup.outfits.filter((o) => o.cate !== 'police');
        const groupOf = (o) => (o.group && o.group.toLowerCase() !== 'civil' ? o.group : '');
        const groups = [...new Set(civil.map(groupOf).filter(Boolean))].sort();
        const banner = { title: 'Civil', sub: plural(civil.length, 'tenue'), color: EUP_COLORS.civil };
        if (!groups.length) return eupOutfitPage('Civil', civil, banner);
        if (civil.some((o) => !groupOf(o))) groups.push('');
        return {
            id: 'civil', title: 'Civil', banner,
            items: groups.map((g) => {
                const list = civil.filter((o) => groupOf(o) === g);
                return { kind: 'menu', label: g || 'Autres', right: `${list.length}`,
                    open: () => eupOutfitPage(g || 'Autres', list, { title: g || 'Autres', sub: 'Civil', color: EUP_COLORS.civil }) };
            }),
        };
    }

    // ---- Modifier ma tenue : pièces de data/modifoutfits.json du service de la tenue mise (+ "Tous") ----
    const eupServiceName = (code) => (EUP_POLICES.find((p) => p.code === code) || {}).name || (code === 'Civil' ? 'Civil' : code);
    const eupServiceColor = (code) => (code === 'Civil' ? EUP_COLORS.civil : agencyColor(code) || EUP_COLORS.other);

    /** Services proposés : WSP, KCSO, autres polices du fichier, Civil (et celui de la tenue mise) */
    function eupModServices() {
        const found = new Set(eup.mods.map((m) => m.service).filter((s) => s && s !== 'Tous'));
        found.add(eup.service || 'Civil');
        const order = [...EUP_POLICES.map((p) => p.code), ...[...found].filter((s) => s !== 'Civil' && !EUP_POLICES.some((p) => p.code === s)).sort(), 'Civil'];
        return order.filter((s) => found.has(s));
    }

    function eupModRefresh(res) {
        if (!res || !res.ok) return;
        eup.modWorn = new Set(toArray(res.worn).map(Number));
        eupMenu.render();
    }

    function eupModButton(m) {
        const worn = eup.modWorn.has(m.id);
        return {
            kind: 'button', label: m.name, mark: worn,
            desc: worn ? 'Entrée : retirer cette pièce (la pièce de la tenue d\'origine revient).' : 'Entrée : mettre cette pièce.',
            action: () => post('eupMod', { id: m.id }).then(eupModRefresh),
        };
    }

    function eupModBanner(sub) {
        const code = eup.modService;
        return { title: 'Modifier ma tenue', sub: sub || eupServiceName(code), color: eupServiceColor(code), logo: agencyLogo(code) };
    }

    function eupModCategoryPage(category) {
        return {
            id: 'modcat', title: category,
            banner: () => eupModBanner(`${eupServiceName(eup.modService)} · ${category}`),
            onEnter: () => post('eupModState').then(eupModRefresh),
            items: () => eupModPieces().filter((m) => m.category === category).map(eupModButton),
        };
    }

    // Pièces du service, puis celles de "Tous"
    const eupModPieces = () => [...eup.mods.filter((m) => m.service === eup.modService), ...eup.mods.filter((m) => m.service === 'Tous' && eup.modService !== 'Tous')];

    function eupModPage() {
        eup.modService = eup.service || 'Civil';
        return {
            id: 'mod', title: 'Modifier ma tenue',
            banner: () => eupModBanner(eup.wornName ? `${eupServiceName(eup.modService)} · ${eup.wornName}` : ''),
            onEnter: () => post('eupModState').then(eupModRefresh),
            items: () => {
                const services = eupModServices();
                const pieces = eupModPieces();
                const categories = [...new Set(pieces.map((m) => m.category).filter(Boolean))];
                const items = [{
                    kind: 'list', label: 'Service', options: services.map(eupServiceName),
                    index: Math.max(0, services.indexOf(eup.modService)),
                    desc: `Pièces proposées pour ce service${eup.wornName ? ` (tenue mise : ${eup.wornName})` : ''}. ← → pour en choisir un autre.`,
                    onChange: (i) => { eup.modService = services[i]; },
                }];
                if (!pieces.length) {
                    items.push({ kind: 'info', label: 'Aucune pièce pour ce service (data/modifoutfits.json).', tone: 'muted' });
                } else {
                    items.push({ kind: 'section', label: 'Pièces' });
                    categories.forEach((c) => {
                        const list = pieces.filter((m) => m.category === c);
                        items.push({ kind: 'menu', label: c, right: `${list.length}`, mark: list.some((m) => eup.modWorn.has(m.id)),
                            desc: plural(list.length, 'pièce'), open: () => eupModCategoryPage(c) });
                    });
                    pieces.filter((m) => !m.category).forEach((m) => items.push(eupModButton(m)));
                }
                items.push({ kind: 'section', label: 'Tenue' });
                items.push({ kind: 'button', label: 'Remettre la tenue d\'origine', desc: 'La tenue telle qu\'elle était avant les modifications.',
                    action: () => post('eupModReset').then(eupModRefresh) });
                return items;
            },
        };
    }

    function eupRootPage() {
        const civilCount = eup.outfits.filter((o) => o.cate !== 'police').length;
        const lockedText = eup.policeLocked ? ' — réservées aux policiers en service (unité du MDC)' : '';
        return {
            id: 'root', title: 'Tenues',
            banner: { title: 'Tenues', sub: 'Choisissez une tenue', color: EUP_COLORS.root },
            items: () => [
                { kind: 'section', label: 'Police' },
                ...eupPoliceGroups().map((g) => ({
                    kind: 'menu', label: g.name, right: g.name !== g.code ? g.code : `${g.list.length}`, color: g.color,
                    desc: `${plural(g.list.length, 'tenue')}${lockedText}`,
                    open: () => eupOutfitPage(g.code, g.list, { title: g.name, sub: g.name !== g.code ? `${g.code} · ${plural(g.list.length, 'tenue')}` : 'Police', color: g.color, logo: agencyLogo(g.code) }),
                })),
                { kind: 'section', label: 'Civil' },
                { kind: 'menu', label: 'Civil', right: `${civilCount}`, open: eupCivilPage, desc: plural(civilCount, 'tenue') },
                { kind: 'section', label: 'Ma tenue' },
                { kind: 'menu', label: 'Modifier ma tenue', right: eup.service || 'Civil', open: eupModPage,
                    desc: `Ajouter ou retirer des pièces (gilet, casquette…) selon le service de la tenue mise : ${eupServiceName(eup.service || 'Civil')}.` },
            ],
        };
    }

    function setEup(data) {
        if (!data.open) {
            eupMenu.stop();
            return;
        }
        eup.outfits = toArray(data.outfits);
        eup.policeLocked = !!data.policeLocked;
        eup.mods = toArray(data.mods).map((m) => ({ ...m, id: Number(m.id) }));
        eup.service = data.service || 'Civil';
        eup.wornName = data.wornName || null;
        eupMenu.start([eupRootPage()]);
    }

    // =====================================================================
    // MESSAGES Lua -> NUI
    // =====================================================================
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
            case 'eye': setEye(data.data || {}); break;
            case 'eyeOptions': showEyeOptions(data.data || {}); break;
            case 'result': if (data.data) showResult(data.data); break;
            case 'menu': setMenu(data.data || {}); break;
            case 'menuGo': menuGo(data.data && data.data.view); break;
            case 'menuPolice': // entrée / sortie d'une unité du MDC pendant que le menu est ouvert
                menu.data.police = data.data ? data.data.police : null;
                if (!menu.data.police) menu.data.agency = menu.data.agencyLabel = null;
                interact.render();
                break;
            case 'tips': setTips(data.data || {}); break;
            case 'smell': setSmell(data.data || {}); break;
            case 'menuActions': setMenuActions(data.data || {}); break;
            case 'progress': setProgress(data.data || {}); break;
            case 'struggle': setStruggle(data.data || {}); break;
            case 'editor': setEditor(data.data || {}); break;
            case 'notify': if (data.data) toast(data.data.text, data.data.type); break;
            case 'radio': radioUpdate(data.data); break;
            case 'radioStop': radioStop(data.data && data.data.id); break;
            case 'eup': setEup(data.data || {}); break;
            case 'eupWorn': // tenue mise : son service est celui de "Modifier ma tenue"
                eup.service = (data.data && data.data.service) || 'Civil';
                eup.wornName = (data.data && data.data.wornName) || null;
                if (eupMenu.open) eupMenu.render();
                break;
            case 'kbKey': if (data.data && kbMenus[data.data.menu]) kbMenus[data.data.menu].key(data.data.key); break;
        }
    });
})();
