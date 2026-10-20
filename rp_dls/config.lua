--[[
    RP DLS - configuration (partagée client / serveur)
]]
DLSConfig = {
    -- =====================================================================
    -- VÉHICULES DLS : un fichier dls/<modèle>.xml chacun (fichiers de DLS solo, tels quels).
    -- Forme longue : { model = 'police3', file = 'police' } (plusieurs modèles sur un même fichier),
    -- native = { 3 } : stages affichés par les gyrophares d'origine du véhicule (son carcols), voir README.
    -- =====================================================================
    Vehicles = {
        'police',
        { model = 'police2', file = 'police' },
    },
    -- Groupes de motifs du Traffic Advisor : dls/trafficadvisory/<nom>.xml (balise <TAgroup> des véhicules)
    TrafficAdvisoryGroups = { 'default' },

    -- Stage 3 = gyrophares d'origine (carcols) pour TOUS les véhicules DLS, même sans GetStage3FromCarcols :
    -- rendu parfait du jeu (ampoules allumées, phares wig-wag) et les PNJ se rangent. Les autres stages sont
    -- dessinés par le script à partir du XML. false : stage 3 dessiné à partir du XML lui aussi.
    Stage3FromCarcols = true,

    -- Véhicules d'urgence SANS fichier DLS (classe 18) : gyrophares du jeu + sons, klaxon, manuel, scan
    -- (comme SirenControlNonDLS de DLS). false : laissés au jeu.
    SirenControlNonDLS = true,
    DefaultTones = { 'VEHICLES_HORNS_SIREN_1', 'VEHICLES_HORNS_SIREN_2', 'VEHICLES_HORNS_POLICE_WARNING', 'VEHICLES_HORNS_AMBULANCE_WARNING' },
    DefaultHorn = 'SIRENS_AIRHORN',
    -- Coupe la sirène quand le conducteur descend (SirenKill de DLS ; SirenKillOverride du XML le force)
    SirenKill = false,
    -- Radio du véhicule coupée tant qu'on conduit un véhicule DLS (comme DLS)
    DisableRadio = true,

    -- =====================================================================
    -- ALLUMER / ÉTEINDRE LES GYROPHARES : uniquement la touche du JEU DE BASE (même touche pour les deux).
    -- C'est un contrôle de GTA, réglé dans les paramètres du jeu (pas dans les raccourcis FiveM) :
    -- 85 = gyrophares / roue des radios : Q sur un clavier QWERTY, A sur un clavier AZERTY, croix gauche à la
    -- manette. Les touches DLS ci-dessous changent seulement le stage quand les gyrophares sont allumés.
    -- =====================================================================
    LightsControl = 85,
    -- Stage allumé par cette touche : 'last' (dernier stage utilisé sur ce véhicule, sinon le premier du XML)
    -- ou un numéro (1, 2, 3, 4 = custom 1, 5 = custom 2)
    LightsOnStage = 'last',

    -- =====================================================================
    -- TOUCHES par défaut : chaque joueur les change dans Échap > Paramètres > Raccourcis clavier > FiveM
    -- (« DLS : … »). Celles de DLS solo, sauf K (MDC), G (ceinture) et T (chat) déjà prises sur ce serveur.
    -- =====================================================================
    Keys = {
        stageNext = 'J',          -- stage suivant (1 -> 2 -> 3 -> … -> 1), gyrophares allumés
        stage1 = 'NUMPAD1',       -- stage 1 direct, gyrophares allumés
        stage2 = 'NUMPAD2',
        stage3 = 'NUMPAD3',
        trafficAdvisor = 'L',     -- Traffic Advisor : gauche -> diverge -> droite -> warn -> éteint
        taPattern = 'NUMPAD4',    -- motif suivant du Traffic Advisor
        steadyBurn = 'LBRACKET',  -- Steady Burn / Cruise (feux fixes)
        interiorLight = 'RBRACKET',
        blackout = 'NUMPAD0',     -- tout éteindre, phares compris (furtif)
        sirenToggle = 'R',        -- sirène marche / arrêt (ton suivant au démarrage)
        tone1 = '1', tone2 = '2', tone3 = '3', tone4 = '4',
        aux = '6',                -- deuxième sirène (ton 1) par-dessus la première
        manual = 'B',             -- sirène manuelle (maintenir) ; E (klaxon) = air horn
        scan = 'NUMPAD7',         -- scan : tons changés au hasard toutes les 2 à 8 s
        lock = 'NUMPAD8',         -- verrouiller toutes les touches DLS
        panel = 'NUMPAD5',        -- afficher / masquer le panneau
    },
    Command = 'dls',              -- /dls : panneau cliquable à la souris (déplacer, cliquer les boutons)

    -- =====================================================================
    -- RENDU des stages dessinés (lumières du XML)
    -- =====================================================================
    Render = {
        Distance = 160.0,         -- m : gyrophares dessinés jusqu'à cette distance
        LightDistance = 90.0,     -- m : éclairage de la route / des murs jusqu'à cette distance
        MaxLights = 40,           -- éclairages dessinés par image au plus (tous véhicules)
        LightRange = 1.0,         -- × lightFalloffMax du XML (portée de l'éclairage)
        LightIntensity = 6.0,     -- × intensity du XML
        LightPush = 1.2,          -- m : éclairage décalé devant l'ampoule (n'éblouit pas le toit)
        CoronaSize = 0.055,       -- taille à l'écran d'un halo (× corona size du XML), à 10 m
        CoronaMin = 0.006,        -- taille à l'écran mini / maxi
        CoronaMax = 0.09,
        CoronaAlpha = 235,
        CoronaCore = true,        -- point blanc au centre du halo
        FacingFade = true,        -- halo atténué quand l'ampoule regarde de l'autre côté
        HideOwnFirstPerson = true,-- pas de halos de son propre véhicule en vue intérieure
        Occlusion = true,         -- halos masqués quand le véhicule est caché (mur, bâtiment)
    },

    -- Diagnostic : setr dls_debug 1 (console F8) affiche les numéros des gyrophares sur le véhicule
}
