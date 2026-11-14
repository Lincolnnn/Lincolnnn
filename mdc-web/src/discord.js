'use strict';
// Discord OAuth2 (côté serveur uniquement : le secret client et les jetons ne vont jamais au navigateur)
const config = require('./config');

const API = () => config.discord.apiBase;

async function discordFetch(path, options = {}) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 10000);
    try {
        const res = await fetch(`${API()}${path}`, { ...options, signal: controller.signal });
        const text = await res.text();
        let body = null;
        try { body = text ? JSON.parse(text) : null; } catch (e) { body = null; }
        return { status: res.status, body };
    } finally {
        clearTimeout(timer);
    }
}

/** Adresse d'autorisation Discord (scopes : identité + lecture de ses rôles sur le serveur configuré) */
function authorizeUrl(state) {
    const p = new URLSearchParams({
        client_id: config.discord.clientId,
        redirect_uri: config.discord.redirectUri,
        response_type: 'code',
        scope: 'identify guilds.members.read',
        state,
        prompt: 'none',
    });
    return `${config.discord.authorizeUrl}?${p.toString()}`;
}

async function tokenRequest(params) {
    const body = new URLSearchParams({ client_id: config.discord.clientId, client_secret: config.discord.clientSecret, ...params });
    const res = await discordFetch('/oauth2/token', {
        method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: body.toString(),
    });
    if (res.status !== 200 || !res.body || !res.body.access_token) {
        throw new Error(`échange de jeton refusé par Discord (${res.status})`);
    }
    return {
        accessToken: res.body.access_token,
        refreshToken: res.body.refresh_token || null,
        expiresAt: Date.now() + (Number(res.body.expires_in) || 3600) * 1000,
    };
}

const exchangeCode = (code) => tokenRequest({ grant_type: 'authorization_code', code, redirect_uri: config.discord.redirectUri });
const refresh = (refreshToken) => tokenRequest({ grant_type: 'refresh_token', refresh_token: refreshToken });

async function fetchUser(accessToken) {
    const res = await discordFetch('/users/@me', { headers: { Authorization: `Bearer ${accessToken}` } });
    if (res.status !== 200 || !res.body || !res.body.id) throw new Error(`profil Discord illisible (${res.status})`);
    return res.body;
}

/**
 * Membre du serveur Discord configuré : avec le bot (si DISCORD_BOT_TOKEN), sinon avec le jeton de l'utilisateur.
 * Retourne { member } (null : pas membre du serveur) ou lève une erreur (Discord injoignable).
 */
async function fetchMember(userId, accessToken) {
    const guild = config.discord.guildId;
    const res = config.discord.botToken
        ? await discordFetch(`/guilds/${guild}/members/${userId}`, { headers: { Authorization: `Bot ${config.discord.botToken}` } })
        : await discordFetch(`/users/@me/guilds/${guild}/member`, { headers: { Authorization: `Bearer ${accessToken}` } });
    if (res.status === 200 && res.body) return { member: res.body };
    if (res.status === 404 || res.status === 403) return { member: null };
    if (res.status === 401) return { member: null, expired: true };
    throw new Error(`Discord ne répond pas correctement (${res.status})`);
}

const hasDispatchRole = (member) => !!member && Array.isArray(member.roles)
    && member.roles.some((r) => config.discord.roleIds.includes(String(r)));

function displayName(user, member) {
    return (member && member.nick) || user.global_name || user.username || 'Dispatcher';
}

function avatarUrl(user) {
    if (!user.avatar) return null;
    return `https://cdn.discordapp.com/avatars/${user.id}/${user.avatar}.png?size=64`;
}

module.exports = { authorizeUrl, exchangeCode, refresh, fetchUser, fetchMember, hasDispatchRole, displayName, avatarUrl };
