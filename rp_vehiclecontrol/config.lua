--[[
    Vehicle Control - configuration (client + serveur)
]]

VCConfig = {
    -- Ressources liées : le MDC dessine le car HUD (et le PLD), le chat reçoit les messages privés
    -- ("Portière ouverte."...). Sans le MDC, tout fonctionne mais rien n'est affiché.
    ChatResource = 'rp_chat',

    -- ---------------------------------------------------------------------
    -- TOUCHES (valeurs par défaut : chaque joueur les change dans
    -- Paramètres > Raccourcis clavier > FiveM)
    -- ---------------------------------------------------------------------
    Keys = {
        engine = 'O',        -- moteur allumé en permanence / coupé (conducteur)
        seatbelt = 'G',      -- attacher / détacher la ceinture (K ouvre le MDC)
        door = 'U',          -- sa portière : avant gauche (conducteur) / avant droite (passager avant)
        frontDoors = 'I',    -- les deux portières avant en même temps (conducteur uniquement)
        parkingBrake = 'L',  -- frein de parcage (conducteur)
    },

    -- ---------------------------------------------------------------------
    -- ESSENCE
    -- ---------------------------------------------------------------------
    Fuel = {
        -- Un plein dure 3 h 30 en temps RÉEL (pas l'heure du jeu) en conduite normale.
        FullTankMinutes = 210,
        -- Consommation selon la charge du moteur (régime) : au ralenti 40 %, conduite normale ~100 %,
        -- pied au plancher 160 %. Moteur coupé : rien.
        IdleFactor = 0.4,
        MaxFactor = 1.6,
        -- Multiplicateur par classe de véhicule (1.0 = 3 h 30). Ex. : [7] = 1.2 pour les super-sportives.
        ClassFactor = {},
        -- Véhicules sans essence (vélos, trains) : jauge masquée, aucune consommation
        NoFuelClasses = { [13] = true, [21] = true },
        -- Essence d'un véhicule jamais vu : créé par un script (garage, menu de spawn) = plein ;
        -- véhicule de la circulation = au hasard entre Min et Max.
        SpawnedFuel = 100.0,
        AmbientFuel = { min = 25.0, max = 85.0 },
        -- Réservoir percé (santé du réservoir sous LeakBelow) : fuite jusqu'à LeakPerMinute % par minute
        LeakBelow = 700.0,
        LeakPerMinute = 4.0,
        -- Plein à la pompe : % par seconde ; le moteur doit être coupé
        RefuelPerSecond = 2.5,
        PumpDistance = 2.5,       -- m : joueur à pied près d'une pompe
        VehicleDistance = 6.0,    -- m : véhicule à faire le plein, autour de la pompe
        PumpModels = {
            'prop_gas_pump_1a', 'prop_gas_pump_1b', 'prop_gas_pump_1c', 'prop_gas_pump_1d',
            'prop_gas_pump_old2', 'prop_gas_pump_old3', 'prop_vintage_pump',
        },
        -- Jerrican (WEAPON_PETROLCAN) : pris à la pompe (touche G), il remplit JerrycanFuel % d'un réservoir
        Jerrycan = true,
        JerrycanFuel = 25.0,
        -- Stations-service sur la carte
        Blips = true,
        Stations = {
            vector3(49.42, 2778.79, 58.04), vector3(263.89, 2606.46, 44.98), vector3(1039.96, 2671.13, 39.55),
            vector3(1207.26, 2660.18, 37.90), vector3(2539.69, 2594.19, 37.94), vector3(2679.86, 3263.95, 55.24),
            vector3(2005.06, 3773.89, 32.40), vector3(1687.16, 4929.39, 42.08), vector3(1701.31, 6416.03, 32.76),
            vector3(179.86, 6602.84, 31.87), vector3(-94.46, 6419.59, 31.49), vector3(-2554.99, 2334.40, 33.08),
            vector3(-1800.38, 803.66, 138.65), vector3(-1437.62, -276.75, 46.21), vector3(-2096.24, -320.29, 13.17),
            vector3(-724.62, -935.16, 19.21), vector3(-526.02, -1211.00, 18.18), vector3(-70.21, -1761.79, 29.53),
            vector3(265.65, -1261.31, 29.29), vector3(819.65, -1028.85, 26.40), vector3(1208.95, -1402.57, 35.22),
            vector3(1181.38, -330.85, 69.32), vector3(620.84, 269.10, 103.09), vector3(2581.32, 362.04, 108.47),
            vector3(176.63, -1562.03, 29.26), vector3(-319.29, -1471.72, 30.55), vector3(1784.32, 3330.55, 41.25),
        },
    },

    -- ---------------------------------------------------------------------
    -- DÉGÂTS (santé du moteur : 1000 = neuf ; le jeu prend feu sous 0)
    -- ---------------------------------------------------------------------
    Damage = {
        EngineMultiplier = 2.5,   -- dégâts du moteur reçus par le jeu, multipliés
        BodyToEngine = 0.6,       -- part des dégâts de carrosserie reportée sur le moteur
        -- Choc violent (perte de vitesse brutale, en MPH) : dégâts supplémentaires du moteur
        ImpactMinDrop = 12.0,     -- en dessous : simple accrochage, rien de plus
        ImpactFactor = 4.0,       -- dégâts = (perte - ImpactMinDrop) ^ 1.5 * ImpactFactor
        EngineFloor = 10.0,       -- ce script n'abaisse jamais le moteur sous cette valeur (pas d'incendie)
        -- Paliers : puissance réduite, calages, véhicule cassé
        Damaged = 650.0,          -- puissance x DamagedPower
        DamagedPower = 0.8,
        Critical = 350.0,         -- puissance x CriticalPower + calages au hasard
        CriticalPower = 0.55,
        StallChance = 0.04,       -- chance de caler par seconde (moteur critique, en roulant)
        Broken = 120.0,           -- en dessous : cassé (moteur coupé, impossible à démarrer, logo rouge)
    },

    -- ---------------------------------------------------------------------
    -- CEINTURE
    -- ---------------------------------------------------------------------
    Seatbelt = {
        AlarmSpeed = 5.0,         -- MPH : bip au-dessus (ceinture détachée), jusqu'à l'arrêt
        StopSpeed = 1.0,          -- MPH : véhicule arrêté
        HearRange = 15.0,         -- m : sons entendus par les joueurs autour
        OutsideVolume = 0.7,      -- volume hors du véhicule (à 0 m) ; occupants : 100 %
        -- Éjection (ceinture détachée) lors d'un accident violent : choc contre un objet fixe ou un véhicule
        --   - au-dessus de HighSpeed MPH : dès que le choc fait perdre au moins HighSpeedDrop MPH ;
        --   - entre MinSpeed et HighSpeed : seulement si la vitesse chute brutalement d'au moins SuddenDrop
        --     MPH (ex. 45 -> 0) ; jamais en dessous de MinSpeed.
        HighSpeed = 55.0,
        HighSpeedDrop = 15.0,
        MinSpeed = 40.0,
        SuddenDrop = 30.0,
        EjectDamage = 35,         -- points de vie perdus par l'éjection
        -- Classes sans ceinture : motos, vélos, bateaux, hélicoptères, avions, trains
        NoBeltClasses = { [8] = true, [13] = true, [14] = true, [15] = true, [16] = true, [21] = true },
    },

    -- ---------------------------------------------------------------------
    -- MOTEUR, PORTIÈRES, FREIN DE PARCAGE
    -- ---------------------------------------------------------------------
    EngineNoticeDuration = 6000,  -- ms : notification "O" en montant côté conducteur
    ParkedRange = 60.0,           -- m : sans frein de parcage, le véhicule laissé reste libre (pente,
                                  -- choc, poussé) tant que son dernier conducteur est à cette distance
    PushSpeed = 1.1,              -- m/s : vitesse à laquelle un joueur à pied pousse un véhicule sans frein
}
