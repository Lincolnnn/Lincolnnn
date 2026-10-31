--[[
    RP Permissions - configuration
    ==============================
    Chaque joueur reçoit, à la connexion, le groupe ACE de son rôle Discord le plus haut :
        Admin               -> group.admin
        Membre              -> group.membre
        Joueur non-officiel -> group.nonofficiel
    Les permissions de chaque groupe (vMenu et scripts du serveur) sont dans permissions.cfg ; les scripts du serveur
    vérifient les ACE « rp.admin » / « rp.membre » (données à ces groupes dans permissions.cfg) ou les exports d'ici.

    À METTRE DANS server.cfg (jamais dans ce fichier, jamais sur GitHub) :
        set rp_discord_token "TOKEN_DU_BOT"            # « set », pas « setr » : jamais envoyé aux joueurs
        add_ace resource.rp_permissions command.add_principal allow
        add_ace resource.rp_permissions command.remove_principal allow
        ensure rp_permissions                          # tôt : avant vMenu et les scripts rp_
    Le bot doit être sur le serveur Discord (permission « Voir les salons » suffit) avec l'intent « Server Members »
    activé (Discord Developer Portal > Bot > Privileged Gateway Intents).
]]

PermsConfig = {
    -- Serveur Discord (ID du serveur : clic droit sur le serveur > Copier l'identifiant) ; la convar
    -- « rp_discord_guild » du server.cfg le remplace si elle est donnée
    GuildId = '1376650496403701832',

    -- Rôles, du plus haut au plus bas : le premier trouvé chez le joueur est le sien
    Roles = {
        { key = 'admin',       label = 'Admin',               role = '1562210128667611216', group = 'group.admin' },
        { key = 'membre',      label = 'Membre',              role = '1562214435886465055', group = 'group.membre' },
        { key = 'nonofficiel', label = 'Joueur non-officiel', role = '1562213048163242004', group = 'group.nonofficiel' },
    },

    -- LISTE BLANCHE (serveur semi-whitelist) : il faut au moins un de ces rôles pour se connecter
    Whitelist = {
        Enabled = true,
        BlacklistRoles = {},          -- rôles interdits (ex. { '123…' }) : refusé même avec un rôle ci-dessus
        -- Discord injoignable (panne, mauvais token…) : 'allow' = connexion acceptée sans rôle (joueur non-officiel :
        -- permissions de base seulement), 'deny' = refusée
        OnApiError = 'allow',
        Messages = {
            checking = 'Bonjour %s, vérification de tes rôles Discord…',
            noDiscord = 'Discord introuvable : ouvre Discord (application) avant FiveM, puis reconnecte-toi.',
            notInGuild = "Tu n'es pas sur notre serveur Discord : rejoins-le, puis reconnecte-toi.",
            notWhitelisted = "Tu n'as pas de rôle d'accès sur notre Discord (Joueur non-officiel, Membre ou Admin).",
            blacklisted = 'Accès refusé.',
            apiError = 'Vérification Discord impossible pour le moment : réessaie dans quelques minutes.',
        },
    },

    CacheMinutes = 10,    -- rôles d'un joueur gardés 10 min (reconnexion rapide sans nouvelle demande à Discord)
    RefreshMinutes = 15,  -- rôles des joueurs connectés revérifiés toutes les 15 min (rôle donné / retiré en jeu)
    Debug = false,        -- détails dans la console du serveur
}
