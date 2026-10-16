--[[
    RP TrafficControl - configuration (partagée client / serveur)
]]
TrafficConfig = {
    -- Commande et touche (aucune par défaut : Échap > Paramètres > Raccourcis clavier > FiveM)
    Command = 'trafic',
    Key = '',

    -- Qui peut poser / lever des mesures : policiers en service (unité du MDC) ; la permission ACE AdminAce l'autorise
    -- toujours (ex. add_ace group.admin rptraffic.admin allow). PoliceOnly = false : tout le monde.
    PoliceOnly = true,
    MdcResource = 'mdc_standalone', -- seulement si le MDC ne publie pas son nom (GlobalState.mdcResource)
    AdminAce = 'rptraffic.admin',

    MaxMeasures = 30,          -- mesures actives sur le serveur
    MaxPerPlayer = 8,          -- mesures actives par joueur
    Durations = { 15, 30, 60, 120, 0 }, -- minutes proposées (0 = jusqu'à ce qu'on la lève)
    DefaultDuration = 30,
    RemoveOnDisconnect = false, -- true : les mesures d'un joueur sont levées quand il se déconnecte

    -- ---------------------------------------------------------------------
    -- ROUTE BARRÉE (déviation) : les nœuds de circulation du jeu sur le tronçon sont fermés. Les PNJ ne les
    -- empruntent plus (ils prennent une autre route), aucun véhicule n'y apparaît. Rien n'est supprimé.
    -- ---------------------------------------------------------------------
    Closure = {
        MinLength = 6.0, MaxLength = 250.0,  -- longueur du tronçon (m)
        DefaultWidth = 14.0, MinWidth = 4.0, MaxWidth = 40.0, WidthStep = 1.0,
        AutoWidth = true,       -- largeur de départ : celle de la route visée (voies du jeu)
        LaneWidth = 3.8,        -- m par voie (largeur automatique)
        Height = 8.0,           -- m au-dessus / au-dessous du tronçon (routes en pente, ponts)
        -- Véhicules PNJ qui arrivent quand même sur le tronçon fermé (ils avaient déjà choisi leur route) :
        -- route recalculée (ils font demi-tour / tournent au carrefour) quand ils sont à moins de ApproachDistance m
        SmartDetour = true,
        ApproachDistance = 25.0,
        StopEntries = false,    -- true : en plus, arrêt du trafic aux deux extrémités (barrage physique)
    },

    -- LIMITATION DE VITESSE (zone ronde) et ARRÊT DU TRAFIC (vitesse 0)
    Speed = {
        DefaultLimit = 25, MinLimit = 5, MaxLimit = 80, Step = 5, -- MPH
        DefaultRadius = 40.0, MinRadius = 10.0, MaxRadius = 200.0, RadiusStep = 5.0,
    },

    -- Outil de pose
    Editor = {
        Range = 150.0,          -- m : portée de la visée au sol
        Snap = true,            -- accroche au milieu de la route la plus proche (Maj gauche maintenu : libre)
        SnapDistance = 12.0,
        NodePreview = true,     -- nœuds de circulation affichés autour de la visée (vert : ouvert, rouge : fermé)
        NodeCount = 60,
    },

    -- Cartes (carte du menu pause / mini-carte) : 'everyone', 'police' ou 'none'
    Blips = 'everyone',
    BlipColors = { close = 1, speed = 47, stop = 49 }, -- rouge, orange, rouge foncé

    -- Avancé : arguments des natives des nœuds (selon la version du jeu, voir README)
    NodeNative = { unknown1 = false, network = false },
    Range = 400.0,              -- m : déviation intelligente seulement pour les tronçons à moins de 400 m du joueur
}
