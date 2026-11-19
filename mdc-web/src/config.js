'use strict';
// Configuration centralisée : lue dans .env (jamais envoyée au navigateur). Valeurs obligatoires vérifiées au démarrage.
const path = require('path');
require('dotenv').config({ path: process.env.MDC_ENV_FILE || path.join(__dirname, '..', '.env') });

const env = (name, def) => {
    const v = process.env[name];
    return v === undefined || v === '' ? def : v;
};
const int = (name, def) => {
    const v = parseInt(env(name, ''), 10);
    return Number.isFinite(v) ? v : def;
};
const list = (name, def) => String(env(name, def || '')).split(',').map((s) => s.trim()).filter(Boolean);

const publicUrl = String(env('PUBLIC_URL', 'http://localhost:3000')).replace(/\/+$/, '');
const cookieSecure = env('COOKIE_SECURE', 'auto');

const config = {
    port: int('PORT', 3000),
    publicUrl,
    sessionSecret: env('SESSION_SECRET', ''),
    sessionHours: int('SESSION_HOURS', 12),
    trustProxy: env('TRUST_PROXY', '0') === '1',
    cookieSecure: cookieSecure === 'auto' ? publicUrl.startsWith('https://') : cookieSecure === 'true',
    discord: {
        clientId: env('DISCORD_CLIENT_ID', ''),
        clientSecret: env('DISCORD_CLIENT_SECRET', ''),
        redirectUri: env('DISCORD_REDIRECT_URI', `${publicUrl}/auth/callback`),
        guildId: env('DISCORD_GUILD_ID', ''),
        roleIds: list('DISCORD_DISPATCH_ROLE_ID', '1562214435886465055'),
        botToken: env('DISCORD_BOT_TOKEN', ''),
        apiBase: String(env('DISCORD_API_BASE', 'https://discord.com/api/v10')).replace(/\/+$/, ''),
        authorizeUrl: env('DISCORD_AUTHORIZE_URL', 'https://discord.com/oauth2/authorize'),
        roleRecheck: int('ROLE_RECHECK_SECONDS', 300),
        sensitiveRecheck: int('SENSITIVE_RECHECK_SECONDS', 60),
    },
    mysql: {
        host: env('MYSQL_HOST', '127.0.0.1'),
        port: int('MYSQL_PORT', 3306),
        user: env('MYSQL_USER', ''),
        password: env('MYSQL_PASSWORD', ''),
        database: env('MYSQL_DATABASE', ''),
    },
    fivem: {
        apiUrl: String(env('FIVEM_API_URL', 'http://127.0.0.1:30120/rp_mdc')).replace(/\/+$/, ''),
        apiKey: env('FIVEM_API_KEY', ''),
        bridgeIps: list('BRIDGE_ALLOWED_IPS', '127.0.0.1'),
        heartbeatSeconds: int('HEARTBEAT_SECONDS', 15),
    },
    // LiveView (vidéo WebRTC écrite de zéro) : le site ne fait que la signalisation ; la vidéo va du jeu au navigateur,
    // en direct ou par un serveur TURN (coturn conseillé, voir docs/LIVEVIEW_WEBRTC.md)
    live: {
        publicUrl: String(env('LIVE_PUBLIC_URL', publicUrl)).replace(/\/+$/, ''),   // adresse du site vue depuis le jeu (https://)
        maxStreams: Math.max(1, Math.min(64, int('LIVE_MAX_STREAMS', 16))),          // joueurs diffusés à la fois
        maxViewers: Math.max(1, Math.min(8, int('LIVE_MAX_VIEWERS', 4))),            // dispatchers par joueur (1 encodage chacun)
        origins: list('LIVE_ALLOWED_ORIGINS', 'https://cfx-nui-rp_mdc,nui://rp_mdc'),
        stun: list('LIVE_STUN_URLS', 'stun:stun.l.google.com:19302,stun:stun.cloudflare.com:3478'),
        turn: {
            urls: list('LIVE_TURN_URLS', ''),           // ex. turn:turn.exemple.fr:3478?transport=udp,turns:turn.exemple.fr:5349
            secret: env('LIVE_TURN_SECRET', ''),        // coturn : static-auth-secret (identifiants temporaires)
            username: env('LIVE_TURN_USERNAME', ''),    // sinon : identifiants fixes
            password: env('LIVE_TURN_PASSWORD', ''),
            ttl: Math.max(300, Math.min(86400, int('LIVE_TURN_TTL', 3600))),
        },
        relayOnly: env('LIVE_RELAY_ONLY', '0') === '1',  // 1 : toujours par TURN (cache l'IP des joueurs et des dispatchers)
        maxWidth: Math.max(640, Math.min(1920, int('LIVE_MAX_WIDTH', 1280))),
        maxHeight: Math.max(360, Math.min(1080, int('LIVE_MAX_HEIGHT', 720))),
        fps: Math.max(10, Math.min(60, int('LIVE_FPS', 30))),
        codec: ['h264', 'vp8', 'vp9'].includes(env('LIVE_CODEC', 'h264')) ? env('LIVE_CODEC', 'h264') : 'h264',
        renewMs: 20000,
        // mosaïque : image réduite de moitié ; agrandi : pleine taille, pleine cadence
        modes: {
            grid: { scale: Math.max(1, Math.min(4, Number(env('LIVE_GRID_SCALE', '2')) || 2)), fps: Math.max(5, Math.min(60, int('LIVE_GRID_FPS', 20))),
                kbps: Math.max(150, Math.min(6000, int('LIVE_GRID_KBPS', 700))) },
            focus: { scale: 1, fps: Math.max(5, Math.min(60, int('LIVE_FPS', 30))), kbps: Math.max(300, Math.min(12000, int('LIVE_FOCUS_KBPS', 3000))) },
        },
    },
};
if (config.live.turn.urls.length && !config.live.turn.secret && !config.live.turn.username) {
    console.warn('[mdc] LiveView : LIVE_TURN_URLS sans LIVE_TURN_SECRET ni LIVE_TURN_USERNAME : serveur TURN ignoré.');
}
if (config.live.relayOnly && !config.live.turn.urls.length) console.warn('[mdc] LiveView : LIVE_RELAY_ONLY=1 sans serveur TURN : aucune vidéo possible.');

// Vérification : sans ces valeurs, le site ne démarre pas (message clair plutôt qu'un site ouvert à tous)
const missing = [];
if (!config.sessionSecret || config.sessionSecret.length < 32) missing.push('SESSION_SECRET (32 caractères au moins)');
if (!config.discord.clientId) missing.push('DISCORD_CLIENT_ID');
if (!config.discord.clientSecret) missing.push('DISCORD_CLIENT_SECRET');
if (!config.discord.guildId) missing.push('DISCORD_GUILD_ID');
if (!config.discord.roleIds.length) missing.push('DISCORD_DISPATCH_ROLE_ID');
if (!config.mysql.user || !config.mysql.database) missing.push('MYSQL_USER / MYSQL_DATABASE');
if (!config.fivem.apiKey || config.fivem.apiKey.length < 24) missing.push('FIVEM_API_KEY (24 caractères au moins, identique à mdc_web_key)');
config.missing = missing;

module.exports = config;
