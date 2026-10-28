--[[
    RP Weapons Control - configuration
    Chaque arme à feu tenue par un joueur :
      - RECUL : la caméra remonte (et part un peu de côté) à chaque tir, selon le type d'arme (Profiles) ;
      - EFFETS AU TIR : petite secousse chez le tireur ; chez les joueurs proches, secousse (Shake) et ACOUPHÈNE
        (sifflement qui monte avec les tirs proches et redescend, Tinnitus) ;
      - FLASH : un éclair jaune éclaire les alentours du canon à chaque tir, vu par tout le monde autour (Flash) ;
      - FUMÉE : après Smoke.Shots tirs rapides (dans Smoke.Window ms), un filet de fumée sort du canon (vu par tous).
    Une arme avec silencieux : ni flash, ni acouphène, secousse réduite.
]]

WeaponsConfig = {
    -- Par type d'arme (groupe du jeu) : recoil = degrés de remontée par tir, side = écart de côté max (degrés),
    -- shake = secousse du tireur, loudness = force du bruit (acouphène / secousse des voisins, 0-1)
    Profiles = {
        GROUP_PISTOL  = { recoil = 0.9, side = 0.25, shake = 0.035, loudness = 0.7 },
        GROUP_SMG     = { recoil = 0.45, side = 0.20, shake = 0.025, loudness = 0.6 },
        GROUP_RIFLE   = { recoil = 0.6, side = 0.25, shake = 0.04, loudness = 0.9 },
        GROUP_MG      = { recoil = 0.65, side = 0.30, shake = 0.05, loudness = 1.0 },
        GROUP_SHOTGUN = { recoil = 2.4, side = 0.60, shake = 0.12, loudness = 1.0 },
        GROUP_SNIPER  = { recoil = 3.0, side = 0.40, shake = 0.15, loudness = 1.0 },
        GROUP_HEAVY   = { recoil = 2.0, side = 0.50, shake = 0.20, loudness = 1.0 },
    },
    -- Armes jamais concernées (même si leur groupe l'est)
    Excluded = { 'WEAPON_STUNGUN', 'WEAPON_STUNGUN_MP', 'WEAPON_FLAREGUN', 'WEAPON_RADARGUN', 'WEAPON_FIREEXTINGUISHER', 'WEAPON_PETROLCAN' },

    Recoil = { Enabled = true, FirstPerson = 1.15, Vehicle = 1.4, Speed = 1.0 },

    -- Flash de bouche : lumière jaune autour du canon (vue par les joueurs à moins de Range m)
    Flash = { Enabled = true, Range = 90.0, Color = { 255, 186, 92 }, Radius = 7.0, Intensity = 7.0, Duration = 60 },

    -- Fumée du canon après des tirs rapides (filet de fumée)
    Smoke = { Enabled = true, Shots = 7, Window = 3000, Duration = 6000, Cooldown = 4000, Range = 60.0,
        Asset = 'core', Name = 'ent_anim_cig_smoke', Scale = 1.6 },

    -- Acouphène : tirs à moins de Range m (le sien aussi, plus faible : Self) ; volume du sifflement
    Tinnitus = { Enabled = true, Range = 10.0, Self = 0.30, Volume = 0.16, MinDuration = 2500, MaxDuration = 9000 },

    -- Secousse chez les joueurs proches d'un tireur
    Shake = { Enabled = true, Range = 15.0, Amount = 0.12, Name = 'SMALL_EXPLOSION_SHAKE' },

    -- Synchronisation : tirs envoyés par paquets (Batch ms), aux joueurs à moins de Range m
    Sync = { Range = 120.0, Batch = 100, MaxPerSecond = 25 },
}
