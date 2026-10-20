--[[
    RP DLS - configuration (partagée client / serveur)
]]
DLSConfig = {
    -- =====================================================================
    -- VÉHICULES DLS : fichiers de DLS solo copiés tels quels dans dls/. Le serveur trouve TOUT SEUL tous les
    -- .xml de dls/ (s'il le permet : sinon un message le dit au démarrage et il faut les lister ici, nom du
    -- fichier sans .xml). Les gyrophares (carcols.meta / carvariations.meta) sont lus TOUT SEULS dans les
    -- ressources de véhicules démarrées (leurs data_file) : rien à copier. Les deux formats :
    --   DLS v1 : un fichier par modèle, nommé comme le modèle ('police' = dls/police.xml) ;
    --            forme longue { model = 'police2', file = 'police' } : un autre modèle sur le même fichier,
    --            native = { 3 } : stages affichés par les gyrophares d'origine du véhicule (son carcols) ;
    --   DLS v2 : <Model vehicles="modèle1,modèle2"> : on met juste le NOM DU FICHIER, ses modèles sont lus
    --            dedans ('nlspdumk' = dls/nlspdumk.xml, pour nlspdbufsxs, nlspdbufsxu…). Il faut aussi son
    --            pack dans Packs (gyrophares du carcols, sur lesquels travaillent les modes DLS v2).
    -- =====================================================================
    Vehicles = {
        'police',                                  -- exemple DLS v1 (dls/police.xml)
        { model = 'police2', file = 'police' },
        'nlspdumk', 'nlspdscouts', 'nlspdmpower',  -- pack NLSPD (DLS v2) : dls/nlspdumk.xml…
    },
    -- Packs de véhicules en plus (facultatif) : dossier dls/packs/<nom>/ contenant un carcols.meta et un
    -- carvariations.meta, si la ressource du véhicule ne les déclare pas en data_file. Les dossiers de dls/packs/
    -- sont aussi trouvés tout seuls (si le serveur permet de lister les dossiers).
    Packs = { 'nlspd' },                           -- dls/packs/nlspd/ (carcols.meta, carvariations.meta)
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
        takedown = 'NUMPAD9',     -- takedown : projecteurs avant (DLS v2 : modes du groupe « Takedown » à la suite)
        alley = 'NUMPAD6',        -- alley : projecteur gauche -> droite -> les deux -> éteint
    },
    Command = 'dls',              -- /dls : panneau cliquable à la souris (déplacer, cliquer les boutons)

    -- =====================================================================
    -- STAGES PAR EXTRAS : véhicules dont le modèle a été modifié pour rattacher des ampoules à des extras
    -- (voir README). Chaque stage est alors affiché par les VRAIS gyrophares du jeu ; les extras éteints cachent
    -- les ampoules qui ne font pas partie du stage. extras = { [n° d'extra] = { gyrophares rattachés } },
    -- off = { [stage] = { extras éteints } } (stage absent : tous les extras allumés).
    -- =====================================================================
    ExtraStages = {
        nlspdsct20 = {
            extras = { [1] = { 1, 2, 3, 4, 5, 10, 13, 14, 15, 16, 29, 30 }, [2] = { 11, 12, 21, 22, 31, 32 } },
            off = { [1] = { 1, 2 }, [2] = { 2 } },
        },
    },

    -- Stationnement (DLS v1) : véhicule arrêté depuis Delay ms, gyrophares allumés, sans sirène -> motif de
    -- stationnement (côté gauche / côté droit en alternance, au rythme Bpm). En DLS v2 : modes « Park » du fichier.
    Park = { Enabled = true, Delay = 2000, Speed = 0.1, Bpm = 300 },
    -- Takedown / alley des véhicules sans DLS v2 : projecteurs blancs dessinés par le script
    Scene = { Distance = 45.0, Brightness = 14.0, Hardness = 2.0, Radius = 25.0, Falloff = 40.0, Tilt = -0.12 },

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
        CoronaSize = 0.012,       -- taille à l'écran d'un halo (× corona size du XML), à 10 m
        CoronaMin = 0.003,        -- taille à l'écran mini / maxi
        CoronaMax = 0.035,
        CoronaAlpha = 235,
        -- Halos (points lumineux dessinés à l'écran) : false = aucun halo, seulement le boîtier de la rampe éclairé
        -- (Lens) et la lumière sur la route / les murs
        Coronas = false,
        CoronaCore = true,        -- point blanc au centre du halo
        FacingFade = true,        -- halo seulement du côté où l'ampoule éclaire
        HideOwnFirstPerson = true,-- pas de halos de son propre véhicule en vue intérieure
        Occlusion = true,         -- halo masqué quand l'ampoule est cachée (toit, carrosserie, boîtier, mur…)
        -- Boîtier de la rampe éclairé autour de chaque ampoule allumée (comme les gyrophares du jeu)
        Lens = { Enabled = true, Range = 0.8, Intensity = 14.0, Push = 0.06 },
        MaxLensLights = 64,       -- lumières de boîtier par image au plus (tous véhicules)
        -- Gyrophare d'intensité >= WorkLightIntensity (takedown / alley DLS v2 : intensity 10) : projecteur
        WorkLightIntensity = 5,
        Work = { Distance = 45.0, Brightness = 2.0, Hardness = 2.0, Radius = 25.0, Falloff = 40.0, Tilt = -0.12 },
    },

    -- Diagnostic : setr dls_debug 1 (console F8) affiche les numéros des gyrophares sur le véhicule
}
