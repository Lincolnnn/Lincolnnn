'use strict';
// Accès MySQL (même base que le serveur FiveM). Le site LIT les tables du MDC ; il n'écrit que dans le journal
// (mdc_action_log : connexions) et ses sessions (mdc_web_sessions). Toutes les modifications métier passent par
// l'API du serveur FiveM (fivem.js), seul à écrire les appels, unités, messages…
const mysql = require('mysql2/promise');
const config = require('./config');

const pool = mysql.createPool({
    host: config.mysql.host,
    port: config.mysql.port,
    user: config.mysql.user,
    password: config.mysql.password,
    database: config.mysql.database,
    charset: 'utf8mb4',
    connectionLimit: 10,
    waitForConnections: true,
    supportBigNumbers: true,
    bigNumberStrings: false,
    dateStrings: true,
});

/** Requête préparée (paramètres « ? » : jamais de texte collé dans le SQL) */
async function query(sql, params = []) {
    const [rows] = await pool.execute(sql, params);
    return rows;
}

/** Variante sans préparation (IN (?, ?, …) de taille variable, LIMIT) : paramètres toujours échappés par mysql2 */
async function queryRaw(sql, params = []) {
    const [rows] = await pool.query(sql, params);
    return rows;
}

async function logAction(source, actorId, actorName, action, details) {
    try {
        await query('INSERT INTO mdc_action_log (source, actor_id, actor_name, action, details, created_at) VALUES (?, ?, ?, ?, ?, ?)',
            [source, String(actorId || '').slice(0, 80), String(actorName || '').slice(0, 60), action, details ? JSON.stringify(details) : null,
                Math.floor(Date.now() / 1000)]);
    } catch (e) {
        // le journal ne doit jamais bloquer une connexion
    }
}

module.exports = { pool, query, queryRaw, logAction };
