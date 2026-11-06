--[[
    RP VehicleProps - configuration (client et serveur)
    Objets possibles : Props (id unique, nom affiché, modèle du jeu, catégorie). Le serveur n'accepte QUE ces modèles.
    Liste des modèles du jeu : https://gtahash.ru ou https://forge.plebmasters.de/objects
]]

VPConfig = {
    Distance = 3.0,          -- œil : distance maximale au véhicule visé (m)
    ServerDistance = 8.0,    -- serveur : distance maximale entre le joueur et le véhicule (m)
    MaxPerVehicle = 12,      -- objets au plus par véhicule
    Restricted = false,      -- true : réservé à la permission ACE "rp_vehicleprops.use" (server.cfg)

    -- Éditeur : position (m, par rapport au centre du véhicule) et rotation (degrés)
    Editor = {
        Range = 3.0,                         -- position de -Range à +Range sur chaque axe
        Step = 0.01,                         -- pas des curseurs de position (x sensibilité)
        RotStep = 1.0,                       -- pas des curseurs de rotation (x sensibilité)
        Sensitivity = { default = 1.0, min = 0.05, max = 3.0, step = 0.05 },
    },

    -- ARME OU LAMPE TENUE EN MAIN (œil de rp_interact) :
    --   sur un véhicule : « Poser l'arme ici » (point visé), « … sur le toit », « … sur le coffre » (coffre plat :
    --     berlines…) : posée directement sur la carrosserie (sans glisser), inclinée comme elle, au ras ; collée au
    --     véhicule avec ses accessoires (rp_interact), sa teinte, ses munitions, sa lampe allumée ; « Reprendre : … » ;
    --   ailleurs (sol, mur, personne…) : « Poser l'arme / la lampe au sol », de la même façon ; « Ramasser : … ».
    --   Le Taser : au sol avec rp_taser10 (sondes gardées). La jeter : rp_RoleplayZone (touche G), inchangé.
    Held = {
        Enabled = true,
        MaxWeaponsPerVehicle = 4,
        GroundDistance = 3.0,   -- au sol : au point visé s'il est à moins de … m, sinon devant soi
        GroundMax = 0,          -- objets posés au sol en même temps, par joueur (0 = sans limite ; GroundTotal s'applique)
        GroundTotal = 100,      -- au sol, en tout (au-delà : le plus ancien disparaît)
        PickupDistance = 2.5,   -- ramasser : à moins de … m de l'objet
        PickupSnap = 0.8,       -- œil : objet au sol à moins de … m du point visé
        Lift = 0.004,           -- m au-dessus de la surface (au ras sans la traverser)
        -- Lampes : modèle posé (celui de CartoonFlashlight, la lampe tenue en main), lumière du modèle
        Torches = { WEAPON_FLASHLIGHT = 'prop_cs_police_torch' },
        -- Lampe posée AU SOL : toujours ce modèle (lampe de poche au sol)
        GroundTorches = { WEAPON_FLASHLIGHT = 'prop_cs_police_torch_02' },
        TorchBeamAxis = nil,    -- faisceau dessiné : axe du modèle ('x', '-x', 'y', '-y', 'z', '-z') ; nil : le plus long
        -- Jamais posées
        Excluded = { 'WEAPON_PETROLCAN', 'WEAPON_HAZARDCAN', 'WEAPON_FERTILIZERCAN', 'WEAPON_FIREEXTINGUISHER', 'WEAPON_PARACHUTE' },
        ExcludedGroups = { 'GROUP_THROWN', 'GROUP_PETROLCAN', 'GROUP_FIREEXTINGUISHER', 'GROUP_DIGISCANNER' },
        -- Lampes torches posées allumées : lumière du modèle ; Drawn = true : faisceau dessiné en plus (vu par tous
        -- à moins de Range m). Arme avec une lampe allumée : vraie lampe du jeu sur l'arme posée.
        Beam = { Drawn = false, Range = 60.0, Color = { 255, 246, 228 }, Distance = 22.0, Brightness = 5.0,
            Hardness = 2.0, Radius = 13.0, Falloff = 30.0 },
    },

    -- CHAPEAU / LUNETTES (tenues EUP ou du jeu), VUS ET REPRIS PAR TOUS (serveur, aucune permission) :
    --   - tombés (chute, coup, balle, ragdoll de rp_adrenaline…) : posés au sol chez tous les joueurs ;
    --   - œil : « Ramasser : chapeau » / « Ramasser : lunettes » : n'importe quel joueur dont le personnage a le même
    --     modèle (homme / femme) ; remis tels quels (même modèle EUP, même texture).
    --   (Poser son chapeau sur un véhicule : retiré, ça ne fonctionnait pas.)
    -- Objet affiché : le VRAI chapeau EUP (RealObject : un personnage local invisible le porte, le jeu le lui fait
    -- tomber, l'objet est gardé). Sinon (échec, ou RealObject = false) : Models (par ancre : 0 chapeau, 1 lunettes) ;
    -- Overrides : un modèle précis pour un numéro (compté comme dans outfits.json si OneBased), il remplace le vrai.
    --   CheckMs : vérification de la tenue (ms) | Distance : ramasser à moins de … m | Snap : œil à moins de … m de
    --   l'objet | Expire : disparaît du sol après … s | GroundTotal : au sol en tout (le plus ancien disparaît)
    LostProps = { Enabled = true, CheckMs = 300, Distance = 2.5, Snap = 1.2, Expire = 900, GroundTotal = 60,
        Anim = { 'pickup_object', 'pickup_low', 900 },
        RealObject = true,
        Models = { [0] = 'prop_cap_01', [1] = 'prop_cs_sol_glasses' },
        OneBased = true,
        Overrides = {
            -- { anchor = 0, drawable = 14, gender = 'male', model = 'reh_prop_reh_hat_cowboy_01a' }, -- EXEMPLE : chapeau à bord
            -- { anchor = 0, drawable = 22, model = 'prop_hard_hat_01' },                                  -- EXEMPLE : casque de chantier
        } },

    Props = {
        { id = 'pistol',     label = 'Pistolet',                category = 'Armes',      model = 'w_pi_combatpistol' },
        { id = 'shotgun',    label = 'Fusil à pompe',           category = 'Armes',      model = 'w_sg_pumpshotgun' },
        { id = 'drugpack',   label = 'Paquet de drogue',        category = 'Illégal',    model = 'prop_drug_package_02' },
        { id = 'drugpack2',  label = 'Paquet de drogue (2)',    category = 'Illégal',    model = 'hei_prop_hei_drug_pack_02' },
        { id = 'moneybag',   label = 'Sac d\'argent',           category = 'Illégal',    model = 'prop_money_bag_01' },
        { id = 'radio',      label = 'Radio portative',         category = 'Objets',     model = 'prop_cs_walkie_talkie' },
        { id = 'torch',      label = 'Lampe torche',            category = 'Objets',     model = 'prop_cs_police_torch' },
        { id = 'backpack',   label = 'Sac à dos',               category = 'Objets',     model = 'prop_michael_backpack' },
        { id = 'case',       label = 'Mallette',                category = 'Objets',     model = 'prop_ld_case_01' },
        { id = 'toolbox',    label = 'Caisse à outils',         category = 'Objets',     model = 'prop_tool_box_04' },
        { id = 'jerrycan',   label = 'Jerrican',                category = 'Objets',     model = 'prop_ld_jerrycan_01' },
        { id = 'cardbox',    label = 'Carton',                  category = 'Objets',     model = 'prop_cs_cardbox_01' },
        { id = 'shopbag',    label = 'Sac de courses',          category = 'Objets',     model = 'prop_cs_shopping_bag' },
        { id = 'pizza',      label = 'Boîte à pizza',           category = 'Objets',     model = 'prop_pizza_box_02' },
        { id = 'whiskey',    label = 'Bouteille de whisky',     category = 'Objets',     model = 'prop_cs_whiskey_bottle' },
        { id = 'cone',       label = 'Plot de signalisation',   category = 'Objets',     model = 'prop_roadcone02a' },
    },
}
