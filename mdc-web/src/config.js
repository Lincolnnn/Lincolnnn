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
    // LiveView : adresse à laquelle le JEU envoie les images (doit être en HTTPS en production : le NUI du jeu est
    // une page https://cfx-nui-rp_mdc), nombre de joueurs regardés à la fois, origines autorisées (NUI du MDC)
    live: {
        uploadUrl: String(env('LIVE_UPLOAD_URL', `${publicUrl}/live/frame`)),
        maxStreams: Math.max(1, Math.min(64, int('LIVE_MAX_STREAMS', 16))),
        origins: list('LIVE_ALLOWED_ORIGINS', 'https://cfx-nui-rp_mdc,nui://rp_mdc'),
        // Vidéo WebRTC par serveur relais (SFU LiveKit + TURN intégré). Vide : repli sur les images JPEG.
        rtc: {
            url: String(env('LIVEKIT_URL', '')).replace(/\/+$/, ''),             // wss://live.exemple.fr (navigateur + jeu)
            apiUrl: String(env('LIVEKIT_API_URL', '')).replace(/\/+$/, ''),      // https://… (API serveur ; déduit de LIVEKIT_URL)
            apiKey: env('LIVEKIT_API_KEY', ''),
            apiSecret: env('LIVEKIT_API_SECRET', ''),
            roomPrefix: env('LIVEKIT_ROOM_PREFIX', 'mdc-live-'),
            maxKbps: Math.max(150, Math.min(4000, int('LIVE_MAX_KBPS', 900))),   // débit max par joueur (agrandi)
        },
    },
};
const rtc = config.live.rtc;
if (!rtc.apiUrl && rtc.url) rtc.apiUrl = rtc.url.replace(/^ws(s?):\/\//, 'http$1://');
rtc.enabled = /^wss?:\/\//.test(rtc.url) && rtc.apiKey.length >= 3 && rtc.apiSecret.length >= 32;
if (rtc.url && !rtc.enabled) console.warn('[mdc] LiveView WebRTC désactivé : LIVEKIT_URL (wss://), LIVEKIT_API_KEY et LIVEKIT_API_SECRET (32 caractères au moins) requis.');

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
