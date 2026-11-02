--[[
    RP Permissions - configuration
    ==============================
    Chaque joueur reçoit, à la connexion, le groupe ACE de son rôle Discord le plus haut :
        Admin               -> group.admin
        Membre              -> group.membre
        Joueur non-officiel -> group.nonofficiel
    Les permissions de chaque groupe (vMenu et scripts du serveur) sont dans permissions.cfg ; les scripts du serveur
    vérifient les ACE « rp.admin » / « rp.membre » (données à ces groupes dans permissions.cfg) ou les exports d'ici.

    TOKEN DU BOT : dans BotToken ci-dessous (ce fichier n'est lu que par le serveur, jamais envoyé aux joueurs), ou dans
    server.cfg avec  set rp_discord_token "TOKEN_DU_BOT"  (« set », pas « setr » ; la convar passe avant BotToken).
    Ne remettez JAMAIS ce fichier rempli sur GitHub ni ailleurs.
    À METTRE DANS server.cfg :
        add_ace resource.rp_permissions command.add_principal allow
        add_ace resource.rp_permissions command.remove_principal allow
        add_ace resource.rp_permissions command.add_ace allow       # repères rp.* et MembersOnly
        add_ace resource.rp_permissions command.remove_ace allow    # MembersOnly (refus retiré quand on devient Membre)
        add_ace resource.rp_permissions command.quit allow          # /whiteliston : redémarrage du serveur (txAdmin)
        ensure rp_permissions                          # tôt : avant vMenu et les scripts rp_
    Le bot doit être sur le serveur Discord (permission « Voir les salons » suffit) avec l'intent « Server Members »
    activé (Discord Developer Portal > Bot > Privileged Gateway Intents).
]]

PermsConfig = {
    -- Token du bot Discord (Discord Developer Portal > votre application > Bot > Reset Token), entre les guillemets
    BotToken = "",

    -- Serveur Discord (ID du serveur : clic droit sur le serveur > Copier l'identifiant) ; la convar
    -- « rp_discord_guild » du server.cfg le remplace si elle est donnée
    GuildId = '1562199084276781157',

    -- Rôles, du plus haut au plus bas : le premier trouvé chez le joueur est le sien. CHAQUE rôle sert à la fois :
    --   - de LISTE BLANCHE : il faut au moins un de ces trois rôles pour se connecter (sinon : refusé) ;
    --   - de PERMISSIONS en jeu, différentes pour chacun (groupe ACE donné au joueur, permissions.cfg).
    Roles = {
        { key = 'admin',       label = 'Admin',               role = '1562210128667611216', group = 'group.admin' },
        { key = 'membre',      label = 'Membre',              role = '1562214435886465055', group = 'group.membre' },
        { key = 'nonofficiel', label = 'Joueur non-officiel', role = '1562213048163242004', group = 'group.nonofficiel' },
    },

    -- LISTE BLANCHE : sans aucun des trois rôles ci-dessus, connexion REFUSÉE (pas de Discord, pas sur le serveur
    -- Discord, aucun rôle)
    Whitelist = {
        Enabled = true,
        BlacklistRoles = {},          -- rôles interdits (ex. { '123…' }) : refusé même avec un rôle ci-dessus
        -- Rôles impossibles à vérifier (Discord en panne, token absent ou refusé) : 'deny' = connexion refusée (personne
        -- n'entre sans rôle vérifié) ; 'allow' = acceptée sans rôle (permissions de base), à éviter
        OnApiError = 'deny',
        Messages = {
            checking = 'Bonjour %s, vérification de tes rôles Discord…',
            noDiscord = 'Discord introuvable : ouvre Discord (application) avant FiveM, puis reconnecte-toi.',
            notInGuild = "Tu n'es pas sur notre serveur Discord : rejoins-le, puis reconnecte-toi.",
            notWhitelisted = "Tu n'as pas de rôle d'accès sur notre Discord (Joueur non-officiel, Membre ou Admin).",
            blacklisted = 'Accès refusé.',
            apiError = 'Vérification de tes rôles Discord impossible pour le moment : réessaie dans quelques minutes.',
        },

        -- SESSION WHITELIST (admins, ou console du serveur) :
        --   /whiteliston  : connexion réservée aux Membres et Admins (les Joueurs non-officiels sont refusés), annoncée à
        --                   tous, puis REDÉMARRAGE du serveur RestartSeconds s après (joueurs prévenus puis déconnectés).
        --                   Gardé au redémarrage (mémoire du serveur) jusqu'à /whitelistoff.
        --   /whitelistoff : accès rétabli tout de suite pour tous (à partir de Joueur non-officiel), sans redémarrage ;
        --                   annule un redémarrage en cours.
        -- Redémarrage : commande RestartCommand ('quit' : le serveur s'arrête et txAdmin le relance tout seul ; '' : pas
        -- de redémarrage automatique). Demande dans server.cfg :  add_ace resource.rp_permissions command.quit allow
        Session = {
            CommandOn = 'whiteliston', CommandOff = 'whitelistoff',
            MinRank = 'membre',         -- rang minimal pendant une session whitelist
            RestartSeconds = 30,
            RestartCommand = 'quit',
            OnTitle = 'SESSION WHITELIST',
            OnText = 'Accès réservé aux membres recrutés : redémarrage du serveur dans %d secondes.',
            OffTitle = 'SESSION OUVERTE',
            OffText = 'Accès rétabli pour tous les membres du Discord (à partir du rôle Joueur non-officiel).',
            DeniedMessage = 'Session whitelist en cours : le serveur est réservé aux membres recrutés. Reviens plus tard !',
            RestartKickMessage = 'Redémarrage du serveur : session whitelist (membres recrutés). Reconnecte-toi dans une minute.',
        },
    },

    -- RÉSERVÉ AUX MEMBRES ET ADMINS : refusé à chaque joueur non-officiel (refus posé sur son identifiant Discord, qui
    -- l'emporte sur un « allow » donné ailleurs ; retiré dès qu'il devient Membre). Ici : les LOADOUTS D'ARMES
    -- ENREGISTRÉS de vMenu (créer, équiper, équiper au respawn). {} = rien de réservé ici (seulement permissions.cfg).
    MembersOnly = {
        'vMenu.WeaponLoadouts.Menu', 'vMenu.WeaponLoadouts.All',
        'vMenu.WeaponLoadouts.Equip', 'vMenu.WeaponLoadouts.EquipOnRespawn',
    },

    CacheMinutes = 10,    -- rôles d'un joueur gardés 10 min (reconnexion rapide sans nouvelle demande à Discord)
    RefreshMinutes = 15,  -- rôles des joueurs connectés revérifiés toutes les 15 min (rôle donné / retiré en jeu)
    Debug = false,        -- détails dans la console du serveur
}

--[[
    ========================================================================================================
    STATUT DU SERVEUR SUR DISCORD (server/discord_status.lua)
    ========================================================================================================
    3 fonctions : embed de statut, embed « joueurs connectés », alertes de connexion / déconnexion.
    Par défaut le script réutilise le MÊME bot que les rôles (PermsConfig.BotToken ci-dessus) : rien d'autre à héberger.
    Le bot doit avoir, dans CHAQUE salon ci-dessous : Voir le salon, Envoyer des messages, Intégrer des liens,
    Lire l'historique des messages. (Pas besoin que le bot apparaisse « en ligne » : il écrit via l'API.)
]]
StatusConfig = {
    Enabled = true,

    -- Laisser vide pour réutiliser le bot des rôles. Pour un AUTRE bot : son token ici, ou dans server.cfg
    -- avec  set rp_status_token "TOKEN"  (la convar passe avant cette ligne).
    BotToken = '',

    Channels = {
        status  = '1563586399955980400',  -- embed « statut du serveur » (un seul message, modifié en continu)
        players = '1564966729753563196',  -- embed « joueurs connectés » (un seul message, modifié en continu)
        logs    = '1566181232750887142',  -- alertes connexion / déconnexion (avec @discord et IP) : salon PRIVÉ staff
    },

    -- Facultatif : reprendre un message déjà posté par le bot (ID du message : clic droit > Copier l'identifiant).
    -- Vide = le script crée le message tout seul et retient son ID dans discord_messages.json.
    MessageIds = { status = '', players = '' },

    UpdateSeconds = 60,   -- mise à jour régulière (minimum 30) ; une arrivée / un départ met à jour en ~10 s
    ServerName = '',      -- vide = sv_projectName (ou sv_hostname) du server.cfg
    ConnectInfo = '',     -- ex. 'cfx.re/join/xxxxxx' ou 'connect monserveur.fr' : affiché dans l'embed de statut
    MaxPlayers = 0,       -- 0 = valeur de sv_maxclients
    ShowIp = true,        -- false = alertes sans adresse IP

    RankEmoji = { admin = '🛡️', membre = '⭐', nonofficiel = '👤' },
    Colors = { online = 0x57F287, offline = 0xED4245, players = 0x5865F2, join = 0x57F287, leave = 0xED4245 },
}
