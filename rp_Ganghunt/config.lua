--[[
    RP Ganghunt - configuration (partagée client / serveur)
    Tous les modèles, véhicules et armes ci-dessous sont ceux du jeu de base (modifiables librement).
]]
GanghuntConfig = {
    Command = 'ganghunt',          -- /ganghunt : menu ; /ganghunt stop : arrêter la chasse en cours
    MaxWaves = 10,                 -- vagues au plus
    MaxWaveSize = 30,              -- ennemis par vague au plus (choisi dans le menu)
    WaveSize = 10,                 -- ennemis par vague proposés par défaut
    NextWaveDelay = 7000,          -- ms entre la fin d'une vague et la suivante (mode « à la fin de la précédente »)
    -- Mode « après un délai » (choisi dans le menu) : la vague suivante arrive N s après l'arrivée de la précédente,
    -- même si elle n'est pas éliminée (MaxAlive ennemis vivants au plus : sinon elle attend un peu de place)
    WaveTimer = { Default = 60, Min = 15, Max = 600, Step = 15 },
    MaxAlive = 60,
    MaxWeapons = 10,               -- armes choisies au plus
    DefaultSidearm = 'WEAPON_COMBATPISTOL', -- arme de poing donnée en plus d'une arme longue / spéciale

    -- APPARITION : tous dans un rayon de SpawnDistance m autour du joueur, de préférence hors de sa vue, jamais dans
    -- l'eau, sur un toit ou dans un intérieur (au niveau de la rue la plus proche). Véhicules / hélicoptère : en
    -- CONVOI, tous depuis le même point de route ; arrivés à DismountDistance m du joueur, ils descendent (sauf
    -- l'hélicoptère, qui reste en l'air avec ses tireurs).
    SpawnDistance = { 40.0, 70.0 },
    ConvoySpacing = 8.0,           -- m entre deux véhicules du convoi
    HeliHeight = 45.0,             -- m au-dessus du sol à l'apparition
    StreetLevel = 4.0,             -- m d'écart au plus avec la route la plus proche (sinon : toit, pont… refusé)

    -- Combat : animosité au maximum (jamais de fuite, avancent sur le joueur, chargent, corps à corps tout près)
    Accuracy = 40,                 -- précision (0-100)
    Health = 200, Armour = 0,      -- vie des ennemis (200 = normal) ; armure (Forces : voir Factions[].armour)
    Blips = true,                  -- ennemis sur la carte (petits points rouges)
    Melee = { Distance = 2.6, Cooldown = 4000 }, -- à moins de 2,6 m du joueur à pied : corps à corps

    -- DÉPLACEMENTS : un ennemi à pied loin de son objectif (FarDistance m, ou joueur en véhicule à plus de
    -- VehicleChaseDistance m) reprend un véhicule de sa faction (le sien s'il est proche) ; un véhicule poursuit le
    -- joueur en véhicule, ou fonce vers lui s'il est à pied, et ses occupants descendent à DismountDistance m.
    FarDistance = 160.0,
    VehicleChaseDistance = 70.0,
    DismountDistance = 35.0,
    ConvergeDistance = 60.0,       -- repéré : à pied plus loin que ça, ils foncent vers lui en courant
    ConvergeRadius = 12.0,         -- repéré : plus près, ils combattent en avançant jusqu'à ce rayon autour de lui
    DriveSpeed = 35.0,             -- m/s (vers le joueur) ; recherche : SearchDriveSpeed
    SearchDriveSpeed = 14.0,
    DrivingStyle = 1074528293,     -- conduite « pressée » (feux grillés, dépassements)
    ManagerInterval = 1000,        -- ms entre deux vérifications des ennemis
    BodyCleanup = 20000,           -- ms avant que les corps soient rendus au jeu (disparaissent)

    -- RECHERCHE (comme la police du jeu) : tant qu'un ennemi voit le joueur, tous savent où il est (radio). Personne
    -- ne le voit depuis LoseTime ms : ils le cherchent dans une zone autour de sa dernière position connue, qui
    -- s'agrandit ; un ennemi qui le revoit (ou l'entend tirer, ou est touché par lui) : tous reviennent sur lui.
    Search = {
        LoseTime = 8000,           -- ms sans que personne ne le voie avant de le perdre
        Sight = 75.0,              -- m de vue pour le RETROUVER (à pied / en voiture), devant eux
        EngagedSight = 150.0,      -- m : quand ils le combattent, ils le suivent des yeux bien plus loin
        VehicleFactor = 1.5,       -- joueur en véhicule : plus visible (plus gros, plus bruyant)
        Bump = 5.0,                -- m : à côté de lui, ils le trouvent même sans le voir
        HeliSight = 150.0,         -- m de vue depuis l'hélicoptère (projecteur la nuit)
        CloseRange = 12.0,         -- m : vu même de dos (il l'entend)
        StealthFactor = 0.6,       -- joueur accroupi / furtif : vue réduite
        NightFactor = 0.7,         -- la nuit (21 h - 6 h) : vue réduite (sauf hélicoptère)
        Hearing = 120.0,           -- m : un tir du joueur est entendu
        SilencedHearing = 20.0,    -- m : tir avec silencieux
        StartRadius = 35.0, MaxRadius = 140.0, Growth = 2.0, -- zone de recherche (m, m, m par seconde)
        TipInterval = 20000,       -- ms : sans le retrouver, la zone se rapproche du joueur (« renseignements »)
        TipShift = 0.3,            -- part du chemin vers le joueur à chaque fois
        Blip = true,               -- zone de recherche sur la carte
    },

    -- NEUTRES (option du menu) : ils n'attaquent pas tant que le joueur ne les attaque pas (en touchant l'un d'eux
    -- ou leurs véhicules, ou en tirant à moins de ProvokeRange m de l'un d'eux). Ensuite : hostiles jusqu'à ce que
    -- tous les ennemis présents soient éliminés ; une vague qui arrive après redevient neutre. Neutres, ils flânent
    -- où ils sont ; s'il s'éloigne à plus de FollowDistance m, ils se rapprochent (en véhicule : ApproachDistance m).
    Passive = { ProvokeRange = 25.0, WanderRadius = 15.0, ApproachDistance = 40.0, FollowDistance = 90.0 },

    -- GRENADES (option du menu) : un ennemi à pied, à portée, lance de temps en temps une grenade de sa faction
    Grenades = {
        Interval = { 7000, 15000 }, -- ms entre deux lancers (au hasard)
        Range = { 8.0, 40.0 },      -- m du joueur
        Spread = 3.0,               -- m d'imprécision
        Chance = 0.5,               -- part des ennemis qui en ont
        Gang = { 'WEAPON_MOLOTOV', 'WEAPON_GRENADE', 'WEAPON_PIPEBOMB' },
        Org = { 'WEAPON_GRENADE', 'WEAPON_MOLOTOV', 'WEAPON_SMOKEGRENADE' },
        Forces = { 'WEAPON_BZGAS', 'WEAPON_SMOKEGRENADE', 'WEAPON_GRENADE' },
    },

    -- SILENCIEUX (option du menu) : le premier de ces accessoires que l'arme accepte (vérifié par le jeu)
    Suppressors = { 'COMPONENT_AT_PI_SUPP', 'COMPONENT_AT_PI_SUPP_02', 'COMPONENT_AT_AR_SUPP',
        'COMPONENT_AT_AR_SUPP_02', 'COMPONENT_AT_SR_SUPP' },

    -- MUSIQUE (option du menu) : fichiers MP3 à placer dans html/music/, joués à la suite et en boucle pendant toute
    -- la traque (fondu enchaîné de Crossfade ms entre deux morceaux) ; fondu d'entrée (FadeIn ms) au lancement, fondu
    -- de sortie (FadeOut ms) à la fin de la traque entière. Volume : réglé par chaque joueur dans le menu (Volume :
    -- valeur de départ, en %). Shuffle : ordre au hasard.
    Music = {
        Tracks = { 'gtav_wantedlevel1.mp3', 'gtav_wantedlevel2.mp3', 'gtav_wantedlevel3.mp3' },
        Shuffle = false,
        FadeIn = 4000, FadeOut = 5000, Crossfade = 3000,
        Volume = 50,
    },

    Sounds = {
        Spotted = { 'CHECKPOINT_MISSED', 'HUD_MINI_GAME_SOUNDSET' }, -- repéré
        Lost = { 'CHECKPOINT_NORMAL', 'HUD_MINI_GAME_SOUNDSET' },    -- ils vous ont perdu
    },

    -- Armes proposées dans le menu (handgun : arme de poing seule ; special : arme spéciale + arme de poing)
    Weapons = {
        { name = 'WEAPON_PISTOL', label = 'Pistolet', handgun = true },
        { name = 'WEAPON_COMBATPISTOL', label = 'Pistolet de combat', handgun = true },
        { name = 'WEAPON_PISTOL50', label = 'Pistolet .50', handgun = true },
        { name = 'WEAPON_HEAVYPISTOL', label = 'Pistolet lourd', handgun = true },
        { name = 'WEAPON_SNSPISTOL', label = 'Pistolet SNS', handgun = true },
        { name = 'WEAPON_APPISTOL', label = 'Pistolet automatique', handgun = true },
        { name = 'WEAPON_REVOLVER', label = 'Revolver lourd', handgun = true },
        { name = 'WEAPON_MICROSMG', label = 'Micro SMG' },
        { name = 'WEAPON_MINISMG', label = 'Mini SMG' },
        { name = 'WEAPON_MACHINEPISTOL', label = 'Pistolet mitrailleur' },
        { name = 'WEAPON_SMG', label = 'Mitraillette (SMG)' },
        { name = 'WEAPON_ASSAULTSMG', label = 'SMG d\'assaut' },
        { name = 'WEAPON_GUSENBERG', label = 'Gusenberg' },
        { name = 'WEAPON_ASSAULTRIFLE', label = 'Fusil d\'assaut' },
        { name = 'WEAPON_CARBINERIFLE', label = 'Carabine (carbine rifle)' },
        { name = 'WEAPON_ADVANCEDRIFLE', label = 'Fusil avancé' },
        { name = 'WEAPON_SPECIALCARBINE', label = 'Carabine spéciale' },
        { name = 'WEAPON_BULLPUPRIFLE', label = 'Fusil bullpup' },
        { name = 'WEAPON_COMPACTRIFLE', label = 'Fusil compact' },
        { name = 'WEAPON_PUMPSHOTGUN', label = 'Fusil à pompe' },
        { name = 'WEAPON_SAWNOFFSHOTGUN', label = 'Fusil à canon scié' },
        { name = 'WEAPON_ASSAULTSHOTGUN', label = 'Fusil à pompe d\'assaut' },
        { name = 'WEAPON_BULLPUPSHOTGUN', label = 'Fusil à pompe bullpup' },
        { name = 'WEAPON_MG', label = 'Mitrailleuse' },
        { name = 'WEAPON_COMBATMG', label = 'Mitrailleuse de combat' },
        { name = 'WEAPON_MARKSMANRIFLE', label = 'Fusil de précision (marksman)' },
        { name = 'WEAPON_SNIPERRIFLE', label = 'Fusil de sniper' },
        { name = 'WEAPON_HEAVYSNIPER', label = 'Fusil de sniper lourd' },
        { name = 'WEAPON_GRENADELAUNCHER', label = 'Lance-grenades', special = true },
        { name = 'WEAPON_COMPACTLAUNCHER', label = 'Lance-grenades compact', special = true },
        { name = 'WEAPON_RPG', label = 'Lance-roquettes (RPG)', special = true },
        { name = 'WEAPON_HOMINGLAUNCHER', label = 'Lance-missiles à tête chercheuse', special = true },
        { name = 'WEAPON_MINIGUN', label = 'Minigun', special = true },
        { name = 'WEAPON_RAILGUN', label = 'Railgun', special = true },
        { name = 'WEAPON_FIREWORK', label = 'Lance-feux d\'artifice', special = true },
    },

    -- FACTIONS : modèles (choisis au hasard), véhicules (4 places au plus utilisées), hélicoptère, armes « aléatoire »
    Categories = {
        { key = 'gang', label = 'Gang', factions = { 'bikers', 'ballas', 'families', 'vagos' } },
        { key = 'org', label = 'Organisation', factions = { 'chinese', 'armenians', 'koreans', 'mexicans', 'salvadorans', 'merryweather' } },
        { key = 'forces', label = 'Forces', factions = { 'police', 'army', 'sheriff', 'noose' } },
    },
    Factions = {
        bikers = { label = 'Bikers (The Lost MC)',
            models = { 'g_m_y_lost_01', 'g_m_y_lost_02', 'g_m_y_lost_03', 'g_f_y_lost_01' },
            vehicles = { 'gburrito', 'slamvan2', 'hexer', 'daemon' }, heli = 'maverick',
            random = { 'WEAPON_SAWNOFFSHOTGUN', 'WEAPON_PUMPSHOTGUN', 'WEAPON_MICROSMG', 'WEAPON_COMPACTRIFLE', 'WEAPON_PISTOL' } },
        ballas = { label = 'Ballas',
            models = { 'g_m_y_ballasout_01', 'g_m_y_ballaeast_01', 'g_m_y_ballaorig_01', 'g_f_y_ballas_01' },
            vehicles = { 'buccaneer', 'peyote', 'tornado', 'baller' }, heli = 'maverick',
            random = { 'WEAPON_MICROSMG', 'WEAPON_PISTOL', 'WEAPON_SAWNOFFSHOTGUN', 'WEAPON_ASSAULTRIFLE', 'WEAPON_MACHINEPISTOL' } },
        families = { label = 'Families',
            models = { 'g_m_y_famca_01', 'g_m_y_famdnf_01', 'g_m_y_famfor_01', 'g_f_y_families_01' },
            vehicles = { 'emperor', 'manana', 'voodoo', 'baller2' }, heli = 'maverick',
            random = { 'WEAPON_PISTOL', 'WEAPON_MICROSMG', 'WEAPON_SAWNOFFSHOTGUN', 'WEAPON_ASSAULTRIFLE', 'WEAPON_SNSPISTOL' } },
        vagos = { label = 'Vagos',
            models = { 'g_m_y_mexgang_01', 'g_m_y_mexgoon_01', 'g_m_y_mexgoon_03', 'g_f_y_vagos_01' },
            vehicles = { 'chino', 'tornado2', 'buccaneer', 'faction' }, heli = 'maverick',
            random = { 'WEAPON_MICROSMG', 'WEAPON_PISTOL', 'WEAPON_PUMPSHOTGUN', 'WEAPON_ASSAULTRIFLE', 'WEAPON_COMPACTRIFLE' } },
        chinese = { label = 'Chinois (Triades Wei Cheng)',
            models = { 'g_m_m_chigoon_01', 'g_m_m_chigoon_02', 'g_m_m_chiboss_01', 'g_m_m_chicold_01' },
            vehicles = { 'oracle2', 'schafter2', 'cavalcade2', 'fugitive' }, heli = 'swift',
            random = { 'WEAPON_SMG', 'WEAPON_APPISTOL', 'WEAPON_ASSAULTRIFLE', 'WEAPON_PUMPSHOTGUN', 'WEAPON_MICROSMG' } },
        armenians = { label = 'Arméniens',
            models = { 'g_m_m_armgoon_01', 'g_m_y_armgoon_02', 'g_m_m_armlieut_01', 'g_m_m_armboss_01' },
            vehicles = { 'schafter2', 'baller', 'tailgater', 'felon' }, heli = 'frogger',
            random = { 'WEAPON_SMG', 'WEAPON_PISTOL50', 'WEAPON_ASSAULTRIFLE', 'WEAPON_PUMPSHOTGUN', 'WEAPON_MICROSMG' } },
        koreans = { label = 'Coréens (Kkangpae)',
            models = { 'g_m_y_korean_01', 'g_m_y_korean_02', 'g_m_y_korlieut_01', 'g_m_m_korboss_01' },
            vehicles = { 'sultan', 'futo', 'kuruma', 'feltzer2' }, heli = 'maverick',
            random = { 'WEAPON_SMG', 'WEAPON_CARBINERIFLE', 'WEAPON_APPISTOL', 'WEAPON_PUMPSHOTGUN', 'WEAPON_ASSAULTSMG' } },
        mexicans = { label = 'Mexicains (cartel Madrazo)',
            models = { 'g_m_y_mexgoon_02', 'g_m_m_mexboss_01', 'g_m_m_mexboss_02', 'g_m_y_mexgoon_01' },
            vehicles = { 'cavalcade', 'patriot', 'granger', 'bison' }, heli = 'frogger',
            random = { 'WEAPON_ASSAULTRIFLE', 'WEAPON_COMPACTRIFLE', 'WEAPON_PUMPSHOTGUN', 'WEAPON_PISTOL50', 'WEAPON_MICROSMG' } },
        salvadorans = { label = 'Salvadoriens (Marabunta Grande)',
            models = { 'g_m_y_salvagoon_01', 'g_m_y_salvagoon_02', 'g_m_y_salvagoon_03', 'g_m_y_salvaboss_01' },
            vehicles = { 'chino2', 'voodoo2', 'emperor2', 'buccaneer2' }, heli = 'maverick',
            random = { 'WEAPON_MACHINEPISTOL', 'WEAPON_SAWNOFFSHOTGUN', 'WEAPON_MICROSMG', 'WEAPON_ASSAULTRIFLE', 'WEAPON_PISTOL' } },
        merryweather = { label = 'Merryweather', armour = 50,
            models = { 's_m_y_blackops_01', 's_m_y_blackops_02', 's_m_y_blackops_03' },
            vehicles = { 'mesa3', 'crusader', 'dubsta2', 'granger' }, heli = 'annihilator',
            random = { 'WEAPON_CARBINERIFLE', 'WEAPON_SPECIALCARBINE', 'WEAPON_COMBATMG', 'WEAPON_ASSAULTSHOTGUN', 'WEAPON_SMG' } },
        police = { label = 'Police (LSPD)', armour = 25,
            models = { 's_m_y_cop_01', 's_f_y_cop_01' },
            vehicles = { 'police', 'police2', 'police3', 'policet' }, heli = 'polmav',
            random = { 'WEAPON_PISTOL', 'WEAPON_CARBINERIFLE', 'WEAPON_PUMPSHOTGUN', 'WEAPON_SMG' } },
        army = { label = 'Armée', armour = 75,
            models = { 's_m_y_marine_01', 's_m_y_marine_02', 's_m_y_marine_03', 's_m_m_marine_01', 's_m_m_marine_02' },
            vehicles = { 'crusader', 'mesa3', 'barracks' }, heli = 'buzzard',
            random = { 'WEAPON_CARBINERIFLE', 'WEAPON_SPECIALCARBINE', 'WEAPON_COMBATMG', 'WEAPON_MARKSMANRIFLE', 'WEAPON_ASSAULTSHOTGUN' } },
        sheriff = { label = 'Sheriff (BCSO)', armour = 25,
            models = { 's_m_y_sheriff_01', 's_f_y_sheriff_01' },
            vehicles = { 'sheriff', 'sheriff2' }, heli = 'polmav', heliLivery = 1,
            random = { 'WEAPON_PISTOL', 'WEAPON_PUMPSHOTGUN', 'WEAPON_CARBINERIFLE' } },
        noose = { label = 'NOOSE (SWAT)', armour = 100,
            models = { 's_m_y_swat_01' },
            vehicles = { 'riot', 'fbi2', 'fbi' }, heli = 'annihilator',
            random = { 'WEAPON_CARBINERIFLE', 'WEAPON_SMG', 'WEAPON_PUMPSHOTGUN', 'WEAPON_SPECIALCARBINE' } },
    },
}
