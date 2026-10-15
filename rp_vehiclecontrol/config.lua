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
        engine = 'O',        -- SEULE touche qui allume / coupe le moteur (conducteur)
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
        -- Dégâts du moteur reçus du jeu, multipliés (1.0 = jeu de base ; moins = plus solide).
        -- Véhicules ~8 % plus résistants qu'avant (0.25 / 0.9 / 0.8 / 0.15 / 2.5).
        LightMultiplier = 0.23,   -- choc léger
        HeavyMultiplier = 0.83,   -- choc fort
        OtherMultiplier = 0.74,   -- sans choc (balles, explosion, chute…)
        BodyToEngine = 0.14,      -- choc fort : part des dégâts de carrosserie reportée sur le moteur
        -- Choc fort et violent (perte de vitesse brutale, en MPH) : dégâts supplémentaires du moteur
        ImpactMinDrop = 20.0,     -- en dessous : rien de plus (un accrochage n'abîme pas le moteur)
        ImpactFactor = 2.3,       -- dégâts = (perte - ImpactMinDrop) ^ 1.5 * ImpactFactor
                                  -- ex. mur à 40 MPH -> ~205 ; à 60 MPH -> ~580 ; à 80 MPH -> ~1070
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
    -- /repair : répare UNIQUEMENT le moteur (santé du moteur remise à neuf, véhicule de nouveau
    -- utilisable) ; la carrosserie, les vitres et les dégâts visibles restent tels quels.
    -- Véhicule : celui où l'on est, sinon le plus proche (Distance m).
    -- ---------------------------------------------------------------------
    Repair = {
        Command = 'repair',
        Restricted = false,       -- true : réservé à la permission ACE "command.repair" (server.cfg)
        Distance = 5.0,
    },

    -- ---------------------------------------------------------------------
    -- CARILLON DE PORTIÈRE (html/sounds/door_chime.ogg, en boucle), moteur allumé uniquement : une portière ou
    -- plus ouverte(s), jusqu'à ce qu'elles soient refermées ou que le moteur soit coupé. Il vient du véhicule,
    -- même vide (personne à bord) : entendu à bord, et dehors autour de la carrosserie (VehicleSounds).
    -- ---------------------------------------------------------------------
    DoorChime = {
        Enabled = true,
        Volume = 1.0,             -- volume du carillon de portière (x réglage du joueur dans le MDC)
        -- Une portière qui bouge un instant (vent, choc, joueur qui passe contre) ne coupe pas le carillon :
        -- considérée encore ouverte pendant DoorHold ms après avoir été vue ouverte
        DoorHold = 800,
        -- Après la descente, le carillon du véhicule laissé moteur allumé est suivi jusqu'à TrackDistance m
        TrackDistance = 60.0,
        -- Descendre portière ouverte : elle RESTE ouverte (le jeu referme la portière à la fin de la descente)
        KeepDoorOpenOnExit = true,
    },

    -- ---------------------------------------------------------------------
    -- CEINTURE
    -- ---------------------------------------------------------------------
    Seatbelt = {
        BeltSoundVolume = 1.0,    -- volume des sons d'attache / de retrait (x réglage du joueur)
        -- Carillon de ceinture, par véhicule roulant, en boucle : UN occupant détaché -> html/sounds/belt_chime.ogg ;
        -- PLUSIEURS détachés en même temps -> fast_belt_chime.ogg (belt_chime coupé net, et inversement)
        ChimeVolume = 1.0,        -- volume des carillons de ceinture (x réglage du joueur)
        -- Lecture des carillons (ceinture ET portière), comme les clignotants :
        --   'loop'   : le fichier est joué en boucle tant que le carillon a lieu d'être ;
        --   'repeat' : le fichier est rejoué toutes les ChimeInterval ms (un seul "ding" dans le fichier).
        ChimeSoundMode = 'loop',
        ChimeInterval = 1000,     -- ms ('repeat' uniquement)
        -- Silence maximal (s) entre deux passages d'un carillon en boucle : un fichier qui finit (ou commence) par
        -- un long silence est raccourci d'autant, sinon le carillon semble s'arrêter puis reprendre tout seul.
        -- 0 : fichiers joués tels quels. (Le silence au milieu du fichier n'est jamais touché.)
        ChimeMaxGap = 1.0,
        AlarmSpeed = 1.0,         -- MPH : carillon dès que le véhicule roule au-dessus (ceinture détachée, moteur allumé)
        -- Ensuite il sonne en boucle SANS JAMAIS S'ARRÊTER, jusqu'à ce que la ceinture soit attachée, le moteur
        -- coupé ou la personne descendue. Un deuxième occupant détaché : fast_belt_chime ; il s'attache : belt_chime.
        StopWhenStopped = false,  -- true : coupé aussi quand le véhicule s'arrête (sous StopSpeed pendant StopDelay ms)
        StopSpeed = 0.5,          -- MPH (StopWhenStopped uniquement)
        StopDelay = 400,          -- ms (StopWhenStopped uniquement)
        -- Coupé net : plus personne de détaché, véhicule arrêté (relancé du début quand il repart).
        -- ÉJECTION (ceinture détachée uniquement), jamais lors d'un simple accrochage :
        --   - pas en dessous de MinSpeed MPH (vitesse avant le choc) ;
        --   - arrêt brutal (vitesse tombée à SuddenStopSpeed MPH ou moins, ex. 60 -> 20) : SuddenChance ;
        --   - accident (perte d'au moins AccidentDrop MPH) sans chute aussi brutale : CrashChance.
        -- Projeté par l'élan du véhicule, en ragdoll, dans le sens de la course. Distance IDÉALE (pas une limite) :
        -- IdealMinDistance m à MinSpeed MPH -> IdealMaxDistance m à MaxDistanceSpeed MPH et plus. Une impulsion de
        -- départ seulement : la physique du jeu fait le reste (un peu plus loin en roulant, moins loin si obstacle).
        Eject = true,
        MinSpeed = 60.0,
        SuddenStopSpeed = 20.0,
        SuddenChance = 0.70,      -- 70 %
        AccidentDrop = 10.0,
        CrashChance = 0.45,       -- 45 %
        IdealMinDistance = 20.0,
        IdealMaxDistance = 60.0,  -- distance idéale à ne pas trop dépasser : la propulsion est limitée pour ça
        MaxDistanceSpeed = 120.0,
        AirShare = 0.8,           -- part de la distance idéale faite en vol (le reste : glissade / roulé au sol)
        ThrowLift = 0.35,         -- élan vers le haut (part de la vitesse horizontale)
        PushTime = 150,           -- ms pendant lesquelles l'impulsion de départ est réappliquée
        EjectDamage = 35,         -- points de vie perdus par l'éjection
        -- Classes sans ceinture : motos, vélos, bateaux, hélicoptères, avions, trains
        NoBeltClasses = { [8] = true, [13] = true, [14] = true, [15] = true, [16] = true, [21] = true },
    },

    -- ---------------------------------------------------------------------
    -- MOTOS : projections et chutes (pas de ceinture), pilote ET passager
    -- ---------------------------------------------------------------------
    Bike = {
        Enabled = true,
        Classes = { [8] = true },  -- 8 = motos (ajoutez [13] = true pour les vélos)
        -- PROJECTION (même système que les voitures : ragdoll, impulsion de départ, la physique fait le reste)
        --   accident à partir de MinSpeed MPH (vitesse avant le choc) : ThrowChance (85 %) ;
        --   accident = perte d'au moins AccidentDrop MPH, ou choc contre un véhicule (perte d'au moins SmallDrop) ;
        --   aussi quand le jeu désarçonne lui-même le motard dans un choc à partir de MinSpeed.
        MinSpeed = 35.0,
        AccidentDrop = 8.0,
        ThrowChance = 0.85,       -- 85 %
        -- Distance IDÉALE (pas une limite), plus grande avec la vitesse :
        -- IdealMinDistance m à MinSpeed MPH -> IdealMaxDistance m à MaxDistanceSpeed MPH et plus
        IdealMinDistance = 12.0,
        IdealMaxDistance = 60.0,
        MaxDistanceSpeed = 120.0,
        -- Sens : dans la course (petit écart de ForwardSpread degrés), sauf OffAxisChance (25 %) des projections :
        --   sur le CÔTÉ, gauche ou droite (SideAngle degrés par rapport à la course, SideDistance de la distance) ;
        --   vers l'ARRIÈRE (RearShare d'entre elles, RearDistance de la distance) seulement quand c'est probable :
        --   choc contre une voiture / un camion (véhicule lourd). Sinon, toujours sur le côté.
        OffAxisChance = 0.25,     -- 25 %
        RearShare = 0.35,
        ForwardSpread = 10.0,
        SideAngle = { 45.0, 80.0 },
        SideDistance = 0.75,
        RearSpread = 25.0,
        RearDistance = 0.4,
        ThrowDamage = 30,         -- points de vie perdus par la projection
        -- CHUTE de la moto (ragdoll SANS projection, élan de la moto gardé) : petits incidents à partir de
        -- FallMinSpeed MPH : FallChance (80 %). Petit incident : piéton renversé, poteau / panneau / objet ou
        -- véhicule touché (perte d'au moins SmallDrop MPH), trottoir (secousse verticale brusque d'au moins
        -- CurbJolt m/s, roues au sol juste avant ; 0 = pas de détection des trottoirs), mur / décor (perte
        -- d'au moins SmallWorldDrop MPH, plus qu'un freinage).
        FallChance = 0.80,        -- 80 %
        FallMinSpeed = 8.0,
        SmallDrop = 3.0,
        SmallWorldDrop = 6.0,
        CurbJolt = 3.5,
        FallIfNotThrown = true,   -- accident sans projection (les 15 % restants) : chute possible (FallChance)
        FallDamage = 5,
        -- Une chute garde l'élan de la moto : le motard part en ragdoll AVEC la moto (même vitesse, il glisse et
        -- roule au sol), jamais arrêté net ni posé à côté. FallCarry : part de la vitesse de la moto gardée ;
        -- FallSide : m/s vers un côté (il bascule) ; FallPushTime : ms pendant lesquelles l'élan est réappliqué.
        FallCarry = 1.0,
        FallSide = 1.5,
        FallPushTime = 200,
    },

    -- ---------------------------------------------------------------------
    -- MOTEUR, PORTIÈRES, FREIN DE PARCAGE
    -- ---------------------------------------------------------------------
    -- Sons du véhicule (html/sounds/*.ogg, remplaçables par vos propres enregistrements) : volume réglé
    -- par chaque joueur dans le MDC (Paramètres > HUD & Display) ; sans le MDC : SoundVolume.
    SoundVolume = 0.7,
    -- Clignotants / warnings, ceinture (attache, retrait) et carillon : entendus à 100 % par les occupants,
    -- et autour du véhicule (distance mesurée depuis la carrosserie, même véhicule laissé vide) :
    VehicleSounds = {
        RangeOpen = 3.0,          -- m : une portière (ou le coffre / le capot) ouverte
        RangeClosed = 1.0,        -- m : tout fermé ; le son est alors étouffé (filtre passe-bas)
        OpenVolume = 0.8,         -- volume juste à côté, portière ouverte
        ClosedVolume = 0.4,       -- volume juste à côté, tout fermé (réduction du bruit)
    },
    -- Clignotants : arrêtés tout seuls après un virage (le volant revenu droit après avoir tourné de
    -- SignalCancelAngle degrés), comme dans une vraie voiture. 0 pour désactiver.
    SignalCancelAngle = 60.0,
    -- Son des clignotants / warnings : html/sounds/indicators_sound.ogg (votre fichier)
    --   'loop'   : le fichier contient le "tic-tac" et est joué en boucle tant que le clignotant est allumé ;
    --   'repeat' : le fichier est un seul "clic", rejoué toutes les SignalInterval ms.
    SignalSoundMode = 'loop',
    SignalInterval = 370,         -- ms entre deux clics (mode 'repeat' uniquement)
    SignalVolume = 1.6,           -- volume du son des clignotants / warnings, x réglage du joueur

    EngineNoticeDuration = 8000,  -- ms : notification "O" en montant côté conducteur (disparaît ensuite)
    EngineStartTime = 1200,       -- ms : durée du démarrage (démarreur) pendant laquelle on ne peut pas accélérer
    -- Feux stop : allumés quand le véhicule est à l'arrêt, moteur tournant, conducteur au volant (vus par tous)
    StopLights = true,
    -- Roues : en descendant, la position du volant (roues braquées) est gardée telle quelle (vue par tous)
    KeepWheelAngle = true,

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
