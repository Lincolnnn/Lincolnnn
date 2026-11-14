'use strict';
// Liaison avec le serveur FiveM (ressource rp_mdc) :
//   - actions du dispatch -> API de la ressource (POST <FIVEM_API_URL>/api/<action>, en-tête X-MDC-Key) ;
//   - battement toutes les HEARTBEAT_SECONDS (dispatchers connectés) : le jeu sait que le dispatch est en ligne.
const config = require('./config');
const log = require('./logger');

const status = { online: false, lastOk: 0, dispatch: null, players: null, error: null };
let onStatus = () => {};

async function call(action, body = {}, timeoutMs = 8000) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
        const res = await fetch(`${config.fivem.apiUrl}/api/${action}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-MDC-Key': config.fivem.apiKey },
            body: JSON.stringify(body),
            signal: controller.signal,
        });
        const text = await res.text();
        let data = null;
        try { data = text ? JSON.parse(text) : null; } catch (e) { data = null; }
        if (res.status === 401 || res.status === 403) {
            setStatus(false, 'clé ou adresse refusée par le serveur FiveM (FIVEM_API_KEY / mdc_web_key / mdc_web_allow_ip)');
            return { ok: false, error: 'Le serveur FiveM refuse la connexion du site (clé ou adresse) : prévenez un administrateur.' };
        }
        if (!data) {
            setStatus(false, `réponse illisible (${res.status})`);
            return { ok: false, error: `Le serveur FiveM a répondu une erreur (${res.status}).` };
        }
        setStatus(true, null, data.dispatch);
        return data;
    } catch (e) {
        setStatus(false, e.name === 'AbortError' ? 'délai dépassé' : e.message);
        return { ok: false, error: 'Serveur FiveM injoignable : l\'action n\'a pas été faite.' };
    } finally {
        clearTimeout(timer);
    }
}

function setStatus(online, error, dispatch) {
    const changed = status.online !== online || (dispatch && JSON.stringify(dispatch) !== JSON.stringify(status.dispatch));
    if (status.online && !online) log.warn(`serveur FiveM injoignable (${error})`);
    if (!status.online && online) log.info('serveur FiveM joignable');
    status.online = online;
    status.error = error;
    if (online) status.lastOk = Date.now();
    if (dispatch) status.dispatch = dispatch;
    if (changed) onStatus(publicStatus());
}

function publicStatus() {
    return { online: status.online, lastOk: status.lastOk, dispatch: status.dispatch, players: status.players };
}

/** Battement : liste des dispatchers connectés (fonction fournie par realtime.js) */
function startHeartbeat(getDispatchers) {
    const beat = async () => {
        const res = await call('heartbeat', { dispatchers: getDispatchers() });
        if (res && res.ok) {
            status.players = res.players;
            onStatus(publicStatus());
        }
    };
    beat();
    const timer = setInterval(beat, Math.max(5, config.fivem.heartbeatSeconds) * 1000);
    return { beat, stop: () => clearInterval(timer) };
}

module.exports = { call, startHeartbeat, publicStatus, setStatusListener: (fn) => { onStatus = fn; } };
