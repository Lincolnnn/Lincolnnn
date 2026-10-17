--[[
    RP RoleplayZone - configuration (partagée client / serveur)
]]
SceneConfig = {
    -- Menu des créations (civils) : commande et touche (aucune par défaut : Échap > Paramètres > Raccourcis clavier > FiveM)
    Command = 'scene',
    Key = '',

    -- QUI CRÉE les scènes :
    --   'civil'    : les joueurs en mode civil (rp_interact, Menu F1 > Civil) qui ne sont pas dans une unité du MDC ;
    --   'everyone' : tout le monde.
    -- La permission ACE AdminAce l'autorise toujours, et voit / supprime les scènes de tout le monde
    -- (ex. add_ace group.admin rpscene.admin allow).
    Creators = 'civil',
    AdminAce = 'rpscene.admin',
    MdcResource = 'mdc_standalone', -- seulement si le MDC ne publie pas son nom (GlobalState.mdcResource)

    -- QUI FOUILLE, voit les zones et a l'œil d'aigle : 'police' (unité du MDC) ou 'everyone'
    Searchers = 'police',

    MaxScenes = 80,                -- scènes actives sur le serveur
    MaxPerPlayer = 12,             -- scènes actives par joueur
    Durations = { 30, 60, 120, 240, 0 }, -- minutes proposées (0 = jusqu'à ce qu'on la supprime)
    DefaultDuration = 120,
    RemoveOnDisconnect = false,    -- true : les scènes d'un joueur sont supprimées à sa déconnexion

    TitleLength = 40,              -- titre (facultatif)
    TextLength = 500,              -- description / contenu trouvé

    -- Les trois types (rayons en mètres)
    Zone = { MinRadius = 15.0, MaxRadius = 60.0, DefaultRadius = 25.0, Step = 2.5 },
    Perimeter = { MinRadius = 0.5, MaxRadius = 5.0, DefaultRadius = 1.5, Step = 0.25 },
    Object = { Distance = 1.8 },   -- m autour de l'objet pour le fouiller

    -- Fouille (périmètre / objet) : barre de chargement, X pour annuler
    Search = {
        Time = 6000,               -- ms
        Key = 38,                  -- E
        Distance = 1.2,            -- m en plus du rayon du périmètre
        PerimeterScenario = 'CODE_HUMAN_MEDIC_KNEEL',
        ObjectScenario = 'PROP_HUMAN_BUM_BIN',
        ResultDuration = 25000,    -- ms : fiche du contenu trouvé à l'écran
        AutoMe = true,             -- /me automatique (rp_chat) : « fouille les lieux »
        NotifyCreator = true,      -- le civil est prévenu quand sa scène est fouillée
    },

    -- Zone : cercle sur la carte (seulement quand le policier est dedans), sons
    ZoneBlip = { Color = 0, Alpha = 90 }, -- 0 : blanc
    Sounds = { Volume = 0.45 },    -- 0 à 1 : sons d'entrée / sortie de zone et de l'œil d'aigle (générés par l'interface)

    -- Mode sélection (création) : portée de la visée, épaisseur du cercle blanc
    Selector = { Range = 60.0, ObjectRange = 30.0, Band = 0.18 },

    -- ŒIL D'AIGLE
    Eagle = {
        Command = 'oeildaigle',
        Key = 'CAPITAL',          -- Verr. Maj (comme la capacité spéciale du mode histoire) ; H / J sont déjà pris (emotes)
        Cooldown = 6000,           -- ms entre deux utilisations
        Radius = 15.0,             -- m : portée de l'onde radar
        WaveTime = 1400,           -- ms pour que l'onde aille du joueur à 15 m
        Highlight = 1200,          -- ms : contours blancs d'un objet / véhicule touché par l'onde
        SearchHighlight = 4000,    -- ms : ce qui est à fouiller (4 s au maximum)
        MaxEntities = 160,         -- objets / véhicules mis en contour au plus
        Vehicles = true,           -- contours des véhicules aussi
        HintRange = 100.0,         -- m : zone de recherche pointée (caméra + flèche) à moins de 100 m de son bord
        HintTime = 2600,           -- ms : caméra tournée vers la zone (comme le mode histoire)
        HintFov = 32.0,            -- zoom pendant ce temps
        ArrowTime = 4500,          -- ms : flèche directionnelle à l'écran
        InZoneArrow = true,        -- dans une zone : la flèche pointe la fouille la plus proche (au-delà de 15 m)
        Timecycle = 'hud_def_desat_cold', TimecycleStrength = 0.55, -- teinte pendant l'œil d'aigle ('' : aucune)
        PostFxIn = 'FocusIn', PostFxOut = 'FocusOut',               -- effets d'écran ('' : aucun)
        OutlineShader = 0,         -- 0 ou 1 (SetEntityDrawOutlineShader)
    },

    -- RIEN NE DISPARAÎT : autour des scènes (zone : tout son cercle ; périmètre / objet : ProtectRadius m), les objets
    -- du décor, les PNJ et les véhicules stationnés sont marqués comme entités de mission : un « ClearArea » d'un
    -- autre script ne les retire plus. L'objet à fouiller est en plus remis à sa place s'il disparaît quand même.
    Protect = {
        Enabled = true,
        Range = 150.0,             -- m : protection appliquée par les joueurs à moins de 150 m de la scène
        Radius = 10.0,             -- m autour d'un périmètre / d'un objet
        Objects = true, Peds = true, ParkedVehicles = true,
        MaxPerScene = 250,
        RestoreObject = true,      -- objet à fouiller disparu : remis (copie fixe, propre à chaque joueur)
    },

    -- ARMES LÂCHÉES (mode civil) : arme sortie -> rappel « [G] Lâcher son arme » pendant 10 s (la touche marche
    -- tout le temps) ; 1er appui : « Jeter son arme », molette : « Poser son arme au sol » ; 2e appui : l'action.
    -- L'arme au sol se ramasse uniquement avec l'œil de rp_interact.
    Weapons = {
        Enabled = true,
        CivilOnly = true,          -- seulement en mode civil (rp_interact) et hors unité du MDC (false : tout le monde)
        Command = 'lacherarme', Key = 'G', -- touche modifiable par chaque joueur (raccourcis FiveM)
        ReminderTime = 10000,      -- ms : rappel affiché quand on sort une arme
        ChoiceTimeout = 10000,     -- ms sans réponse : le choix jeter / poser se ferme
        ThrowSpeed = 7.5,          -- m/s vers l'avant
        ThrowUp = 3.0,             -- m/s vers le haut
        ThrowAnim = { 'anim@heists@narcotics@trash', 'throw_b' }, ThrowAnimTime = 1200,
        ThrowRelease = 550,        -- ms après le début du geste : l'arme quitte la main
        Expire = 60,               -- minutes avant de disparaître (0 : jamais)
        MaxPerPlayer = 5,
        PickupDistance = 2.0,
        Blacklist = { 'WEAPON_UNARMED', 'WEAPON_FLARE', 'WEAPON_PETROLCAN', 'WEAPON_FIREEXTINGUISHER' },
    },
}
