OverheadConfig = {
    -- Touche à MAINTENIR (chaque joueur peut la changer : Paramètres > Raccourcis clavier > FiveM >
    -- « Afficher les noms RP et numéros des joueurs (maintenir) ») ; ils disparaissent quand on la relâche.
    Key = 'HOME',
    Command = 'numeros',  -- +numeros / -numeros (raccourci FiveM)

    -- Affiché : le NOM RP du joueur (/nomrp, en gros) et, en dessous, son numéro sur le serveur (ID). Pas encore de
    -- nom RP : son numéro seul. NameState : état du joueur qui porte le nom RP (rp_chat / MDC : 'rpName').
    NameState = 'rpName',
    Distance = 25.0,      -- m : joueurs affichés autour de soi
    LineOfSight = true,   -- seulement les joueurs visibles (pas derrière un mur)
    ShowSelf = true,      -- son propre numéro aussi
    Height = 0.38,        -- m au-dessus de la tête

    -- Couleurs (R, G, B) : nom RP, numéro, joueur qui parle (nom en bleu clair : pma-voice / micro du jeu)
    NameColor = { 255, 255, 255 },
    IdColor = { 205, 214, 224 },
    TalkingColor = { 120, 200, 255 },
}
