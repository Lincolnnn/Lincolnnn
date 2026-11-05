--[[
    RP CamShake - Configuration (client)
    Secousses du jeu : 'HAND_SHAKE' (balancement continu), 'SMALL_EXPLOSION_SHAKE', 'MEDIUM_EXPLOSION_SHAKE',
    'LARGE_EXPLOSION_SHAKE', 'JOLT_SHAKE', 'ROAD_VIBRATION_SHAKE', 'VIBRATE_SHAKE'…
]]
CamShakeConfig = {
    -- Commande pour que chaque joueur active / coupe le tremblement (gardé chez lui) ; false = aucune
    Command = 'tremblement',

    -- À PIED : tremblement continu, de plus en plus fort (amplitude), réglé en douceur
    Walk   = { shake = 'ROAD_VIBRATION_SHAKE', amp = 1.4 },
    Run    = { shake = 'ROAD_VIBRATION_SHAKE', amp = 2.3 },
    Sprint = { shake = 'ROAD_VIBRATION_SHAKE', amp = 3.2 },
    AimFactor = 0.3,      -- en visant avec une arme : amplitude x 0.3 (0 = aucun tremblement en visant)
    Smoothing = 0.35,     -- part du chemin faite à chaque vérification (100 ms) vers l'amplitude voulue

    -- CHOCS : secousse ponctuelle (shake, amplitude, durée avant de reprendre le tremblement de marche, force)
    -- Une secousse plus faible ne remplace pas une plus forte en cours.
    Impacts = {
        carLight  = { shake = 'SMALL_EXPLOSION_SHAKE',  amp = 0.10, duration = 700,  power = 1 }, -- accrochage
        carMedium = { shake = 'MEDIUM_EXPLOSION_SHAKE', amp = 0.18, duration = 1000, power = 2 },
        carHeavy  = { shake = 'LARGE_EXPLOSION_SHAKE',  amp = 0.30, duration = 1500, power = 3 }, -- gros accident
        damage    = { shake = 'SMALL_EXPLOSION_SHAKE',  amp = 0.12, duration = 600,  power = 1 }, -- coup, balle
        fall      = { shake = 'MEDIUM_EXPLOSION_SHAKE', amp = 0.22, duration = 1000, power = 2 }, -- chute
        ragdoll   = { shake = 'LARGE_EXPLOSION_SHAKE',  amp = 0.20, duration = 1200, power = 2 }, -- personnage à terre
        hit       = { shake = 'LARGE_EXPLOSION_SHAKE',  amp = 0.35, duration = 1500, power = 3 }, -- percuté par un véhicule
    },

    -- EN VÉHICULE : aucun tremblement, sauf accident. Accident = la carrosserie / le moteur perd de la vie
    -- (même un petit accrochage), ou une décélération impossible au freinage.
    Crash = {
        HardDrop = 3.0,   -- m/s perdus en 100 ms sans dégât visible : choc quand même (freinage max ≈ 1 m/s)
        Medium = 4.0,     -- m/s perdus en 100 ms (≈ 9 MPH) : secousse moyenne
        Heavy = 9.0,      -- m/s perdus en 100 ms (≈ 20 MPH) : grosse secousse
        BigDamage = 120,  -- points de carrosserie + moteur perdus d'un coup : au moins une secousse moyenne
    },

    FallTime = 600,       -- ms de chute avant qu'une réception compte comme une chute
}
