--[[
    RP Interact - Configuration (partagée client / serveur)
]]
InteractConfig = {
    -- Touches par défaut (modifiables par chaque joueur : Échap > Paramètres > Raccourcis
    -- clavier > FiveM > "Menu Interaction" et "Œil : interagir (maintenir)")
    MenuKey = 'F1',
    TargetKey = 'LMENU',          -- Alt gauche

    -- PERMISSIONS (identifiant Steam hex, "steam:1100001..." : visible dans la console du serveur, commande
    -- "status", ou sur un site de conversion SteamID). Les catégories de la partie "Configuration" du
    -- Menu Interaction listées dans Sections sont réservées à ces joueurs (les autres les voient grisées,
    -- le serveur refuse leurs demandes). Sections = {} : ouvertes à tous.
    Permissions = {
        Players = {
            'steam:11000013ca597a9',
            'steam:11000011977aecd',
            'steam:110000114f6ac4d',
        },
        Sections = { equipment = true, car = true }, -- Équipements, Voiture (spawn, radio)
    },

    -- MENU > VOITURE (véhicules listés dans data/vehicles.txt) et ÉQUIPEMENTS (data/equipment.lua)
    SpawnPoliceOnly = true,         -- véhicules de police (APD / GSP) réservés aux policiers en service
    EquipmentPoliceOnly = true,     -- tenues et armes réservées aux policiers en service
    -- Radio du véhicule (lien YouTube ou lien direct vers un son / une radio en ligne)
    RadioRangeClosed = 15.0,        -- m : entendue dehors jusqu'à 15 m, vitres et portières fermées
    RadioRangeOpen = 25.0,          -- m : jusqu'à 25 m avec une portière (coffre, capot) ouverte ou une vitre baissée
    RadioInsulation = 0.18,         -- volume entendu dehors quand tout est fermé ("insonorisé", en plus du
                                    -- filtre passe-bas qui étouffe le son : on n'entend plus que les basses)
    RadioMaxVolume = 0.8,           -- volume maximal (radio à 100 %) pour tous les joueurs
    -- Liens YouTube : le SERVEUR cherche le flux audio de la vidéo auprès de ces services (Piped, puis
    -- Invidious ; le premier qui répond est gardé). Lu en flux audio, le son peut être étouffé et placé
    -- (gauche / droite) ; sinon, lecteur YouTube classique (volume seulement). Ces services publics
    -- changent souvent : ajoutez / retirez des adresses au besoin. {} = toujours le lecteur classique.
    RadioPiped = {
        'https://pipedapi.kavin.rocks',
        'https://pipedapi.adminforge.de',
        'https://api.piped.private.coffee',
        'https://pipedapi.r4fo.com',
    },
    RadioInvidious = {
        'https://inv.nadeko.net',
        'https://invidious.nerdvpn.de',
        'https://yewtu.be',
        'https://invidious.f5.si',
    },

    -- Ressources liées (nom des dossiers)
    MdcResource = 'mdc_standalone', -- "policier" = joueur dans une unité du MDC
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
    -- Individu tenu par le bras : position par rapport au policier (à droite, un peu devant). Il n'est
    -- pas accroché : il suit cette position et tourne sur lui-même (pas avec le tronc du policier),
    -- sans collisions. DragTurnSpeed : vitesse (°/s) à laquelle il s'oriente comme le policier.
    DragOffset = { x = 0.45, y = 0.3, z = 0.0 },
    DragTurnSpeed = 240.0,
    DragReleaseKey = 'X',           -- policier : lâcher le bras (modifiable dans les raccourcis FiveM)
    PlaceVehicleDistance = 6.0,     -- m : véhicule où placer l'individu tenu par le bras

    -- SUPPRIMER des PNJ, des véhicules sans joueur et des objets (y compris ceux créés par des
    -- joueurs ou des scripts) en les visant, jusqu'à DeleteDistance mètres.
    -- 'police' = joueurs dans une unité du MDC ; 'everyone' = tout le monde.
    -- La permission ACE DeleteAce l'autorise toujours (ex. add_ace group.admin rpinteract.delete allow).
    DeleteAccess = 'police',
    DeleteAce = 'rpinteract.delete',

    -- VÉHICULES DE POLICE : /policeon -> seuls les policiers (unité du MDC) y montent ; /policeoff (par
    -- défaut à chaque démarrage du serveur) -> tout le monde. Voir client/policevehicles.lua.
    -- Pas d'annonce : seul l'auteur de la commande reçoit une notification de confirmation.
    -- Autorisés : console serveur, joueurs en unité du MDC, ou permission ACE ci-dessous.
    PoliceVehiclesAce = 'rpinteract.admin',
    PoliceVehicleClasses = { 18 },  -- classes du jeu considérées comme "véhicule de police" (18 = urgence)
    PoliceVehicleModels = {},       -- modèles en plus (véhicules ajoutés d'une autre classe), ex. { 'police5' }
    -- Animation jouée quand un non-policier tire sur la poignée d'un véhicule de police (/policeon)
    LockedDoorAnim = { dict = 'veh@std@ds@enter_exit', clip = 'd_locked' },
    -- Où se tient le joueur pour tirer sur la poignée : distance (m) entre le centre du personnage et la
    -- poignée (0.38 = à ~3 cm de la portière), décalage le long du véhicule (m, + vers l'avant)
    LockedDoorStand = { distance = 0.38, along = 0.0 },

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
