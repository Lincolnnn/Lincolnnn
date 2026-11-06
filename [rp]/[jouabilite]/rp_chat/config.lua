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
        hrp = false,
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
        Aliases = { 'aide', 'commandes' }, -- autres commandes qui ouvrent / ferment le tuto
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
                { "/copyped", "copier son personnage (arme, emote) pour une photo ; /copyped suppr" },
                { "Début", "noms RP et numéros des joueurs au-dessus des têtes (maintenir ou appuyer : /configtetes)" },
                { "/goto ID · /back", "aller à un joueur, sur toute la carte / revenir" },
                { "/blip ID · /players", "suivre un joueur sur la carte (/blip off) / liste des joueurs" },
                { "/viser", "visée : maintenir le clic droit, ou appuyer une fois (/viser maintenir | appuyer)" },
                { "/roles", "rôle Discord reçu en jeu : le prendre en compte tout de suite" },
            } },
            { title = "Interfaces (commandes)", items = {
                { "/mdc · K", "MDC (police)" }, { "/menu · F1", "Menu Interaction" },
                { "/notepad · F2", "bloc-notes (aussi /blocnotes) ; retranscrit dans la note de l'unité du MDC" },
                { "/miranda · /alphabet", "carte Miranda, alphabet phonétique de la police (on peut marcher) ; /cartes : les déplacer" },
                { "/joueurs", "liste des joueurs : se téléporter (admins : téléporter à soi, kick, ban)" },
                { "/equipements · /mestenues", "Menu > Équipements ; vos tenues enregistrées" },
                { "/eup", "tenues (Modifier ma tenue, Enregistrer ma tenue)" }, { "/fichecivil", "fiche civile (profils, véhicule)" },
                { "/voiture", "Menu > Voiture : faire apparaître un véhicule" }, { "/radio", "radio du véhicule (Menu > Musique)" }, { "/musique", "musique sur soi, à un endroit ou sur un objet (tapage, fête)" }, { "/meteo", "météo et heure du serveur" },
                { "/coffre · E", "police : équipement du véhicule (portière avant ou coffre)" }, { "/radargun", "police : prendre / ranger le pistolet radar, assis à l'avant" },
                { "/freecam", "mode photo : caméra libre, zoom, inclinaison 90°, interfaces masquées" },
                { "Ctrl gauche", "à bord : projecteur (appui : allumer ; maintenu : viser, clic gauche verrouiller, clic droit suivre) ; /editspotlight : régler" },
                { "/trafic · /scene", "gestion du trafic (police) ; scène à fouiller (civil)" },
                { "/tuto · /aide", "cette page" },
            } },
            { title = "MDC & menus", items = {
                { "K", "MDC : unités, appels, recherches, BOLO, rapports, messages entre unités" }, { "Y / N", "accepter / refuser un appel" },
                { "F1", "Menu Interaction : civil, police, équipements, voiture" },
                { "/trafic", "police : choisir la zone du trafic, puis fermer la voie, ralentir ou arrêter le trafic" },
                { "Verr. Maj", "police : œil d'aigle (ce qui est à fouiller, zone proche)" },
                { "/scene", "civil : zone de recherche, lieu ou objet à fouiller" },
                { "G", "civil, arme en main : jeter / poser son arme (molette)" },
                { "Alt", "œil (maintenir) : inspecter, fouiller, portières, s'asseoir, objets sur un véhicule…" },
                { "Alt + arme", "œil, arme / lampe / Taser en main : la poser sur un véhicule ou au sol, la reprendre" },
            } },
            { title = "Véhicule", items = {
                { "O", "moteur" }, { "G", "ceinture" }, { "U / I", "sa portière / les deux avant" },
                { "← →", "clignotants" }, { "↓", "warnings" }, { "Alt", "œil : pousser un véhicule (à pied)" },
            } },
            { title = "Bodycam", items = {
                { "/bwc", "choisir sa caméra (menu) : /bwc axon2, axon3, axon4, motorola, focusx2" },
                { "O", "allumer / éteindre la bodycam choisie (« Toggle bodycam » dans les raccourcis)" },
                { "/bwc off", "couper la bodycam" }, { "/bwcsize", "taille de l'affichage : 50 à 200, ou reset" },
                { "/bwcedit", "bodycam allumée : déplacer / agrandir le texte (molette), enregistrer en haut à droite" },
                { "/bwcanim", "geste vers la caméra : center, high, left, low, right" },
            } },
            { title = "Interpellations", items = {
                { "H", "mains en l'air" }, { "J", "à genoux" }, { "L", "s'allonger" }, { "X", "arrêter l'emote / lâcher le bras" },
            } },
        },
        Footer = "Toutes les touches se changent dans Échap > Paramètres > Raccourcis clavier > FiveM.",
    },
}
