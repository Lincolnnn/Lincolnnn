--[[
    RP Equipment - configuration
    Menu "Équipement" d'un véhicule de police : à pied, près d'une PORTIÈRE AVANT ou du COFFRE, la touche
    (Key, modifiable : Paramètres > Raccourcis clavier > FiveM) ouvre le menu. Il se ferme tout seul au-delà
    de CloseDistance m du véhicule.
]]

EquipConfig = {
    Key = 'E',                    -- touche par défaut (chaque joueur peut la changer)
    PoliceOnly = true,            -- réservé aux policiers en service (dans une unité du MDC)
    MdcResource = 'rp_mdc', -- nom du dossier du MDC si le MDC ne le publie pas lui-même
    ChatResource = 'rp_chat',     -- messages privés (sans rp_chat : notification du jeu)

    InteractDistance = 1.6,       -- m d'une portière avant / du coffre pour voir la proposition et ouvrir le menu
    CloseDistance = 4.0,          -- m du véhicule (carrosserie) : au-delà, le menu se ferme
    OpenTrunk = true,             -- menu ouvert au coffre : le coffre s'ouvre (refermé à la fermeture du menu)
    OpenFrontDoor = true,         -- menu ouvert à l'avant : portière la plus proche (gauche : conducteur, droite :
                                  -- passager avant) ouverte, refermée à la fermeture ; jamais rouverte si déjà ouverte

    -- ---------------------------------------------------------------------
    -- TYPES DE VÉHICULES : un type par police du MDC (son équipement : equipment.json)
    -- Un véhicule est d'un type si son modèle est dans Models, sinon si rp_interact (data/vehicle.json) le
    -- range dans une police ("subCategory" : ServiceTypes), sinon si sa classe est dans Classes.
    -- ---------------------------------------------------------------------
    Types = {
        wsp    = { Label = 'Washington State Patrol',    Short = 'WSP',  Color = '#2d63b3', Models = {} },
        kcso   = { Label = 'King County Sheriff Office', Short = 'KCSO', Color = '#2f7a55', Models = {} },
        -- Véhicules d'urgence (classe 18) qui ne sont dans aucune police : râtelier, et objets de la catégorie
        -- "Police" d'equipment.json
        police = { Label = 'Véhicule de police',         Short = 'POLICE', Color = '#4d5d80', Models = {}, Classes = { 18 } },
    },
    -- Véhicules de rp_interact : data/vehicle.json ("subCategory") ; à défaut, l'ancien data/vehicles.json ("Service")
    InteractVehicles = { Resource = 'rp_interact', File = 'data/vehicle.json', OldFile = 'data/vehicles.json' },
    ServiceTypes = {
        ['washington state patrol'] = 'wsp', wsp = 'wsp',
        ['king county sheriff office'] = 'kcso', ["king county sheriff's office"] = 'kcso', kcso = 'kcso',
    },

    -- ---------------------------------------------------------------------
    -- ÉQUIPEMENT EUP (casque, gilet, casquette…) : fichier equipment.json de ce dossier, une liste par
    -- police ("Washington State Patrol", "King County Sheriff Office" : la police du véhicule dans
    -- rp_interact/data/vehicle.json, champ "subCategory"). Chaque pièce
    -- s'écrit comme une tenue du /eup ("Name", "Gender", et seulement les parties qu'elle change, ex.
    -- "Armor": "13:1") : le policier la met et la retire de sa tenue depuis le menu.
    -- OBJETS : une entrée avec "Weapon" (et "Ammo") est un objet que le policier PREND et RANGE (sans limite). Le
    -- jerrican d'essence n'est plus ici : il est dans le COFFRE (Stock.Jerrycans, un par véhicule, à prendre et ranger).
    -- Catégorie "Police" : véhicules de police d'aucune de ces polices.
    -- ---------------------------------------------------------------------
    EquipmentFile = 'equipment.json',
    Eup = { OneBased = true },    -- numéros comptés à partir de 1, comme les tenues du /eup (rp_interact)

    -- ---------------------------------------------------------------------
    -- RÂTELIER D'ARMES LONGUES : vide par défaut. DEUX emplacements séparés, une arme longue chacun : l'AVANT
    -- (portières avant) et le COFFRE. Une arme rangée à l'avant ne se reprend qu'à l'avant, une arme rangée dans le
    -- coffre qu'au coffre (Slots : Where = 'front' / 'trunk'). Le policier range l'arme
    -- qu'il TIENT EN MAIN ("Ranger l'arme longue") : modèle, accessoires et teintes sont gardés ; lui ou un
    -- collègue la ressort à l'identique (pas de gestion des munitions : l'arme ressort avec GiveAmmo). Sauvegardé par plaque (data/racks.json) : gardé au
    -- redémarrage du serveur et quand le véhicule réapparaît avec la même plaque.
    -- ---------------------------------------------------------------------
    LongGuns = {
        Vehicles = nil,           -- types de véhicules qui ont un râtelier (nil : tous)
        -- Armes longues acceptées (groupes d'armes du jeu) ; un emplacement peut avoir ses propres Groups
        Groups = { 'GROUP_SHOTGUN', 'GROUP_RIFLE', 'GROUP_SNIPER', 'GROUP_MG' },
        Slots = {
            { Id = 'front', Label = 'Avant (habitacle)', Where = 'front' },
            { Id = 'trunk', Label = 'Coffre',            Where = 'trunk' },
        },
        SaveFile = 'data/racks.json',
        GiveAmmo = 250,           -- munitions données avec l'arme quand elle est sortie
        -- Accessoires d'armes ajoutées (addon) à reconnaître en plus de ceux du jeu, ex. { 'COMPONENT_MON_VISEUR' }
        ExtraComponents = {},
        -- Noms affichés (armes du jeu déjà connues ; ajoutez vos armes addon : ['WEAPON_MONFUSIL'] = 'Mon fusil')
        Names = {},
    },

    -- ---------------------------------------------------------------------
    -- COFFRE COMME UN INVENTAIRE (par plaque, SaveFile : gardé au redémarrage) : ce qui est pris n'y est plus,
    -- ce qui est rangé y revient.
    --   - Plots de circulation (bandes blanches) : Default au départ dans chaque coffre, Max au maximum. Pris : le
    --     policier le PORTE ; touche PlaceKey (G) : posé au sol ; l'œil (rp_interact) : "Ramasser le plot" ; menu du
    --     coffre : "Ranger le plot" (n'importe quel coffre, dans la limite).
    --   - Fusées de détresse (WEAPON_FLARE, rp_flares) : rangées / prises comme les armes longues.
    --   - Jerrican d'essence et pistolet radar (WEAPON_RADARGUN) : un de chaque par coffre, à prendre et ranger.
    -- ---------------------------------------------------------------------
    Stock = {
        Enabled = true,
        Where = 'trunk',          -- 'trunk', 'front' ou 'both'
        SaveFile = 'data/stock.json',
        Cones = {
            Default = 7, Max = 10,  -- 7 / 10 dans chaque véhicule de police jamais utilisé
            MaxCarry = 5,         -- plots qu'un policier porte en même temps, 5 au plus (il choisit combien il en prend)
            PickupRadius = 8.0,   -- œil « Ramasser les plots autour » : plots à moins de 8 m du plot visé
            Model = 'prop_roadcone02a',
            PlaceDistance = 0.8,  -- m devant le joueur
            -- Plots portés : os de la main droite, décalage x y z et rotation, animation (porter un carton) ;
            -- pile : un objet par plot (MaxProps au plus), chacun StackStep m au-dessus du précédent
            Carry = { Bone = 28422, Offset = { 0.0, -0.05, -0.15, 0.0, 0.0, 0.0 }, Anim = { 'anim@heists@box_carry@', 'idle' },
                MaxProps = 5, StackStep = 0.07 },
            -- Trafic PNJ (client/traffic.lua) : seulement les plots posés avec ce menu
            Traffic = {
                Enabled = true,
                Detect = 10.0,        -- m : un plot dans sa trajectoire à moins de 10 m devant : contournement anticipé
                GroupDistance = 6.0,  -- plots à moins de 6 m les uns des autres = un même dispositif (ligne, biseau)
                Margin = 0.8,         -- m laissés entre la carrosserie et les plots
                MaxShift = 9.0,       -- m de décalage latéral au plus pour trouver un passage (voie voisine / d'en face)
                PassSpeed = 7.0,      -- m/s pendant le contournement (~25 km/h)
                PassBeyond = 8.0,     -- m après le dernier plot avant de reprendre la route
                ResumeSpeed = 17.0,   -- m/s : vitesse de croisière rendue après le contournement
                SlowSpeed = 8.0,      -- m/s : zone de vitesse du jeu autour du dispositif (0 : aucune)
                SlowRadius = 25.0,    -- m autour du dispositif
                Range = 200.0,        -- m : rien n'est fait pour les dispositifs plus loin du joueur
                Interval = 250,       -- ms entre deux vérifications (dispositif à portée)
                MaxDeviateTime = 15000,
                DrivingStyle = 820,   -- éviter véhicules (4), piétons (16), objets (32), clignotants (256), voie d'en face (512)
            },
        },
        -- Fusées de détresse : dans le coffre (Default au départ, Max au plus) et à l'avant, prises / rangées par les
        -- portières avant (FrontDefault, FrontMax ; 0 : aucune à l'avant)
        Flares = { Default = 10, Max = 15, FrontDefault = 5, FrontMax = 5, Weapon = 'WEAPON_FLARE' },
        -- Jerrican d'essence : PLEIN dans le coffre de chaque véhicule de police (Default), à prendre et ranger ; il garde
        -- l'essence qui lui reste (plein = Ammo = 2/5 d'un réservoir avec rp_vehiclecontrol). /restock le remet plein.
        Jerrycans = { Default = 1, Max = 1, Weapon = 'WEAPON_PETROLCAN', Ammo = 4500 },
        -- Pistolet radar (jumelles de vitesse) : un dans le coffre de chaque véhicule de police, à prendre et ranger
        RadarGuns = { Default = 1, Max = 1, Weapon = 'WEAPON_RADARGUN' },
        -- Herse de riven_spikes (script payant, s'il est installé) : prise et rangée avec l'ŒIL sur le coffre (options de
        -- Riven). Menu = true : ligne « Herse » en plus dans ce menu (désactivée). KeepInHands : en main, la touche X de
        -- Riven ne la fait plus disparaître (elle revient en main) : la poser au sol ou la ranger dans le coffre (œil).
        -- Type : modèle de Riven pris au coffre (stopstick : le seul proposé au coffre, voir la config de riven_spikes).
        Spikes = { Enabled = true, Menu = false, KeepInHands = true, Resource = 'riven_spikes', Type = 'stopstick' },
        PlaceKey = 'G',
        RestockCommand = 'restock', -- /restock : coffre rempli à 100 % (plots, fusées, jerrican, pistolet radar), sauf armes longues
        RestockDistance = 6.0,      -- m : véhicule de police le plus proche (ou celui où l'on est assis)
    },
}
