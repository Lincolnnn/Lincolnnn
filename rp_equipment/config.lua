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
        -- Véhicules d'urgence (classe 18) qui ne sont dans aucune catégorie : râtelier seulement
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
}
