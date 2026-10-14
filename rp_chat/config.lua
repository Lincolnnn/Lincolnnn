--[[
    RP Chat - Configuration (partagée client / serveur)
]]
ChatConfig = {
    -- REMPLACEMENT DU CHAT D'ORIGINE
    -- Les ressources d'origine "chat" et "chat-theme-gtao" (thème GTA Online du chat d'origine)
    -- n'ont pas besoin d'être supprimées : il suffit qu'elles ne soient pas démarrées. Si elles
    -- le sont quand même (ligne "ensure" oubliée, panel de l'hébergeur…), rp_chat les arrête
    -- automatiquement (sauf si une autre ressource en dépend : message dans la console).
    StopDefaultChat = true,
    DefaultChatResources = { 'chat-theme-gtao', 'chat' }, -- arrêtées dans cet ordre (le thème d'abord)

    -- Touche d'ouverture par défaut. Chaque joueur peut la changer dans :
    -- Échap > Paramètres > Raccourcis clavier > FiveM > "Chat : ouvrir / fermer"
    -- (une fois le raccourci enregistré chez un joueur, changer cette valeur ne l'affecte plus)
    DefaultKey = 'T',

    -- /me : visible uniquement par les joueurs dans ce rayon (mètres) au moment de l'envoi
    MeDistance = 50.0,

    -- Longueur max d'un message (caractères) et délai mini entre deux messages (ms)
    MaxLength = 250,
    Cooldown = 1000,

    -- Nom RP : longueur min / max
    NameMin = 2,
    NameMax = 40,

    -- /info, /qst, /rep restent dans le chat : les N derniers sont envoyés aux joueurs
    -- qui se connectent (gardés en mémoire, perdus au redémarrage du serveur)
    GlobalHistory = 50,

    -- Permission ACE facultative par commande (false = tout le monde). Exemple :
    --   info = 'rpchat.info'   puis dans server.cfg :  add_ace group.admin rpchat.info allow
    Permissions = {
        dv = false,          -- /dv (supprimer un véhicule), ex. 'rpchat.dv'
        me = false,
        info = false,
        qst = false,
        rep = false,
    },

    -- /dv : supprime UN véhicule : celui où se trouve le joueur, sinon celui qu'il regarde, sinon le plus
    -- proche, dans ce rayon (mètres). Jamais un véhicule où se trouve un autre joueur.
    DvDistance = 5.0,

    -- /me au-dessus des têtes (option du joueur) : durée d'affichage (ms) et lignes max par joueur
    OverheadDuration = 7000,
    OverheadMaxLines = 3,

    -- Taille du /me au-dessus des têtes (uniquement là : le chat écrit n'est pas concerné).
    -- La taille suit la distance : plus grande quand on s'approche, plus petite quand on recule.
    OverheadScale = 0.62,      -- taille du texte à ~4 m
    OverheadMinScale = 0.25,   -- facteur minimal au loin (atteint vers 30 m, texte toujours lisible)
    OverheadMaxScale = 1.50,   -- facteur maximal tout près

    -- /tuto : touches et fonctionnalités du serveur, affichées en privé dans le chat (le chat s'ouvre pour
    -- pouvoir les lire et faire défiler). Touches par défaut : chaque joueur peut les changer dans
    -- Échap > Paramètres > Raccourcis clavier > FiveM. Modifiez librement les textes ci-dessous.
    Tuto = {
        Command = 'tuto',
        -- Message privé affiché à chaque connexion ('' = aucun), quelques secondes après l'arrivée en jeu
        JoinMessage = 'Faites /tuto pour découvrir les fonctionnalités du serveur !',
        JoinDelay = 5000, -- ms après l'apparition du personnage
        Sections = {
            { title = "Chat écrit (T)", text = "/nomrp [nom] : votre nom RP, obligatoire avant le reste (sauf /dv, /eup, /tuto).\n"
                .. "/me [action] : action RP (50 m) · /info : information à tous · /qst : question · /rep : réponse\n"
                .. "/dv : supprimer le véhicule où vous êtes / regardé / le plus proche (5 m) · /eup : tenues" },
            { title = "MDC (K)", text = "Unités et statut, interventions, recherches, BOLO, rapports, paramètres (HUD, chat, sons).\n"
                .. "Appel proposé à l'unité la plus proche : Y accepter, N refuser." },
            { title = "Menu Interaction (F1)", text = "Civil : profils, mode civil, tips d'arrestation · Police · "
                .. "Équipements : tenues (/eup), armes · Voiture : spawn, radio (lien, file « Écouter ensuite », pause)." },
            { title = "Œil (Alt gauche maintenu)", text = "Visez une personne, un véhicule ou un objet puis cliquez : inspections, "
                .. "fouilles (police), portières, coffre, s'asseoir, poubelles, radio, déplacer / supprimer." },
            { title = "Véhicule", text = "O : moteur · G : ceinture · U : sa portière · I : les deux portières avant\n"
                .. "← / → : clignotants · ↓ : warnings · K (à pied, devant / derrière) : pousser" },
            { title = "Interpellations", text = "Civil (tips) : H mains en l'air · J à genoux · L allongé · X arrêter l'emote\n"
                .. "Police : X lâcher le bras · /policeon, /policeoff : véhicules de police réservés" },
            { title = "Touches", text = "Toutes ces touches se changent dans Échap > Paramètres > Raccourcis clavier > FiveM." },
        },
    },
}
