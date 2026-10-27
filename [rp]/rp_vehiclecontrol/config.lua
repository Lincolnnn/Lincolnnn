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
    -- RIVEN IMPACT DYNAMICS (script payant de Riven Systems, installé à part, jamais dans ce dépôt) : s'il est sur le
    -- serveur, c'est LUI qui gère les accidents, la carrosserie, le verre, les débris, les tonneaux, les roues, le
    -- terrain, les blessures, la ceinture (touche G, voir son config) et /inspectvehicle, /fieldrepair. Ce script
    -- coupe alors ses propres modules qui feraient doublon (voir README, « Avec Riven Impact Dynamics ») et garde
    -- le reste : essence, moteur (O), portières, clignotants, warnings d'accident, D / R, poussée, motos, tirs, car
    -- HUD du MDC (ceinture lue chez Riven). Mode : 'auto' (dès que la ressource est installée), true ou false.
    -- Pont riven/bridge.lua (UNE ligne à ajouter dans le fxmanifest de Riven, voir README) :
    --   Lamps : ses voyants de dégâts juste au-dessus du car HUD du MDC, liés à lui (place, taille, affichés avec lui) ;
    --     le logo « moteur abîmé » du car HUD disparaît : les dégâts, ce sont ses voyants ;
    --   HideLamps : ses voyants déjà présents sur le car HUD (ceinture) ;
    --   Notify : ses notifications en français, en message privé du chat (titre « Véhicule ») comme les nôtres ;
    --   MuteBelt : true = sans « ceinture attachée / détachée » (le logo du car HUD et le son suffisent).
    -- Pont absent (ligne oubliée) : Fallback = notifications de secours en français (voyants qui s'allument, ceinture)
    -- et HideGameFeed = notifications du jeu (celles de Riven, en anglais) masquées à bord. Console F8 : « pont Riven actif ».
    Riven = { Mode = 'auto', Resource = 'riven-impact-dynamics',
        Lamps = true, HideLamps = { 'belt' }, Notify = true, MuteBelt = false, Fallback = true, HideGameFeed = true },

    Keys = {
        engine = 'O',        -- SEULE touche qui allume / coupe le moteur (conducteur)
        seatbelt = 'G',      -- attacher / détacher la ceinture (K ouvre le MDC)
        door = 'U',          -- sa portière : avant gauche (conducteur) / avant droite (passager avant)
        frontDoors = 'I',    -- les deux portières avant en même temps (conducteur uniquement)
        indicatorLeft = 'LEFT',   -- clignotant gauche (flèche gauche, conducteur)
        indicatorRight = 'RIGHT', -- clignotant droit (flèche droite, conducteur)
        hazards = 'DOWN',         -- feux de détresse / warnings (flèche bas, conducteur)
        gear = 'UP',              -- marche avant (D) / marche arrière (R) (flèche haut, conducteur)
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
        -- Essence d'un véhicule jamais vu, au hasard entre min et max (% du plein) : créé par un script (n'importe
        -- lequel : garage, menu de spawn, /car…) = SpawnedFuel ; véhicule de la circulation = AmbientFuel.
        -- (Un nombre seul, ex. SpawnedFuel = 100.0, donne toujours cette valeur.)
        SpawnedFuel = { min = 35.0, max = 87.0 },
        AmbientFuel = { min = 25.0, max = 85.0 },
        -- Réservoir percé (santé du réservoir sous LeakBelow) : fuite jusqu'à LeakPerMinute % par minute
        LeakBelow = 700.0,
        LeakPerMinute = 4.0,
        -- PLEIN À LA POMPE (client/refuel.lua) : prendre le pistolet (E), le mettre dans la trappe (toujours à l'ARRIÈRE
        -- GAUCHE), moteur coupé. Vitesse : % par seconde (100 / 60 : de vide à plein en 1 minute au maximum).
        RefuelPerSecond = 100.0 / 60.0,
        PumpDistance = 2.5,       -- m : joueur à pied près d'une pompe
        FlapDistance = 1.3,       -- m : joueur près de la trappe à essence
        -- Trappe : côté gauche, à Y (fraction de la longueur, depuis l'arrière) et Z (fraction de la hauteur, depuis le bas)
        Flap = { Y = 0.22, Z = 0.5 },
        Nozzle = {
            Model = 'prop_cs_fuel_nozle',
            HoseLength = 7.0,     -- m : longueur du tuyau (au-delà, le pistolet retourne à la pompe)
            PumpHeight = 1.2,     -- m : hauteur du tuyau sur la pompe
            Rope = true,          -- tuyau visible (corde du jeu), vu par les joueurs proches
            Hand = { 0.13, 0.04, 0.01, -42.0, -115.0, -63.42 },  -- position du pistolet dans la main droite
            -- Pistolet dans la trappe : décalage x y z (m, par rapport à la carrosserie à la trappe ; x négatif = vers
            -- l'extérieur) et rotation, ordre de rotation du jeu. Réglage en jeu : commande vc_nozzle x y z rx ry rz [ordre]
            -- (pistolet dans une trappe), puis recopier les valeurs affichées dans la console F8.
            InFlap = { -0.10, 0.0, 0.05, -125.0, -90.0, -90.0 },
            RotationOrder = 1,
        },
        PumpModels = {
            'prop_gas_pump_1a', 'prop_gas_pump_1b', 'prop_gas_pump_1c', 'prop_gas_pump_1d',
            'prop_gas_pump_old2', 'prop_gas_pump_old3', 'prop_vintage_pump',
        },
        -- JERRICAN (WEAPON_PETROLCAN) : rempli à la pompe (touche G, JerrycanFillTime ms) ou pris dans le coffre d'un
        -- véhicule de police (rp_equipment). Plein, il remplit JerrycanFuel % d'un réservoir (2/5), versé à
        -- JerrycanPerSecond % par seconde (en main près de la trappe : E).
        Jerrycan = true,
        JerrycanFuel = 40.0,
        JerrycanPerSecond = 4.0,
        JerrycanFillTime = 3000,
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
    -- ---------------------------------------------------------------------
    -- TIRS SUR UN VÉHICULE : une balle bien placée abîme vraiment le véhicule (le tireur envoie le point d'impact,
    -- le joueur qui contrôle le véhicule applique les dégâts). Pneus, vitres, carrosserie : le jeu.
    -- ---------------------------------------------------------------------
    Gunshots = {
        Enabled = true,
        EngineBones = { 'engine' }, EngineRadius = 0.85, -- m autour de l'os du moteur
        FrontFallback = 0.33,     -- sans os "engine" : le tiers avant du véhicule
        EngineFactor = 2.2,       -- dégâts moteur = dégâts de l'arme x 2.2 (pistolet ~55, fusil ~70, sniper ~220)
        TankBones = { 'petroltank', 'petroltank_l', 'petroltank_r' }, TankRadius = 0.6,
        TankFactor = 3.0,         -- dégâts du réservoir (fuite d'essence sous Fuel.LeakBelow)
        TankFloor = 50.0,         -- le réservoir ne descend pas plus bas (pas d'explosion causée par ce script)
        DefaultWeaponDamage = 30.0,
        MaxDistance = 300.0,      -- m : tireur trop loin du véhicule -> ignoré (serveur)
        MaxPerSecond = 20,        -- balles prises en compte par tireur et par seconde (serveur)
    },

    -- MARCHE AVANT / MARCHE ARRIÈRE (touche Keys.gear) : en D on ne peut qu'avancer et freiner, en R que freiner et
    -- reculer ; la pédale « interdite » freine puis, à l'arrêt (sous StopSpeed m/s), retient le véhicule.
    Gear = {
        Enabled = true,
        StopSpeed = 0.5,
        Sound = { 'NAV_UP_DOWN', 'HUD_FRONTEND_DEFAULT_SOUNDSET' }, -- petit clic au changement (nil : aucun)
        SkipClasses = { [13] = true, [14] = true, [15] = true, [16] = true, [21] = true }, -- vélos, bateaux, aéronefs, trains
    },

    -- DÉGÂTS VISUELS DES ACCIDENTS. Violence d'un choc (MPH) : la perte de vitesse (on percute) ou la secousse x
    -- JoltFactor (on est percuté, même à l'arrêt ou par l'arrière). Un choc d'au moins MinDrop MPH compte ; il ajoute
    -- sa violence à l'USURE du côté touché (un choc de côté ajoute aussi SideToBumpers x la violence aux pare-chocs).
    -- CE QUI S'OUVRE (Open ; ne se détache jamais, NeverFall) : COFFRE sur un choc à l'arrière, CAPOT sur un choc à
    -- l'avant, PORTIÈRES touchées sur un choc de côté (avant / arrière selon l'endroit du choc), une portière
    -- entrebâillée sur un très gros choc avant / arrière ; aussi dès que l'usure du côté dépasse Open.Wear. Ouverture :
    -- entre Angle[1] et Angle[2] (0 = fermé, 1 = grand ouvert). Unlock : la sécurité saute (déverrouillé).
    -- CE QUI SE DÉTACHE (usure du côté >= Wear, avec Chance) : pare-chocs, pare-brise ; roues : choc d'au moins
    -- Wheel.Drop MPH d'un coup ou usure extrême. CE QUI S'ABÎME : bosses en plus au point d'impact (Deform), vitres du
    -- côté touché, pneu le plus proche qui éclate (Tyre). Carrosserie sous WornBody : seuils x WornFactor.
    -- Véhicule percuté sans conducteur joueur (garé, PNJ) : même calcul, appliqué par celui qui le contrôle (Other).
    Bodywork = {
        Enabled = true,
        MinDrop = 22.0,                          -- en dessous : un accrochage, ne compte pas
        JoltFactor = 1.0,                        -- secousse (percuté) -> violence
        SideToBumpers = 0.4,
        Open = {
            Trunk = { Min = 22.0, Chance = 0.8, Angle = { 0.45, 1.0 } },     -- choc à l'arrière : le coffre s'ouvre
            Hood = { Min = 26.0, Chance = 0.65, Angle = { 0.15, 0.5 } },      -- choc à l'avant : le capot se soulève
            Doors = { Min = 24.0, Chance = 0.6, Angle = { 0.25, 0.7 }, Max = 2 }, -- choc de côté : portières touchées
            FrontRear = { Min = 40.0, Chance = 0.25, Angle = { 0.06, 0.18 } }, -- très gros choc avant / arrière
            Wear = 110.0,                         -- côté très usé : s'ouvre comme sur un choc
            Unlock = true, NeverFall = true,
        },
        Windows = { Wear = 35.0, Chance = 0.4 },  -- vitres du côté touché
        Bumper = { Wear = 60.0, Chance = 0.85 },
        Windscreen = { Wear = 90.0, Chance = 0.5 },
        Wheel = { Drop = 60.0, Wear = 140.0, Chance = 0.5, Second = 0.25 },
        Deform = { Enabled = true, Min = 24.0, Factor = 7.0, Max = 450.0, Radius = 0.8 }, -- bosses en plus
        Tyre = { Min = 35.0, Chance = 0.35 },     -- pneu de la roue la plus proche du choc qui éclate
        Other = { Enabled = true, MaxDistance = 15.0 }, -- véhicule percuté sans conducteur joueur
        WornBody = 400.0, WornFactor = 0.75,
        BumperForce = 900.0, -- déformation appliquée pour arracher un pare-choc
        -- Verre brisé au sol : gros accident (MinDrop MPH), sous chaque vitre qui vient de casser (Outside m à
        -- l'extérieur) : gerbe d'éclats (Effect), DecalCount plaques de verre brisé à plat sur la route (Decals :
        -- décalques "verre" du jeu, 5031 / 5032 ; taille DecalSize m) dans un rayon de Spread m, retirées après
        -- Lifetime ms, bruit du verre (Sound) ; vu et entendu par les joueurs à moins de Range m. Models (facultatif,
        -- vide par défaut) : objets posés en plus (Pieces par vitre, MaxPieces au plus autour de soi).
        Glass = {
            Enabled = true, MinDrop = 35.0, Outside = 0.35,
            Decals = { 5031, 5032 }, DecalCount = 3, DecalSize = { 0.7, 1.3 },
            Pieces = 6, Spread = 0.6, Lifetime = 300000, MaxPieces = 150, Range = 120.0,
            Models = {},
            Effect = { 'core', 'glass_shards', 1.0 },
            Sound = { 'Glass_Smash', 'FBI_HEIST_RAID', 25 }, -- nom, groupe, portée (m) ; nil : seulement le bruit du jeu
        },
        -- pas de dégâts visuels : motos, vélos, bateaux, hélicoptères, avions, trains
        SkipClasses = { [8] = true, [13] = true, [14] = true, [15] = true, [16] = true, [21] = true },
    },

    -- TONNEAUX. Départ (Trip) : un véhicule part plus facilement en tonneau quand il glisse sur le côté à une vitesse
    -- inadaptée : dérapage (glissade latérale d'au moins Slide m/s à au moins MinSpeed MPH), virage mal engagé (il
    -- penche déjà d'au moins Lean degrés : chance x2), PIT (après un choc de côté par un véhicule, pendant PitWindow
    -- ms : glissade PitSlide m/s suffit, chance PitChance). Chance toutes les 100 ms x intensité de la glissade x
    -- ClassFactor du type de véhicule ; il bascule du côté où il glisse (RollSpeed rad/s, élan Lift m/s).
    -- Accentués : un véhicule qui part en tonneau (penché de plus de StartRoll degrés, plus sur ses roues, à au moins
    -- MinSpeed MPH) en fait davantage et plus vite : rotation relancée (au moins RollSpeed rad/s, ou Boost x la
    -- rotation du moment) avec un élan vers le haut (Lift m/s) ; Max relances par accident, une toutes les Interval ms ;
    -- une vitre peut éclater à chaque relance (SmashWindow). Enabled = false : tonneaux du jeu de base.
    Rollover = {
        Enabled = true, MinSpeed = 28.0, StartRoll = 45.0, RollSpeed = 5.2, Boost = 1.45, Lift = 2.0,
        Max = 3, Interval = 550, SmashWindow = true,
        Trip = {
            Enabled = true, MinSpeed = 35.0, Slide = 10.0, Chance = 0.04, Lean = 14.0,
            PitWindow = 2500, PitSlide = 5.0, PitChance = 0.3,
            RollSpeed = 3.2, Lift = 2.4, Cooldown = 4000,
            -- plus haut = bascule plus vite : SUV 2, tout-terrain 9, industriels 10, utilitaires 12, commerciaux 20 ;
            -- plus bas = moins vite : sportives 6, supercars 7, sportives classiques 5
            ClassFactor = { [2] = 1.5, [9] = 1.4, [10] = 1.3, [12] = 1.6, [20] = 1.3, [5] = 0.8, [6] = 0.6, [7] = 0.5 },
        },
        SkipClasses = { [8] = true, [13] = true, [14] = true, [15] = true, [16] = true, [21] = true },
    },

    -- ROUES QUI SE DÉTACHENT hors des chocs. Virage beaucoup trop violent (Turn) : à au moins MinSpeed MPH, accélération
    -- latérale d'au moins Accel m/s² ou glissade latérale d'au moins Slide m/s : la roue avant extérieure peut se
    -- détacher (Chance toutes les 100 ms x l'excès). Trottoir percuté très fort (Curb) : à au moins MinSpeed MPH,
    -- secousse vers le haut d'au moins Jolt m/s d'un coup avec un coup sur le côté / vers l'arrière d'au moins Kick m/s,
    -- roues au sol juste avant : la roue qui a tapé éclate (Burst) ou se détache (Detach), x la violence.
    Wheels = {
        Enabled = true,
        Turn = { Enabled = true, MinSpeed = 60.0, Accel = 16.0, Slide = 12.0, Chance = 0.03 },
        Curb = { Enabled = true, MinSpeed = 35.0, Jolt = 3.0, Kick = 2.0, Burst = 0.45, Detach = 0.15 },
        SkipClasses = { [8] = true, [13] = true, [14] = true, [15] = true, [16] = true, [21] = true },
    },

    -- DÉBRIS : après un gros choc (violence d'au moins Min, pas un piéton ni un plot), des morceaux de carrosserie
    -- restent sur la route du côté touché (Base + 1 par Step de violence, au plus Max ; objets Models posés à plat,
    -- sans collision) avec une gerbe d'étincelles (Effect). Vus par les joueurs à moins de Range m (relayé par le
    -- serveur), retirés après Lifetime ms ; MaxPieces au plus autour de soi (les plus anciens disparaissent).
    -- /cleardebris : retire les débris et le verre autour de soi (chez soi). /cleardebrisall : chez tous les joueurs,
    -- réservé à la permission ACE ClearAllAce (server.cfg : add_ace group.admin rp_vehiclecontrol.cleardebris allow).
    Debris = {
        Enabled = true, Min = 32.0, Base = 2, Step = 12.0, Max = 7, Spread = 1.4,
        Lifetime = 600000, MaxPieces = 120, Range = 150.0,
        Models = { 'prop_rub_carpart_02', 'prop_rub_carpart_03', 'prop_rub_carpart_04', 'prop_rub_carpart_05' },
        Effect = { 'core', 'bul_carmetal', 2.5 },
        Command = 'cleardebris', CommandAll = 'cleardebrisall', ClearAllAce = 'rp_vehiclecontrol.cleardebris',
        ClearRange = 60.0,
        SkipClasses = { [8] = true, [13] = true, [14] = true, [15] = true, [16] = true, [21] = true },
    },

    -- TERRAIN : sol sous le véhicule (lu toutes les Interval ms en roulant). Sur l'herbe, la terre, le gravier, le
    -- sable, la boue, la neige : moins de puissance (Power : 1 = normal), vitesse freinée au-dessus de MaxSpeed MPH et
    -- adhérence réduite (Grip = true : le véhicule glisse). Sol détrempé (pluie d'au moins RainLevel) : effet x Rain.
    -- ClassFactor : part de l'effet subie selon le type de véhicule (tout-terrain, SUV, militaires presque pas ;
    -- sportives, supercars davantage). Surfaces : codes de matière du jeu (/vcsurface, si Debug = true, affiche celui
    -- sous le véhicule pour en ajouter).
    Terrain = {
        Enabled = true, Interval = 250, MinSpeed = 8.0, Rain = 1.35, RainLevel = 0.25, Debug = false,
        Surfaces = {
            grass  = { Power = 0.82, MaxSpeed = 70.0, Grip = false, Materials = { 1333033863, -1286696947, -461750719, -1833527165, 581794674 } },
            dirt   = { Power = 0.88, MaxSpeed = 75.0, Grip = false, Materials = { -1885547121, -700658213, 1144315879, 560985072 } },
            gravel = { Power = 0.85, MaxSpeed = 70.0, Grip = true,  Materials = { 951832588, 2128369009, -356706482 } },
            sand   = { Power = 0.62, MaxSpeed = 45.0, Grip = true,  Materials = { -1595148316, 510490462, 909950165, -1907520769, 1288448767, -1918439396 } },
            mud    = { Power = 0.55, MaxSpeed = 40.0, Grip = true,  Materials = { -1942898710, 1635937914, 1109728704 } },
        },
        ClassFactor = { [9] = 0.2, [19] = 0.2, [2] = 0.55, [10] = 0.6, [11] = 0.7, [20] = 0.7, [12] = 0.85, [6] = 1.2, [7] = 1.35, [5] = 1.15 },
        SkipClasses = { [8] = true, [13] = true, [14] = true, [15] = true, [16] = true, [21] = true },
    },

    -- OCCUPANTS : chaque joueur à bord ressent un gros choc (violence d'au moins Min ; pas un piéton ni un plot).
    -- Blessure (Injury) : (violence - Min) x Factor points de vie (x Belted avec la ceinture), au plus Max, jamais sous
    -- MinHealth (100 = mort : ce script ne tue pas). Effets (Effects) : flash blanc à partir de Flash, vue troublée et
    -- caméra qui tangue (Shake) pendant (violence - Min) x Duration ms (au plus MaxDuration, x Belted avec la ceinture).
    -- Sonné (Stun) : à partir de Min, plus de volant ni de pédales pendant Time ms (x Belted avec la ceinture).
    -- Vue à la première personne (FirstPerson) : la tête part avec le choc (Kick degrés).
    Occupants = {
        Enabled = true, Min = 28.0, Cooldown = 1500,
        Injury = { Enabled = true, Factor = 1.3, Belted = 0.35, Max = 70, MinHealth = 115 },
        Effects = { Enabled = true, Flash = 40.0, Duration = 160, MaxDuration = 9000, Belted = 0.6, Shake = 'DRUNK_SHAKE', ShakeAmp = 0.8, Blur = 'hud_def_blur' },
        Stun = { Enabled = true, Min = 50.0, Time = { 1500, 3500 }, Belted = 0.5 },
        FirstPerson = { Enabled = true, Kick = 9.0 },
        SkipClasses = { [8] = true, [13] = true, [14] = true, [15] = true, [16] = true, [21] = true },
    },

    -- /inspectvehicle : état du véhicule où l'on est (ou du plus proche, Distance m) : moteur, carrosserie, réservoir,
    -- essence, pneus, roues, portières / capot / coffre, pare-chocs, vitres, phares. Affiché Duration ms (la commande
    -- refait disparaît la fiche).
    Inspect = { Command = 'inspectvehicle', Distance = 5.0, Duration = 15000 },

    -- /fieldrepair : réparation de fortune, à pied, devant le capot (FrontDistance m) : animation de Duration ms (capot
    -- ouvert), annulée en s'éloignant ou en montant ; le moteur remonte à Engine (s'il est plus bas) : le véhicule roule
    -- de nouveau, puissance réduite. Au plus Max réparations de fortune par véhicule (une vraie réparation remet le
    -- compte à zéro). Moteur détruit : seulement si AllowDestroyed. Restricted = true : permission ACE
    -- "command.fieldrepair".
    FieldRepair = {
        Command = 'fieldrepair', Restricted = false, Distance = 4.0, FrontDistance = 2.2, Duration = 15000,
        Engine = 450.0, Max = 2, AllowDestroyed = false,
        Anim = { 'mini@repair', 'fixing_a_ped' },
    },

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
        -- Moteur abîmé (sous Damaged) : un peu moins de puissance
        Damaged = 500.0,          -- puissance x DamagedPower
        DamagedPower = 0.8,
        -- PALIER 1 : moteur TRÈS ABÎMÉ (sous Critical) : roule très lentement, cale, fumée sous le capot,
        -- warnings allumés tout seuls (éteints tout seuls au moteur coupé ou au palier 2), logo moteur orange
        Critical = 300.0,
        CriticalPower = 0.35,     -- puissance x CriticalPower
        CriticalMaxSpeed = 25.0,  -- vitesse maximale (MPH)
        StallChance = 0.06,       -- chance de caler par seconde (en roulant)
        StallTime = { 2000, 4500 }, -- calé : il repart tout seul au bout de 2 à 4,5 s (ou tout de suite avec la touche)
        CriticalHazards = true,   -- warnings automatiques
        -- ACCIDENT IMPORTANT (pas un accrochage) : warnings allumés tout seuls (éteints par le conducteur). Choc fort
        -- (mur, voiture, poteau… pas un piéton / plot) avec une perte de vitesse d'au moins MinDrop MPH, ou au moins
        -- MinDamage de dégâts (moteur + carrosserie, sur 1000) pendant le choc.
        AccidentHazards = { Enabled = true, MinDrop = 25.0, MinDamage = 150.0 },
        -- PALIER 2 : moteur DÉTRUIT (sous Broken) : véhicule éteint, moteur coupé, impossible à rallumer, logo rouge
        Broken = 100.0,
        -- Fumée sous le capot (paliers 1 et 2), vue par tous les joueurs jusqu'à Distance m. Le jeu ajoute aussi
        -- sa propre fumée à un moteur très abîmé. Effet : Asset / Name (particules du jeu), Scale (taille).
        Smoke = { Enabled = true, Asset = 'core', Name = 'ent_amb_smoke_foundry', Scale = 0.35, Offset = { 0.0, 0.0, 0.25 }, Distance = 120.0 },

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

    -- PORTIÈRES : descendre portière ouverte, elle RESTE ouverte (le jeu referme la portière à la fin de la descente ; une
    -- portière déjà ouverte avant de descendre, touche U / I, est rouverte aussitôt)
    KeepDoorOpenOnExit = true,

    -- ---------------------------------------------------------------------
    -- CEINTURE
    -- ---------------------------------------------------------------------
    Seatbelt = {
        BeltSoundVolume = 1.0,    -- volume des sons d'attache / de retrait (x réglage du joueur)
        -- Geste en s'attachant : celui du changement de station de radio (haut du corps, flag 48)
        BuckleAnim = { Enabled = true, Driver = { 'veh@std@ds@base', 'change_station' },
            Passenger = { 'veh@std@ps@base', 'change_station' }, Duration = 1300, Flag = 48 },
        -- Carillon de ceinture, par véhicule roulant, en boucle : UN occupant détaché -> html/sounds/belt_chime.ogg ;
        -- PLUSIEURS détachés en même temps -> fast_belt_chime.ogg (belt_chime coupé net, et inversement)
        ChimeVolume = 1.0,        -- volume des carillons de ceinture (x réglage du joueur)
        -- Lecture des carillons de ceinture, comme les clignotants :
        --   'loop'   : le fichier est joué en boucle tant que le carillon a lieu d'être ;
        --   'repeat' : le fichier est rejoué toutes les ChimeInterval ms (un seul "ding" dans le fichier).
        ChimeSoundMode = 'loop',
        ChimeInterval = 1000,     -- ms ('repeat' uniquement)
        -- Boucle RECOLLÉE : la fin du fichier rejoint le début au rythme du carillon (l'écart habituel entre deux
        -- « ding » du fichier), sans pause au passage de la boucle ; un son continu perd son silence de début / fin.
        ChimeSeamless = true,
        -- Sinon (un seul « ding » court dans le fichier) : silence maximal (s) entre deux passages en boucle : un fichier qui finit (ou commence) par
        -- un long silence est raccourci d'autant, sinon le carillon semble s'arrêter puis reprendre tout seul.
        -- 0 : fichiers joués tels quels. (Le silence au milieu du fichier n'est jamais touché.)
        ChimeMaxGap = 1.0,
        AlarmSpeed = 1.0,         -- MPH : carillon dès que le véhicule roule au-dessus (ceinture détachée, moteur allumé)
        -- Ensuite il sonne en boucle sans s'arrêter, jusqu'à ce que le véhicule soit IMMOBILE, la ceinture attachée,
        -- le moteur coupé ou la personne descendue ; il repart dès que le véhicule roule à nouveau.
        -- Un deuxième occupant détaché : fast_belt_chime ; il s'attache : belt_chime.
        StopWhenStopped = true,   -- coupé quand le véhicule est immobile (false : il continue à l'arrêt)
        StopSpeed = 0.3,          -- MPH : en dessous, véhicule immobile (0 MPH, à l'imprécision du jeu près)
        StopDelay = 250,          -- ms d'affilée sous StopSpeed (une lecture isolée ne coupe rien)
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
        --   accident = perte d'au moins AccidentDrop MPH, ou choc contre un véhicule (perte d'au moins VehicleDrop) ;
        --   aussi quand le jeu désarçonne lui-même le motard dans un choc à partir de MinSpeed.
        -- Rien d'autre : pas de chute ajoutée pour les petits incidents (le jeu garde son comportement normal).
        MinSpeed = 35.0,
        AccidentDrop = 8.0,
        VehicleDrop = 3.0,
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
        Pedal = 0.25,             -- pédale simulée chez le conducteur pendant la poussée (le jeu ne freine pas)
        Reach = 1.4,              -- m : zone devant le capot / derrière le coffre où le message apparaît
        Gap = 0.35,               -- m : distance entre le personnage et le pare-chocs pendant la poussée
        Height = 0.95,            -- m : hauteur du personnage par rapport au bas du véhicule
        Anim = { dict = 'missfinale_c2ig_11', clip = 'pushcar_offcliff_m' },
        -- Classes poussables : voitures, SUV, utilitaires, services, urgences, commerciaux
        Classes = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true,
            [7] = true, [9] = true, [10] = true, [11] = true, [12] = true, [17] = true, [18] = true, [20] = true },
    },
}
