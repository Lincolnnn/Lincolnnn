--[[
    RP Interact - Configuration (partagée client / serveur)
]]
InteractConfig = {
    -- Touches par défaut (modifiables par chaque joueur : Échap > Paramètres > Raccourcis
    -- clavier > FiveM > "Menu Interaction" et "Œil : interagir (maintenir)")
    MenuKey = 'F1',
    TargetKey = 'LMENU',          -- Alt gauche
    EditorCommand = 'fichecivil', -- commande qui ouvre la fiche civile (création de profils) ; false = aucune

    -- PERMISSIONS (identifiant Steam hex, "steam:1100001..." : visible dans la console du serveur, commande
    -- "status", ou sur un site de conversion SteamID). Les catégories de la partie "Configuration" du
    -- Menu Interaction listées dans Sections sont réservées à ces joueurs (les autres les voient grisées,
    -- le serveur refuse leurs demandes). Sections = {} : ouvertes à tous.
    Permissions = {
        -- TEMPORAIREMENT DÉSACTIVÉES : tout le monde a accès à toutes les catégories. Remettre true pour
        -- réserver les catégories de Sections aux joueurs de Players.
        Enabled = false,
        Players = {
            'steam:11000013ca597a9',
            'steam:11000011977aecd',
            'steam:110000114f6ac4d',
        },
        Sections = { equipment = true, car = true }, -- Équipements, Voiture (spawn, radio)
    },

    -- MENU > VOITURE (véhicules de data/vehicle.json) et ÉQUIPEMENTS (armes de data/loadouts.json)
    SpawnPoliceOnly = true,         -- véhicules de police (WSP / KCSO) réservés aux policiers en service
    EquipmentPoliceOnly = true,     -- armes réservées aux policiers en service
    MaxCustomEquipment = 10,        -- "Équipements modifiés" (nommés, enregistrés) par joueur

    -- MENU DES TENUES (/eup, ou Menu Interaction > Équipements > "Accéder aux tenues") : tenues de
    -- data/outfits.json, uniquement dans ce fichier. Menu au clavier : flèches haut / bas, Entrée (ou
    -- flèche droite) pour ouvrir / mettre la tenue, Retour arrière (ou flèche gauche) pour revenir.
    Eup = {
        Command = 'eup',
        PoliceOnly = false,         -- true : tenues de police réservées aux policiers en service (unité du MDC)
        OneBased = true,            -- numéros "24:1" comptés à partir de 1 (format EUP habituel) ; false : à partir de 0
    },
    -- Radio du véhicule (lien YouTube ou lien direct vers un son / une radio en ligne)
    RadioRangeClosed = 15.0,        -- m : entendue dehors jusqu'à 15 m, vitres et portières fermées
    RadioRangeOpen = 25.0,          -- m : jusqu'à 25 m avec une portière (coffre, capot) ouverte ou une vitre baissée
    RadioInsulation = 0.18,         -- volume entendu dehors quand tout est fermé (pas d'autre effet sur le son)
    RadioMaxVolume = 0.8,           -- volume maximal (radio à 100 %) pour tous les joueurs

    -- Ressources liées (nom des dossiers)
    MdcResource = 'rp_mdc', -- "policier" = joueur dans une unité du MDC
    ChatResource = 'rp_chat',       -- /me automatiques et copie des résultats dans le chat
    -- Mode d'emotes du serveur (dossier RPEMOTES / rpemotes / rpemotes-reborn). 'auto' : détecté seul.
    -- Les emotes de ce script y sont lues (animation exacte) au démarrage : voir server/emotes.lua.
    EmotesResource = 'auto',
    EmoteFiles = {},                -- fichiers supplémentaires où chercher les emotes (ex. 'client/MesEmotes.lua')

    -- Œil : distances (m) entre le joueur et ce qu'il vise. Les options apparaissent quand on s'approche.
    ObserveDistance = 10.0,         -- inspections visuelles / olfactives, détail notoire
    SearchDistance = 3.0,           -- fouilles (personne, véhicule)
    ActionDistance = 2.0,           -- menotter, prendre par le bras (autour du policier)
    DoorDistance = 3.0,             -- portières, capot, coffre, monter
    ObjectDistance = 2.5,           -- s'asseoir, fouiller une poubelle
    DeleteDistance = 50.0,          -- "Supprimer" : seule option visible de loin (joueurs autorisés)

    -- PROPS POSÉS avec le script de props du serveur (dossier "props") : avec l'œil, options "Déplacer le
    -- props" et "Supprimer le props". Un objet est reconnu comme posé par ce script (le premier qui répond) :
    --   1. automatiquement : le serveur demande au joueur qui l'a créé quel script l'a fait apparaître
    --      (OneSync) ; si c'est Props.Resource, l'objet est marqué pour tout le monde (état "rpiProp") ;
    --   2. un état de l'objet posé par le script de props (StateKeys) ;
    --   3. un export du script de props (Export : exports.props:<Export>(entity) -> true).
    --   Votre script peut aussi marquer lui-même ses objets : exports.rp_interact:registerProp(entity)
    --   (client) ou TriggerServerEvent('rp_interact:server:registerProp', netId).
    -- Objets d'AUTRES scripts reconnus à l'œil par leur état (Entity(objet).state[clé]) : nom affiché sous l'œil et
    -- une action qui prévient le SERVEUR de ce script (événement réseau, avec le n° réseau de l'objet) ;
    -- plusieurs actions : Options = { { Label, Icon, Event }, ... }.
    ExternalSnap = 0.7,             -- m : objet ci-dessous trouvé même si le rayon touche le sol à côté (arme couchée)
    -- Scripts qui ajoutent leurs options à l'œil (exports targetOptions / targetSelect), même sur le sol ou un mur
    TargetProviders = { 'rp_RoleplayZone', 'rp_doorlock', 'rp_vehicleprops', 'rp_taser10' },
    -- Scènes de roleplay : dans leur secteur (zone / lieu / objet + 70 m), « Supprimer » (props, véhicules, objets)
    -- n'est ni proposé ni accepté
    SceneResource = 'rp_RoleplayZone',
    ExternalObjects = {
        rpFlare = { Name = 'Fusée de détresse', Label = 'Retirer la fusée', Icon = 'trash', Event = 'rp_flares:remove', Distance = 2.5 },
        rpCone = { Name = 'Plot de circulation', Distance = 2.5, Options = {
            { Label = 'Ramasser le plot', Icon = 'hand', Event = 'rp_equipment:cone:pickup' },
            { Label = 'Ramasser les plots autour', Icon = 'hand', Event = 'rp_equipment:cone:pickupAll' },
        } },
        rpDroppedWeapon = { Name = 'Arme au sol', Label = 'Ramasser l\'arme', Icon = 'hand', Event = 'rp_scene:weapon:pickup', Distance = 2.0 }, -- rp_RoleplayZone
    },

    Props = {
        Resource = 'props',
        StateKeys = { 'rpiProp', 'prop', 'isProp', 'placedProp', 'propOwner', 'placedBy' },
        Export = '',                -- ex. 'isProp' ; '' : pas d'export
        Distance = 3.0,             -- m : distance pour déplacer / supprimer
        MoveRange = 6.0,            -- m : jusqu'où le props peut être déplacé autour du joueur
        Access = 'everyone',        -- 'everyone' | 'police' (joueurs dans une unité du MDC) | 'owner' (celui qui l'a posé)
        -- Événements SERVEUR du script de props à prévenir (facultatif, ex. pour sa sauvegarde) :
        --   DeletedEvent(netId, source) ; MovedEvent(netId, { x, y, z, heading }, source)
        DeletedEvent = '',
        MovedEvent = '',
    },

    -- Test : viser son propre personnage (vue à la 3e personne) pour vérifier son profil actif.
    -- Mettez false en production si vous ne voulez pas de cette possibilité.
    AllowSelfTarget = true,

    InspectCooldown = 750,          -- ms entre deux inspections (serveur)

    -- Durée des fouilles (barre de chargement ; X pour annuler)
    SearchDurations = { person = 6000, vehicle = 35000 }, -- personne : 6 s par partie (supérieure / inférieure)

    -- POLICE (joueur dans une unité du MDC) : menottes, prendre par le bras, placer dans un véhicule
    CuffDuration = 7000,            -- ms pour menotter
    UncuffDuration = 3000,          -- ms pour retirer les menottes
    Emotes = {
        drag = 'e tenirlebras',     -- joué par le policier qui tient quelqu'un par le bras
        seated = 'e menotté2',      -- "Faire s'asseoir l'individu" (au sol, pas dans un véhicule)
        cancel = 'e c',             -- arrête l'emote en cours (touche X des tips, lâcher le bras)
    },
    -- Individu menotté DEBOUT : comportement de base de GTA 5 (aucune emote) : menottes du jeu
    -- (SetEnableHandcuffs) + animation "mains dans le dos" du jeu, rejouée si elle s'arrête.
    CuffAnim = { dict = 'mp_arresting', clip = 'idle', flag = 49 },
    -- Assis au sol ("/e menotté2") : animation de SECOURS, utilisée seulement si l'emote n'a pas été
    -- trouvée dans le mode d'emotes (le serveur y lit l'animation exacte de menotté2) ou pour un PNJ.
    SeatedAnim = { dict = 'amb@world_human_picnic@male@base', clip = 'base', flag = 1 },
    CuffProp = 'p_cs_cuffs_02_s',   -- menottes aux poignets (voir README : dossier stream)
    -- Position (m) et orientation (°) des menottes sur l'os du poignet gauche (60309), réglées pour
    -- l'animation "mains dans le dos" du jeu (CuffAnim).
    CuffPropPlacement = { bone = 60309, x = -0.055, y = 0.06, z = 0.04, rx = 265.0, ry = 155.0, rz = 80.0 },
    -- Individu tenu par le bras : tenu DE FORCE, accroché au policier à ce point (à sa droite, un peu devant),
    -- au CENTRE du policier (pas à un os) : il reste droit et ne bascule plus avec le tronc du policier.
    -- Menotté : mains dans le dos ; sinon aucune animation imposée.
    DragOffset = { x = 0.45, y = 0.3, z = 0.0 },
    -- Ses jambes suivent SON déplacement réel : arrêté sous Idle m/s, trottine à partir de Trot m/s (le policier
    -- qui le tient ne peut pas sprinter).
    DragMove = { Idle = 0.35, Trot = 2.6 },
    -- Animations des jambes (dictionnaire, clip) : marche / trot, devant, à gauche, à droite, en arrière ; menotté,
    -- vers l'avant : la marche menottée du jeu (les menottes restent jouées sur le haut du corps). Si la gauche et
    -- la droite vous semblent inversées en jeu, échangez left / right.
    DragMoves = {
        walk = {
            forward = { 'move_m@generic', 'walk' },
            left = { 'move_strafe@generic', 'walk_fwd_90_loop' },
            right = { 'move_strafe@generic', 'walk_bwd_-90_loop' },
            back = { 'move_strafe@generic', 'walk_bwd_180_loop' },
        },
        trot = {
            forward = { 'move_m@generic', 'run' },
            left = { 'move_strafe@generic', 'run_fwd_90_loop' },
            right = { 'move_strafe@generic', 'run_bwd_-90_loop' },
            back = { 'move_strafe@generic', 'run_bwd_180_loop' },
        },
        cuffed = { walk = { 'mp_arresting', 'walk' }, trot = { 'mp_arresting', 'run' } },
    },
    -- Se débattre (tenu SANS menottes) : touche Key à marteler ; chaque appui +Gain à la jauge (sur 100), qui
    -- redescend de Decay par seconde ; écrans du civil et du policier qui tremblent (Shake). Jauge pleine : un
    -- autre policier était déjà à moins de Radius m -> LoseChance (85 %) de perdre ; un autre policier qui
    -- arrive pendant qu'il se débat -> perdu ; sinon il se dégage (et ne peut pas être repris pendant Cooldown
    -- ms). Perdu : plus possible tant qu'il est tenu.
    Struggle = {
        Enabled = true, Key = 'SPACE', KeyLabel = 'ESPACE',
        Gain = 9.0, Decay = 22.0,
        Radius = 2.0, LoseChance = 0.85, Cooldown = 5000,
        Shake = 'JOLT_SHAKE', ShakeAmount = 0.35, PoliceShakeAmount = 0.25,
    },
    DragReleaseKey = 'X',           -- policier : lâcher le bras (modifiable dans les raccourcis FiveM)
    PlaceVehicleDistance = 6.0,     -- m : véhicule où placer l'individu tenu par le bras

    -- SUPPRIMER des PNJ, des véhicules sans joueur et des objets (y compris ceux créés par des
    -- joueurs ou des scripts) en les visant, jusqu'à DeleteDistance mètres.
    -- 'police' = joueurs dans une unité du MDC ; 'everyone' = tout le monde.
    -- La permission ACE DeleteAce l'autorise toujours (ex. add_ace group.admin rpinteract.delete allow).
    DeleteAccess = 'everyone',
    DeleteAce = 'rpinteract.delete',

    -- Permission ACE des commandes d'administration (rechargement des fichiers : emotes, véhicules)
    AdminAce = 'rpinteract.admin',

    -- ARME À FEU EN MAIN (client/combat.lua)
    NoFirearmMelee = true,          -- plus de coup de crosse ni de coup donné dans le vide (corps à corps léger / lourd)
    NoCombatRoll = true,            -- plus de roulade (saut pendant la visée)

    MaxProfiles = 20,               -- profils civils par joueur
    TextMax = 1000,                 -- caractères max par case de texte

    -- Annonce RP automatique dans le chat (/me) quand un joueur inspecte / fouille
    AnnounceWithMe = true,
    -- Résultat copié dans le chat écrit du joueur qui inspecte (en plus de la fiche à l'écran)
    ResultsInChat = true,
    ResultDuration = 20000,         -- ms d'affichage d'un résultat à l'écran (+ selon la longueur)

    -- MODE CIVIL (case à cocher du menu d'interactions, propre à chaque joueur)
    -- Tips d'arrestation : mini menu en haut de l'écran (non interactif) quand un policier (joueur dans
    -- une unité du MDC) vous met en joue, ou via Menu > Civil > Tips arrestation. Les touches ne
    -- déclenchent l'emote QUE pendant que ce mini menu est affiché. Touches modifiables par chaque
    -- joueur : Échap > Paramètres > Raccourcis clavier > FiveM > "Civil : …".
    Surrender = {
        { command = 'rpi_hands', key = 'H', label = 'Mains en l\'air', emote = 'e serendre17' },
        { command = 'rpi_knees', key = 'J', label = 'À genoux', emote = 'e serendre3' },
        { command = 'rpi_prone', key = 'L', label = 'S\'allonger', emote = 'e serendre6' },
    },
    -- + touche X (non modifiable) : arrêter l'emote en cours (par le mode d'emotes), affichée dans les tips
    AimRadius = 5.0,              -- m : civil visé directement ou à moins de 5 m de la ligne de visée
    AimRange = 60.0,              -- m : portée max de la détection
    AimRefresh = 1000,            -- ms : le policier confirme sa visée à ce rythme (fin auto sinon)
    -- Les tips ne se ferment qu'avec la touche Échap (ni à la fin de la mise en joue, ni après un délai)

    -- Réponses par défaut quand la case n'est pas cochée / pas remplie (ou sans profil).
    -- Pour une même cible, la réponse choisie dans la liste est toujours la même.
    Defaults = {
        visual    = { 'Rien à signaler', 'Rien d\'anormal', 'Tout est correct' },
        olfactory = { 'Rien à signaler', 'Rien d\'anormal', 'Tout est correct' },
        search    = { 'Rien à signaler', 'Aucun élément', 'Rien d\'illégal' },
        notable   = { 'Aucun détail notoire' },
        vehicleVisual    = { 'Rien d\'anormal', 'Tout semble normal', 'Rien de suspect', 'Rien à signaler' },
        vehicleOlfactory = { 'Rien d\'anormal', 'Rien de suspect' },
        vehicleSearch    = { 'Rien à signaler', 'Aucun élément', 'Rien d\'illégal' },
    },

    -- Objets de l'environnement (noms de modèles). Ajoutez les vôtres.
    -- Sièges : décalage de la position assise par rapport à l'objet (z = hauteur, heading = orientation)
    Seats = {
        bench = {
            scenario = 'PROP_HUMAN_SEAT_BENCH', z = 0.5, heading = 180.0, width = 0.6,
            models = {
                'prop_bench_01a', 'prop_bench_01b', 'prop_bench_01c', 'prop_bench_02', 'prop_bench_03',
                'prop_bench_04', 'prop_bench_05', 'prop_bench_06', 'prop_bench_07', 'prop_bench_08',
                'prop_bench_09', 'prop_bench_10', 'prop_bench_11', 'prop_fib_3b_bench', 'prop_ld_bench01',
                'prop_wait_bench_01', 'prop_busstop_02', 'prop_busstop_04', 'prop_busstop_05',
            },
        },
        chair = {
            scenario = 'PROP_HUMAN_SEAT_CHAIR', z = 0.5, heading = 180.0, width = 0.0,
            models = {
                'prop_chair_01a', 'prop_chair_01b', 'prop_chair_02', 'prop_chair_03', 'prop_chair_04a',
                'prop_chair_04b', 'prop_chair_05', 'prop_chair_06', 'prop_chair_08', 'prop_chair_09',
                'prop_chair_10', 'prop_off_chair_01', 'prop_off_chair_03', 'prop_off_chair_04',
                'prop_off_chair_05', 'prop_cs_office_chair', 'v_corp_offchair', 'v_club_officechair',
                'prop_table_01_chr_a', 'prop_table_03_chr', 'prop_gc_chair02', 'prop_skid_chair_01',
                'prop_skid_chair_02', 'prop_skid_chair_03', 'prop_rock_chair_01', 'prop_old_deck_chair',
            },
        },
    },
    TrashBins = {
        'prop_bin_01a', 'prop_bin_03a', 'prop_bin_05a', 'prop_bin_07a', 'prop_bin_08a', 'prop_cs_bin_01',
        'prop_dumpster_01a', 'prop_dumpster_02a', 'prop_dumpster_02b', 'prop_dumpster_4a', 'prop_dumpster_4b',
        'prop_recyclebin_01a', 'prop_recyclebin_02_c', 'prop_recyclebin_03_a',
    },
}
