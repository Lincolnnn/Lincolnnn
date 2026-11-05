--[[
    RP Stamina - configuration
    ==========================
    Le sprint est limité dès qu'un joueur a une arme dans son INVENTAIRE (pas seulement en main) :
      - POLICE (joueur dans une unité du MDC) : selon le nombre d'ARMES LONGUES sur lui (Police.LongGroups : fusils à
        pompe et fusils d'assaut) : 2 et plus -> 7 s de sprint ; 1 -> 10 s ; aucune -> pas de limite (endurance du jeu) ;
      - CIVILS (mode civil, ou ni civil ni dans une unité) : chaque type d'arme pèse (sauf les armes de poing) ; avec
        plusieurs armes, c'est la plus lourde (le sprint le plus court) qui compte.
    Seul le SPRINT est limité : la course normale (footing) n'a jamais de limite. Sprint épuisé : le joueur passe à la
    course normale, jusqu'à ce qu'il ait repris ResumeAt de son endurance. Sans arme qui pèse (police sans arme longue,
    civil avec seulement des armes de poing) : endurance du jeu, rien ne change, pas de barre.
    Quand une arme se met à peser (prise, ou plus lourde que la précédente) : petite notification sous la barre.
]]

StaminaConfig = {
    Enabled = true,

    -- POLICE : secondes de sprint selon le nombre d'armes longues portées (la dernière ligne = « et plus »)
    Police = {
        LongGroups = { 'GROUP_SHOTGUN', 'GROUP_RIFLE' },  -- fusils à pompe & fusils d'assaut
        Sprint = { [1] = 10, [2] = 7 },  -- 1 arme longue : 10 s ; 2 et plus : 7 s ; aucune : pas de limite
    },

    -- CIVILS : secondes de sprint par type d'arme (la plus lourde portée compte). Armes de poing : aucun poids.
    Civil = {
        Groups = {
            GROUP_RIFLE = 25,    -- fusils d'assaut
            GROUP_SHOTGUN = 25,  -- fusils à pompe
            GROUP_SMG = 25,      -- pistolets-mitrailleurs
            GROUP_MG = 25,       -- mitrailleuses légères
            GROUP_THROWN = 45,   -- armes de jet (grenades, cocktails Molotov, fusées…)
            GROUP_HEAVY = 15,    -- armes lourdes (lance-roquettes, minigun…)
            GROUP_SNIPER = 35,   -- fusils de précision
        },
        MeleeLong = 30,          -- armes blanches longues (MeleeLongWeapons)
        MeleeShort = 50,         -- autres armes blanches (couteau, poing américain, matraque, lampe…)
        MeleeLongWeapons = { 'WEAPON_BAT', 'WEAPON_GOLFCLUB', 'WEAPON_CROWBAR', 'WEAPON_POOLCUE', 'WEAPON_BATTLEAXE',
            'WEAPON_MACHETE', 'WEAPON_WRENCH', 'WEAPON_STONE_HATCHET', 'WEAPON_HATCHET', 'WEAPON_CANDYCANE' },
    },

    -- Récupération (sprint arrêté) : secondes pour reprendre TOUTE l'endurance, à l'arrêt / en marchant, ou en courant
    Regen = { Idle = 20, Run = 45 },
    ResumeAt = 0.25,     -- épuisé : le sprint revient à 25 % d'endurance (pas de « sprint haché »)

    -- Barre en haut au milieu : affichée pendant le sprint et tant que l'endurance n'est pas pleine, puis HideAfter s
    -- (AlwaysShow = true : toujours affichée tant qu'une arme pèse)
    Bar = { AlwaysShow = false, HideAfter = 3 },

    CheckMs = 1000,      -- relecture de l'inventaire (ms)

    -- Notification sous la barre quand une arme se met à peser (prise, ou plus lourde que la précédente)
    Notify = { Enabled = true, Seconds = 4,
        Police = 'Votre arme longue pèse sur vous : votre endurance est réduite.',
        Civil = 'L\'arme que vous portez pèse : votre endurance est réduite.' },

    -- Armes vérifiées dans l'inventaire (le jeu ne sait pas les énumérer) : armes du jeu + armes ajoutées du serveur.
    -- Le TYPE de chaque arme est lu dans le jeu (groupe) : une arme ajoutée n'a qu'à figurer ici.
    Weapons = {
        -- armes blanches
        'WEAPON_DAGGER', 'WEAPON_BAT', 'WEAPON_BOTTLE', 'WEAPON_CROWBAR', 'WEAPON_FLASHLIGHT', 'WEAPON_GOLFCLUB',
        'WEAPON_HAMMER', 'WEAPON_HATCHET', 'WEAPON_KNUCKLE', 'WEAPON_KNIFE', 'WEAPON_MACHETE', 'WEAPON_SWITCHBLADE',
        'WEAPON_NIGHTSTICK', 'WEAPON_WRENCH', 'WEAPON_BATTLEAXE', 'WEAPON_POOLCUE', 'WEAPON_STONE_HATCHET',
        'WEAPON_CANDYCANE',
        -- pistolets-mitrailleurs, mitrailleuses
        'WEAPON_MICROSMG', 'WEAPON_SMG', 'WEAPON_SMG_MK2', 'WEAPON_ASSAULTSMG', 'WEAPON_COMBATPDW', 'WEAPON_MACHINEPISTOL',
        'WEAPON_MINISMG', 'WEAPON_TECPISTOL', 'WEAPON_MG', 'WEAPON_COMBATMG', 'WEAPON_COMBATMG_MK2', 'WEAPON_GUSENBERG',
        -- fusils d'assaut
        'WEAPON_ASSAULTRIFLE', 'WEAPON_ASSAULTRIFLE_MK2', 'WEAPON_CARBINERIFLE', 'WEAPON_CARBINERIFLE_MK2',
        'WEAPON_ADVANCEDRIFLE', 'WEAPON_SPECIALCARBINE', 'WEAPON_SPECIALCARBINE_MK2', 'WEAPON_BULLPUPRIFLE',
        'WEAPON_BULLPUPRIFLE_MK2', 'WEAPON_COMPACTRIFLE', 'WEAPON_MILITARYRIFLE', 'WEAPON_HEAVYRIFLE',
        'WEAPON_TACTICALRIFLE', 'WEAPON_BATTLERIFLE',
        -- fusils à pompe
        'WEAPON_PUMPSHOTGUN', 'WEAPON_PUMPSHOTGUN_MK2', 'WEAPON_SAWNOFFSHOTGUN', 'WEAPON_ASSAULTSHOTGUN',
        'WEAPON_BULLPUPSHOTGUN', 'WEAPON_MUSKET', 'WEAPON_HEAVYSHOTGUN', 'WEAPON_DBSHOTGUN', 'WEAPON_AUTOSHOTGUN',
        'WEAPON_COMBATSHOTGUN',
        -- précision
        'WEAPON_SNIPERRIFLE', 'WEAPON_HEAVYSNIPER', 'WEAPON_HEAVYSNIPER_MK2', 'WEAPON_MARKSMANRIFLE',
        'WEAPON_MARKSMANRIFLE_MK2', 'WEAPON_PRECISIONRIFLE',
        -- armes lourdes
        'WEAPON_RPG', 'WEAPON_GRENADELAUNCHER', 'WEAPON_GRENADELAUNCHER_SMOKE', 'WEAPON_MINIGUN', 'WEAPON_FIREWORK',
        'WEAPON_RAILGUN', 'WEAPON_HOMINGLAUNCHER', 'WEAPON_COMPACTLAUNCHER', 'WEAPON_RAYMINIGUN', 'WEAPON_EMPLAUNCHER',
        'WEAPON_RAILGUNXM3',
        -- armes de jet
        'WEAPON_GRENADE', 'WEAPON_BZGAS', 'WEAPON_MOLOTOV', 'WEAPON_STICKYBOMB', 'WEAPON_PROXMINE', 'WEAPON_SNOWBALL',
        'WEAPON_PIPEBOMB', 'WEAPON_BALL', 'WEAPON_SMOKEGRENADE', 'WEAPON_FLARE', 'WEAPON_ACIDPACKAGE',
        -- armes ajoutées du serveur
        'WEAPON_PM4', 'WEAPON_FM1_M16A4', 'WEAPON_M6IC', 'WEAPON_BEANBAG', 'WEAPON_MP92', 'WEAPON_COLBATON',
        'WEAPON_POCKETLIGHT',
    },

    Debug = false,
}
