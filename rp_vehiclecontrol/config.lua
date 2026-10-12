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
        indicatorLeft = 'LEFT',   -- clignotant gauche (flèche gauche, conducteur)
        indicatorRight = 'RIGHT', -- clignotant droit (flèche droite, conducteur)
        hazards = 'DOWN',         -- feux de détresse / warnings (flèche bas, conducteur)
        push = 'K',          -- à pied, devant / derrière un véhicule : pousser / arrêter de pousser
                             -- (près d'un véhicule poussable, K n'ouvre pas le MDC)
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
    -- Le véhicule encaisse comme un vrai : ce qui a été percuté est reconnu au moment du choc.
    --   - LÉGER : piéton, moto, vélo, petits objets (barrière, plot, compteur électrique, poubelle,
    --     panneau…) : le moteur souffre peu ;
    --   - FORT : mur, bâtiment, rocher (décor fixe), voiture, camion, lampadaire, poteau, feu tricolore,
    --     bouche d'incendie… : dégâts du jeu + dégâts selon la violence du choc.
    -- ---------------------------------------------------------------------
    Damage = {
        -- Dégâts du moteur reçus du jeu, multipliés (1.0 = jeu de base ; moins = plus solide)
        LightMultiplier = 0.25,   -- choc léger
        HeavyMultiplier = 0.9,    -- choc fort
        OtherMultiplier = 0.8,    -- sans choc (balles, explosion, chute…)
        BodyToEngine = 0.15,      -- choc fort : part des dégâts de carrosserie reportée sur le moteur
        -- Choc fort et violent (perte de vitesse brutale, en MPH) : dégâts supplémentaires du moteur
        ImpactMinDrop = 20.0,     -- en dessous : rien de plus (un accrochage n'abîme pas le moteur)
        ImpactFactor = 2.5,       -- dégâts = (perte - ImpactMinDrop) ^ 1.5 * ImpactFactor
                                  -- ex. mur à 40 MPH -> ~220 ; à 60 MPH -> ~630 ; à 80 MPH -> ~1160
        EngineFloor = 10.0,       -- ce script n'abaisse jamais le moteur sous cette valeur (pas d'incendie)
        -- Paliers : puissance réduite, calages, véhicule cassé
        Damaged = 500.0,          -- puissance x DamagedPower
        DamagedPower = 0.8,
        Critical = 300.0,         -- puissance x CriticalPower + calages au hasard
        CriticalPower = 0.6,
        StallChance = 0.03,       -- chance de caler par seconde (moteur critique, en roulant)
        Broken = 100.0,           -- en dessous : cassé (moteur coupé, impossible à démarrer, logo rouge)

        -- Ce qui a été percuté : véhicules selon leur classe, objets selon leur modèle
        LightVehicleClasses = { [8] = true, [13] = true }, -- motos, vélos (les autres véhicules : choc fort)
        UnknownObject = 'light',  -- objet absent des deux listes : 'light' ou 'heavy'
        LightModels = {
            -- barrières, plots, séparateurs
            'prop_barrier_work01a', 'prop_barrier_work02a', 'prop_barrier_work04a', 'prop_barrier_work05',
            'prop_barrier_work06a', 'prop_barrier_work06b', 'prop_mp_barrier_01', 'prop_mp_barrier_01b',
            'prop_mp_barrier_02', 'prop_mp_barrier_02b', 'prop_trafficdiv_01a',
            'prop_trafficdiv_02', 'prop_roadcone01a', 'prop_roadcone01b', 'prop_roadcone01c', 'prop_roadcone02a',
            'prop_roadcone02b', 'prop_roadcone02c', 'prop_mp_cone_01', 'prop_mp_cone_02', 'prop_mp_cone_03',
            'prop_mp_cone_04', 'prop_cone_float_1', 'prop_consign_01a', 'prop_consign_02a',
            -- compteurs et boîtiers électriques
            'prop_elecbox_01a', 'prop_elecbox_01b', 'prop_elecbox_02a', 'prop_elecbox_02b', 'prop_elecbox_03a',
            'prop_elecbox_04a', 'prop_elecbox_05a', 'prop_elecbox_06a', 'prop_elecbox_07a', 'prop_elecbox_08',
            'prop_elecbox_09', 'prop_elecbox_10', 'prop_elecbox_11', 'prop_elecbox_12', 'prop_elecbox_13',
            'prop_elecbox_14', 'prop_elecbox_15', 'prop_elecbox_16', 'prop_elecbox_17', 'prop_elecbox_18',
            'prop_elecbox_19', 'prop_elecbox_20', 'prop_elecbox_21', 'prop_elecbox_22', 'prop_elecbox_23',
            'prop_elecbox_24', 'prop_elecbox_25', 'prop_parknmeter_01', 'prop_parknmeter_02',
            -- poubelles, panneaux, mobilier urbain léger
            'prop_bin_01a', 'prop_bin_02a', 'prop_bin_03a', 'prop_bin_04a', 'prop_bin_05a', 'prop_bin_06a',
            'prop_bin_07a', 'prop_bin_07b', 'prop_bin_08a', 'prop_bin_10a', 'prop_bin_12a', 'prop_sign_road_01a',
            'prop_sign_road_02a', 'prop_sign_road_03a', 'prop_sign_road_04a', 'prop_sign_road_05a',
            'prop_sign_road_06a', 'prop_sign_road_07a', 'prop_news_disp_01a', 'prop_news_disp_02a',
            'prop_news_disp_03a', 'prop_news_disp_05a', 'prop_news_disp_06a', 'prop_bench_01a', 'prop_bench_05',
            'prop_fncwood_13c', 'prop_fncwood_14a', 'prop_rub_cardpile_01', 'prop_cs_cardbox_01',
        },
        HeavyModels = {
            -- lampadaires
            'prop_streetlight_01', 'prop_streetlight_01b', 'prop_streetlight_02', 'prop_streetlight_03',
            'prop_streetlight_03b', 'prop_streetlight_03c', 'prop_streetlight_03d', 'prop_streetlight_03e',
            'prop_streetlight_04', 'prop_streetlight_05', 'prop_streetlight_05_b', 'prop_streetlight_06',
            'prop_streetlight_07a', 'prop_streetlight_07b', 'prop_streetlight_08', 'prop_streetlight_09',
            'prop_streetlight_10', 'prop_streetlight_11a', 'prop_streetlight_11b', 'prop_streetlight_11c',
            'prop_streetlight_12a', 'prop_streetlight_12b', 'prop_streetlight_14a', 'prop_streetlight_15a',
            'prop_streetlight_16a',
            -- feux tricolores, poteaux, bouches d'incendie, bornes
            'prop_traffic_01a', 'prop_traffic_01b', 'prop_traffic_01d', 'prop_traffic_02a', 'prop_traffic_02b',
            'prop_traffic_03a', 'prop_traffic_03b', 'prop_traffic_lightset_01', 'prop_telegraph_01a',
            'prop_telegraph_01b', 'prop_telegraph_01c', 'prop_telegraph_01d', 'prop_telegraph_01e',
            'prop_telegraph_01f', 'prop_telegraph_02a', 'prop_telegraph_02b', 'prop_telegraph_03',
            'prop_telegraph_04a', 'prop_telegraph_04b', 'prop_telegraph_05a', 'prop_telegraph_06a',
            'prop_telegraph_06b', 'prop_telegraph_06c', 'prop_fire_hydrant_1', 'prop_fire_hydrant_2',
            'prop_fire_hydrant_2_l1', 'prop_fire_hydrant_4', 'prop_bollard_01a', 'prop_bollard_02a',
            'prop_bollard_02b', 'prop_bollard_03a', 'prop_bollard_04', 'prop_bollard_05', 'prop_postbox_01a',
            'prop_barier_conc_01a', 'prop_barier_conc_01b', 'prop_barier_conc_02a', 'prop_barier_conc_05a',
            'prop_phonebox_01a', 'prop_phonebox_01b', 'prop_phonebox_01c', 'prop_phonebox_02', 'prop_dumpster_01a',
            'prop_dumpster_02a', 'prop_dumpster_02b', 'prop_dumpster_3a', 'prop_dumpster_4a', 'prop_dumpster_4b',
        },
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
    -- Sons du véhicule (html/sounds/*.ogg, remplaçables par vos propres enregistrements) : volume réglé
    -- par chaque joueur dans le MDC (Paramètres > HUD & Display) ; sans le MDC : SoundVolume.
    SoundVolume = 0.7,
    -- Clignotants : arrêtés tout seuls après un virage (le volant revenu droit après avoir tourné de
    -- SignalCancelAngle degrés), comme dans une vraie voiture. 0 pour désactiver.
    SignalCancelAngle = 60.0,
    -- Son des clignotants / warnings : html/sounds/indicators_sound.ogg (votre fichier)
    --   'loop'   : le fichier contient le "tic-tac" et est joué en boucle tant que le clignotant est allumé ;
    --   'repeat' : le fichier est un seul "clic", rejoué toutes les SignalInterval ms.
    SignalSoundMode = 'loop',
    SignalInterval = 370,         -- ms entre deux clics (mode 'repeat' uniquement)
    SignalVolume = 1.0625,        -- volume du son des clignotants (0,85 d'avant + 25 %), x réglage du joueur

    EngineNoticeDuration = 8000,  -- ms : notification "O" en montant côté conducteur (disparaît ensuite)

    -- ---------------------------------------------------------------------
    -- POUSSER UN VÉHICULE (à pied, devant le capot ou derrière le coffre, avec ou sans conducteur) :
    -- touche Keys.push, puis avancer (Z / W) : tout droit uniquement. Quelqu'un au volant : il peut
    -- seulement tourner le volant.
    -- ---------------------------------------------------------------------
    Push = {
        Speed = 1.1,              -- m/s : vitesse du véhicule poussé
        Reach = 1.4,              -- m : zone devant le capot / derrière le coffre où le message apparaît
        Gap = 0.35,               -- m : distance entre le personnage et le pare-chocs pendant la poussée
        Height = 0.95,            -- m : hauteur du personnage par rapport au bas du véhicule
        Anim = { dict = 'missfinale_c2ig_11', clip = 'pushcar_offcliff_m' },
        -- Classes poussables : voitures, SUV, utilitaires, services, urgences, commerciaux
        Classes = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true,
            [7] = true, [9] = true, [10] = true, [11] = true, [12] = true, [17] = true, [18] = true, [20] = true },
    },
}
