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
    MdcResource = 'rp_mdc', -- seulement si le MDC ne publie pas son nom (GlobalState.mdcResource)
    AdminAce = 'rptraffic.admin',

    MaxMeasures = 30,          -- mesures actives sur le serveur
    MaxPerPlayer = 8,          -- mesures actives par joueur
    Durations = { 15, 30, 60, 120, 0 }, -- minutes proposées (0 = jusqu'à ce qu'on la lève)
    DefaultDuration = 30,
    RemoveOnDisconnect = false, -- true : les mesures d'un joueur sont levées quand il se déconnecte

    -- ---------------------------------------------------------------------
    -- TRONÇON : toutes les mesures (fermeture, ralentissement, arrêt) portent sur un tronçon de route choisi
    -- précisément : début, fin, et la portée :
    --   'lane'      : UNE voie de circulation (ex. la voie de gauche d'une interstate) ;
    --   'direction' : un SENS de circulation (toutes ses voies) ;
    --   'road'      : la route entière (les deux sens).
    -- ---------------------------------------------------------------------
    Segment = {
        MinLength = 6.0, MaxLength = 200.0,
        LaneWidth = 5.4,        -- m : largeur d'une voie dans le jeu (aperçu, voie visée) ; à ajuster avec l'aperçu
        Height = 4.0,           -- m au-dessus / au-dessous des nœuds (ponts, routes superposées)
        NodeMargin = 1.5,       -- m : nœuds retenus jusqu'à cette distance hors de la bande choisie
        MaxNodes = 80,
        RoadWidthStep = 1.0, MaxRoadWidth = 60.0, -- route entière : largeur réglable (molette)
    },

    -- FERMETURE : nœuds du jeu fermés quand ils ne servent qu'à la portée choisie (route entière, ou sens d'une
    -- route à chaussées séparées) ; sinon (une voie, un sens d'une route à double sens), les PNJ sont redirigés.
    Closure = {
        NodeBox = 1.2,          -- m : zone fermée autour de chaque nœud (SetRoadsInArea)
        ApproachDistance = 60.0, -- m avant le tronçon : les PNJ concernés changent de voie / de route
        ReplanDistance = 45.0,  -- sens / route fermés : route recalculée à cette distance, demi-tour plus près
        RedirectSpeed = 18.0,   -- m/s au plus pendant le changement de voie / le demi-tour (garde sa vitesse en dessous)
        -- Changement de voie : le PNJ est conduit EN LIGNE DROITE vers un point de la voie ouverte qui avance avec lui
        -- (sinon le suivi de route du jeu le garde sur sa voie) : style « ForceStraightLine » (16777216) + s'arrête
        -- pour les véhicules (1) et les piétons (2) + contourne les véhicules arrêtés (8) et les objets (32)
        MergeStyle = 16777216 + 1 + 2 + 8 + 32,
        MergeLead = 22.0,       -- m : point visé devant pour se rabattre (plus loin à grande vitesse)
        PassLead = 25.0,        -- m : point visé devant en longeant le tronçon
        InLaneTolerance = 1.3,  -- m : sur la voie ouverte
        Refresh = 4000,         -- ms : consigne redonnée au plus tard
        PhaseTimeout = 25000,   -- ms : PNJ bloqué plus longtemps : relâché
        DrivingStyle = 786603,  -- style de conduite pendant le changement de voie / le demi-tour
        WanderStyle = 786603,   -- style redonné ensuite (circulation normale)
        ResumeSpeed = 17.0,     -- m/s : vitesse de croisière redonnée
    },

    -- OBSTACLES INVISIBLES (fermeture) : véhicules du jeu de base, invisibles, figés, sans conducteur, posés le long
    -- de la VOIE fermée (sens / route fermés : une rangée en travers au début, Barrier). Les PNJ du jeu contournent
    -- d'eux-mêmes un véhicule arrêté (changement de voie d'origine) et, avec la collision, ne passent pas au travers.
    -- Locaux (chaque joueur pose les siens, seulement à moins de Range m) ; jamais de collision avec les joueurs et
    -- leurs véhicules ; l'œil de rp_interact les traverse. Debug = true : visibles en transparence (réglage).
    Obstacles = {
        Enabled = true,
        Model = 'blista',       -- petite voiture du jeu de base
        Spacing = 7.0,          -- m entre deux obstacles le long de la voie
        StartOffset = 2.5,      -- m après le début du tronçon
        FreeRadius = 2.6,       -- m : un véhicule déjà là (police garée…) : pas d'obstacle à cet endroit
        MaxPerMeasure = 30, MaxTotal = 80, PerTick = 6,
        Range = 220.0,          -- m du tronçon
        Collision = true,
        Barrier = true,
        Debug = false,
    },

    -- RALENTISSEMENT et ARRÊT
    Speed = {
        DefaultLimit = 25, MinLimit = 5, MaxLimit = 80, Step = 5, -- MPH
        NodeZoneRadius = 4.0,   -- m : zone de vitesse du jeu autour de chaque nœud retenu
        SlowFrom = 25.0,        -- m avant le tronçon : les PNJ concernés ralentissent
        StopBefore = 20.0,      -- m avant le tronçon : les PNJ concernés s'arrêtent
    },

    -- Choix de la zone du trafic (visée de la route)
    Editor = {
        Range = 150.0,          -- m : portée de la visée au sol
        SnapDistance = 14.0,    -- m : distance max à la route visée
        NodePreview = true,     -- nœuds affichés autour de la visée (vert : ouvert, orange : concerné, rouge : fermé)
        NodeCount = 80,
    },

    -- Cartes (carte du menu pause / mini-carte) : 'everyone', 'police' ou 'none'
    Blips = 'everyone',
    BlipColors = { close = 1, slow = 47, stop = 49 }, -- rouge, orange, rouge foncé

    Range = 400.0,              -- m : PNJ gérés seulement pour les tronçons à moins de 400 m du joueur
    Interval = 300,             -- ms entre deux vérifications des PNJ (tronçon à portée)
}
