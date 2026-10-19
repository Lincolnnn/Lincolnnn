--[[
    RP Ganghunt - configuration (partagée client / serveur)
    Tous les modèles, véhicules et armes ci-dessous sont ceux du jeu de base (modifiables librement).
]]
GanghuntConfig = {
    Command = 'ganghunt',          -- /ganghunt : menu ; /ganghunt stop : arrêter la chasse en cours
    MaxWaves = 10,
    WaveSize = 10,                 -- ennemis par vague
    NextWaveDelay = 7000,          -- ms entre la fin d'une vague et la suivante
    MaxWeapons = 10,               -- armes choisies au plus
    DefaultSidearm = 'WEAPON_COMBATPISTOL', -- arme de poing donnée en plus d'une arme longue

    -- Apparition : hors de vue, autour du joueur
    SpawnDistance = { 90.0, 150.0 }, -- m (à pied et en véhicule, sur la route la plus proche)
    HeliDistance = 260.0, HeliHeight = 70.0,

    -- Combat
    Accuracy = 35,                 -- précision (0-100)
    Health = 200, Armour = 0,      -- vie des ennemis (200 = normal) ; armure (Forces : voir Factions[].armour)
    Blips = true,                  -- ennemis sur la carte (petits points rouges)

    -- TRAQUE : pas de périmètre. Un ennemi à pied trop loin du joueur (FarDistance m, ou joueur en véhicule à plus de
    -- VehicleChaseDistance m) reçoit un véhicule de sa faction (jusqu'à 4 par véhicule) et le poursuit ; un véhicule
    -- poursuit à pleine vitesse, ses passagers tirent ; près du joueur à pied, ils descendent et combattent.
    FarDistance = 160.0,
    VehicleChaseDistance = 70.0,
    DismountDistance = 30.0,
    ManagerInterval = 1000,        -- ms entre deux vérifications des ennemis
    BodyCleanup = 20000,           -- ms avant que les corps soient rendus au jeu (disparaissent)

    -- Armes proposées dans le menu (groupe : arme de poing -> pas d'arme de poing en plus)
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
