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
        LaneWidth = 5.4,        -- m : largeur d'une voie au départ (aperçu, voie visée) ; Maj + ← → pendant le choix
        MinLaneWidth = 2.5, MaxLaneWidth = 7.0,
        MaxShift = 8.0,         -- m : décalage latéral au plus (← → pendant le choix : aligner sur les voies peintes)
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
        -- Fermeture d'une VOIE : les autres voies du même sens ralentissent à SideSlow MPH (0 = non), progressivement
        -- depuis l'amont (Speed.Upstream) jusqu'à la fin de la zone (zones de vitesse du jeu + PNJ ralentis), pour que
        -- le rabattement ne se fasse pas à pleine vitesse ; le rabattement lui-même se fait à cette vitesse
        SideSlow = 20,
        DrivingStyle = 786603,  -- style de conduite pendant le changement de voie / le demi-tour
        WanderStyle = 786603,   -- style redonné ensuite (circulation normale)
        ResumeSpeed = 17.0,     -- m/s : vitesse de croisière redonnée
    },

    -- FAUX OBSTACLES : RIEN DE PHYSIQUE (pas de collision, invisibles : ni joueur ni PNJ ne heurte quoi que ce soit),
    -- mais l'IA du jeu les voit comme des véhicules arrêtés et les contourne. Posés sur les plots VIRTUELS des mesures
    -- (VirtualCones) et le long des plots posés par la police (rp_equipment, Cones). Locaux (chaque joueur pose les
    -- siens, seulement à moins de Range m). Debug = true : visibles en transparence ; Collision = true : physiques.
    Obstacles = {
        Enabled = true,
        Model = 'blista',       -- petite voiture du jeu de base
        FreeRadius = 2.6,       -- m : un véhicule déjà là (police garée…) : pas d'obstacle à cet endroit
        MaxPerMeasure = 60, MaxTotal = 150, PerTick = 8,
        Range = 220.0,          -- m du tronçon / du dispositif de plots
        Collision = false,
        Debug = false,
        -- Plots de la police (GlobalState.rpCones) : plots à moins de GroupDistance m = un dispositif ; un obstacle tous
        -- les Spacing m le long de sa ligne (un plot seul : un obstacle dans le sens de la route)
        Cones = { Enabled = true, GroupDistance = 6.0, Spacing = 3.5, MaxPerGroup = 20 },
    },

    -- RALENTISSEMENT et ARRÊT : sur TOUT LE SENS (la voie choisie et les autres voies de ce sens ; route entière : les
    -- deux sens), avec un PÉRIMÈTRE EN AMONT : la vitesse baisse progressivement de UpstreamStart MPH (Upstream m avant
    -- la zone) jusqu'à la limite au début de la zone (zones de vitesse du jeu sur les nœuds de ce sens, pour tous les
    -- PNJ, et PNJ dirigés) : ils freinent en arrivant, ils ne pilent pas. Ex. interstate à 65 MPH, limite 10 MPH.
    Speed = {
        DefaultLimit = 25, MinLimit = 5, MaxLimit = 80, Step = 5, -- MPH
        NodeZoneRadius = 4.0,   -- m : zone de vitesse du jeu autour de chaque nœud
        Upstream = 150.0,       -- m : longueur du périmètre en amont
        UpstreamStart = 70,     -- MPH au début du périmètre (une route plus lente n'est pas accélérée)
        StopBefore = 8.0,       -- m avant la zone : arrêt (Arrêt du trafic)
        BandMargin = 1.5,       -- m de marge de chaque côté du sens (PNJ un peu à cheval sur la ligne)
    },

    -- PLOTS VIRTUELS : invisibles, sans collision (rien dans le monde), traités comme les plots de la police :
    --   - fermeture d'une voie : biseau en amont (Taper m) puis ligne le long de la voie ouverte : les PNJ CONTOURNENT ;
    --   - arrêt du trafic, sens / route fermés : une ligne en travers du sens au début de la zone : ils S'ARRÊTENT.
    -- Chaque ligne reçoit des faux obstacles (Obstacles) ; les PNJ que ce joueur contrôle : même logique que les plots
    -- de la police (passage le plus proche sur la route à moins de Detect m, sinon arrêt devant).
    VirtualCones = {
        Enabled = true,
        Taper = 30.0,           -- m : biseau avant une voie fermée
        Spacing = 3.0,          -- m entre deux plots le long de la voie
        LineSpacing = 2.0,      -- m entre deux plots d'une ligne en travers
        Inset = 0.3,            -- m à l'intérieur de la bande
        Detect = 12.0, Margin = 0.8, MaxShift = 9.0, PassBeyond = 8.0, PassSpeed = 7.0, DrivingStyle = 820,
        MaxDeviateTime = 15000,
    },

    -- Choix de la zone du trafic (visée de la route)
    Editor = {
        Range = 150.0,          -- m : portée de la visée au sol
        SnapDistance = 14.0,    -- m : distance max à la route visée
        NodePreview = true,     -- nœuds affichés autour de la visée (vert : ouvert, orange : concerné, rouge : fermé)
        NodeCount = 120,        -- nœuds lus autour de la zone (zone + périmètre en amont)
        FillLanes = true,       -- voies remplies au sol (cases transparentes : zone, autres voies du sens, autre sens)
        -- Vues pour choisir la zone (menu ; V pendant le choix) : joueur, dessus, libre
        CameraRange = 100.0,    -- m : les caméras du dessus / libre restent à moins de 100 m du joueur
        TopHeight = 50.0, TopMin = 15.0, TopMax = 120.0, TopFov = 60.0, TopSpeed = 18.0, -- vue du dessus
        FreeSpeed = 8.0,        -- m/s, caméra libre (Maj : x3)
    },

    -- Cartes (carte du menu pause / mini-carte) : 'everyone', 'police' ou 'none'
    Blips = 'everyone',
    BlipColors = { close = 1, slow = 47, stop = 49 }, -- rouge, orange, rouge foncé

    Range = 400.0,              -- m : PNJ gérés seulement pour les tronçons à moins de 400 m du joueur
    Interval = 300,             -- ms entre deux vérifications des PNJ (tronçon à portée)
}
