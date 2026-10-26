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
