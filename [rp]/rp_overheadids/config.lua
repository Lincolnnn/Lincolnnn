OverheadConfig = {
    -- Touche à MAINTENIR (chaque joueur peut la changer : Paramètres > Raccourcis clavier > FiveM >
    -- « Afficher les numéros des joueurs (maintenir) ») ; les numéros disparaissent quand on la relâche.
    Key = 'HOME',
    Command = 'numeros',  -- +numeros / -numeros (raccourci FiveM)

    -- Ce qui est affiché : 'id' (numéro du joueur sur le serveur), 'name' (nom FiveM) ou 'both' (les deux)
    Show = 'both',
    Distance = 25.0,      -- m : joueurs affichés autour de soi
    LineOfSight = true,   -- seulement les joueurs visibles (pas derrière un mur)
    ShowSelf = true,      -- son propre numéro aussi
    Height = 0.38,        -- m au-dessus de la tête

    -- Couleurs (R, G, B) : numéro, nom, joueur qui parle (pma-voice / micro du jeu)
    IdColor = { 255, 255, 255 },
    NameColor = { 205, 214, 224 },
    TalkingColor = { 120, 200, 255 },
}
