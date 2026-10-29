--[[
    RP Weapons Control - configuration
    Chaque arme à feu tenue par un joueur :
      - RECUL (sur le modèle du script de Lyrad / Blumlaut) : à chaque tir, la caméra remonte de Recoil.Step degré par
        image jusqu'à la valeur de l'arme (Weapons), à la 3e personne ; pas en tirant depuis un véhicule (drive-by) ;
      - SECOUSSE au tir (Weapons : shake) ; chez les joueurs proches, petite secousse (Shake) ;
      - ACOUPHÈNE : seulement quand ça tire beaucoup tout près : au moins Tinnitus.Shots tirs en Tinnitus.Window ms par
        des tireurs à moins de Tinnitus.Range m (soi-même, un autre joueur ou un PNJ) ; sifflement léger ;
      - FLASH : un éclair jaune éclaire les alentours du canon à chaque tir, vu par tout le monde autour (Flash) ;
      - FUMÉE : après Smoke.Shots tirs rapides (dans Smoke.Window ms), un filet de fumée sort du canon (vu par tous) ;
      - PAS DE RECHARGEMENT AUTOMATIQUE : chargeur vide, il faut recharger soi-même (touche R) ;
      - LAMPE TOUJOURS ALLUMÉE : une lampe allumée (arme équipée d'une lampe, lampe de poche) le reste, même en courant
        et même si l'arme est rangée puis ressortie (Flashlight) ;
      - SÉLECTEUR DE TIR : coup par coup / automatique sur les armes qui en ont un (FireMode), touche B : petit clic et
        logo en bas au milieu de l'écran.
    Une arme avec silencieux : ni flash, ni acouphène, secousse réduite.
]]

WeaponsConfig = {
    -- Par arme : recoil = remontée totale de la caméra par tir (degrés), shake = secousse du tireur.
    -- Valeurs du script de Lyrad / Blumlaut, à ajuster. Arme absente : valeurs de son type (Profiles).
    Weapons = {
        -- Pistolets
        WEAPON_PISTOL = { recoil = 0.5, shake = 0.045 },       WEAPON_PISTOL_MK2 = { recoil = 0.3, shake = 0.03 },
        WEAPON_COMBATPISTOL = { recoil = 0.5, shake = 0.045},  WEAPON_APPISTOL = { recoil = 0.1, shake = 0.05 },
        WEAPON_PISTOL50 = { recoil = 0.8, shake = 0.07 },      WEAPON_SNSPISTOL = { recoil = 0.2, shake = 0.02 },
        WEAPON_SNSPISTOL_MK2 = { recoil = 0.5, shake = 0.045 }, WEAPON_HEAVYPISTOL = { recoil = 0.5, shake = 0.03 },
        WEAPON_VINTAGEPISTOL = { recoil = 0.5, shake = 0.045 }, WEAPON_MARKSMANPISTOL = { recoil = 0.9, shake = 0.03 },
        WEAPON_REVOLVER = { recoil = 0.5, shake = 0.045 },     WEAPON_REVOLVER_MK2 = { recoil = 0.65, shake = 0.055 },
        WEAPON_DOUBLEACTION = { recoil = 0.5, shake = 0.045 }, WEAPON_MACHINEPISTOL = { recoil = 0.3, shake = 0.035 },
        WEAPON_GLOCK19 = { recoil = 0.5, shake = 0.045 },      WEAPON_FM1_P226 = { recoil = 0.5, shake = 0.045 },
        WEAPON_SWMP9 = { recoil = 0.5, shake = 0.045 },        WEAPON_P320 = { recoil = 0.5, shake = 0.045 },
        -- Pistolets-mitrailleurs, mitrailleuses
        WEAPON_MICROSMG = { recoil = 0.2, shake = 0.035 },     WEAPON_SMG = { recoil = 0.1, shake = 0.045 },
        WEAPON_SMG_MK2 = { recoil = 0.1, shake = 0.055 },      WEAPON_ASSAULTSMG = { recoil = 0.1, shake = 0.05 },
        WEAPON_COMBATPDW = { recoil = 0.2, shake = 0.045 },    WEAPON_MINISMG = { recoil = 0.1, shake = 0.035 },
        WEAPON_GUSENBERG = { recoil = 0.1, shake = 0.05 },     WEAPON_MG = { recoil = 0.1, shake = 0.07 },
        WEAPON_COMBATMG = { recoil = 0.1, shake = 0.08 },      WEAPON_COMBATMG_MK2 = { recoil = 0.1, shake = 0.085 },
        -- Fusils
        WEAPON_ASSAULTRIFLE = { recoil = 0.5, shake = 0.09 },  WEAPON_ASSAULTRIFLE_MK2 = { recoil = 0.2, shake = 0.075 },
        WEAPON_CARBINERIFLE = { recoil = 0.5, shake = 0.09 },  WEAPON_CARBINERIFLE_MK2 = { recoil = 0.1, shake = 0.065 },
        WEAPON_ADVANCEDRIFLE = { recoil = 0.1, shake = 0.06 }, WEAPON_SPECIALCARBINE = { recoil = 0.2, shake = 0.06 },
        WEAPON_SPECIALCARBINE_MK2 = { recoil = 0.25, shake = 0.075 }, WEAPON_BULLPUPRIFLE = { recoil = 0.2, shake = 0.05 },
        WEAPON_BULLPUPRIFLE_MK2 = { recoil = 0.25, shake = 0.065 }, WEAPON_COMPACTRIFLE = { recoil = 0.3, shake = 0.05 },
        WEAPON_PM4 = { recoil = 0.5, shake = 0.09 },           WEAPON_FM1_M16A4 = { recoil = 0.5, shake = 0.09 },
        WEAPON_M6IC = { recoil = 0.5, shake = 0.09 },
        -- Fusils à pompe
        WEAPON_PUMPSHOTGUN = { recoil = 0.4, shake = 0.07 },   WEAPON_PUMPSHOTGUN_MK2 = { recoil = 0.4, shake = 0.085 },
        WEAPON_BEANBAG = { recoil = 0.4, shake = 0.07 },       WEAPON_SAWNOFFSHOTGUN = { recoil = 0.7, shake = 0.06 },
        WEAPON_ASSAULTSHOTGUN = { recoil = 0.4, shake = 0.12 }, WEAPON_BULLPUPSHOTGUN = { recoil = 0.2, shake = 0.08 },
        WEAPON_DBSHOTGUN = { recoil = 0.7, shake = 0.05 },     WEAPON_AUTOSHOTGUN = { recoil = 0.2, shake = 0.08 },
        WEAPON_HEAVYSHOTGUN = { recoil = 0.2, shake = 0.13 },  WEAPON_MUSKET = { recoil = 0.7, shake = 0.04 },
        -- Précision
        WEAPON_SNIPERRIFLE = { recoil = 0.5, shake = 0.2 },    WEAPON_HEAVYSNIPER = { recoil = 0.7, shake = 0.3 },
        WEAPON_HEAVYSNIPER_MK2 = { recoil = 0.7, shake = 0.35 }, WEAPON_MARKSMANRIFLE = { recoil = 0.3, shake = 0.1 },
        WEAPON_MARKSMANRIFLE_MK2 = { recoil = 0.35, shake = 0.1 },
        -- Lanceurs, armes lourdes
        WEAPON_GRENADELAUNCHER = { recoil = 1.0, shake = 0.08 }, WEAPON_COMPACTLAUNCHER = { recoil = 0.5, shake = 0.08 },
        WEAPON_RPG = { recoil = 0.0, shake = 0.9 },            WEAPON_HOMINGLAUNCHER = { recoil = 0.0, shake = 0.9 },
        WEAPON_MINIGUN = { recoil = 0.01, shake = 0.2 },       WEAPON_RAILGUN = { recoil = 2.4, shake = 1.0 },
    },

    -- Par type d'arme (groupe du jeu) : valeurs pour une arme absente de Weapons, force du bruit (loudness, 0-1 :
    -- secousse des voisins). Une arme dont le groupe n'est pas ici n'est pas concernée.
    Profiles = {
        GROUP_PISTOL  = { recoil = 0.3, shake = 0.03, loudness = 0.7 },
        GROUP_SMG     = { recoil = 0.15, shake = 0.045, loudness = 0.6 },
        GROUP_RIFLE   = { recoil = 0.2, shake = 0.065, loudness = 0.9 },
        GROUP_MG      = { recoil = 0.1, shake = 0.08, loudness = 1.0 },
        GROUP_SHOTGUN = { recoil = 0.4, shake = 0.08, loudness = 1.0 },
        GROUP_SNIPER  = { recoil = 0.5, shake = 0.2, loudness = 1.0 },
        GROUP_HEAVY   = { recoil = 0.5, shake = 0.3, loudness = 1.0 },
    },
    -- Armes jamais concernées (même si leur groupe l'est)
    Excluded = { 'WEAPON_STUNGUN', 'WEAPON_STUNGUN_MP', 'WEAPON_FLAREGUN', 'WEAPON_RADARGUN', 'WEAPON_FIREEXTINGUISHER', 'WEAPON_PETROLCAN' },

    -- Recul : Step degrés par image jusqu'à la valeur de l'arme ; Smooth : « scalingFactor » de la caméra (0.2 comme
    -- l'original) ; FirstPerson : recul aussi à la 1re personne (l'original : non) ; DriveBy : en tirant d'un véhicule
    Recoil = { Enabled = true, Step = 0.1, Smooth = 0.2, FirstPerson = false, DriveBy = false, Multiplier = 1.0 },

    -- Pas de rechargement automatique (chargeur vide : touche R)
    NoAutoReload = true,

    -- Lampe toujours allumée : allumée par le joueur (touche du jeu), elle reste allumée (aussi en courant, sans viser)
    -- et se rallume quand l'arme revient en main (rangée puis ressortie, reprise dans l'équipement…). Lampes de poche
    -- simples (WEAPON_FLASHLIGHT, WEAPON_POCKETLIGHT…) : pareil. Toutes les armes sont concernées (une arme sans lampe
    -- n'a rien à rallumer). Éteinte par le joueur : elle reste éteinte.
    Flashlight = { Enabled = true, KeepOnWhileMoving = true },

    -- Sélecteur de tir (coup par coup / automatique) : armes automatiques des groupes Groups et armes Weapons (sauf
    -- Excluded). Touche Key (Raccourcis clavier > FiveM) : petit clic (Volume) et logo en bas au milieu de l'écran,
    -- affiché tant que l'arme est en main (Badge = false : seulement quelques secondes après un changement).
    -- Mode gardé pour chaque arme ; Default : mode d'une arme jamais réglée ('auto' ou 'semi').
    FireMode = {
        Enabled = true, Key = 'B', Default = 'auto', Volume = 0.35, Badge = true,
        Groups = { 'GROUP_SMG', 'GROUP_MG', 'GROUP_RIFLE' },
        Weapons = { 'WEAPON_APPISTOL', 'WEAPON_MACHINEPISTOL', 'WEAPON_ASSAULTSHOTGUN', 'WEAPON_AUTOSHOTGUN' },
        Excluded = {},  -- ex. { 'WEAPON_GUSENBERG' } : arme automatique sans sélecteur
    },

    -- Flash de bouche : lumière jaune autour du canon (vue par les joueurs à moins de Range m)
    Flash = { Enabled = true, Range = 90.0, Color = { 255, 186, 92 }, Radius = 7.0, Intensity = 7.0, Duration = 60 },

    -- Fumée du canon après des tirs rapides (filet de fumée)
    Smoke = { Enabled = true, Shots = 15, Window = 3000, Duration = 6000, Cooldown = 4000, Range = 60.0,
        Asset = 'core', Name = 'ent_anim_cig_smoke', Scale = 1.6 },

    -- Acouphène : Shots tirs au moins en Window ms par des tireurs à moins de Range m (soi, joueurs, PNJ : Npc) ;
    -- sifflement léger (Volume), Duration ms (min / max selon le nombre de tirs) ; Cooldown ms avant un nouveau
    Tinnitus = { Enabled = true, Range = 10.0, Shots = 15, Window = 10000, Npc = true,
        Volume = 0.05, MinDuration = 2500, MaxDuration = 6000, Cooldown = 12000 },

    -- Secousse chez les joueurs proches d'un tireur
    Shake = { Enabled = true, Range = 15.0, Amount = 0.08, Name = 'SMALL_EXPLOSION_SHAKE' },

    -- Synchronisation : tirs envoyés par paquets (Batch ms), aux joueurs à moins de Range m
    Sync = { Range = 120.0, Batch = 100, MaxPerSecond = 25 },
}
