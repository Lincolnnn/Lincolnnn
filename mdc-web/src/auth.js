'use strict';
// Authentification Discord OAuth2 + contrôle du rôle DISPATCH côté serveur, protection des routes et CSRF.
const crypto = require('crypto');
const express = require('express');
const config = require('./config');
const discord = require('./discord');
const { logAction } = require('./db');
const log = require('./logger');

const router = express.Router();

/** Vérifie (ou revérifie) que l'utilisateur de la session a toujours le rôle. Met la session à jour. */
async function verifyRole(session, maxAgeSeconds) {
    const u = session && session.user;
    if (!u) return { ok: false, reason: 'not_logged' };
    const age = (Date.now() - (u.checkedAt || 0)) / 1000;
    if (age < maxAgeSeconds) return { ok: true };
    try {
        let tokens = session.tokens || {};
        if (!config.discord.botToken && tokens.expiresAt && tokens.expiresAt - Date.now() < 60000 && tokens.refreshToken) {
            tokens = await discord.refresh(tokens.refreshToken);
            session.tokens = tokens;
        }
        const res = await discord.fetchMember(u.id, tokens.accessToken);
        if (!res.member || !discord.hasDispatchRole(res.member)) {
            return { ok: false, reason: res.member ? 'role' : 'guild' };
        }
        u.checkedAt = Date.now();
        u.name = discord.displayName({ global_name: u.globalName, username: u.username }, res.member);
        return { ok: true };
    } catch (e) {
        // Discord injoignable : on tolère jusqu'à 3x la durée normale, puis on refuse (jamais d'accès sans contrôle)
        if (age < config.discord.roleRecheck * 3) {
            log.warn('vérification du rôle impossible (Discord) :', e.message);
            return { ok: true };
        }
        return { ok: false, reason: 'discord' };
    }
}

function destroy(req) {
    return new Promise((resolve) => req.session.destroy(() => resolve()));
}

/** Pages et API : connecté et rôle valide. `sensitive` : revérification plus fréquente (actions). */
function requireDispatcher(sensitive = false) {
    return async (req, res, next) => {
        const check = await verifyRole(req.session, sensitive ? config.discord.sensitiveRecheck : config.discord.roleRecheck);
        if (check.ok) return next();
        if (req.session && req.session.user) {
            log.info(`accès retiré (${check.reason}) : ${req.session.user.name} (${req.session.user.id})`);
            await logAction('web', `discord:${req.session.user.id}`, req.session.user.name, 'web.revoked', { reason: check.reason });
            await destroy(req);
        }
        if (req.path.startsWith('/api/') || req.originalUrl.startsWith('/api/')) {
            return res.status(401).json({ ok: false, error: 'Session expirée ou accès retiré : reconnectez-vous.' });
        }
        return res.redirect(check.reason === 'not_logged' ? '/login' : `/denied?reason=${encodeURIComponent(check.reason)}`);
    };
}

/** Actions (POST) : jeton CSRF de la session dans l'en-tête X-CSRF-Token + même origine */
function requireCsrf(req, res, next) {
    const token = req.get('X-CSRF-Token') || '';
    const expected = req.session && req.session.csrf;
    const ok = expected && token.length === expected.length
        && crypto.timingSafeEqual(Buffer.from(token), Buffer.from(expected));
    const origin = req.get('Origin');
    if (!ok || (origin && origin !== config.publicUrl)) {
        return res.status(403).json({ ok: false, error: 'Requête refusée (jeton de sécurité invalide) : rechargez la page.' });
    }
    return next();
}

router.get('/auth/login', (req, res) => {
    const state = crypto.randomBytes(24).toString('hex');
    req.session.oauthState = state;
    req.session.save(() => res.redirect(discord.authorizeUrl(state)));
});

router.get('/auth/callback', async (req, res) => {
    const { code, state, error } = req.query;
    const expected = req.session.oauthState;
    delete req.session.oauthState;
    if (error) return res.redirect('/login?error=cancelled');
    if (!code || !state || !expected || state !== expected) return res.redirect('/login?error=state');
    try {
        const tokens = await discord.exchangeCode(String(code));
        const user = await discord.fetchUser(tokens.accessToken);
        const { member } = await discord.fetchMember(user.id, tokens.accessToken);
        const name = discord.displayName(user, member);
        if (!member || !discord.hasDispatchRole(member)) {
            const reason = member ? 'role' : 'guild';
            log.info(`connexion refusée (${reason}) : ${name} (${user.id})`);
            await logAction('web', `discord:${user.id}`, name, 'web.denied', { reason });
            return res.redirect(`/denied?reason=${reason}`);
        }
        // nouvelle session (évite la fixation de session), jeton CSRF propre à la session
        req.session.regenerate(async (err) => {
            if (err) return res.redirect('/login?error=session');
            req.session.user = {
                id: String(user.id), username: user.username, globalName: user.global_name || null, name,
                avatar: discord.avatarUrl(user), checkedAt: Date.now(),
            };
            req.session.tokens = tokens;
            req.session.csrf = crypto.randomBytes(32).toString('hex');
            log.info(`connexion : ${name} (${user.id})`);
            await logAction('web', `discord:${user.id}`, name, 'web.login', null);
            req.session.save(() => res.redirect('/'));
        });
    } catch (e) {
        log.error('connexion Discord :', e.message);
        return res.redirect('/login?error=discord');
    }
});

router.post('/auth/logout', requireCsrf, async (req, res) => {
    const u = req.session.user;
    if (u) await logAction('web', `discord:${u.id}`, u.name, 'web.logout', null);
    await destroy(req);
    res.clearCookie('mdc.sid');
    res.json({ ok: true });
});

module.exports = { router, requireDispatcher, requireCsrf, verifyRole };
