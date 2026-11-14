# MDC Web du dispatch — Washington Dispatch

Centre de dispatch **en ligne** relié au MDC en jeu (ressource FiveM `rp_mdc`). Ce n'est pas une copie du MDC en jeu :
c'est une console de dispatch, avec ses propres écrans et ses propres outils :

- **Tableau de bord** : interventions à valider, en attente d'unité, en cours, unités connectées / disponibles,
  file de validation, unités en service (statut modifiable), interventions actives, dispatchers en ligne ;
- **Interventions** : onglets *À valider / En attente d'unité / En cours / Terminées récentes / Toutes*, fiche
  détaillée (priorité, code de réponse, requérant, adresse, description, unités affectées, notes du déroulé, fiches
  liées, messages avec les unités de l'intervention, actions enregistrées) ;
- **Mode Dispatch** (interrupteur en haut) : les appels des civils attendent votre **validation** avant d'arriver aux
  unités ; **valider** (en choisissant les unités), **refuser** ou **annuler** avec un motif, **clôturer** (Clear A/B/C) ;
- **Unités** : indicatif, police, agents (nom RP et **grade**), **statut modifiable à distance**, interventions,
  depuis quand, **affectation** à une intervention, message direct ;
- **Messagerie** : conversations avec chaque **unité**, avec les unités de chaque **intervention** (n° RD) et avec le
  **groupe civil** (tous les joueurs du MDC civil) ; non-lus, heures, expéditeurs ;
- **Historique** (recherche, filtres, dates, pagination) et **Journal** des actions (dispatch, jeu, connexions) ;
- **Temps réel** (Socket.IO) : rien à rafraîchir ; **notifications visuelles et sonores** (nouvelle intervention à
  valider : alarme répétée tant qu'elle attend ; nouveau message).

Tout est **synchronisé** avec le jeu : les deux MDC utilisent la **même base MySQL** ; le site agit **par l'API de la
ressource** (le serveur FiveM reste le seul à écrire les données du MDC, prévient tout de suite les joueurs et renvoie
l'événement au site).

```
 Navigateur du dispatcher  <— HTTPS + Socket.IO —>  Site Node.js (ce dossier)  —— lit ——>  MySQL / MariaDB
                                                        |      ^                                  ^
                     actions (API, clé partagée)        v      |  événements (clé partagée)       | écrit (oxmysql)
                                                    Serveur FiveM : ressource rp_mdc  ————————————+
                                                        |
                                                  MDC en jeu (unités, civils)
```

---

## 1. Prérequis

- **Node.js 18.17 ou plus récent** (20 ou 22 conseillé) sur la machine du site (peut être la même que le serveur FiveM).
- **MySQL 8** ou **MariaDB 10.5+** (fonctions de fenêtre utilisées).
- Ressource FiveM **[oxmysql](https://github.com/overextended/oxmysql/releases)** (dernière version publiée).
- Une **application Discord** (portail des développeurs) et l'accès au serveur Discord de la communauté.

## 2. MySQL

1. Créez la base (si vous n'en avez pas déjà une pour le serveur) :
   ```sql
   CREATE DATABASE fivem CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
   CREATE USER 'fivem'@'localhost' IDENTIFIED BY 'MOT_DE_PASSE_FIVEM';
   GRANT ALL PRIVILEGES ON fivem.* TO 'fivem'@'localhost';
   ```
2. **Les tables du MDC sont créées automatiquement** par la ressource `rp_mdc` au premier démarrage (migrations
   `rp_mdc/sql/migrations/`, suivies dans la table `mdc_schema_migrations`). Import manuel possible :
   `rp_mdc/sql/migrations/001_init.sql`.
3. **Utilisateur du site** (conseillé : droits limités, le site ne fait que lire les données du MDC). **Après** le
   premier démarrage de `rp_mdc` (tables créées) :
   ```sql
   CREATE USER 'mdc_web'@'localhost' IDENTIFIED BY 'MOT_DE_PASSE_WEB';
   GRANT SELECT ON fivem.mdc_calls TO 'mdc_web'@'localhost';
   GRANT SELECT ON fivem.mdc_call_units TO 'mdc_web'@'localhost';
   GRANT SELECT ON fivem.mdc_call_notes TO 'mdc_web'@'localhost';
   GRANT SELECT ON fivem.mdc_call_links TO 'mdc_web'@'localhost';
   GRANT SELECT ON fivem.mdc_units TO 'mdc_web'@'localhost';
   GRANT SELECT ON fivem.mdc_unit_members TO 'mdc_web'@'localhost';
   GRANT SELECT ON fivem.mdc_unit_status_log TO 'mdc_web'@'localhost';
   GRANT SELECT ON fivem.mdc_agents TO 'mdc_web'@'localhost';
   GRANT SELECT ON fivem.mdc_messages TO 'mdc_web'@'localhost';
   GRANT SELECT ON fivem.mdc_message_reads TO 'mdc_web'@'localhost';
   GRANT SELECT ON fivem.mdc_settings TO 'mdc_web'@'localhost';
   GRANT SELECT ON fivem.mdc_identities TO 'mdc_web'@'localhost';
   GRANT SELECT ON fivem.mdc_vehicles TO 'mdc_web'@'localhost';
   GRANT SELECT, INSERT ON fivem.mdc_action_log TO 'mdc_web'@'localhost';
   GRANT CREATE ON fivem.* TO 'mdc_web'@'localhost';            -- création de la table des sessions (une fois)
   CREATE TABLE IF NOT EXISTS fivem.mdc_web_sessions (session_id VARCHAR(128) NOT NULL PRIMARY KEY,
       expires INT UNSIGNED NOT NULL, data MEDIUMTEXT) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
   GRANT SELECT, INSERT, UPDATE, DELETE ON fivem.mdc_web_sessions TO 'mdc_web'@'localhost';
   ```
   (Plus simple, mais moins sûr : utiliser le même utilisateur que le serveur FiveM.)

## 3. Ressource FiveM `rp_mdc`

1. Installez **oxmysql** dans `resources/` et la ressource **`rp_mdc`** (dossier `[rp]/[jouabilite]/rp_mdc`).
2. Dans `server.cfg` (**oxmysql AVANT rp_mdc**) :
   ```cfg
   set mysql_connection_string "mysql://fivem:MOT_DE_PASSE_FIVEM@127.0.0.1/fivem?charset=utf8mb4"
   # Liaison avec le site du dispatch (valeurs secrètes : jamais dans un fichier publié)
   set mdc_web_url "http://127.0.0.1:3000"        # adresse du SITE vue depuis le serveur FiveM
   set mdc_web_key "LONGUE_CLE_SECRETE_48_CARACTERES_OU_PLUS"
   set mdc_web_allow_ip "127.0.0.1"               # IP du site (séparées par des virgules) ; vide = toutes
   ensure oxmysql
   ensure rp_mdc
   ```
   Générez la clé : `node -e "console.log(require('crypto').randomBytes(36).toString('hex'))"`.
3. Démarrez le serveur : la console affiche `MySQL : migration 001_init appliquée`, puis
   `MySQL prêt : … mode Dispatch désactivé` et `API du MDC Web active`. Les anciennes données (`rp_mdc/data/*.json`)
   sont **importées une seule fois**.
4. L'API de la ressource répond sur le port du serveur FiveM : `http://IP_DU_SERVEUR:30120/rp_mdc/api/...`
   (uniquement avec la clé ; toute autre requête : 401 / 403 / 404).

## 4. Discord OAuth2

1. <https://discord.com/developers/applications> → **New Application** (ex. « Washington Dispatch »).
2. **OAuth2** → copiez le **Client ID** et générez le **Client Secret** (gardez-le secret).
3. **OAuth2 → Redirects** : ajoutez exactement `https://dispatch.votredomaine.fr/auth/callback`
   (= `DISCORD_REDIRECT_URI`). En local : `http://localhost:3000/auth/callback`.
4. Scopes demandés par le site : `identify` et `guilds.members.read` (rien à cocher : le site les demande lui-même).
5. **Identifiant du serveur Discord** : Paramètres utilisateur → Avancés → **Mode développeur**, puis clic droit sur
   le serveur → *Copier l'identifiant du serveur* (`DISCORD_GUILD_ID`).
6. **Facultatif mais conseillé** : un **bot** dans le serveur Discord (onglet *Bot* de l'application : *Reset Token*,
   puis invitez-le avec le lien OAuth2 *bot*, aucune permission spéciale) et son jeton dans `DISCORD_BOT_TOKEN` :
   les rôles sont alors vérifiés par le bot (plus fiable que le jeton de l'utilisateur).

## 5. Permissions (qui accède au panel)

- Seuls les membres du serveur Discord configuré qui ont le rôle **`1562214435886465055`** (`DISCORD_DISPATCH_ROLE_ID`,
  plusieurs rôles possibles séparés par des virgules) entrent. **Vérifié côté serveur**, jamais dans le navigateur.
- Revérification : à chaque page et connexion temps réel au-delà de `ROLE_RECHECK_SECONDS` (300 s), avant **chaque
  action** au-delà de `SENSITIVE_RECHECK_SECONDS` (60 s), et toutes les minutes pour les connexions temps réel.
  **Rôle retiré ou membre parti : session fermée**, le dispatcher est renvoyé à la page « Accès refusé ».
- Toutes les connexions, refus et retraits d'accès sont inscrits dans le **Journal** (et la console du site).

## 6. Installer et démarrer le site

```bash
cd mdc-web
npm install --omit=dev
cp .env.example .env      # puis remplissez .env (voir les commentaires du fichier)
npm start
```

Valeurs principales de `.env` :

| Clé | Rôle |
|---|---|
| `PUBLIC_URL`, `PORT` | adresse publique du site, port d'écoute |
| `SESSION_SECRET` | secret des sessions (48 caractères aléatoires) |
| `DISCORD_CLIENT_ID`, `DISCORD_CLIENT_SECRET`, `DISCORD_REDIRECT_URI`, `DISCORD_GUILD_ID`, `DISCORD_DISPATCH_ROLE_ID`, `DISCORD_BOT_TOKEN` | Discord (section 4) |
| `MYSQL_HOST`, `MYSQL_PORT`, `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_DATABASE` | même base que le serveur FiveM |
| `FIVEM_API_URL` | `http://IP_DU_SERVEUR_FIVEM:30120/rp_mdc` |
| `FIVEM_API_KEY` | **identique** à `set mdc_web_key` |
| `BRIDGE_ALLOWED_IPS` | IP du serveur FiveM (seul autorisé à envoyer les événements du jeu) |
| `TRUST_PROXY`, `COOKIE_SECURE` | derrière Nginx / Caddy / Cloudflare en HTTPS : `TRUST_PROXY=1` |

Le site **refuse de démarrer** si une valeur obligatoire manque (message dans la console), et si les tables du MDC
n'existent pas encore (démarrez d'abord `rp_mdc`).

**En production** : laissez-le tourner avec un gestionnaire de processus, par exemple **pm2**
(`npm i -g pm2 && pm2 start src/server.js --name mdc-web && pm2 save && pm2 startup`) ou un service systemd, derrière
un **proxy HTTPS**. Exemple Nginx (le temps réel a besoin de l'en-tête `Upgrade`) :

```nginx
server {
    server_name dispatch.votredomaine.fr;
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    # listen 443 ssl ; certificats (certbot --nginx)
}
```

## 7. Relier le site au serveur FiveM — vérification

1. `set mdc_web_url` (adresse du site **vue du serveur FiveM**) et `set mdc_web_key` dans `server.cfg` ;
   `FIVEM_API_URL` (adresse du **serveur FiveM vue du site**) et `FIVEM_API_KEY` (même clé) dans `.env`.
2. Si les deux ne sont pas sur la même machine : ouvrez le port du serveur FiveM au site (API) et le port du site au
   serveur FiveM (événements), et renseignez `mdc_web_allow_ip` / `BRIDGE_ALLOWED_IPS` avec les bonnes IP.
3. Connectez-vous au site : en haut, **Temps réel** et **Serveur FiveM** doivent être **verts** et le nombre de
   joueurs affiché. En jeu, le MDC affiche **DISPATCH EN LIGNE** dans sa barre de titre.
4. Activez le **mode Dispatch** : le MDC en jeu affiche **MODE DISPATCH** ; créez une intervention avec le MDC civil :
   elle apparaît **aussitôt** dans la file de validation du site (avec son n° RD et l'alarme).

Pannes : site arrêté ou injoignable plus de 45 s → le jeu repasse **automatiquement** en fonctionnement normal (les
appels en attente partent aux unités) ; serveur FiveM arrêté → le site affiche un bandeau rouge, les données restent
consultables, les actions sont refusées avec un message clair.

## 8. Sécurité (résumé)

- Secrets uniquement dans `.env` (site) et `server.cfg` (convars) : jamais dans le JavaScript du navigateur, jamais
  dans le dépôt (`.gitignore`).
- Sessions **httpOnly**, `SameSite=Lax`, `Secure` en HTTPS, enregistrées dans MySQL, régénérées à la connexion ;
  **jeton CSRF** + contrôle de l'origine sur chaque action ; en-têtes de sécurité (CSP stricte, pas de script inline) ;
  limite de requêtes par session.
- Site ↔ serveur FiveM : **clé partagée** comparée en temps constant + **liste d'IP** ; le serveur FiveM revalide
  chaque action (appel, unité, statut, canal, longueur des textes) et ne fait **jamais** confiance aux données d'un
  joueur.
- Requêtes SQL **préparées** partout ; le site n'écrit que dans son journal et ses sessions.
- **Journal** : connexions, refus, retraits d'accès, et chaque action du dispatch (qui, quoi, quand, sur quoi).

## 9. Mise à jour

Remplacez les fichiers (gardez `.env`), `npm install --omit=dev`, redémarrez. Côté FiveM, les nouvelles migrations SQL
s'appliquent seules au démarrage de `rp_mdc`.
