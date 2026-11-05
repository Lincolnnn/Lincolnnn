--[[
    RP Teleport - configuration
    ===========================
    PERMISSIONS (Permissions) : par commande, l'ACE demandée ; false = tout le monde.
      'rp.nonofficiel' = tous les joueurs whitelistés (Joueur non-officiel, Membre, Admin)
      'rp.membre'      = Membres et Admins
      'rp.admin'       = Admins seulement
    Lu sur le rang Discord donné par rp_permissions (état « rpRank ») ou sur l'ACE elle-même (permissions.cfg) :
    rien à ajouter dans server.cfg avec rp_permissions. N'importe quelle autre ACE marche aussi (ex. 'onesynctp.goto').
]]

TeleportConfig = {
    Permissions = {
        ['goto'] = 'rp.nonofficiel', -- ([''] : goto est un mot réservé de Lua) /goto <id> : se téléporter à un joueur
        bring   = 'rp.admin',       -- /bring <id> : amener un joueur à soi
        back    = 'rp.nonofficiel', -- /back : revenir à sa position d'avant la dernière téléportation
        players = 'rp.nonofficiel', -- /players : liste des joueurs (ID, nom, nom RP, distance)
        blip    = 'rp.nonofficiel', -- /blip <id> : suivre un joueur sur la carte / la minimap (/blip off)
    },

    NotifyTarget = true,   -- /goto : le joueur rejoint est prévenu (« X s'est téléporté à vous »)
    Cooldown = 3000,       -- ms entre deux téléportations d'un même joueur (/goto, /back) ; les admins n'en ont pas
    SideDistance = 1.5,    -- m : arrivée à côté du joueur (pas dans lui) ; à côté du véhicule s'il conduit
    VehicleSideDistance = 3.0,
    LoadTimeout = 8000,    -- ms max d'attente du décor / des collisions à l'arrivée (sinon on tomberait sous la map)
    ScreenFade = true,     -- fondu au noir pendant le chargement

    -- Blips : position envoyée par le serveur toutes les BlipInterval ms (seulement si quelqu'un suit un joueur)
    Blip = { Interval = 1500, Max = 10, Sprite = 1, Colour = 3, Scale = 0.9, ShortRange = false },

    ChatTitle = 'Téléportation', -- titre des messages privés dans le chat (rp_chat)

    -- vMenu : sa téléportation vers un joueur (Joueurs en ligne) marche à toute distance si la convar
    -- « onesync_enableInfinity » vaut "true" ; ce script la pose au démarrage quand OneSync est actif. false : ne rien
    -- toucher (à mettre alors dans server.cfg : set onesync_enableInfinity true). Démarrez rp_teleport AVANT vMenu.
    VMenuInfinity = true,
}
