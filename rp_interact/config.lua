--[[
    RP Interact - Configuration (partagée client / serveur)
]]
InteractConfig = {
    -- Touches par défaut (modifiables par chaque joueur : Échap > Paramètres > Raccourcis
    -- clavier > FiveM > "Menu d'interactions" et "Œil : interagir (maintenir)")
    MenuKey = 'F1',
    TargetKey = 'LMENU',          -- Alt gauche

    -- Ressources liées (nom des dossiers)
    MdcResource = 'mdc_standalone', -- "policier" = joueur dans une unité du MDC
    ChatResource = 'rp_chat',       -- /me automatiques et copie des résultats dans le chat

    -- Œil : distance max (m) entre le joueur et ce qu'il vise
    ObjectDistance = 2.5,           -- objets (bancs, chaises, poubelles…)
    EntityDistance = 4.0,           -- personnes et véhicules

    -- Test : viser son propre personnage (vue à la 3e personne) pour vérifier son profil actif.
    -- Mettez false en production si vous ne voulez pas de cette possibilité.
    AllowSelfTarget = true,

    -- Serveur : distance max (m) entre le joueur qui inspecte et sa cible (avec OneSync)
    InspectDistance = 8.0,
    InspectCooldown = 750,          -- ms entre deux inspections

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
    AimRadius = 5.0,              -- m : civil visé directement ou à moins de 5 m de la ligne de visée
    AimRange = 60.0,              -- m : portée max de la détection
    AimRefresh = 1500,            -- ms : le policier confirme sa visée à ce rythme (fin auto sinon)
    AimWatchKey = 'MOUSE_RIGHT',  -- touche de visée surveillée côté policier (clic droit)
    TipsAimDelay = 2500,          -- ms : les tips restent affichés après la fin de la mise en joue
    TipsManualDuration = 60000,   -- ms : durée des tips ouverts depuis le menu

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
