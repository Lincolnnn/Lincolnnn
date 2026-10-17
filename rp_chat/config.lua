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

    -- Naviguer dans la conversation (remonter / redescendre), chat ouvert OU fermé : le chat s'affiche et défile.
    -- Modifiables : Raccourcis clavier > FiveM > "Chat : remonter / descendre dans la conversation".
    -- Chat ouvert : aussi la molette de la souris.
    ScrollUpKey = 'PAGEUP',
    ScrollDownKey = 'PAGEDOWN',

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

    -- /tuto : affiche des touches et fonctionnalités du serveur, en haut de l'écran, au milieu. Elle ne prend ni
    -- la souris ni le clavier (on peut jouer, ouvrir le MDC, les menus, le chat…) ; /tuto à nouveau la
    -- retire. Touches par défaut : chaque joueur peut les changer dans Échap > Paramètres > Raccourcis
    -- clavier > FiveM. Modifiez librement les textes : chaque ligne = { touche ou commande, description }.
    Tuto = {
        Command = 'tuto',
        Title = 'Bienvenue sur le serveur',
        -- Message privé dans le chat à chaque connexion ('' = aucun), quelques secondes après l'arrivée en jeu
        JoinMessage = 'Faites /tuto pour découvrir les fonctionnalités du serveur !',
        JoinDelay = 5000, -- ms après l'apparition du personnage
        Sections = {
            { title = "Chat écrit", items = {
                { "T", "ouvrir le chat" }, { "PgUp / PgDn", "remonter / descendre dans le chat" },
                { "/nomrp", "votre nom RP (avant /me, /info…)" },
                { "/me", "action RP (50 m)" }, { "/info /qst /rep", "info, question, réponse" },
                { "/dv", "supprimer un véhicule (5 m)" }, { "/eup", "tenues" },
                { "/fichecivil", "vos profils civils" }, { "/repair", "réparer le moteur" },
            } },
            { title = "MDC & menus", items = {
                { "K", "MDC : unités, appels, recherches, BOLO, rapports" }, { "Y / N", "accepter / refuser un appel" },
                { "F1", "Menu Interaction : civil, police, équipements, voiture" },
                { "/trafic", "police : fermer une voie / un sens, ralentir, arrêter le trafic" },
                { "Verr. Maj", "police : œil d'aigle (ce qui est à fouiller, zone proche)" },
                { "/scene", "civil : zone de recherche, lieu ou objet à fouiller" },
                { "G", "civil, arme en main : jeter / poser son arme (molette)" },
                { "Alt", "œil (maintenir) : inspecter, fouiller, portières, s'asseoir…" },
            } },
            { title = "Véhicule", items = {
                { "O", "moteur" }, { "G", "ceinture" }, { "U / I", "sa portière / les deux avant" },
                { "← →", "clignotants" }, { "↓", "warnings" }, { "K", "pousser (à pied)" },
            } },
            { title = "Interpellations", items = {
                { "H", "mains en l'air" }, { "J", "à genoux" }, { "L", "s'allonger" }, { "X", "arrêter l'emote / lâcher le bras" },
            } },
        },
        Footer = "Toutes les touches se changent dans Échap > Paramètres > Raccourcis clavier > FiveM.",
    },
}
