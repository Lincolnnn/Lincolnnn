--[[
    RP Chat - Configuration (partagée client / serveur)
]]
ChatConfig = {
    -- Touche d'ouverture par défaut. Chaque joueur peut la changer dans :
    -- Échap > Paramètres > Raccourcis clavier > FiveM > "Chat : ouvrir / fermer"
    -- (une fois le raccourci enregistré chez un joueur, changer cette valeur ne l'affecte plus)
    DefaultKey = 'T',

    -- /me : visible uniquement par les joueurs dans ce rayon (mètres) au moment de l'envoi
    MeDistance = 100.0,

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
        me = false,
        info = false,
        qst = false,
        rep = false,
    },

    -- /me au-dessus des têtes (option du joueur) : durée d'affichage (ms) et lignes max par joueur
    OverheadDuration = 7000,
    OverheadMaxLines = 3,
}
