--[[
    RP Equipment - configuration
    Menu "Équipement" d'un véhicule de police : à pied, près d'une PORTIÈRE AVANT ou du COFFRE, la touche
    (Key, modifiable : Paramètres > Raccourcis clavier > FiveM) ouvre le menu. Il se ferme tout seul au-delà
    de CloseDistance m du véhicule.
]]

EquipConfig = {
    Key = 'E',                    -- touche par défaut (chaque joueur peut la changer)
    PoliceOnly = true,            -- réservé aux policiers en service (dans une unité du MDC)
    MdcResource = 'mdc_standalone', -- nom du dossier du MDC si le MDC ne le publie pas lui-même
    ChatResource = 'rp_chat',     -- messages privés (sans rp_chat : notification du jeu)

    InteractDistance = 1.6,       -- m d'une portière avant / du coffre pour voir la proposition et ouvrir le menu
    CloseDistance = 4.0,          -- m du véhicule (carrosserie) : au-delà, le menu se ferme
    OpenTrunk = true,             -- menu ouvert au coffre : le coffre s'ouvre (refermé à la fermeture du menu)

    -- ---------------------------------------------------------------------
    -- TYPES DE VÉHICULES : un type par catégorie (son équipement : equipment.json)
    -- Un véhicule est d'un type si son modèle est dans Models, sinon si rp_interact (data/vehicles.json) le
    -- range dans une catégorie ("Service" : ServiceTypes), sinon si sa classe est dans Classes.
    -- ---------------------------------------------------------------------
    Types = {
        apd    = { Label = 'Atlanta Police Department',     Short = 'APD',  Color = '#12357a', Models = {} },
        gsp    = { Label = 'Georgia State Patrol',          Short = 'GSP',  Color = '#ff6a00', Models = {} },
        fcso   = { Label = 'Fayette County Sheriff Office', Short = 'FCSO', Color = '#1e5631', Models = {} },
        -- Véhicules d'urgence (classe 18) qui ne sont dans aucune catégorie : râtelier, et objets de la catégorie
        -- "Police" d'equipment.json (jerrican)
        police = { Label = 'Véhicule de police',            Short = 'POLICE', Color = '#3a3a3a', Models = {}, Classes = { 18 } },
    },
    -- Services de rp_interact/data/vehicles.json ("Service") -> type
    InteractVehicles = { Resource = 'rp_interact', File = 'data/vehicles.json' },
    ServiceTypes = {
        ['atlanta police department'] = 'apd',
        ['georgia state patrol'] = 'gsp',
        ['fayette county sheriff office'] = 'fcso',
    },

    -- ---------------------------------------------------------------------
    -- ÉQUIPEMENT EUP (casque, gilet, casquette…) : fichier equipment.json de ce dossier, une liste par
    -- catégorie de véhicule ("Atlanta Police Department", "Georgia State Patrol", "Fayette County Sheriff
    -- Office" : la catégorie du véhicule dans rp_interact/data/vehicles.json, champ "Service"). Chaque pièce
    -- s'écrit comme une tenue du /eup ("Name", "Gender", et seulement les parties qu'elle change, ex.
    -- "Armor": "13:1") : le policier la met et la retire de sa tenue depuis le menu.
    -- OBJETS : une entrée avec "Weapon" (et "Ammo") est un objet que le policier PREND et RANGE, ex. le jerrican
    -- d'essence (fourni dans toutes les catégories de police : { "Name", "Weapon": "WEAPON_PETROLCAN", "Ammo": 4500 },
    -- plein = 2/5 d'un réservoir avec rp_vehiclecontrol). Catégorie "Police" : véhicules de police sans service.
    -- ---------------------------------------------------------------------
    EquipmentFile = 'equipment.json',
    Eup = { OneBased = true },    -- numéros comptés à partir de 1, comme les tenues du /eup (rp_interact)

    -- ---------------------------------------------------------------------
    -- RÂTELIER D'ARMES LONGUES : vide par défaut, un emplacement par sorte d'arme. Le policier range l'arme
    -- qu'il TIENT EN MAIN ("Ranger l'arme longue") : modèle, accessoires et teintes sont gardés ; lui ou un
    -- collègue la ressort à l'identique (pas de gestion des munitions : l'arme ressort avec GiveAmmo). Sauvegardé par plaque (data/racks.json) : gardé au
    -- redémarrage du serveur et quand le véhicule réapparaît avec la même plaque.
    -- ---------------------------------------------------------------------
    LongGuns = {
        Where = 'both',           -- 'front', 'trunk' ou 'both'
        Vehicles = nil,           -- types de véhicules qui ont un râtelier (nil : tous)
        Slots = {
            { Id = 'shotgun', Label = 'Fusil à pompe',   Groups = { 'GROUP_SHOTGUN' } },
            { Id = 'rifle',   Label = 'Fusil d\'assaut', Groups = { 'GROUP_RIFLE' } },
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
    -- ---------------------------------------------------------------------
    Stock = {
        Enabled = true,
        Where = 'trunk',          -- 'trunk', 'front' ou 'both'
        SaveFile = 'data/stock.json',
        Cones = {
            Default = 6, Max = 10,
            MaxCarry = 10,        -- plots qu'un policier porte en même temps (il choisit combien il en prend)
            PickupRadius = 8.0,   -- œil « Ramasser les plots autour » : plots à moins de 8 m du plot visé
            Model = 'prop_roadcone02a',
            PlaceDistance = 0.8,  -- m devant le joueur
            -- Plots portés : os de la main droite, décalage x y z et rotation, animation (porter un carton) ;
            -- pile : un objet par plot (MaxProps au plus), chacun StackStep m au-dessus du précédent
            Carry = { Bone = 28422, Offset = { 0.0, -0.05, -0.15, 0.0, 0.0, 0.0 }, Anim = { 'anim@heists@box_carry@', 'idle' },
                MaxProps = 5, StackStep = 0.07 },
        },
        Flares = { Default = 0, Max = 20, Weapon = 'WEAPON_FLARE' },
        PlaceKey = 'G',
    },
}
