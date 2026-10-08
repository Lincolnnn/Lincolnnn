/* =========================================================================
   MDC Standalone - NUI (Vanilla JS)
   - Communication NUI -> Lua : fetch(`https://<ressource>/<callback>`)
   - Communication Lua -> NUI : window 'message' (SendNUIMessage)
   ========================================================================= */
(() => {
    'use strict';

    // Nom de la ressource (permet de renommer le dossier sans casser les callbacks)
    const RESOURCE = typeof GetParentResourceName === 'function'
        ? GetParentResourceName()
        : 'mdc_standalone';

    const STATUS_LABELS = {
        available: 'Disponible',
        unavailable: 'Indisponible',
        traffic_stop: 'Contrôle Routier',
        busy: 'Occupé',
        on_scene: 'Sur Place',
        en_route: 'En route',
    };

    const PRIORITY_LABELS = { low: 'Basse', medium: 'Moyenne', high: 'Haute' };

    const state = {
        open: false,
        page: 'units',
        status: 'available',
        serverId: null,
        searchType: 'person',
        createKind: 'report',
        clockTimer: null,
    };

    // ---------------------------------------------------------------------
    // Raccourcis DOM
    // ---------------------------------------------------------------------
    const $ = (sel) => document.querySelector(sel);
    const $$ = (sel) => document.querySelectorAll(sel);
    const mdc = $('#mdc');

    // Échappe le HTML (les noms de joueurs peuvent contenir du HTML malveillant)
    const esc = (value) => String(value ?? '').replace(/[&<>"']/g, (c) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c]));

    // Lua peut sérialiser une table vide en {} au lieu de [] : on normalise.
    const toArray = (value) => Array.isArray(value) ? value : Object.values(value || {});

    const formatTime = (unix) => {
        if (!unix) return '-';
        return new Date(unix * 1000).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
    };

    // ---------------------------------------------------------------------
    // Appel d'un callback NUI côté Lua
    // ---------------------------------------------------------------------
    async function post(name, data = {}) {
        try {
            const res = await fetch(`https://${RESOURCE}/${name}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(data),
            });
            return await res.json();
        } catch (err) {
            // Hors jeu (ouverture dans un navigateur pour tester le design)
            return { ok: false, error: 'Callback indisponible (hors jeu ?)' };
        }
    }

    function toast(message, type = 'info') {
        const el = document.createElement('div');
        el.className = `toast ${type}`;
        el.textContent = message;
        $('#toasts').appendChild(el);
        setTimeout(() => el.remove(), 3000);
    }

    // ---------------------------------------------------------------------
    // Ouverture / Fermeture
    // ---------------------------------------------------------------------
    function openUI(data = {}) {
        state.open = true;
        state.serverId = data.serverId ?? null;

        $('#profileName').textContent = data.name || 'Agent';
        $('#profileId').textContent = `ID ${data.serverId ?? '-'}`;
        $('#profileAvatar').textContent = (data.name || '?').trim().charAt(0).toUpperCase() || '?';
        $('#callsignInput').value = data.callsign || '';

        setActiveStatus(data.status || 'available');
        mdc.classList.remove('hidden');

        updateClock();
        state.clockTimer = setInterval(updateClock, 1000);

        loadPage(state.page);
    }

    function closeUI(notifyLua = true) {
        if (!state.open) return;
        state.open = false;
        mdc.classList.add('hidden');
        clearInterval(state.clockTimer);
        state.clockTimer = null;

        // Relâche le SetNuiFocus côté Lua
        if (notifyLua) post('close');
    }

    function updateClock() {
        $('#clock').textContent = new Date().toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
    }

    // Touche Échap -> fermeture
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && state.open) {
            e.preventDefault();
            closeUI();
        }
    });

    $('#closeBtn').addEventListener('click', () => closeUI());

    // ---------------------------------------------------------------------
    // Navigation (Top Bar) - sans rechargement
    // ---------------------------------------------------------------------
    function showPage(page) {
        state.page = page;
        $$('.tab').forEach((t) => t.classList.toggle('active', t.dataset.page === page));
        $$('.page').forEach((p) => p.classList.toggle('active', p.id === `page-${page}`));
        loadPage(page);
    }

    // Charge les données nécessaires à la page affichée
    function loadPage(page) {
        if (page === 'units') refreshUnits();
        else if (page === 'interventions') refreshInterventions();
        else if (page === 'search') $('#searchInput').focus();
    }

    $$('.tab').forEach((tab) => tab.addEventListener('click', () => showPage(tab.dataset.page)));

    // ---------------------------------------------------------------------
    // Statuts (Sidebar)
    // ---------------------------------------------------------------------
    function setActiveStatus(status) {
        state.status = status;
        $$('.status-btn').forEach((b) => b.classList.toggle('active', b.dataset.status === status));
    }

    async function changeStatus(status) {
        if (status === state.status) return;
        const previous = state.status;
        setActiveStatus(status); // retour visuel immédiat

        const res = await post('setStatus', { status });
        if (res && res.ok) {
            toast(`Statut : ${STATUS_LABELS[status]}`, 'success');
        } else {
            setActiveStatus(previous);
            toast(res?.error || 'Impossible de changer de statut.', 'error');
        }
    }

    $$('.status-btn').forEach((btn) => btn.addEventListener('click', () => changeStatus(btn.dataset.status)));

    // Matricule
    async function saveCallsign() {
        const res = await post('setCallsign', { callsign: $('#callsignInput').value });
        if (res && res.ok) {
            $('#callsignInput').value = res.callsign;
            toast('Matricule enregistré.', 'success');
        } else {
            toast(res?.error || 'Erreur lors de l\'enregistrement.', 'error');
        }
    }

    $('#callsignSave').addEventListener('click', saveCallsign);
    $('#callsignInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') saveCallsign(); });

    // ---------------------------------------------------------------------
    // Page : Unités
    // ---------------------------------------------------------------------
    function renderUnits(units) {
        units = toArray(units);
        const body = $('#unitsBody');
        $('#unitsEmpty').classList.toggle('hidden', units.length > 0);

        body.innerHTML = units.map((u) => `
            <tr class="${u.id === state.serverId ? 'me' : ''}">
                <td>${esc(u.id)}</td>
                <td>${esc(u.callsign || '-')}</td>
                <td>${esc(u.name)}</td>
                <td><span class="badge ${esc(u.status)}">${esc(STATUS_LABELS[u.status] || u.status)}</span></td>
                <td>${esc(formatTime(u.updatedAt))}</td>
            </tr>`).join('');
    }

    async function refreshUnits() {
        const res = await post('getUnits');
        if (res && res.ok) renderUnits(res.units);
    }

    $('#refreshUnits').addEventListener('click', refreshUnits);

    // ---------------------------------------------------------------------
    // Page : Recherches
    // ---------------------------------------------------------------------
    $$('#searchType .seg').forEach((seg) => seg.addEventListener('click', () => {
        state.searchType = seg.dataset.type;
        $$('#searchType .seg').forEach((s) => s.classList.toggle('active', s === seg));
        $('#searchInput').placeholder = state.searchType === 'person' ? 'Nom, prénom...' : 'Plaque d\'immatriculation...';
        $('#searchInput').focus();
    }));

    $('#searchForm').addEventListener('submit', async (e) => {
        e.preventDefault();
        const container = $('#searchResults');
        const query = $('#searchInput').value.trim();
        container.innerHTML = '<div class="empty">Recherche en cours...</div>';

        const res = await post('search', { type: state.searchType, query });

        if (!res || !res.ok) {
            container.innerHTML = `<div class="empty">${esc(res?.error || 'Erreur de recherche.')}</div>`;
            return;
        }

        const results = toArray(res.results);
        if (!results.length) {
            container.innerHTML = '<div class="empty">Aucun résultat.</div>';
            return;
        }

        container.innerHTML = results.map((r) => `
            <div class="result ${r.danger ? 'danger' : ''}">
                <div>
                    <div class="result-title">${esc(r.title)}</div>
                    <div class="result-sub">${esc(r.subtitle)}</div>
                </div>
                <span class="tag">${esc(r.tag)}</span>
            </div>`).join('');
    });

    // ---------------------------------------------------------------------
    // Page : Interventions
    // ---------------------------------------------------------------------
    function renderInterventions(list) {
        list = toArray(list);
        const container = $('#interventionsList');

        if (!list.length) {
            container.innerHTML = '<div class="empty">Aucune intervention en cours. Créez-en une depuis l\'onglet « Créations ».</div>';
            return;
        }

        const me = String(state.serverId);

        container.innerHTML = list.map((i) => {
            const units = i.units || {};
            const attached = Object.prototype.hasOwnProperty.call(units, me);
            const unitNames = Object.values(units);
            const prio = PRIORITY_LABELS[i.priority] ? i.priority : 'medium';

            return `
            <div class="card prio-${prio}">
                <div class="card-head">
                    <span class="card-title">#${esc(i.id)} - ${esc(i.title)}</span>
                    <span class="card-meta">${esc(formatTime(i.createdAt))}</span>
                </div>
                <div class="card-meta">
                    Priorité ${esc(PRIORITY_LABELS[prio])}
                    ${i.location ? ` · ${esc(i.location)}` : ''} · par ${esc(i.author)}
                </div>
                ${i.description ? `<div class="card-desc">${esc(i.description)}</div>` : ''}
                <div class="card-units">Unités : ${unitNames.length ? unitNames.map(esc).join(', ') : 'aucune'}</div>
                <div class="card-actions">
                    ${attached
                        ? `<button class="btn btn-small" data-action="detach" data-id="${esc(i.id)}">Se retirer</button>`
                        : `<button class="btn btn-small btn-primary" data-action="attach" data-id="${esc(i.id)}">Prendre l'appel</button>`}
                    <button class="btn btn-small btn-danger" data-action="close" data-id="${esc(i.id)}">Clôturer</button>
                </div>
            </div>`;
        }).join('');
    }

    async function refreshInterventions() {
        const res = await post('getInterventions');
        if (res && res.ok) renderInterventions(res.interventions);
    }

    // Délégation d'événements pour les boutons des cartes
    $('#interventionsList').addEventListener('click', async (e) => {
        const btn = e.target.closest('button[data-action]');
        if (!btn) return;

        btn.disabled = true;
        const action = btn.dataset.action;
        const res = await post('updateIntervention', { id: Number(btn.dataset.id), action });
        btn.disabled = false;

        if (!res || !res.ok) {
            toast(res?.error || 'Action impossible.', 'error');
            return;
        }

        // Prendre un appel passe automatiquement l'agent "En route"
        if (action === 'attach') changeStatus('en_route');
        if (action === 'close') toast('Intervention clôturée.', 'success');
        refreshInterventions();
    });

    $('#refreshInterventions').addEventListener('click', refreshInterventions);

    // ---------------------------------------------------------------------
    // Page : Créations
    // ---------------------------------------------------------------------
    $$('#createType .seg').forEach((seg) => seg.addEventListener('click', () => {
        state.createKind = seg.dataset.kind;
        $$('#createType .seg').forEach((s) => s.classList.toggle('active', s === seg));
        $('.intervention-only').classList.toggle('hidden', state.createKind !== 'intervention');
    }));

    $('#createForm').addEventListener('submit', async (e) => {
        e.preventDefault();
        const form = e.currentTarget;
        const submit = form.querySelector('button[type="submit"]');

        const payload = {
            kind: state.createKind,
            title: $('#createTitle').value.trim(),
            description: $('#createDescription').value.trim(),
        };
        if (state.createKind === 'intervention') {
            payload.location = $('#createLocation').value.trim();
            payload.priority = $('#createPriority').value;
        }

        submit.disabled = true;
        const res = await post('create', payload);
        submit.disabled = false;

        if (res && res.ok) {
            toast(`Enregistré (#${res.id}).`, 'success');
            form.reset();
            if (payload.kind === 'intervention') showPage('interventions');
        } else {
            toast(res?.error || 'Erreur lors de l\'enregistrement.', 'error');
        }
    });

    // ---------------------------------------------------------------------
    // Messages Lua -> NUI
    // ---------------------------------------------------------------------
    window.addEventListener('message', ({ data }) => {
        if (!data || !data.action) return;

        switch (data.action) {
            case 'open':
                openUI(data.data);
                break;
            case 'close':
                closeUI(false); // fermé côté Lua : inutile de renvoyer "close"
                break;
            case 'units': // mise à jour temps réel envoyée par le serveur
                renderUnits(data.data);
                break;
            case 'interventions':
                renderInterventions(data.data);
                break;
        }
    });
})();
