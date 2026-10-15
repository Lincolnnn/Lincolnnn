--[[
    RP Equipment - configuration
    Menu "Équipement" d'un véhicule de police : à pied, près d'une PORTIÈRE AVANT ou du COFFRE, la touche
    (Key, modifiable : Paramètres > Raccourcis clavier > FiveM) ouvre le menu. Il se ferme tout seul au-delà
    de CloseDistance m du véhicule.
]]

EquipConfig = {
    Key = 'E',                    -- touche par défaut (chaque joueur peut la changer)
    PoliceOnly = true,            -- réservé aux policiers en service (dans une unité du MDC)
    MdcResource = 'mdc_standalone',
    ChatResource = 'rp_chat',     -- messages privés (sans rp_chat : notification du jeu)

    InteractDistance = 1.6,       -- m d'une portière avant / du coffre pour voir la proposition et ouvrir le menu
    CloseDistance = 4.0,          -- m du véhicule (carrosserie) : au-delà, le menu se ferme
    OpenTrunk = true,             -- menu ouvert au coffre : le coffre s'ouvre (refermé à la fermeture du menu)

    -- ---------------------------------------------------------------------
    -- TYPES DE VÉHICULES : chaque type a son équipement (voir Equipment.Vehicles)
    -- Un véhicule est d'un type si son modèle est dans Models, sinon si rp_interact (data/vehicles.json) le
    -- range dans un service (ServiceTypes), sinon si sa classe est dans Classes.
    -- ---------------------------------------------------------------------
    Types = {
        apd    = { Label = 'Atlanta Police Department',     Short = 'APD',  Color = '#12357a', Models = {} },
        gsp    = { Label = 'Georgia State Patrol',          Short = 'GSP',  Color = '#ff6a00', Models = {} },
        fcso   = { Label = 'Fayette County Sheriff Office', Short = 'FCSO', Color = '#1e5631', Models = {} },
        -- Véhicules d'urgence (classe 18) qui ne sont dans aucun service : équipement commun
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
    -- ÉQUIPEMENT : ce qu'on prend dans le véhicule
    --   Type   : 'weapon' (Weapon, Ammo, Components), 'ammo' (AmmoType, Amount), 'armor' (Amount),
    --            'health' (Amount) ou 'event' (Event : événement client déclenché, pour un autre script)
    --   Where  : 'front' (portières avant), 'trunk' (coffre) ou 'both'
    --   Vehicles : types de véhicules qui l'ont (absent : tous les types)
    -- ---------------------------------------------------------------------
    Equipment = {
        { Id = 'flashlight',   Label = 'Lampe torche',               Type = 'weapon', Weapon = 'WEAPON_FLASHLIGHT', Ammo = 1, Where = 'front' },
        { Id = 'nightstick',   Label = 'Matraque',                   Type = 'weapon', Weapon = 'WEAPON_NIGHTSTICK', Ammo = 1, Where = 'front' },
        { Id = 'stungun',      Label = 'Taser',                      Type = 'weapon', Weapon = 'WEAPON_STUNGUN', Ammo = 1, Where = 'front' },
        { Id = 'pistol_ammo',  Label = 'Chargeurs de pistolet (x3)', Type = 'ammo', AmmoType = 'AMMO_PISTOL', Amount = 36, Where = 'front' },
        { Id = 'armor',        Label = 'Gilet pare-balles',          Type = 'armor', Amount = 100, Where = 'trunk' },
        { Id = 'medkit',       Label = 'Trousse de premiers secours', Type = 'health', Amount = 50, Where = 'trunk' },
        { Id = 'extinguisher', Label = 'Extincteur',                 Type = 'weapon', Weapon = 'WEAPON_FIREEXTINGUISHER', Ammo = 2000, Where = 'trunk' },
        { Id = 'flares',       Label = 'Fusées de détresse (x5)',    Type = 'weapon', Weapon = 'WEAPON_FLARE', Ammo = 5, Where = 'trunk' },
        { Id = 'rifle_ammo',   Label = 'Munitions de fusil (x60)',   Type = 'ammo', AmmoType = 'AMMO_RIFLE', Amount = 60, Where = 'trunk' },
        { Id = 'shotgun_ammo', Label = 'Cartouches (x16)',           Type = 'ammo', AmmoType = 'AMMO_SHOTGUN', Amount = 16, Where = 'trunk' },
        -- Uniquement dans certains véhicules (exemples)
        { Id = 'flaregun',     Label = 'Pistolet lance-fusées',      Type = 'weapon', Weapon = 'WEAPON_FLAREGUN', Ammo = 10, Where = 'trunk', Vehicles = { 'gsp' } },
        { Id = 'parachute',    Label = 'Parachute',                  Type = 'weapon', Weapon = 'GADGET_PARACHUTE', Ammo = 1, Where = 'trunk', Vehicles = { 'gsp' } },
        -- Exemple pour un autre script (événement client) :
        -- { Id = 'cones', Label = 'Cônes de signalisation', Type = 'event', Event = 'monscript:ouvrirProps', Where = 'trunk', Vehicles = { 'gsp' } },
    },

    -- ---------------------------------------------------------------------
    -- RÂTELIER D'ARMES LONGUES : vide par défaut, un emplacement par sorte d'arme. Le policier range l'arme
    -- qu'il TIENT EN MAIN ("Ranger l'arme longue") : modèle, accessoires, teinte et munitions sont gardés ;
    -- lui ou un collègue la ressort à l'identique. Sauvegardé par plaque (data/racks.json) : gardé au
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
        -- Accessoires d'armes ajoutées (addon) à reconnaître en plus de ceux du jeu, ex. { 'COMPONENT_MON_VISEUR' }
        ExtraComponents = {},
        -- Noms affichés (armes du jeu déjà connues ; ajoutez vos armes addon : ['WEAPON_MONFUSIL'] = 'Mon fusil')
        Names = {},
    },
}
